/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 *
 * Downloads the room TV's apps from Google Drive and installs any that are
 * missing or a different version. The list lives in a JSON file on Drive:
 *
 * {"apps": [{"package": "com.google.android.youtube.tv", "label": "YouTube",
 *            "versionCode": 803300320,
 *            "files": [{"name": "base.apk", "id": "<drive file id>"}, ...]}]}
 *
 * Downloads resume after a Wi-Fi drop, so a weak connection is slow, not broken.
 */
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'amadi_bridge.dart';
import 'amadi_settings.dart';

Uri driveDownloadUrl(String id) =>
    Uri.parse('https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t');

class _AppJob {
  final String package;
  final String label;
  final String version;
  final List<Map<String, dynamic>> files;
  String status = 'Waiting';
  double progress = 0;
  bool failed = false;
  _AppJob(this.package, this.label, this.version, this.files);
}

class AppInstallerPage extends StatefulWidget {
  /// Close by itself when everything is installed (used after the setup script).
  final bool closeWhenDone;
  /// Close even if something failed (power-on retries must not leave guests on this screen).
  final bool closeAlways;
  const AppInstallerPage({super.key, this.closeWhenDone = false, this.closeAlways = false});

  @override
  State<AppInstallerPage> createState() => _AppInstallerPageState();
}

class _AppInstallerPageState extends State<AppInstallerPage> {
  final List<_AppJob> _jobs = [];
  String _headline = 'Getting the app list…';
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    AmadiBridge.wifiHighPerf(false);
    super.dispose();
  }

  Future<void> _run() async {
    AmadiBridge.wifiHighPerf(true);
    final manifestId = context.read<AmadiSettings>().appsManifestId;
    if (manifestId.isEmpty) {
      setState(() {
        _headline = 'No app list is set. Add its Google Drive ID in settings.';
        _running = false;
      });
      return;
    }
    Map<String, dynamic> manifest;
    try {
      manifest = await _withRetry(() async => jsonDecode(await _getText(driveDownloadUrl(manifestId))) as Map<String, dynamic>);
    } catch (e) {
      setState(() {
        _headline = 'Could not download the app list. Check the Wi-Fi and try again.';
        _running = false;
      });
      if (widget.closeAlways) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (mounted) Navigator.of(context).maybePop();
      }
      return;
    }
    for (final a in (manifest['apps'] as List? ?? const [])) {
      final m = (a as Map).cast<String, dynamic>();
      _jobs.add(_AppJob(m['package'] as String, (m['label'] ?? m['package']) as String, '${m['versionCode'] ?? ''}',
          [for (final f in (m['files'] as List? ?? const [])) (f as Map).cast<String, dynamic>()]));
    }
    setState(() => _headline = 'Setting up apps');

    final base = (await getExternalStorageDirectory()) ?? await getApplicationSupportDirectory();
    for (final job in _jobs) {
      final have = await AmadiBridge.installedVersion(job.package);
      // Keep every TV on the EXACT Drive version: reinstall if the installed
      // versionCode differs at all (older or newer), download only when it differs.
      final haveCode = int.tryParse(have ?? '');
      final wantCode = int.tryParse(job.version);
      if (have != null && (wantCode == null || (haveCode != null && haveCode == wantCode))) {
        setState(() {
          job.status = 'Up to date';
          job.progress = 1;
        });
        continue;
      }
      final dir = Directory('${base.path}/dl/${job.package}')..createSync(recursive: true);
      try {
        final total = job.files.length;
        final paths = <String>[];
        for (var i = 0; i < total; i++) {
          final f = job.files[i];
          final out = File('${dir.path}/${f['name']}');
          await _withRetry(() => _download(driveDownloadUrl(f['id'] as String), out, (p) {
                if (mounted) {
                  setState(() {
                    job.status = 'Downloading';
                    job.progress = (i + p) / total * 0.9;
                  });
                }
              }));
          paths.add(out.path);
        }
        setState(() => job.status = 'Installing');
        final r = await AmadiBridge.installApks(paths);
        setState(() {
          job.failed = r != 'ok';
          job.status = r == 'ok' ? 'Installed' : 'Failed: $r';
          job.progress = r == 'ok' ? 1 : job.progress;
        });
      } catch (e) {
        setState(() {
          job.failed = true;
          job.status = 'Download failed. Try again later.';
        });
      } finally {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
    final anyFailed = _jobs.any((j) => j.failed);
    setState(() {
      _running = false;
      _headline = anyFailed ? 'Some apps did not install. Try again later.' : 'All apps are ready';
    });
    if ((!anyFailed && widget.closeWhenDone) || widget.closeAlways) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<T> _withRetry<T>(Future<T> Function() f) async {
    Object? last;
    for (var attempt = 0; attempt < 30; attempt++) {
      try {
        return await f();
      } catch (e) {
        last = e;
        await Future<void>.delayed(Duration(seconds: (3 + attempt * 3).clamp(3, 30)));
      }
    }
    throw last!;
  }

  Future<String> _getText(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final res = await (await client.getUrl(url)).close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return await res.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads to [out], resuming from what is already there.
  Future<void> _download(Uri url, File out, void Function(double) onProgress) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final have = out.existsSync() ? out.lengthSync() : 0;
      final req = await client.getUrl(url);
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final res = await req.close();
      if (res.statusCode == 416) return; // already complete
      final resumed = res.statusCode == 206;
      if (res.statusCode != 200 && !resumed) throw HttpException('HTTP ${res.statusCode}');
      final ctype = res.headers.contentType?.mimeType ?? '';
      if (ctype == 'text/html') throw const HttpException('Drive returned a web page, not the file (is it shared?)');
      final start = resumed ? have : 0;
      final total = res.contentLength < 0 ? -1 : res.contentLength + start;
      final sink = out.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      var got = start;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress(got / total);
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got < total) throw const HttpException('Download cut off');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_running,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1A1A),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 120, vertical: 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_headline, style: const TextStyle(color: Colors.white, fontSize: 28, fontFamily: 'Playfair Display')),
              const SizedBox(height: 8),
              Text(_running ? 'Please leave the TV on. This can take a few minutes.' : 'Press Back to close.',
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 32),
              for (final j in _jobs) ...[
                Row(children: [
                  SizedBox(width: 160, child: Text(j.label, style: const TextStyle(color: Colors.white, fontSize: 16))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: j.progress,
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        color: j.failed ? Colors.redAccent : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                      width: 260,
                      child: Text(j.status,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: j.failed ? Colors.redAccent : Colors.white70, fontSize: 13))),
                ]),
                const SizedBox(height: 18),
              ],
              const Spacer(),
              if (!_running)
                Focus(
                  autofocus: true,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Done'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
