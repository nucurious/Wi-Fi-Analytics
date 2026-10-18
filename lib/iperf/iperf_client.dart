// Pure-Dart iperf3 client (protocol-compatible with iperf3 3.x servers).
//
// Supports TCP and UDP, upload (client -> server) and download
// (server -> client, iperf3 "-R" reverse mode), parallel streams, a fixed
// duration or "run until stopped", and per-second interval reporting.
//
// The protocol flow below was validated against a real iperf3 3.16 server.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import '../util/host_address.dart';

enum IperfProtocol { tcp, udp }

enum IperfDirection { upload, download }

class IperfConfig {
  final String host;
  final int port;
  final IperfProtocol protocol;
  final IperfDirection direction;

  /// Test length in seconds. 0 means "run until stop() is called".
  final int durationSeconds;

  /// Number of parallel streams.
  final int parallel;

  /// UDP only: total target bitrate across all streams, in bits per second.
  final int udpBandwidthBps;

  /// UDP only: datagram size in bytes (1200 avoids fragmentation on most
  /// cellular networks).
  final int udpPacketLength;

  const IperfConfig({
    required this.host,
    this.port = 5201,
    required this.protocol,
    required this.direction,
    this.durationSeconds = 10,
    this.parallel = 1,
    this.udpBandwidthBps = 10000000,
    this.udpPacketLength = 1200,
  });

  String get label =>
      '${protocol == IperfProtocol.tcp ? 'TCP' : 'UDP'} '
      '${direction == IperfDirection.upload ? 'Upload' : 'Download'}';
}

class IperfInterval {
  final double elapsedSeconds;
  final int bytes;
  final double mbps;
  const IperfInterval(this.elapsedSeconds, this.bytes, this.mbps);
}

class IperfResult {
  final IperfConfig config;
  final double durationSeconds;
  final int bytes;
  final double mbps;
  final double? jitterMs;
  final int? lostPackets;
  final int? totalPackets;
  final bool stoppedByUser;

  const IperfResult({
    required this.config,
    required this.durationSeconds,
    required this.bytes,
    required this.mbps,
    this.jitterMs,
    this.lostPackets,
    this.totalPackets,
    this.stoppedByUser = false,
  });

  double? get lossPercent {
    if (lostPackets == null || totalPackets == null || totalPackets == 0) {
      return null;
    }
    return lostPackets! * 100.0 / totalPackets!;
  }
}

class IperfException implements Exception {
  final String message;
  IperfException(this.message);
  @override
  String toString() => message;
}

// iperf3 control-channel states.
const int _testStart = 1;
const int _testRunning = 2;
const int _testEnd = 4;
const int _paramExchange = 9;
const int _createStreams = 10;
const int _serverTerminate = 11;
const int _exchangeResults = 13;
const int _displayResults = 14;
const int _iperfDone = 16;
const int _accessDenied = 0xFF; // -1 as a signed byte
const int _serverError = 0xFE; // -2 as a signed byte

const int _tcpBlockSize = 128 * 1024;
const Duration _ioTimeout = Duration(seconds: 15);

class IperfClient {
  final IperfConfig config;
  IperfClient(this.config);

  final _intervalController = StreamController<IperfInterval>.broadcast();

  /// Emits throughput once per second while the test runs.
  Stream<IperfInterval> get intervals => _intervalController.stream;

  final Completer<void> _stopSignal = Completer<void>();
  bool _stoppedByUser = false;
  bool _finished = false;

  Socket? _control;
  _ControlReader? _reader;
  final List<Socket> _tcpSockets = [];
  final List<StreamSubscription> _subscriptions = [];
  final List<_UdpStream> _udpStreams = [];
  final List<int> _tcpBytes = [];

  /// Ends the test early. Results up to this point are still collected.
  void stop() {
    _stoppedByUser = true;
    if (!_stopSignal.isCompleted) _stopSignal.complete();
  }

  bool _started = false;

