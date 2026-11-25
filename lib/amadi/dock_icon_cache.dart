import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the dock's app artwork on disk so the tiles show instantly after the
/// TV kills and restarts the launcher (it does this whenever an app is playing,
/// because the TV has little memory). Without it, tiles show their names for a
/// few seconds while Android is asked for each icon again.
class DockIconCache {
  DockIconCache._();

  /// package -> (image bytes, is TV banner)
  static final Map<String, (Uint8List, bool)> mem = {};

  /// dock slot id -> package it opened last time (used before the app list loads).
  static final Map<String, String> lastPackage = {};

  static Directory? _dir;
  static SharedPreferences? _prefs;

  static Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final d = Directory('${(await getApplicationSupportDirectory()).path}/dock_icons');
    if (!d.existsSync()) d.createSync(recursive: true);
    return _dir = d;
  }

  static String _safe(String pkg) => pkg.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Called once in main() before the first frame.
  static Future<void> preload(SharedPreferences prefs, Iterable<String> slotIds) async {
    _prefs = prefs;
    try {
      final dir = await _folder();
      for (final id in slotIds) {
        final pkg = prefs.getString('dock_last_$id');
        if (pkg == null) continue;
        lastPackage[id] = pkg;
        final hit = _readSync(dir, pkg);
        if (hit != null) mem[pkg] = hit;
      }
    } catch (_) {}
  }

  static (Uint8List, bool)? _readSync(Directory dir, String pkg) {
    final b = File('${dir.path}/${_safe(pkg)}.banner');
    if (b.existsSync()) return (b.readAsBytesSync(), true);
    final i = File('${dir.path}/${_safe(pkg)}.icon');
    if (i.existsSync()) return (i.readAsBytesSync(), false);
    return null;
  }

  static void rememberSlot(String slotId, String pkg) {
    if (lastPackage[slotId] == pkg) return;
    lastPackage[slotId] = pkg;
    _prefs?.setString('dock_last_$slotId', pkg);
  }

  static Future<void> store(String pkg, Uint8List bytes, bool banner) async {
    final old = mem[pkg];
    mem[pkg] = (bytes, banner);
    if (old != null && old.$2 == banner && old.$1.length == bytes.length) return; // unchanged
    try {
      final dir = await _folder();
      final name = _safe(pkg);
      final other = File('${dir.path}/$name.${banner ? 'icon' : 'banner'}');
      if (other.existsSync()) other.deleteSync();
      await File('${dir.path}/$name.${banner ? 'banner' : 'icon'}').writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }
}
