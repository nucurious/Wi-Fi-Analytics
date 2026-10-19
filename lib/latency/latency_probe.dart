import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// How latency is measured.
enum LatencyMethod { twamp, icmp }

extension LatencyMethodLabel on LatencyMethod {
  String get label => this == LatencyMethod.twamp ? 'TWAMP' : 'ICMP';
}

class LatencyException implements Exception {
  final String message;
  LatencyException(this.message);
  @override
  String toString() => message;
}

/// Outcome of one probe packet: a reply (with round-trip time) or a loss.
class ProbeResult {
  final int seq;

  /// Wall-clock time the packet was sent.
  final DateTime sentAt;

  /// Round-trip time in ms, with the reflector's own processing time removed.
  /// Null when the packet was lost.
  final double? rttMs;

  /// One-way times (TWAMP only). They need the phone and reflector clocks to
  /// be in sync, so treat them as indicative unless the reflector uses NTP/PTP.
  final double? outboundMs;
  final double? inboundMs;

  const ProbeResult(this.seq, this.sentAt, this.rttMs, {this.outboundMs, this.inboundMs});

  bool get lost => rttMs == null;
}

/// Summary of a set of probe results.
class LatencyStats {
  final int sent;
  final int received;
  final double? minMs, avgMs, maxMs, medianMs;

  /// Mean absolute difference between consecutive round-trip times (IPDV).
  final double? jitterMs;
  final double? outboundAvgMs, inboundAvgMs;

  const LatencyStats({
    required this.sent,
    required this.received,
    this.minMs,
    this.avgMs,
    this.maxMs,
    this.medianMs,
    this.jitterMs,
    this.outboundAvgMs,
    this.inboundAvgMs,
  });

  int get lost => max(0, sent - received);
  double? get lossPercent => sent > 0 ? lost * 100 / sent : null;
}

/// Collects probe results and produces [LatencyStats].
class LatencyAccumulator {
  final List<ProbeResult> _results = [];

  void add(ProbeResult r) => _results.add(r);
  bool get isEmpty => _results.isEmpty;

  LatencyStats stats() {
    final ordered = List<ProbeResult>.of(_results)..sort((a, b) => a.seq.compareTo(b.seq));
    final rtts = <double>[for (final r in ordered) if (r.rttMs != null) r.rttMs!];
    double? avg(Iterable<double> v) => v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    double? jitter;
    if (rtts.length >= 2) {
      var sum = 0.0;
      for (var i = 1; i < rtts.length; i++) {
        sum += (rtts[i] - rtts[i - 1]).abs();
      }
      jitter = sum / (rtts.length - 1);
    }
    final sorted = List<double>.of(rtts)..sort();
    double? median;
    if (sorted.isNotEmpty) {
      final mid = sorted.length ~/ 2;
      median = sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
    }
    return LatencyStats(
      sent: ordered.length,
      received: rtts.length,
      minMs: sorted.isEmpty ? null : sorted.first,
      avgMs: avg(rtts),
      maxMs: sorted.isEmpty ? null : sorted.last,
      medianMs: median,
      jitterMs: jitter,
      outboundAvgMs: avg([for (final r in ordered) if (r.outboundMs != null) r.outboundMs!]),
      inboundAvgMs: avg([for (final r in ordered) if (r.inboundMs != null) r.inboundMs!]),
    );
  }
}

/// A running latency probe. Every packet sent produces exactly one
/// [ProbeResult] on [results]: a reply, or a loss once [timeout] passes.
abstract class LatencyProbe {
  LatencyMethod get method;
  String get target;
  Duration get timeout;
  Stream<ProbeResult> get results;
  Future<void> start();
  /// [quick]: the user pressed Stop; don't wait the full timeout for late replies.
  Future<void> stop({bool quick = false});

  static Future<InternetAddress> resolve(String host) async {
    final parsed = InternetAddress.tryParse(host);
    if (parsed != null) return parsed;
    try {
      final list = await InternetAddress.lookup(host);
      return list.firstWhere((a) => a.type == InternetAddressType.IPv4, orElse: () => list.first);
    } on SocketException {
      throw LatencyException('Could not find "$host". Check the address.');
    }
  }
}

// ---------------------------------------------------------------------------
// TWAMP-Light (RFC 5357 Appendix I) / STAMP (RFC 8762) unauthenticated mode
// ---------------------------------------------------------------------------

/// Seconds between 1900-01-01 (NTP epoch) and 1970-01-01 (Unix epoch).
const int _ntpOffset = 2208988800;

