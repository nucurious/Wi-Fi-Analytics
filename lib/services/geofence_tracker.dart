import 'dart:convert';
import 'dart:math';

import '../models.dart';

/// A circular geofence: a saved site, or one CBSD area of the Spectrum HMNO
/// (CBRS) geofence file.
class Fence {
  final String id;
  final String name;
  final double latitude, longitude, radiusM;
  const Fence(this.id, this.name, this.latitude, this.longitude, this.radiusM);
}

/// The HMNO CBRS geofence (GeoFence_<date>.json: cbsd_deployment[] with
/// radial_coverage), bundled with the app.
class HmnoGeofence {
  final String version; // e.g. 20260708
  final double bufferM; // delay_buffer_meters from the file
  final List<Fence> areas;
  HmnoGeofence(this.version, this.bufferM, this.areas);

  static HmnoGeofence parse(String json, String version) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    final out = <Fence>[];
    for (final d in (j['cbsd_deployment'] as List? ?? const [])) {
      final c = (d as Map)['coverage']?['radial_coverage'] as Map?;
      if (c == null) continue;
      out.add(Fence(
        d['cbsd_id'].toString(),
        d['cbsd_id'].toString(),
        (c['latitude'] as num).toDouble(),
        (c['longitude'] as num).toDouble(),
        (c['radius_meters'] as num).toDouble(),
      ));
    }
    return HmnoGeofence(version, (j['delay_buffer_meters'] as num?)?.toDouble() ?? 0, out);
  }

  /// Areas containing the point (with distance to centre), nearest first, and
  /// the distance to the nearest edge (negative = inside).
  (List<(Fence, double)>, Fence?, double) locate(double lat, double lon) {
    final inside = <(Fence, double)>[];
    Fence? nearest;
    var edge = double.infinity;
    for (final f in areas) {
      // Cheap box check before the exact distance (6.5 km ~ 0.06 degrees).
      if ((f.latitude - lat).abs() > 0.5 || (f.longitude - lon).abs() > 0.7) continue;
      final d = GeofenceTracker.distanceM(lat, lon, f.latitude, f.longitude);
      final e = d - (f.radiusM + bufferM);
      if (e <= 0) inside.add((f, d));
      if (e < edge) {
        edge = e;
        nearest = f;
      }
    }
    inside.sort((a, b) => a.$2.compareTo(b.$2));
    return (inside, nearest, edge);
  }
}

/// One geofence crossing.
class GeofenceEvent {
  final DateTime time;
  final String event; // Entered, Exited, Inside at start
  final String source; // Site or HMNO CBRS
  final String fenceId, fenceName;
  final double radiusM;
  final double distanceM; // to the fence centre
  final double edgeM; // to the edge; negative = inside
  final int areasInside; // HMNO: how many CBSD areas contain the point
  final double? dwellSeconds; // time inside, on Exited
  final double latitude, longitude, accuracyM;
  final double? speedKmh, headingDeg;
  const GeofenceEvent({
    required this.time,
    required this.event,
    required this.source,
    required this.fenceId,
    required this.fenceName,
    required this.radiusM,
    required this.distanceM,
    required this.edgeM,
    this.areasInside = 0,
    this.dwellSeconds,
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    this.speedKmh,
    this.headingDeg,
  });

  String get summary =>
      '$event ${source == 'Site' ? fenceId : 'HMNO $fenceId'}${dwellSeconds == null ? '' : ' after ${_dur(dwellSeconds!)}'}';

  static String _dur(double s) {
    final m = s ~/ 60;
    return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : (m > 0 ? '${m}m ${(s % 60).round()}s' : '${s.round()}s');
  }
}

/// Saved sites: each is its own fence. HMNO: the 541 CBSD areas are treated as
/// one coverage area (their union), since that is what decides whether the
/// phone may use Spectrum HMNO / CBRS; each event names the area involved.
/// Enter when within the radius; exit only [hysteresisM] beyond it, so GPS
/// jitter at the edge doesn't produce pairs. Fixes worse than [maxAccuracyM]
/// are ignored.
class GeofenceTracker {
  static const double hysteresisM = 10;
  static const double maxAccuracyM = 50;

  HmnoGeofence? hmno;

  final _inside = <String, DateTime>{}; // site id -> entered at
  final _known = <String>{};
  bool? _inHmno;
  DateTime? _hmnoSince;
  Fence? _hmnoFence; // area the phone entered through

  /// Latest HMNO position: areas containing the phone, nearest area, edge distance.
  List<(Fence, double)> hmnoInside = const [];
  Fence? hmnoNearest;
  double hmnoEdgeM = double.infinity;

