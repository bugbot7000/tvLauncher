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

  static Future<Map<String, dynamic>> ownerStatus() async {
    try {
      final m = await _channel.invokeMethod<Map<dynamic, dynamic>>('ownerStatus');
      return (m ?? {}).cast<String, dynamic>();
    } on PlatformException {
      return {};
    } on MissingPluginException {
      return {};
    }
  }

  static Future<void> signOutNow() async {
    try {
      await _channel.invokeMethod('signOutNow');
    } catch (_) {}
  }

  static Future<void> setSettingsHidden(bool hidden) async {
    try {
      await _channel.invokeMethod('setSettingsHidden', {'hidden': hidden});
    } catch (_) {}
  }

  static Future<bool> removeOwner() async {
    try {
      return await _channel.invokeMethod<bool>('removeOwner') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> connectWifi(String ssid, String password) async {
    try {
      return await _channel.invokeMethod<String>('connectWifi', {'ssid': ssid, 'password': password}) ?? 'error';
    } on PlatformException catch (e) {
      return 'error:${e.message}';
    }
  }
}
