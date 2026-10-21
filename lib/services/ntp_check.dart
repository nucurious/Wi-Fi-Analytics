import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Phone clock minus network time, in milliseconds (positive = the phone is ahead), measured with one
/// SNTP request. Null when the time server can't be reached. Logged at session start so the two phones
/// of a call pair can be lined up when their logs are merged.
Future<double?> ntpOffsetMs({String host = 'time.google.com', Duration timeout = const Duration(seconds: 3)}) async {
  RawDatagramSocket? socket;
  StreamSubscription<RawSocketEvent>? sub;
  try {
    final addr = (await InternetAddress.lookup(host, type: InternetAddressType.IPv4)).first;
    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket = sock;
    final done = Completer<double?>();
    final t1 = DateTime.now().toUtc().millisecondsSinceEpoch;
    sub = sock.listen((e) {
      if (e != RawSocketEvent.read || done.isCompleted) return;
      final d = sock.receive();
      if (d == null || d.data.length < 48) return;
      final t4 = DateTime.now().toUtc().millisecondsSinceEpoch;
      final b = ByteData.sublistView(d.data);
      double ts(int o) => (b.getUint32(o) - 2208988800) * 1000.0 + b.getUint32(o + 4) / 4294967296.0 * 1000.0;
      final t2 = ts(32), t3 = ts(40);
      done.complete(-(((t2 - t1) + (t3 - t4)) / 2));
    });
    sock.send(Uint8List(48)..[0] = 0x1B, addr, 123);
    return await done.future.timeout(timeout, onTimeout: () => null);
  } catch (_) {
    return null;
  } finally {
    await sub?.cancel();
    socket?.close();
  }
}