  bool isInside(String siteId) => _inside.containsKey(siteId);
  bool? get inHmno => _inHmno;

  List<GeofenceEvent> update(List<Site> sites, double lat, double lon, double accuracy,
      {double? speedMs, double? heading, DateTime? at}) {
    final now = at ?? DateTime.now();
    if (accuracy > maxAccuracyM) return const [];
    final speed = speedMs == null || speedMs < 0 ? null : speedMs * 3.6;
    GeofenceEvent ev(String what, String source, Fence f, double d, {double? dwell, int areas = 0}) => GeofenceEvent(
          time: now,
          event: what,
          source: source,
          fenceId: f.id,
          fenceName: f.name,
          radiusM: f.radiusM,
          distanceM: d,
          edgeM: d - f.radiusM,
          areasInside: areas,
          dwellSeconds: dwell,
          latitude: lat,
          longitude: lon,
          accuracyM: accuracy,
          speedKmh: speed,
          headingDeg: heading,
        );
    final out = <GeofenceEvent>[];

    // Saved sites.
    final ids = <String>{};
    for (final s in sites) {
      if (s.latitude == null || s.longitude == null) continue;
      ids.add(s.id);
      final f = Fence(s.id, s.name, s.latitude!, s.longitude!, s.radiusM);
      final d = distanceM(lat, lon, f.latitude, f.longitude);
      final inside = _inside.containsKey(s.id);
      if (!_known.contains(s.id)) {
        _known.add(s.id);
        if (d <= f.radiusM) {
          _inside[s.id] = now;
          out.add(ev('Inside at start', 'Site', f, d));
        }
        continue;
      }
      if (!inside && d <= f.radiusM) {
        _inside[s.id] = now;
        out.add(ev('Entered', 'Site', f, d));
      } else if (inside && d > f.radiusM + hysteresisM) {
        final since = _inside.remove(s.id)!;
        out.add(ev('Exited', 'Site', f, d, dwell: now.difference(since).inMilliseconds / 1000));
      }
    }
    _known.removeWhere((id) => !ids.contains(id));
    _inside.removeWhere((id, _) => !ids.contains(id));

    // HMNO CBRS geofence (union of all areas).
    final h = hmno;
    if (h != null) {
      final (inside, nearest, edge) = h.locate(lat, lon);
      hmnoInside = inside;
      hmnoNearest = nearest;
      hmnoEdgeM = edge;
      final nowIn = inside.isNotEmpty;
      if (_inHmno == null) {
        _inHmno = nowIn;
        if (nowIn) {
          _hmnoSince = now;
          _hmnoFence = inside.first.$1;
          out.add(ev('Inside at start', 'HMNO CBRS', inside.first.$1, inside.first.$2, areas: inside.length));
        }
      } else if (!_inHmno! && nowIn) {
        _inHmno = true;
        _hmnoSince = now;
        _hmnoFence = inside.first.$1;
        out.add(ev('Entered', 'HMNO CBRS', inside.first.$1, inside.first.$2, areas: inside.length));
      } else if (_inHmno! && !nowIn && edge > hysteresisM && nearest != null) {
        _inHmno = false;
        final dwell = _hmnoSince == null ? null : now.difference(_hmnoSince!).inMilliseconds / 1000;
        final f = nearest;
        out.add(ev('Exited', 'HMNO CBRS', f, distanceM(lat, lon, f.latitude, f.longitude), dwell: dwell));
        _hmnoFence = null;
      }
    }
    return out;
  }

  /// "inside DALLAS_113TX_1004 (3 areas), 1.2 km to edge" / "outside, nearest X 4.1 km".
  String hmnoStatus() {
    if (hmno == null || _inHmno == null) return '';
    String km(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
    if (hmnoInside.isNotEmpty) {
      final f = hmnoInside.first.$1;
      final toEdge = f.radiusM + (hmno?.bufferM ?? 0) - hmnoInside.first.$2;
      return 'inside ${f.id}${hmnoInside.length > 1 ? ' (+${hmnoInside.length - 1})' : ''}, ${km(toEdge)} to its edge';
    }
    return hmnoNearest == null ? 'outside (no area within 50 km)' : 'outside, nearest ${hmnoNearest!.id} ${km(hmnoEdgeM)}';
  }

  Fence? get hmnoEntry => _hmnoFence;

  static double distanceM(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) + cos(rad(lat1)) * cos(rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(min(1.0, sqrt(a)));
  }
}