/// Sends TWAMP-Light test packets to a reflector and times the replies.
///
/// Sender packet (RFC 5357 4.1.2): seq(4) | timestamp(8, NTP) | error
/// estimate(2) | padding. Reflected packet (4.2.1): seq(4) | T3(8) | error(2)
/// | MBZ(2) | T2 receive time(8) | sender seq(4) | T1(8) | sender error(2) |
/// MBZ(2) | sender TTL(1) | padding.
class TwampLightProbe implements LatencyProbe {
  final String host;
  final int port;
  final int rateHz;
  final int packetBytes;
  @override
  final Duration timeout;

  TwampLightProbe({
    required this.host,
    this.port = 862,
    this.rateHz = 10,
    this.packetBytes = 64,
    this.timeout = const Duration(seconds: 2),
  });

  @override
  LatencyMethod get method => LatencyMethod.twamp;
  @override
  String get target => '$host:$port';

  final _controller = StreamController<ProbeResult>.broadcast();
  @override
  Stream<ProbeResult> get results => _controller.stream;

  RawDatagramSocket? _socket;
  InternetAddress? _address;
  StreamSubscription<RawSocketEvent>? _sub;
  Timer? _sendTimer;
  Timer? _sweepTimer;
  final Stopwatch _clock = Stopwatch();
  int _seq = 0;
  int _received = 0;

  /// seq -> (monotonic send time in microseconds, wall-clock send time)
  final Map<int, (int, DateTime)> _pending = {};

  @override
  Future<void> start() async {
    _address = await LatencyProbe.resolve(host);
    final bindAddr = _address!.type == InternetAddressType.IPv6 ? InternetAddress.anyIPv6 : InternetAddress.anyIPv4;
    _socket = await RawDatagramSocket.bind(bindAddr, 0);
    _sub = _socket!.listen(_onEvent);
    _clock.start();
    final interval = Duration(microseconds: (1e6 / rateHz.clamp(1, 100)).round());
    _send();
    _sendTimer = Timer.periodic(interval, (_) => _send());
    _sweepTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _sweep());

    // Fail fast if nothing at all comes back, so the user knows the reflector
    // is unreachable instead of seeing 100% loss.
    Future.delayed(timeout + const Duration(seconds: 3), () {
      if (_socket != null && _received == 0 && _seq > 5 && !_controller.isClosed) {
        _controller.addError(LatencyException(
            'No TWAMP replies from $host:$port. Check that a TWAMP-Light reflector is running there and UDP $port is open.'));
      }
    });
  }

  void _send() {
    final sock = _socket;
    if (sock == null) return;
    final len = max(packetBytes, 41); // >= reflected size keeps the test symmetric
    final b = ByteData(len);
    final now = DateTime.now();
    final seq = _seq++;
    b.setUint32(0, seq);
    final us = now.microsecondsSinceEpoch;
    b.setUint32(4, us ~/ 1000000 + _ntpOffset);
    b.setUint32(8, ((us % 1000000) / 1e6 * 4294967296).floor() & 0xFFFFFFFF);
    b.setUint16(12, 0x0001); // error estimate: S=0 (not synced), scale 0, multiplier 1
    _pending[seq] = (_clock.elapsedMicroseconds, now);
    try {
      sock.send(b.buffer.asUint8List(), _address!, port);
    } on SocketException {
      // No route for a moment (e.g. switching networks): counts as lost.
    }
  }

  static double _ntpToSeconds(ByteData b, int offset) =>
      (b.getUint32(offset) - _ntpOffset) + b.getUint32(offset + 4) / 4294967296.0;

  void _onEvent(RawSocketEvent e) {
    if (e != RawSocketEvent.read) return;
    var dg = _socket?.receive();
    while (dg != null) {
      _onReply(dg.data);
      dg = _socket?.receive();
    }
  }

  void _onReply(Uint8List data) {
    final recvMono = _clock.elapsedMicroseconds;
    final recvWall = DateTime.now().microsecondsSinceEpoch / 1e6;
    if (data.length < 36) return;
    final b = ByteData.sublistView(data);
    final senderSeq = b.getUint32(24);
    final sent = _pending.remove(senderSeq);
    if (sent == null) return; // late (already counted lost) or not ours
    final t3 = _ntpToSeconds(b, 4); // reflector send time
    final t2 = _ntpToSeconds(b, 16); // reflector receive time
    final t1 = _ntpToSeconds(b, 28); // our send time, echoed back
    final reflectorMs = max(0.0, (t3 - t2) * 1000);
    final rtt = max(0.0, (recvMono - sent.$1) / 1000 - reflectorMs);
    _received++;
    _controller.add(ProbeResult(senderSeq, sent.$2, rtt,
        outboundMs: (t2 - t1) * 1000, inboundMs: (recvWall - t3) * 1000));
  }

  void _sweep() {
    final cutoff = _clock.elapsedMicroseconds - timeout.inMicroseconds;
    final expired = [for (final e in _pending.entries) if (e.value.$1 < cutoff) e.key];
    for (final seq in expired) {
      final s = _pending.remove(seq)!;
      _controller.add(ProbeResult(seq, s.$2, null));
    }
  }

  @override
  Future<void> stop({bool quick = false}) async {
    _sendTimer?.cancel();
    _sendTimer = null;
    // Give in-flight packets a chance to come back, then count the rest lost.
    await Future.delayed(quick ? const Duration(milliseconds: 300) : timeout);
    _sweepTimer?.cancel();
    for (final e in _pending.entries.toList()) {
      _controller.add(ProbeResult(e.key, e.value.$2, null));
    }
    _pending.clear();
    await _sub?.cancel();
    _socket?.close();
    _socket = null;
    await _controller.close();
  }
}

