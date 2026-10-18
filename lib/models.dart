import 'package:geolocator/geolocator.dart';

import 'latency/latency_probe.dart';

/// Snapshot of radio state (cellular + Wi-Fi) at a moment in time.
class RadioSnapshot {
  final Map<String, dynamic> raw;
  final DateTime time;
  RadioSnapshot(this.raw) : time = DateTime.now();

  static RadioSnapshot empty() => RadioSnapshot(const {});

  String? _s(String k) => raw[k]?.toString();
  int? _i(String k) => (raw[k] as num?)?.toInt();

  String get connection => _s('connection') ?? 'UNKNOWN';
  String get rat => _s('rat') ?? 'Unknown';
  String? get operatorName => _s('operator');
  bool get isWifi => connection == 'WIFI';
  bool get isNr => rat.startsWith('5G');

  int? get lteRsrp => _i('lteRsrp');
  int? get lteSinr => _i('lteSinr');
  int? get nrRsrp => _i('nrSsRsrp');
  int? get nrSinr => _i('nrSsSinr');
  int? get wifiRssi => _i('wifiRssi');
  String? get wifiSsid => _s('wifiSsid');
  int? get wifiChannel => _i('wifiChannel');
  String? get wifiBand => _s('wifiBand');
  String? get band => _s('lteBand') != null ? 'B${_s('lteBand')}' : _s('nrBand');
  int? get pci => _i('ltePci') ?? _i('nrPci');

  /// Field order used for every CSV that includes radio info.
  static const List<String> csvFields = [
    'connection', 'rat', 'dataNetworkType', 'overrideNetworkType', 'operator', 'mcc', 'mnc',
    'lteRsrp', 'lteRsrq', 'lteSinr', 'lteRssi', 'lteCqi', 'ltePci', 'lteTac', 'lteEci', 'lteEnb',
    'lteCellId', 'lteEarfcn', 'lteBand', 'lteBandwidthKhz', 'lteTimingAdvance',
    'nrSsRsrp', 'nrSsRsrq', 'nrSsSinr', 'nrCsiRsrp', 'nrCsiSinr', 'nrPci', 'nrTac', 'nrNci',
    'nrArfcn', 'nrBand',
    'umtsDbm', 'umtsCid', 'umtsLac', 'umtsPsc', 'umtsUarfcn', 'gsmDbm', 'gsmCid', 'gsmLac', 'gsmArfcn',
    'wifiSsid', 'wifiBssid', 'wifiRssi', 'wifiFreqMhz', 'wifiBand', 'wifiChannel', 'wifiStandard',
    'wifiLinkMbps', 'wifiTxMbps', 'wifiRxMbps',
  ];

  static List<String> get csvHeader => csvFields.map(_snake).toList();

  List<Object?> get csvValues => csvFields.map((k) => raw[k]).toList();

  static String _snake(String k) => k.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
}

/// A named location (cell site, building, test point).
class Site {
  final String id;
  final String name;
  final String notes;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final DateTime created;

  Site({
    required this.id,
    required this.name,
    this.notes = '',
    this.latitude,
    this.longitude,
    this.accuracy,
    DateTime? created,
  }) : created = created ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'created': created.toIso8601String(),
      };

  factory Site.fromJson(Map<String, dynamic> j) => Site(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        created: DateTime.tryParse(j['created'] as String? ?? ''),
      );
}

/// GPS columns shared by every CSV.
class GpsCsv {
  static const header = [
    'latitude', 'longitude', 'altitude_m', 'gps_accuracy_m', 'speed_kmh', 'heading_deg', 'gps_time_utc',
  ];

  static List<Object?> values(Position? p) {
    if (p == null) return List<Object?>.filled(header.length, null);
    return [
      p.latitude.toStringAsFixed(7),
      p.longitude.toStringAsFixed(7),
      p.altitude.toStringAsFixed(1),
      p.accuracy.toStringAsFixed(1),
      p.speed >= 0 ? (p.speed * 3.6).toStringAsFixed(1) : null,
      p.heading >= 0 ? p.heading.toStringAsFixed(0) : null,
      p.timestamp.toUtc().toIso8601String(),
    ];
  }
}

/// Summary of one completed (or failed) test.
class TestRecord {
  final String testId;
  final String type; // e.g. "TCP Download"
  final DateTime start;
  final double durationSeconds;
  final double? mbps;
  final double? jitterMs;
  final int? lost;
  final int? total;
  final String? error;
  final bool stoppedByUser;

  /// Per-second throughput statistics (Mbps) over the test.
  final double? minMbps;
  final double? maxMbps;
  final double? medianMbps;
  final double? p10Mbps;
  final double? p90Mbps;

  /// Latency measured while this test ran (TWAMP or ping), if enabled.
  final LatencyStats? latency;
  final String? latencyTarget; // e.g. "TWAMP 203.0.113.5:862"

  TestRecord({
    required this.testId,
    required this.type,
    required this.start,
    required this.durationSeconds,
    this.mbps,
    this.jitterMs,
    this.lost,
    this.total,
    this.error,
    this.stoppedByUser = false,
    this.minMbps,
    this.maxMbps,
    this.medianMbps,
    this.p10Mbps,
    this.p90Mbps,
    this.latency,
    this.latencyTarget,
  });

  TestRecord withLatency(LatencyStats? l, String? target) => TestRecord(
        testId: testId,
        type: type,
        start: start,
        durationSeconds: durationSeconds,
        mbps: mbps,
        jitterMs: jitterMs,
        lost: lost,
        total: total,
        error: error,
        stoppedByUser: stoppedByUser,
        minMbps: minMbps,
        maxMbps: maxMbps,
        medianMbps: medianMbps,
        p10Mbps: p10Mbps,
        p90Mbps: p90Mbps,
        latency: l,
        latencyTarget: l == null ? null : target,
      );

  double? get lossPercent => (lost != null && total != null && total! > 0) ? lost! * 100 / total! : null;
}

/// Min / max / median / percentiles of per-second throughput samples.
class SpeedStats {
  final double min, max, median, p10, p90;
  const SpeedStats(this.min, this.max, this.median, this.p10, this.p90);

  /// Returns null when there are no samples.
  static SpeedStats? of(List<double> samples) {
    if (samples.isEmpty) return null;
    final s = List<double>.of(samples)..sort();
    double pct(double p) {
      // Linear interpolation between closest ranks.
      final pos = (s.length - 1) * p;
      final lo = pos.floor();
      final hi = pos.ceil();
      return s[lo] + (s[hi] - s[lo]) * (pos - lo);
    }

    return SpeedStats(s.first, s.last, pct(0.5), pct(0.1), pct(0.9));
  }
}