  /// Runs the test. Retries a couple of times if the server is busy or still
  /// resetting from a previous test.
  Future<IperfResult> run() async {
    for (var attempt = 0;; attempt++) {
      try {
        return await _runOnce();
      } on _ServerBusy {
        await _cleanup();
        if (attempt >= 2 || _stoppedByUser) {
          throw IperfException(
              'The iperf3 server is busy running another test. Try again in a moment.');
        }
      } on IperfException {
        await _cleanup();
        // A connection reset before the test starts usually means the server
        // hasn't finished tearing down the previous test.
        if (_started || attempt >= 1 || _stoppedByUser) rethrow;
      } catch (_) {
        await _cleanup();
        rethrow;
      }
      await Future.delayed(const Duration(milliseconds: 1500));
    }
  }

  Future<IperfResult> _runOnce() async {
    _finished = false;
    _started = false;
    final udp = config.protocol == IperfProtocol.udp;
    final download = config.direction == IperfDirection.download;
    final parallel = max(1, config.parallel);

    final address = await _resolve(config.host);
    final cookie = _makeCookie();

    // 1. Control connection.
    try {
      _control = await Socket.connect(address, config.port, timeout: const Duration(seconds: 10));
    } on SocketException catch (e) {
      throw IperfException(
          'Could not reach ${config.host}:${config.port} (${e.osError?.message ?? e.message}).');
    }
    _control!.setOption(SocketOption.tcpNoDelay, true);
    _reader = _ControlReader(_control!);
    _control!.add(cookie);
    await _control!.flush();

    await _expectState(_paramExchange);

    // 2. Send test parameters.
    final params = <String, dynamic>{
      'omit': 0,
      'time': config.durationSeconds > 0 ? config.durationSeconds : 86400,
      'num': 0,
      'blockcount': 0,
      'parallel': parallel,
      'len': udp ? config.udpPacketLength : _tcpBlockSize,
      'pacing_timer': 1000,
      'client_version': '3.16',
    };
    if (udp) {
      params['udp'] = true;
      // iperf3 applies the bandwidth per stream.
      params['bandwidth'] = max(1, config.udpBandwidthBps ~/ parallel);
    } else {
      params['tcp'] = true;
    }
    if (download) params['reverse'] = true;
    await _sendJson(params);

    await _expectState(_createStreams);

    // 3. Open data streams (order matters: the server numbers them 1,3,4,5...).
    for (var i = 0; i < parallel; i++) {
      if (udp) {
        _udpStreams.add(await _UdpStream.open(address, config.port));
      } else {
        final s = await Socket.connect(address, config.port, timeout: const Duration(seconds: 10));
        s.add(cookie);
        await s.flush();
        _tcpSockets.add(s);
        _tcpBytes.add(0);
      }
    }

    await _expectState(_testStart);
    await _expectState(_testRunning);
    _started = true;

    // 4. Run.
    final stopwatch = Stopwatch()..start();
    final senders = <Future<void>>[];
    if (udp) {
      for (final s in _udpStreams) {
        s.counting = download;
      }
      if (!download) senders.add(_udpSendLoop(parallel));
    } else {
      for (var i = 0; i < _tcpSockets.length; i++) {
        if (download) {
          final idx = i;
          _subscriptions.add(_tcpSockets[i].listen(
            (data) {
              if (!_finished) _tcpBytes[idx] += data.length;
            },
            onError: (_) {},
            cancelOnError: true,
          ));
        } else {
          senders.add(_tcpSendLoop(i));
        }
      }
    }

    var lastBytes = 0;
    var lastTime = 0.0;
    var serverEnded = false;
    final ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = stopwatch.elapsedMicroseconds / 1e6;
      final total = _totalLocalBytes();
      final delta = total - lastBytes;
      final dt = now - lastTime;
      if (dt > 0) {
        _intervalController.add(IperfInterval(now, delta, delta * 8 / dt / 1e6));
      }
      lastBytes = total;
      lastTime = now;
      // Server may abort mid-test.
      if (_reader!.available > 0 && !_stopSignal.isCompleted) {
        serverEnded = true;
        _stopSignal.complete();
      }
    });

    final waits = <Future<void>>[_stopSignal.future];
    if (config.durationSeconds > 0) {
      waits.add(Future.delayed(Duration(seconds: config.durationSeconds)));
    }
    await Future.any(waits);
    ticker.cancel();
    _finished = true;
    final elapsed = stopwatch.elapsedMicroseconds / 1e6;

    if (serverEnded) {
      final st = await _reader!.readByte(_ioTimeout);
      if (st == _serverTerminate || st == _serverError) {
        throw IperfException('The server ended the test early.');
      }
    }

    // 5. Tell the server we're done and exchange results.
    _control!.add([_testEnd]);
    await _control!.flush();
    await _expectState(_exchangeResults);

    final localStreams = <Map<String, dynamic>>[];
    final streamCount = udp ? _udpStreams.length : _tcpSockets.length;
    for (var i = 0; i < streamCount; i++) {
      final id = i == 0 ? 1 : i + 2;
      if (udp) {
        final s = _udpStreams[i];
        localStreams.add({
          'id': id,
          'bytes': s.bytes,
          'retransmits': -1,
          'jitter': download ? s.jitterSeconds : 0,
          'errors': download ? s.lost : 0,
          'packets': download ? s.maxSeq : s.sentPackets,
          'start_time': 0,
          'end_time': elapsed,
        });
      } else {
        localStreams.add({
          'id': id,
          'bytes': _tcpBytes[i],
          'retransmits': -1,
          'jitter': 0,
          'errors': 0,
          'packets': 0,
          'start_time': 0,
          'end_time': elapsed,
        });
      }
    }
    await _sendJson({
      'cpu_util_total': 0,
      'cpu_util_user': 0,
      'cpu_util_system': 0,
      'sender_has_retransmits': -1,
      'streams': localStreams,
    });

    final serverResults = await _recvJson();
    await _expectState(_displayResults);
    _control!.add([_iperfDone]);
    try {
      await _control!.flush();
    } catch (_) {}

    // Don't let pending sender loops outlive the test.
    for (final f in senders) {
      unawaited(f.catchError((_) {}));
    }

    final result = _buildResult(serverResults, elapsed, udp, download);
    await _cleanup();
    return result;
  }

  IperfResult _buildResult(
      Map<String, dynamic> server, double elapsed, bool udp, bool download) {
    final serverStreams = (server['streams'] as List?)?.cast<Map>() ?? const [];
    int serverBytes = 0, serverPackets = 0, serverErrors = 0;
    double jitterSum = 0;
    for (final s in serverStreams) {
      serverBytes += (s['bytes'] as num?)?.toInt() ?? 0;
      serverPackets += (s['packets'] as num?)?.toInt() ?? 0;
      serverErrors += (s['errors'] as num?)?.toInt() ?? 0;
      jitterSum += (s['jitter'] as num?)?.toDouble() ?? 0;
    }
    final duration = elapsed > 0 ? elapsed : 1.0;

    if (!download) {
      // Upload: the server is the receiver, so its counts are authoritative.
      final bytes = serverBytes > 0 ? serverBytes : _totalLocalBytes();
      return IperfResult(
        config: config,
        durationSeconds: elapsed,
        bytes: bytes,
        mbps: bytes * 8 / duration / 1e6,
        jitterMs: udp && serverStreams.isNotEmpty
            ? jitterSum / serverStreams.length * 1000
            : null,
        lostPackets: udp ? serverErrors : null,
        totalPackets: udp ? serverPackets : null,
        stoppedByUser: _stoppedByUser,
      );
    }

    // Download: we are the receiver.
    final bytes = _totalLocalBytes();
    int? lost, total;
    double? jitter;
    if (udp) {
      lost = _udpStreams.fold<int>(0, (a, s) => a + s.lost);
      total = _udpStreams.fold<int>(0, (a, s) => a + s.maxSeq);
      jitter = _udpStreams.isEmpty
          ? null
          : _udpStreams.fold<double>(0, (a, s) => a + s.jitterSeconds) /
              _udpStreams.length *
              1000;
    }
    return IperfResult(
      config: config,
      durationSeconds: elapsed,
      bytes: bytes,
      mbps: bytes * 8 / duration / 1e6,
      jitterMs: jitter,
      lostPackets: lost,
      totalPackets: total,
      stoppedByUser: _stoppedByUser,
    );
  }

  int _totalLocalBytes() {
    if (config.protocol == IperfProtocol.udp) {
      return _udpStreams.fold<int>(0, (a, s) => a + s.bytes);
    }
    return _tcpBytes.fold<int>(0, (a, b) => a + b);
  }

  Future<void> _tcpSendLoop(int index) async {
    final payload = _randomBytes(_tcpBlockSize);
    final socket = _tcpSockets[index];
    try {
      while (!_finished) {
        socket.add(payload);
        await socket.flush();
        if (!_finished) _tcpBytes[index] += payload.length;
      }
    } catch (_) {
      // Socket closed at end of test.
    }
  }

  Future<void> _udpSendLoop(int parallel) async {
    final len = max(16, config.udpPacketLength);
    final perStreamBps = config.udpBandwidthBps / parallel;
    final packetsPerSecond = perStreamBps / (len * 8);
    final payload = _randomBytes(len);
    final header = ByteData.sublistView(payload);
    final sw = Stopwatch()..start();

    while (!_finished) {
      final due = (sw.elapsedMicroseconds / 1e6 * packetsPerSecond).floor();
      for (final s in _udpStreams) {
        var budget = min(due - s.sentPackets, 500);
        while (budget-- > 0 && !_finished) {
          final now = DateTime.now().microsecondsSinceEpoch;
          header.setUint32(0, now ~/ 1000000);
          header.setUint32(4, now % 1000000);
          header.setUint32(8, (s.sentPackets + 1) & 0xFFFFFFFF);
          int sent;
          try {
            sent = s.socket.send(payload, s.address, s.port);
          } catch (_) {
            // Brief network change (e.g. signal drop). Count the packet as
            // sent so the server records it as lost, and keep going.
            sent = len;
          }
          if (sent <= 0) break; // OS buffer full; try again next tick
          s.sentPackets++;
          s.bytes += len;
        }
      }
      await Future.delayed(const Duration(milliseconds: 2));
    }
  }

  Future<void> _expectState(int expected) async {
    final st = await _reader!.readByte(_ioTimeout);
    if (st == expected) return;
    if (st == _accessDenied) throw _ServerBusy();
    if (st == _serverError) {
      throw IperfException('The iperf3 server reported an error.');
    }
    if (st == _serverTerminate) {
      throw IperfException('The iperf3 server terminated the test.');
    }
    throw IperfException('Unexpected response from server (state $st, expected $expected).');
  }

  Future<void> _sendJson(Map<String, dynamic> obj) async {
    final data = utf8.encode(jsonEncode(obj));
    final header = ByteData(4)..setUint32(0, data.length);
    _control!.add(header.buffer.asUint8List());
    _control!.add(data);
    await _control!.flush();
  }

  Future<Map<String, dynamic>> _recvJson() async {
    final lenBytes = await _reader!.read(4, _ioTimeout);
    final len = ByteData.sublistView(lenBytes).getUint32(0);
    final body = await _reader!.read(len, _ioTimeout);
    return jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
  }

  Future<void> _cleanup() async {
    _finished = true;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    for (final s in _tcpSockets) {
      s.destroy();
    }
    _tcpSockets.clear();
    _tcpBytes.clear();
    for (final u in _udpStreams) {
      await u.close();
    }
    _udpStreams.clear();
    await _reader?.cancel();
    _reader = null;
    _control?.destroy();
    _control = null;
  }

  /// Call when the client is no longer needed.
  Future<void> dispose() async {
    await _cleanup();
    await _intervalController.close();
  }

  static Future<InternetAddress> _resolve(String raw) async {
    final (host, _) = splitHostPort(raw); // last line of defence against "addr:port"
    final parsed = InternetAddress.tryParse(host);
    if (parsed != null) return parsed;
    try {
      final list = await InternetAddress.lookup(host);
      return list.firstWhere((a) => a.type == InternetAddressType.IPv4,
          orElse: () => list.first);
    } on SocketException {
      throw IperfException(host.contains(':')
          ? 'Server "$host" is not a valid IPv6 address. Check for a typo; put the port in the Port field.'
          : 'Could not find server "$host". Check the address.');
    }
  }

  static Uint8List _makeCookie() {
    const chars = 'abcdefghijklmnopqrstuvwxyz234567';
    final rnd = Random.secure();
    final b = Uint8List(37);
    for (var i = 0; i < 36; i++) {
      b[i] = chars.codeUnitAt(rnd.nextInt(chars.length));
    }
    b[36] = 0;
    return b;
  }

  static Uint8List _randomBytes(int n) {
    final rnd = Random();
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = rnd.nextInt(256);
    }
    return b;
  }
}

