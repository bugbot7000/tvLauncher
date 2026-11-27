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

  /// versionCode of an installed app (as text), or null when it isn't installed.
  static Future<String?> installedVersion(String package) async {
    try {
      return await _channel.invokeMethod<String>('installedVersion', {'package': package});
    } catch (_) {
      return null;
    }
  }

  /// Installs an app from downloaded APK files (base first, then splits). "ok" or an error.
  static Future<String> installApks(List<String> paths) async {
    try {
      return await _channel.invokeMethod<String>('installApks', {'paths': paths}) ?? 'failed';
    } catch (e) {
      return '$e';
    }
  }

  /// Network details for the settings page: ssid, ip, wifiMac, ethMac, type.
  static Future<Map<String, String>> networkInfo() async {
    try {
      final m = await _channel.invokeMethod<Map<dynamic, dynamic>>('networkInfo');
      return (m ?? {}).map((k, v) => MapEntry('$k', '${v ?? ''}'));
    } catch (_) {
      return {};
    }
  }

  /// Media volume: {'max': steps, 'now': current}.
  static Future<Map<String, int>> volumeInfo() async {
    try {
      final m = await _channel.invokeMethod<Map<dynamic, dynamic>>('volumeInfo');
      return (m ?? {}).map((k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0));
    } catch (_) {
      return {};
    }
  }

  /// Lowers the volume right away if it is above the new limit.
  static Future<void> applyVolumeLimit() async {
    try {
      await _channel.invokeMethod('applyVolumeLimit');
    } catch (_) {}
  }

  /// Puts the TV into standby (like pressing the power button).
  static Future<void> sleepNow() async {
    try {
      await _channel.invokeMethod('sleepNow');
    } catch (_) {}
  }

  static Future<void> wifiHighPerf(bool on) async {
    try {
      await _channel.invokeMethod('wifiHighPerf', {'on': on});
    } catch (_) {}
  }
}
