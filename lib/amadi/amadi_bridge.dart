/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 */
import 'package:flutter/services.dart';

class AmadiBridge {
  static const _channel = MethodChannel('amadi/bridge');

  static void onScreenOn(void Function() handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'screenOn') handler();
      return null;
    });
  }

  static Future<String> connectWifi(String ssid, String password) async {
    try {
      return await _channel.invokeMethod<String>('connectWifi', {'ssid': ssid, 'password': password}) ?? 'error';
    } on PlatformException catch (e) {
      return 'error:${e.message}';
    }
  }
}
