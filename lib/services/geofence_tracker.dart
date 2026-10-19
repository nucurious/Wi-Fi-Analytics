import 'dart:math';

import '../models.dart';

/// One geofence crossing.
class GeofenceEvent {
  final DateTime time;
  final String event; // Entered, Exited, Inside at start
  final Site site;
  final double distanceM;
  final double? dwellSeconds; // time inside, on Exited
  final double latitude, longitude, accuracyM;
  final double? speedKmh, headingDeg;
  const GeofenceEvent({
    required this.time,
    required this.event,
    required this.site,
    required this.distanceM,
    this.dwellSeconds,
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    this.speedKmh,
    this.headingDeg,
  });

  String get summary => '$event ${site.id}${dwellSeconds == null ? '' : ' after ${_dur(dwellSeconds!)}'}';

  static String _dur(double s) {
    final m = s ~/ 60;
    return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : (m > 0 ? '${m}m ${(s % 60).round()}s' : '${s.round()}s');
  }
}

/// Every saved site with coordinates is a circular geofence of
/// [Site.radiusM]. Enter when the phone is within the radius; exit only when
/// it is [hysteresisM] beyond it, so GPS jitter at the edge doesn't produce
/// enter/exit pairs. Fixes less accurate than [maxAccuracyM] are ignored.
class GeofenceTracker {
  static const double hysteresisM = 10;
  static const double maxAccuracyM = 50;

  final _inside = <String, DateTime>{}; // site id -> entered at
  final _known = <String>{}; // site ids with a decided state

  void reset() {
    _inside.clear();
    _known.clear();
  }

  bool isInside(String siteId) => _inside.containsKey(siteId);

  /// Feed every GPS fix; returns the crossings it caused.
  List<GeofenceEvent> update(List<Site> sites, double lat, double lon, double accuracy,
      {double? speedMs, double? heading, DateTime? at}) {
    final now = at ?? DateTime.now();
    if (accuracy > maxAccuracyM) return const [];
    final out = <GeofenceEvent>[];
    final ids = <String>{};
    for (final s in sites) {
      if (s.latitude == null || s.longitude == null) continue;
      ids.add(s.id);
      final d = distanceM(lat, lon, s.latitude!, s.longitude!);
      GeofenceEvent ev(String what, {double? dwell}) => GeofenceEvent(
            time: now,
            event: what,
            site: s,
            distanceM: d,
            dwellSeconds: dwell,
            latitude: lat,
            longitude: lon,
            accuracyM: accuracy,
            speedKmh: speedMs == null || speedMs < 0 ? null : speedMs * 3.6,
            headingDeg: heading,
          );
      final inside = _inside.containsKey(s.id);
      if (!_known.contains(s.id)) {
        _known.add(s.id);
        if (d <= s.radiusM) {
          _inside[s.id] = now;
          out.add(ev('Inside at start'));
        }
        continue;
      }
      if (!inside && d <= s.radiusM) {
        _inside[s.id] = now;
        out.add(ev('Entered'));
      } else if (inside && d > s.radiusM + hysteresisM) {
        final since = _inside.remove(s.id)!;
        out.add(ev('Exited', dwell: now.difference(since).inMilliseconds / 1000));
      }
    }
    // Sites deleted or moved: forget them.
    _known.removeWhere((id) => !ids.contains(id));
    _inside.removeWhere((id, _) => !ids.contains(id));
    return out;
  }

  static double distanceM(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) + cos(rad(lat1)) * cos(rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * asin(min(1.0, sqrt(a)));
  }
}