// ---------------------------------------------------------------------------
// ICMP ping fallback (Android only: iOS does not let apps run ping)
// ---------------------------------------------------------------------------

/// Runs the phone's `ping` command and turns its replies into [ProbeResult]s.
/// Android limits apps to one ping every 0.2 s (5 per second).
class PingProbe implements LatencyProbe {
  final String host;
  final int rateHz;
  @override
  final Duration timeout;

  PingProbe({required this.host, this.rateHz = 5, this.timeout = const Duration(seconds: 2)});

  static bool get supported => Platform.isAndroid;

  @override
  LatencyMethod get method => LatencyMethod.icmp;
  @override
  String get target => host;

  final _controller = StreamController<ProbeResult>.broadcast();
  @override
  Stream<ProbeResult> get results => _controller.stream;

  Process? _process;
  Timer? _sweepTimer;
  final Stopwatch _clock = Stopwatch();
  late DateTime _startWall;
  late double _intervalS;
  int _nextToSettle = 1; // ping numbers packets from 1
  final Map<int, double> _replies = {}; // seq -> rtt ms
  bool _stopping = false;

  static final _reply = RegExp(r'icmp_seq=(\d+).*?time[=<]([\d.]+)');

  @override
  Future<void> start() async {
    if (!supported) {
      throw LatencyException('Ping is not available on this phone. Set a TWAMP reflector in Settings.');
    }
    _intervalS = max(0.2, 1 / rateHz.clamp(1, 5));
    final address = await LatencyProbe.resolve(host);
    try {
      _process = await Process.start('/system/bin/ping', [
        '-n',
        '-i', _intervalS.toStringAsFixed(1),
        '-W', '${timeout.inSeconds}',
        address.address,
      ]);
    } on ProcessException catch (e) {
      throw LatencyException('Could not start ping: ${e.message}');
    }
    _startWall = DateTime.now();
    _clock.start();
    _process!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
    _process!.stderr.drain<void>();
    _sweepTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _settle());
  }

  void _onLine(String line) {
    final m = _reply.firstMatch(line);
    if (m == null) return;
    final seq = int.parse(m[1]!);
    if (seq < _nextToSettle) return; // already counted lost
    _replies[seq] = double.parse(m[2]!);
  }

  /// Packet n is sent about (n-1) * interval after start. Once its timeout
  /// has passed, report it as received or lost, in order.
  void _settle({bool all = false}) {
    final elapsed = _clock.elapsedMicroseconds / 1e6;
    while (true) {
      final sendAt = (_nextToSettle - 1) * _intervalS;
      if (!all && sendAt + timeout.inMilliseconds / 1000 > elapsed) break;
      if (all && sendAt > elapsed) break;
      final seq = _nextToSettle++;
      final sentAt = _startWall.add(Duration(microseconds: (sendAt * 1e6).round()));
      _controller.add(ProbeResult(seq, sentAt, _replies.remove(seq)));
    }
  }

  @override
  Future<void> stop({bool quick = false}) async {
    if (_stopping) return;
    _stopping = true;
    // Let the last replies arrive, then settle every packet sent so far.
    await Future.delayed(quick ? const Duration(milliseconds: 300) : timeout);
    _process?.kill();
    _sweepTimer?.cancel();
    _settle(all: true);
    await _controller.close();
  }
}
