/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Current weather from Open-Meteo (free, no API key).
 */
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'amadi_settings.dart';

class WeatherService extends ChangeNotifier {
  final AmadiSettings settings;
  int? _tempC;
  int? _code;
  Timer? _timer;

  WeatherService(this.settings) {
    refresh();
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => refresh());
  }

  int? get tempC => _tempC;
  String get description => _describe(_code);
  IconData get icon => _icon(_code);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': settings.weatherLat.toString(),
        'longitude': settings.weatherLon.toString(),
        'current': 'temperature_2m,weather_code',
        'timezone': 'auto',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return;
      final current = (jsonDecode(res.body) as Map<String, dynamic>)['current'] as Map<String, dynamic>?;
      if (current == null) return;
      _tempC = (current['temperature_2m'] as num?)?.round();
      _code = (current['weather_code'] as num?)?.toInt();
      notifyListeners();
    } catch (_) {
      // Keep last known value when offline.
    }
  }

  static String _describe(int? c) {
    if (c == null) return '';
    if (c == 0) return 'Clear';
    if (c <= 2) return 'Partly cloudy';
    if (c == 3) return 'Cloudy';
    if (c == 45 || c == 48) return 'Fog';
    if (c >= 51 && c <= 57) return 'Drizzle';
    if (c >= 61 && c <= 67) return 'Rain';
    if (c >= 71 && c <= 77) return 'Snow';
    if (c >= 80 && c <= 82) return 'Showers';
    if (c >= 95) return 'Thunderstorm';
    return '';
  }

  static IconData _icon(int? c) {
    if (c == null) return Icons.cloud_outlined;
    if (c == 0) return Icons.wb_sunny_outlined;
    if (c <= 3) return Icons.cloud_outlined;
    if (c >= 95) return Icons.thunderstorm_outlined;
    if (c >= 51) return Icons.water_drop_outlined;
    return Icons.cloud_outlined;
  }
}
