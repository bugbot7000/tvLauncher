/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Power-on welcome over the blurred sunset video, then the home screen.
 */
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flauncher/models/app.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import 'amadi_bridge.dart';
import 'amadi_settings.dart';
import 'amadi_settings_page.dart';
import 'guest_service.dart';
import 'weather_service.dart';

const _kVideoAsset = 'assets/welcome.mp4';
const _kTeal = Color(0xFF04342C);
const _kMint = Color(0xFF9FE1CB);
const _kText = Color(0xFFF1EFE8);
const _kResortName = 'Amadi Beach Front Resort';

class AmadiHome extends StatefulWidget {
  const AmadiHome({super.key});

  @override
  State<AmadiHome> createState() => _AmadiHomeState();
}

class _AmadiHomeState extends State<AmadiHome> with TickerProviderStateMixin {
  late final AnimationController _reveal; // 0 = welcome, 1 = home
  late final AnimationController _intro; // welcome text entrance
  VideoPlayerController? _video;
  bool _videoFailed = false;
  bool _welcome = true;
  final FocusNode _rootFocus = FocusNode(debugLabel: 'amadi-root');
  final FocusNode _firstTileFocus = FocusNode(debugLabel: 'amadi-dock-0');
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _initVideo();
    _clock = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    AmadiBridge.onScreenOn(_showWelcome);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _intro.forward();
      _ensureWifi();
    });
  }

  Future<void> _initVideo() async {
    try {
      final c = VideoPlayerController.asset(_kVideoAsset,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _video = c);
    } catch (_) {
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  Future<void> _ensureWifi() async {
    final settings = context.read<AmadiSettings>();
    final network = context.read<NetworkService>();
    await Future<void>.delayed(const Duration(seconds: 8));
    if (!mounted) return;
    if (!network.hasInternetAccess && settings.wifiSsid.isNotEmpty) {
      await AmadiBridge.connectWifi(settings.wifiSsid, settings.wifiPassword);
    }
  }

  void _showWelcome() {
    if (!mounted) return;
    context.read<GuestService>().refresh();
    context.read<WeatherService>().refresh();
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _welcome = true);
    _reveal.value = 0;
    _intro.forward(from: 0);
    _rootFocus.requestFocus();
    _video?.play();
    _ensureWifi();
  }

  void _dismissWelcome() {
    if (!_welcome) return;
    setState(() => _welcome = false);
    _reveal.forward();
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _firstTileFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _reveal.dispose();
    _intro.dispose();
    _video?.dispose();
    _rootFocus.dispose();
    _firstTileFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guest = context.watch<GuestService>().guest;
    final settings = context.watch<AmadiSettings>();
    final online = context.watch<NetworkService>().hasInternetAccess;
    final weather = context.watch<WeatherService>();
    return PopScope(
      canPop: false,
      child: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (_welcome && event is KeyDownEvent) {
            _dismissWelcome();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _welcome ? _dismissWelcome : null,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: AnimatedBuilder(
              animation: Listenable.merge([_reveal, _intro]),
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_reveal.value);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _background(t),
                    // Darken slightly so text stays readable on bright frames.
                    Container(color: _kTeal.withOpacity(0.18 + 0.2 * (1 - t))),
                    IgnorePointer(
                      ignoring: _welcome,
                      child: Opacity(
                        opacity: t,
                        child: _homeUi(settings, online, weather),
                      ),
                    ),
                    _greeting(t, guest, settings.roomNumber),
                    if (_welcome)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 32,
                        child: Opacity(
                          opacity: (_intro.value * 2 - 1).clamp(0.0, 1.0) * 0.7,
                          child: const Text('Press any button to continue',
                              textAlign: TextAlign.center, style: TextStyle(color: _kText, fontSize: 13)),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _background(double t) {
    Widget child;
    final v = _video;
    if (v != null && v.value.isInitialized) {
      child = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v)),
      );
    } else {
      child = Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0C447C), Color(0xFF854F0B), Color(0xFF412402)],
          ),
        ),
      );
    }
    final sigma = 14.0 * (1 - t);
    if (sigma < 0.5) return child;
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.clamp),
        child: child,
      ),
    );
  }

  Widget _greeting(double t, Guest? guest, String room) {
    final introT = Curves.easeOut.transform(_intro.value);
    final scale = ui.lerpDouble(2.0, 1.0, t)!;
    final align = Alignment.lerp(Alignment.center, Alignment.topRight, t)!;
    final lineAlign = Alignment.lerp(Alignment.center, Alignment.centerRight, t)!;

    final lines = <Widget>[];
    if (guest != null) {
      lines.add(const Text('Welcome to $_kResortName', style: TextStyle(color: _kMint, fontSize: 14)));
      lines.add(Text(guest.display,
          style: const TextStyle(color: _kText, fontSize: 30, fontWeight: FontWeight.w500, height: 1.15)));
      if (room.isNotEmpty) {
        lines.add(Text('Room $room', style: const TextStyle(color: _kMint, fontSize: 12)));
      }
    } else {
      // Empty room: the big welcome only, nothing left in the corner afterwards.
      lines.add(Opacity(
        opacity: 1 - t,
        child: const Text('Welcome to $_kResortName',
            style: TextStyle(color: _kText, fontSize: 24, fontWeight: FontWeight.w500)),
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 32, 48, 32),
      child: Align(
        alignment: align,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - introT)),
          child: Opacity(
            opacity: introT,
            child: Transform.scale(
              scale: scale,
              alignment: align,
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final l in lines) Align(alignment: lineAlign, child: l)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _homeUi(AmadiSettings settings, bool online, WeatherService weather) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 32, 48, 28),
      child: Stack(
        children: [
          Align(alignment: Alignment.topLeft, child: _clockAndWeather(online, weather, settings.weatherPlace)),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: _infoStrip(settings)),
                const SizedBox(height: 18),
                _Dock(firstFocus: _firstTileFocus, onOpenSettings: _openSettings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _clockAndWeather(bool online, WeatherService weather, String place) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(DateFormat('h:mm a').format(_now),
            style: const TextStyle(color: _kText, fontSize: 44, fontWeight: FontWeight.w500, height: 1)),
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(DateFormat('EEEE, d MMMM').format(_now), style: const TextStyle(color: _kMint, fontSize: 14)),
          const SizedBox(width: 8),
          Icon(online ? Icons.wifi : Icons.wifi_off,
              size: 16, color: online ? const Color(0xFF5DCAA5) : const Color(0xFFEF9F27)),
        ]),
        if (weather.tempC != null) ...[
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(weather.icon, size: 22, color: _kText),
            const SizedBox(width: 6),
            Text('${weather.tempC}°C',
                style: const TextStyle(color: _kText, fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Text([weather.description, place].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(color: _kMint, fontSize: 12)),
          ]),
        ],
      ],
    );
  }

  Widget _infoStrip(AmadiSettings s) {
    final items = <List<String>>[
      ['Breakfast', s.breakfast],
      ['Housekeeping', s.housekeeping],
      ['Front desk', s.frontDesk],
      ['Restaurant', s.restaurant],
    ].where((e) => e[1].isNotEmpty).toList();
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: _kTeal.withOpacity(0.72), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(items[i][0], style: const TextStyle(color: _kMint, fontSize: 11)),
                const SizedBox(height: 2),
                Text(items[i][1],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _kText, fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openSettings() async {
    final ok = await showPasscodeDialog(context);
    if (!ok || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AmadiSettingsPage()));
    if (mounted) _firstTileFocus.requestFocus();
  }
}