class _ServerBusy implements Exception {}

/// Buffers bytes from the control socket so we can read exact lengths.
class _ControlReader {
  final List<int> _buffer = [];
  Completer<void>? _waiter;
  bool _closed = false;
  Object? _error;
  late final StreamSubscription<Uint8List> _sub;

  _ControlReader(Socket socket) {
    _sub = socket.listen(
      (chunk) {
        _buffer.addAll(chunk);
        _wake();
      },
      onError: (Object e) {
        _error = e;
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  int get available => _buffer.length;

  void _wake() {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<Uint8List> read(int n, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_buffer.length < n) {
      if (_error != null) {
        throw IperfException('Connection to server failed: $_error');
      }
      if (_closed) {
        throw IperfException('The server closed the connection.');
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw IperfException('Timed out waiting for the server.');
      }
      _waiter = Completer<void>();
      try {
        await _waiter!.future.timeout(remaining);
      } on TimeoutException {
        throw IperfException('Timed out waiting for the server.');
      }
    }
    final out = Uint8List.fromList(_buffer.sublist(0, n));
    _buffer.removeRange(0, n);
    return out;
  }

  Future<int> readByte(Duration timeout) async => (await read(1, timeout))[0];

  Future<void> cancel() => _sub.cancel();
}

/// One UDP data stream, including receive-side jitter/loss accounting.
class _UdpStream {
  final RawDatagramSocket socket;
  final InternetAddress address;
  final int port;
  late final StreamSubscription<RawSocketEvent> _sub;

  Completer<void>? _handshake = Completer<void>();
  bool counting = false;

  int bytes = 0;
  int sentPackets = 0;
  int receivedPackets = 0;
  int maxSeq = 0;
  double jitterSeconds = 0;
  double? _prevTransit;

  _UdpStream._(this.socket, this.address, this.port) {
    _sub = socket.listen(_onEvent);
  }

  int get lost => max(0, maxSeq - receivedPackets);

  static Future<_UdpStream> open(InternetAddress address, int port) async {
    final bindAddr = address.type == InternetAddressType.IPv6
        ? InternetAddress.anyIPv6
        : InternetAddress.anyIPv4;
    final sock = await RawDatagramSocket.bind(bindAddr, 0);
    final stream = _UdpStream._(sock, address, port);

    // iperf3 UDP "connect" handshake: send 0x36373839 (host byte order,
    // little-endian on phones), wait for the server's reply.
    final hello = Uint8List.fromList([0x39, 0x38, 0x37, 0x36]);
    for (var attempt = 0; attempt < 5; attempt++) {
      sock.send(hello, address, port);
      try {
        await stream._handshake!.future.timeout(const Duration(seconds: 2));
        stream._handshake = null;
        return stream;
      } on TimeoutException {
        // retry
      }
    }
    await stream.close();
    throw IperfException(
        'No UDP reply from the server. Check that UDP port $port is open on the server and firewall.');
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    var dg = socket.receive();
    while (dg != null) {
      final hs = _handshake;
      if (hs != null && !hs.isCompleted) {
        hs.complete();
      } else if (counting && dg.data.length >= 12) {
        _onData(dg.data);
      }
      dg = socket.receive();
    }
  }

  void _onData(Uint8List data) {
    final bd = ByteData.sublistView(data);
    final sec = bd.getUint32(0);
    final usec = bd.getUint32(4);
    final seq = bd.getUint32(8);
    final arrival = DateTime.now().microsecondsSinceEpoch / 1e6;
    final transit = arrival - (sec + usec / 1e6);
    final prev = _prevTransit;
    if (prev != null) {
      final d = (transit - prev).abs();
      jitterSeconds += (d - jitterSeconds) / 16.0; // RFC 1889
    }
    _prevTransit = transit;
    receivedPackets++;
    bytes += data.length;
    if (seq > maxSeq) maxSeq = seq;
  }

  Future<void> close() async {
    await _sub.cancel();
    socket.close();
  }
}
