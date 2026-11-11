import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Outside weather at a position, as one line for the run summary, e.g.
/// "8.4 C (feels 5.9 C), humidity 41%, wind 14 km/h, clear sky".
/// Lets phone temperature and thermal flags be read against the climate the test ran in.
/// One HTTPS request to the free Open-Meteo service (no account or key). The position is
/// rounded to two decimals (about 1 km) before it is sent. Null when it can't be fetched.
Future<String?> outsideWeather(double lat, double lon, {Duration timeout = const Duration(seconds: 5)}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(2),
      'longitude': lon.toStringAsFixed(2),
      'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code',
    });
    final req = await client.getUrl(uri).timeout(timeout);
    final res = await req.close().timeout(timeout);
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join().timeout(timeout);
    final cur = (jsonDecode(body) as Map<String, dynamic>)['current'] as Map<String, dynamic>?;
    if (cur == null) return null;
    final t = cur['temperature_2m'] as num?;
    if (t == null) return null;
    final feels = cur['apparent_temperature'] as num?;
    final hum = cur['relative_humidity_2m'] as num?;
    final wind = cur['wind_speed_10m'] as num?;
    final code = (cur['weather_code'] as num?)?.toInt();
    String f(num c) => '${(c * 9 / 5 + 32).round()} F';
    return [
      '${t.toStringAsFixed(1)} C / ${f(t)}${feels == null ? '' : ' (feels ${feels.toStringAsFixed(1)} C / ${f(feels)})'}',
      if (hum != null) 'humidity ${hum.round()}%',
      if (wind != null) 'wind ${wind.round()} km/h',
      if (code != null) _sky(code),
    ].join(', ');
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// WMO weather code to words.
String _sky(int c) {
  if (c == 0) return 'clear sky';
  if (c <= 2) return 'partly cloudy';
  if (c == 3) return 'overcast';
  if (c == 45 || c == 48) return 'fog';
  if (c >= 51 && c <= 57) return 'drizzle';
  if (c >= 61 && c <= 67) return 'rain';
  if (c >= 71 && c <= 77) return 'snow';
  if (c >= 80 && c <= 82) return 'rain showers';
  if (c == 85 || c == 86) return 'snow showers';
  if (c >= 95) return 'thunderstorm';
  return 'weather code $c';
}