/// Finds the installed app for a dock slot: staff choice first, then by name.
App? resolveDockApp(DockSlot slot, List<App> apps, AmadiSettings settings) {
  final chosen = settings.dockPackage(slot.id);
  if (chosen != null) {
    for (final a in apps) {
      if (a.packageName == chosen) return a;
    }
  }
  for (final a in apps) {
    final n = a.name.toLowerCase();
    if (slot.nameMatches.any(n.contains)) return a;
  }
  return null;
}

class _Dock extends StatelessWidget {
  final FocusNode firstFocus;
  final VoidCallback onOpenSettings;
  const _Dock({required this.firstFocus, required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final apps = context.watch<AppsService>().applications;
    final settings = context.watch<AmadiSettings>();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0x2EF1EFE8), borderRadius: BorderRadius.circular(18)),
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Row(
          children: [
            for (var i = 0; i < kDockSlots.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: _AppTile(
                  slot: kDockSlots[i],
                  app: resolveDockApp(kDockSlots[i], apps, settings),
                  focusNode: i == 0 ? firstFocus : null,
                ),
              ),
            ],
            const SizedBox(width: 12),
            SizedBox(
              width: 76,
              child: _FocusTile(
                onActivate: onOpenSettings,
                builder: (focused) => Container(
                  height: 76,
                  decoration: BoxDecoration(color: const Color(0xFFD3D1C7), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.settings_outlined, color: Color(0xFF2C2C2A), size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppTile extends StatefulWidget {
  final DockSlot slot;
  final App? app;
  final FocusNode? focusNode;
  const _AppTile({required this.slot, required this.app, this.focusNode});

  @override
  State<_AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<_AppTile> {
  Future<Uint8List>? _image;
  String? _imagePkg;

  Future<Uint8List> _loadImage(AppsService apps, String pkg) async {
    final banner = await apps.getAppBanner(pkg);
    if (banner.isNotEmpty) return banner;
    return apps.getAppIcon(pkg);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final appsService = context.read<AppsService>();
    if (app != null && _imagePkg != app.packageName) {
      _imagePkg = app.packageName;
      _image = _loadImage(appsService, app.packageName);
    }
    return _FocusTile(
      focusNode: widget.focusNode,
      onActivate: () {
        if (app != null) {
          appsService.launchApp(app);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${widget.slot.label} is not installed on this TV. Please contact the front desk.'),
          ));
        }
      },
      builder: (focused) => Container(
        height: 76,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: const Color(0xFFF1EFE8), borderRadius: BorderRadius.circular(12)),
        child: app == null
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.slot.label, style: const TextStyle(color: Color(0xFF2C2C2A), fontSize: 14)),
                  const Text('Not installed', style: TextStyle(color: Color(0xFF888780), fontSize: 11)),
                ]),
              )
            : FutureBuilder<Uint8List>(
                future: _image,
                builder: (context, snap) {
                  final bytes = snap.data;
                  if (bytes == null || bytes.isEmpty) {
                    return Center(
                        child: Text(widget.slot.label,
                            style: const TextStyle(color: Color(0xFF2C2C2A), fontSize: 14)));
                  }
                  return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
                },
              ),
      ),
    );
  }
}

/// A D-pad focusable tile with a white focus ring and slight zoom.
class _FocusTile extends StatefulWidget {
  final FocusNode? focusNode;
  final VoidCallback onActivate;
  final Widget Function(bool focused) builder;
  const _FocusTile({this.focusNode, required this.onActivate, required this.builder});

  @override
  State<_FocusTile> createState() => _FocusTileState();
}

class _FocusTileState extends State<_FocusTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onActivate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onActivate,
        child: AnimatedScale(
          scale: _focused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 2.5),
            ),
            child: widget.builder(_focused),
          ),
        ),
      ),
    );
  }
}
