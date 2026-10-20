import 'dart:math';

/// A public iperf3 server and the ports it listens on.
class PublicServer {
  final String name;
  final String host;
  final int firstPort;
  final int lastPort;
  final bool udp; // accepts UDP tests (-u)
  final bool ipv6;
  const PublicServer(this.name, this.host, this.firstPort, this.lastPort, {this.udp = false, this.ipv6 = false});

  int get portCount => lastPort - firstPort + 1;
  bool hasPort(int p) => p >= firstPort && p <= lastPort;
}

/// US public iperf3 servers, nearest to Denver first (Dallas, Chicago,
/// Atlanta, Boston). When a test can't start on one, the app moves to the next.
const publicServers = <PublicServer>[
  PublicServer('Clouvider Dallas', 'dal.speedtest.clouvider.net', 5200, 5209, udp: true, ipv6: true),
  PublicServer('Leaseweb Dallas', 'speedtest.dal13.us.leaseweb.net', 5201, 5210, ipv6: true),
  PublicServer('IS.CC Dallas', 'dfw.speedtest.is.cc', 5203, 5210),
  PublicServer('Dallas 66.35.27.207', '66.35.27.207', 30001, 30009),
  PublicServer('Dallas 89.187.164.1', '89.187.164.1', 5201, 5201),
  PublicServer('Chicago 185.93.1.65', '185.93.1.65', 5201, 5201, udp: true),
  PublicServer('Clouvider Chicago', 'chi.speedtest.clouvider.net', 5201, 5209, ipv6: true),
  PublicServer('Leaseweb Chicago', 'speedtest.chi11.us.leaseweb.net', 5201, 5210, ipv6: true),
  PublicServer('Clouvider Atlanta', 'atl.speedtest.clouvider.net', 5200, 5209, udp: true, ipv6: true),
  PublicServer('Atlanta 185.152.66.67', '185.152.66.67', 5201, 5201, udp: true),
  PublicServer('Boston 109.61.86.65', '109.61.86.65', 5201, 5201, udp: true),
];

PublicServer? publicServerFor(String host) {
  final h = host.trim().toLowerCase();
  for (final s in publicServers) {
    if (s.host == h) return s;
  }
  return null;
}

final _rnd = Random();

/// Where to try next after a test could not start on [host]:[port].
///
/// A busy server ("server is busy") gets its next port first, since each port
/// runs one test at a time. Anything else (timeout, unreachable, not found)
/// moves on to the next server in [publicServers]. UDP tests skip servers
/// that don't accept UDP. [tried] holds "host:port" already used for this
/// test; returns null when nothing is left.
(String, int)? nextServer(String host, int port,
    {required bool busy, bool refused = false, required bool udp, required Set<String> tried}) {
  final current = publicServerFor(host);
  // A server not in the public list (e.g. your own on 5201-5205): another port first when
  // this one is busy or not listening.
  if (current == null && (busy || refused)) {
    final ports = port >= 5201 && port <= 5205 ? [for (var p = 5201; p <= 5205; p++) p] : [for (var i = 1; i <= 4; i++) port + i];
    for (final p in ports) {
      if (!tried.contains('$host:$p')) return (host, p);
    }
  }
  if (busy && current != null && current.portCount > 1 && (!udp || current.udp)) {
    for (var i = 1; i < current.portCount; i++) {
      final p = current.firstPort + (port - current.firstPort + i) % current.portCount;
      if (!tried.contains('${current.host}:$p')) return (current.host, p);
    }
  }
  final start = current == null ? 0 : publicServers.indexOf(current) + 1;
  for (var i = 0; i < publicServers.length; i++) {
    final s = publicServers[(start + i) % publicServers.length];
    if (s == current) continue;
    if (udp && !s.udp) continue;
    if (tried.any((t) => t.startsWith('${s.host}:'))) continue;
    // Random port in the range spreads load, so we hit busy ports less often.
    return (s.host, s.firstPort + _rnd.nextInt(s.portCount));
  }
  return null;
}
