import 'dart:io';

/// Cleans a typed server address and splits off a port if one was included:
/// "10.0.0.5:5201" -> (10.0.0.5, 5201); "[2600::1]:5201" -> (2600::1, 5201);
/// "[2600::1]" -> (2600::1, null); spaces removed; a plain IPv6 address is
/// left as is (its colons are not a port).
(String, int?) splitHostPort(String raw) {
  // Drop spaces and invisible characters that copy/paste brings along.
  var s = raw.replaceAll(RegExp(r'[\s\u200B-\u200D\u2060\uFEFF\u00A0]'), '');
  s = s.replaceFirst(RegExp(r'^[a-zA-Z]+://'), ''); // pasted "http://..."
  if (s.endsWith('/')) s = s.substring(0, s.length - 1);
  final bracket = RegExp(r'^\[([0-9a-fA-F:.%]+)\](?::(\d{1,5}))?$').firstMatch(s);
  if (bracket != null) return (bracket[1]!, bracket[2] == null ? null : int.parse(bracket[2]!));
  final colons = ':'.allMatches(s).length;
  // IPv6 with the port stuck on the end, no brackets: "2600:...:9c38:5201".
  if (colons >= 2 && InternetAddress.tryParse(s) == null) {
    final i = s.lastIndexOf(':');
    final port = int.tryParse(s.substring(i + 1));
    final head = s.substring(0, i);
    if (port != null && port <= 65535 && InternetAddress.tryParse(head) != null) return (head, port);
  }
  if (colons == 1) {
    final i = s.lastIndexOf(':');
    final port = int.tryParse(s.substring(i + 1));
    if (port != null) return (s.substring(0, i), port);
  }
  return (s, null);
}

