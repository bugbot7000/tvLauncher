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

  static Future<bool> signOutNow() async {
    try {
      return await _channel.invokeMethod<bool>('signOutNow') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sets the TV's network/Bluetooth device name, e.g. "212 TV".
  static Future<bool> setDeviceName(String name) async {
    try {
      return await _channel.invokeMethod<bool>('setDeviceName', {'name': name}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enables (if disabled) and opens an app by package name.
  static Future<bool> openPackage(String package) async {
    try {
      return await _channel.invokeMethod<bool>('openPackage', {'package': package}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setSettingsHidden(bool hidden) async {
    try {
      await _channel.invokeMethod('setSettingsHidden', {'hidden': hidden});
    } catch (_) {}
  }

  /// True when the welcome was already dismissed since the TV last booted.
  static Future<bool> welcomeAlreadyShownThisBoot() async {
    try {
      return await _channel.invokeMethod<bool>('welcomeShownThisBoot') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markWelcomeShown() async {
    try {
      await _channel.invokeMethod('markWelcomeShown');
    } catch (_) {}
  }

  static Future<bool> removeOwner() async {
    try {
      return await _channel.invokeMethod<bool>('removeOwner') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Connects to the staff network, falling back to the guest network.
  static Future<String> ensureWifi(String ssid, String password, String fallbackSsid, String fallbackPassword) async {
    try {
      return await _channel.invokeMethod<String>('ensureWifi', {
            'ssid': ssid,
            'password': password,
            'fallbackSsid': fallbackSsid,
            'fallbackPassword': fallbackPassword,
          }) ??
          'error';
    } catch (e) {
      return 'error:$e';
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
