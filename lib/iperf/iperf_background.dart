import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'iperf_client.dart';

/// Runs an [IperfClient] on its own background isolate.
///
/// At hundreds of Mbps a test handles thousands of socket events per second.
/// On the UI isolate that starves screen updates and touches (the app looks
/// hung); here the UI isolate only receives one interval per second.
/// Same interface as [IperfClient]: [intervals], [run], [stop], [dispose].
class BackgroundIperfClient {
  final IperfConfig config;
  BackgroundIperfClient(this.config);

  final _intervals = StreamController<IperfInterval>.broadcast();
  Stream<IperfInterval> get intervals => _intervals.stream;

  SendPort? _toWorker;
  bool _stopRequested = false;
  Isolate? _isolate;
  Completer<IperfResult>? _done;
  bool _abandoned = false;

  Future<IperfResult> run() async {
    final fromWorker = ReceivePort();
    final done = _done = Completer<IperfResult>();
    fromWorker.listen((Object? msg) {
      if (msg is SendPort) {
        _toWorker = msg;
        if (_stopRequested) msg.send('stop');
      } else if (msg is IperfInterval) {
        if (!_intervals.isClosed) _intervals.add(msg);
      } else if (msg is IperfResult) {
        if (!done.isCompleted) done.complete(msg);
      } else if (msg is Map && msg['error'] != null) {
        if (!done.isCompleted) done.completeError(IperfException(msg['error'] as String));
      } else if (msg is List) {
        // Uncaught error in the worker: [error, stack trace].
        if (!done.isCompleted) done.completeError(IperfException('Test engine error: ${msg.isEmpty ? '' : msg.first}'));
      } else if (msg == null) {
        // Worker exited.
        if (!done.isCompleted) done.completeError(IperfException('Test engine stopped unexpectedly'));
      }
    });
    try {
      _isolate = await Isolate.spawn<List<Object>>(_worker, [fromWorker.sendPort, config],
          onError: fromWorker.sendPort, onExit: fromWorker.sendPort, debugName: 'iperf ${config.label}');
      if (_abandoned) _isolate?.kill(priority: Isolate.immediate);
      return await done.future;
    } finally {
      fromWorker.close();
      _toWorker = null;
    }
  }

  void stop() {
    _stopRequested = true;
    _toWorker?.send('stop');
  }

  /// The network under this test went away (data SIM switch, new default
  /// network): end it now instead of waiting up to 3 s for the server's final
  /// results on a dead network, so the next test starts at once. The worker
  /// gets 0.3 s to tell the server (if that network still works), then is killed.
  void abandon() {
    if (_abandoned) return;
    _abandoned = true;
    stop();
    final d = _done;
    if (d != null && !d.isCompleted) d.completeError(IperfException('Abandoned: network changed'));
    Timer(const Duration(milliseconds: 300), () => _isolate?.kill(priority: Isolate.immediate));
  }

  Future<void> dispose() async {
    if (!_intervals.isClosed) await _intervals.close();
  }
}

Future<void> _worker(List<Object> args) async {
  final out = args[0] as SendPort;
  final config = args[1] as IperfConfig;
  final commands = ReceivePort();
  out.send(commands.sendPort);
  final client = IperfClient(config);
  final sub = commands.listen((Object? m) {
    if (m == 'stop') client.stop();
  });
  client.intervals.listen(out.send);
  try {
    out.send(await client.run());
  } on IperfException catch (e) {
    out.send({'error': e.message});
  } on SocketException catch (e) {
    out.send({'error': 'Network error: ${e.osError?.message ?? e.message}'});
  } catch (e) {
    out.send({'error': e.toString()});
  } finally {
    await sub.cancel();
    commands.close();
    await client.dispose();
  }
}
