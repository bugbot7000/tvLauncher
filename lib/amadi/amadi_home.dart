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

import 'amadi_bridge.dart';
import 'amadi_settings.dart';
import 'amadi_settings_page.dart';
import 'guest_service.dart';
import 'weather_service.dart';

const _kWallpapers = [
  'assets/wallpapers/Wall_1.jpg',
  'assets/wallpapers/Wall_2.jpg',
  'assets/wallpapers/Wall_3.jpg',
  'assets/wallpapers/Wall_4.jpg',
  'assets/wallpapers/Wall_5.jpg',
  'assets/wallpapers/Wall_6.jpg',
  'assets/wallpapers/Wall_7.jpg',
];
const _kWallpaperInterval = Duration(seconds: 60);
String _blurOf(String p) => p.replaceFirst('.jpg', '_blur.jpg');
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
  int _wallIndex = 0;
  Timer? _wallTimer;
  bool _welcome = true;
  final FocusNode _rootFocus = FocusNode(debugLabel: 'amadi-root');
  final FocusNode _firstTileFocus = FocusNode(debugLabel: 'amadi-dock-0');
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _wallTimer = Timer.periodic(_kWallpaperInterval, (_) async {
      if (!mounted) return;
      final next = (_wallIndex + 1) % _kWallpapers.length;
      await precacheImage(AssetImage(_kWallpapers[next]), context);
      if (!mounted) return;
      await precacheImage(AssetImage(_blurOf(_kWallpapers[next])), context);
      if (mounted) setState(() => _wallIndex = next);
    });
    _clock = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    AmadiBridge.onScreenOn(_showWelcome);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await AmadiBridge.welcomeAlreadyShownThisBoot()) {
        setState(() => _welcome = false);
        _reveal.value = 1;
        _intro.value = 1;
        _firstTileFocus.requestFocus();
      } else {
        _intro.forward();
      }
      if (!mounted) return;
      _ensureWifi();
      final room = context.read<AmadiSettings>().roomNumber;
      if (room.isNotEmpty) AmadiBridge.setDeviceName('$room TV');
    });
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
    _ensureWifi();
  }

  void _dismissWelcome() {
    if (!_welcome) return;
    AmadiBridge.markWelcomeShown();
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
    _wallTimer?.cancel();
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
    final path = _kWallpapers[_wallIndex];
    Widget img(String p) => Image.asset(
          p,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Container(color: _kTeal),
        );
    // Pre-blurred copies are faded instead of blurring live, which the TV's GPU
    // cannot do smoothly.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 2000),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
      child: Stack(
        key: ValueKey<int>(_wallIndex),
        fit: StackFit.expand,
        children: [
          img(path),
          if (t < 1) Opacity(opacity: (1 - t).clamp(0.0, 1.0), child: img(_blurOf(path))),
        ],
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
      lines.add(Text('Dear ${guest.name},',
          style: const TextStyle(color: _kText, fontSize: 30, fontWeight: FontWeight.w500, height: 1.15)));
      lines.add(const Text('welcome to $_kResortName', style: TextStyle(color: _kMint, fontSize: 15)));
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
              child: ConstrainedBox(
                // Keep the big centred welcome inside the screen at any scale.
                constraints: BoxConstraints(maxWidth: (MediaQuery.of(context).size.width - 120) / scale),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
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
                _infoStrip(settings),
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
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(color: _kTeal.withOpacity(0.72), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(items[i][0], style: const TextStyle(color: _kMint, fontSize: 15)),
                const SizedBox(height: 2),
                Text(items[i][1],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _kText, fontSize: 20, fontWeight: FontWeight.w500)),
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
    if (a.packageName == slot.package) return a;
  }
  for (final a in apps) {
    final n = a.name.toLowerCase();
    if (slot.nameMatches.any(n.contains)) return a;
  }
  return null;
}

class _Dock extends StatefulWidget {
  final FocusNode firstFocus;
  final VoidCallback onOpenSettings;
  const _Dock({required this.firstFocus, required this.onOpenSettings});

  @override
  State<_Dock> createState() => _DockState();
}

class _DockState extends State<_Dock> {
  late final List<FocusNode> _nodes = [
    widget.firstFocus,
    for (var i = 1; i <= kDockSlots.length; i++) FocusNode(debugLabel: 'amadi-dock-$i'),
  ];

  @override
  void dispose() {
    for (final n in _nodes.skip(1)) {
      n.dispose();
    }
    super.dispose();
  }

  KeyEventResult _move(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (index < _nodes.length - 1) _nodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) _nodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.handled; // nothing else on screen takes focus
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final firstFocus = widget.firstFocus;
    final onOpenSettings = widget.onOpenSettings;
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
                  focusNode: _nodes[i],
                  onArrow: (e) => _move(i, e),
                ),
              ),
            ],
            const SizedBox(width: 12),
            SizedBox(
              width: 76,
              child: _FocusTile(
                focusNode: _nodes[kDockSlots.length],
                onArrow: (e) => _move(kDockSlots.length, e),
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
  final KeyEventResult Function(KeyEvent)? onArrow;
  const _AppTile({required this.slot, required this.app, this.focusNode, this.onArrow});

  @override
  State<_AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<_AppTile> {
  Future<Uint8List>? _image;
  String? _imagePkg;

  bool _isBanner = true;

  Future<Uint8List> _loadImage(AppsService apps, String pkg) async {
    final banner = await apps.getAppBanner(pkg);
    if (banner.isNotEmpty) {
      _isBanner = true;
      return banner;
    }
    _isBanner = false;
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
      onArrow: widget.onArrow,
      onActivate: () {
        if (app != null) {
          Navigator.of(context).push(PageRouteBuilder<void>(
            opaque: true,
            transitionDuration: const Duration(milliseconds: 250),
            pageBuilder: (_, __, ___) => _PrivacySplash(appName: widget.slot.label, onDone: () => appsService.launchApp(app)),
            transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
          ));
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
                  if (_isBanner) return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
                  // Phone apps only have a square icon: show it centred on black.
                  return Container(
                    color: Colors.black,
                    padding: const EdgeInsets.all(10),
                    child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
                  );
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
  final KeyEventResult Function(KeyEvent)? onArrow;
  final Widget Function(bool focused) builder;
  const _FocusTile({this.focusNode, required this.onActivate, this.onArrow, required this.builder});

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
        return widget.onArrow?.call(event) ?? KeyEventResult.ignored;
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


/// Shown for 6 seconds before a streaming app opens.
class _PrivacySplash extends StatefulWidget {
  final String appName;
  final VoidCallback onDone;
  const _PrivacySplash({required this.appName, required this.onDone});

  @override
  State<_PrivacySplash> createState() => _PrivacySplashState();
}

class _PrivacySplashState extends State<_PrivacySplash> with SingleTickerProviderStateMixin {
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..forward();

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      widget.onDone();
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.of(context).pop();
      });
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, __) => KeyEventResult.handled,
      child: Scaffold(
        backgroundColor: _kTeal,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 64,
                height: 64,
                child: AnimatedBuilder(
                  animation: _progress,
                  builder: (_, __) => CircularProgressIndicator(
                    value: _progress.value,
                    strokeWidth: 5,
                    color: _kMint,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Opening ${widget.appName}',
                  style: const TextStyle(color: _kText, fontSize: 28, fontWeight: FontWeight.w500)),
              const SizedBox(height: 14),
              const Text(
                'Sign in with your own account to watch. For your privacy, you will be signed out of all streaming apps on this TV automatically every 24 hours.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _kMint, fontSize: 17, height: 1.5),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
