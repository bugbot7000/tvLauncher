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
import 'dock_icon_cache.dart';
import 'amadi_settings_page.dart';
import 'app_installer_page.dart';
import 'guest_service.dart';
import 'ticker_service.dart';
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
const _kShadow = [
  Shadow(color: Color(0xB3000000), blurRadius: 12, offset: Offset(0, 2)),
  Shadow(color: Color(0x80000000), blurRadius: 3, offset: Offset(0, 1)),
];
const _kSerif = 'Playfair Display';

class AmadiHome extends StatefulWidget {
  const AmadiHome({super.key});

  @override
  State<AmadiHome> createState() => _AmadiHomeState();
}

class _AmadiHomeState extends State<AmadiHome> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _reveal; // 0 = welcome, 1 = home
  late final AnimationController _intro; // welcome text entrance
  int _wallIndex = 0;
  int _prevWallIndex = 0;
  late final AnimationController _wallFade;
  late final AnimationController _pulse;
  Timer? _wallTimer;
  bool _welcome = true;
  final FocusNode _rootFocus = FocusNode(debugLabel: 'amadi-root');
  final FocusNode _firstTileFocus = FocusNode(debugLabel: 'amadi-dock-0');
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reveal = AnimationController(vsync: this, animationBehavior: AnimationBehavior.preserve, duration: const Duration(milliseconds: 1600));
    _intro = AnimationController(vsync: this, animationBehavior: AnimationBehavior.preserve, duration: const Duration(milliseconds: 1100));
    _pulse = AnimationController(vsync: this, animationBehavior: AnimationBehavior.preserve, duration: const Duration(milliseconds: 1400));
    _wallFade = AnimationController(vsync: this, animationBehavior: AnimationBehavior.preserve, duration: const Duration(milliseconds: 2000), value: 1);
    _wallTimer = Timer.periodic(_kWallpaperInterval, (_) async {
      if (!mounted) return;
      // Don't decode wallpapers while an app is playing in front.
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      final next = (_wallIndex + 1) % _kWallpapers.length;
      await precacheImage(AssetImage(_kWallpapers[next]), context);
      if (!mounted) return;
      await precacheImage(AssetImage(_blurOf(_kWallpapers[next])), context);
      if (!mounted) return;
      setState(() {
        _prevWallIndex = _wallIndex;
        _wallIndex = next;
      });
      _wallFade.forward(from: 0);
    });
    _clock = Timer.periodic(const Duration(seconds: 5), (_) {
      final n = DateTime.now();
      if (mounted && n.minute != _now.minute) setState(() => _now = n);
    });
    AmadiBridge.onScreenOn(() {
      _showWelcome();
      _ensureWifi();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final alreadyShown = await AmadiBridge.welcomeAlreadyShownThisBoot();
      if (alreadyShown) {
        setState(() => _welcome = false);
        _reveal.value = 1;
        _intro.value = 1;
        _firstTileFocus.requestFocus();
      } else {
        _intro.forward();
        _pulse.repeat(reverse: true);
      }
      if (!mounted) return;
      final settings = context.read<AmadiSettings>();
      // After power-on, finish any app that a past setup could not install.
      var missing = false;
      if (!alreadyShown && !settings.runSetupPending) {
        for (final slot in kDockSlots) {
          if (await AmadiBridge.installedVersion(slot.package) == null) missing = true;
        }
      }
      if (settings.runSetupPending || missing) {
        // Started by the setup script: install the apps, then carry on.
        await settings.clearRunSetup();
        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AppInstallerPage(closeWhenDone: true)));
        }
      }
      // Join the default Wi-Fi only on the first start after power-on (not when
      // Android restarts the launcher after an app), so a network picked by hand stays.
      if (!alreadyShown) _ensureWifi();
      final room = context.read<AmadiSettings>().roomNumber;
      if (room.isNotEmpty) AmadiBridge.setDeviceName('$room TV');
    });
  }

  Future<void> _ensureWifi() async {
    final s = context.read<AmadiSettings>();
    await Future<void>.delayed(const Duration(seconds: 5));
    if (!mounted || s.wifiSsid.isEmpty) return;
    await AmadiBridge.ensureWifi(s.wifiSsid, s.wifiPassword, s.fallbackSsid, s.fallbackPassword);
  }

  void _showWelcome() {
    if (!mounted) return;
    context.read<GuestService>().refresh();
    context.read<WeatherService>().refresh();
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _welcome = true);
    _pulse.repeat(reverse: true);
    _reveal.value = 0;
    _intro.forward(from: 0);
    _rootFocus.requestFocus();
  }

  void _dismissWelcome() {
    if (!_welcome) return;
    AmadiBridge.markWelcomeShown();
    setState(() => _welcome = false);
    _pulse.stop();
    _reveal.forward();
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _firstTileFocus.requestFocus();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // While an app (YouTube etc.) is in front, give its memory back: this TV has ~440 MB RAM.
    if (state == AppLifecycleState.paused) {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
    // Back on the home screen (e.g. after closing an app): re-check the guest name.
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<GuestService>().refresh();
      context.read<TickerService>().refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _reveal.dispose();
    _intro.dispose();
    _wallFade.dispose();
    _pulse.dispose();
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
          if (_handleDigit(event)) return KeyEventResult.handled;
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _welcome ? _dismissWelcome : null,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'Roboto'),
              child: AnimatedBuilder(
              animation: Listenable.merge([_reveal, _intro, _wallFade]),
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_reveal.value);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _background(t),
                    // Darken slightly so text stays readable on bright frames.
                    Container(color: _kTeal.withOpacity(0.18 + 0.2 * (1 - t))),
                    if (t > 0) IgnorePointer(child: Opacity(opacity: t, child: const _Scrims())),
                    IgnorePointer(
                      ignoring: _welcome,
                      child: _homeUi(settings, online, weather, _reveal.value),
                    ),
                    _greeting(t, guest, settings.roomNumber),
                    if (_welcome)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 32,
                        child: RepaintBoundary(child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (_, __) => Opacity(
                            opacity: (_intro.value * 2 - 1).clamp(0.0, 1.0) * (0.25 + 0.7 * _pulse.value),
                            child: const Text('Press any button to continue',
                                textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15)),
                          ),
                        )),
                      ),
                  ],
                );
              },
            ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _background(double t) {
    Widget img(String p) => Image.asset(
          p,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Container(color: _kTeal),
        );
    // Pre-blurred copies are faded instead of blurring live (the TV GPU is too slow).
    Widget layer(int i) {
      final path = _kWallpapers[i];
      return Stack(fit: StackFit.expand, children: [
        img(path),
        if (t < 1) Opacity(opacity: (1 - t).clamp(0.0, 1.0), child: img(_blurOf(path))),
      ]);
    }

    final f = Curves.easeInOut.transform(_wallFade.value);
    return Stack(fit: StackFit.expand, children: [
      if (f < 1) layer(_prevWallIndex),
      Opacity(opacity: f, child: layer(_wallIndex)),
    ]);
  }

  Widget _greeting(double t, Guest? guest, String room) {
    final introT = Curves.easeOut.transform(_intro.value);
    final scale = ui.lerpDouble(1.6, 1.0, t)!;
    final align = Alignment.lerp(Alignment.center, Alignment.topRight, t)!;
    final lineAlign = Alignment.lerp(Alignment.center, Alignment.centerRight, t)!;
    // Shadows only on the home screen, not on the power-on greeting.
    final shadows = t > 0.05
        ? [for (final sh in _kShadow) Shadow(color: sh.color.withOpacity(sh.color.opacity * t), blurRadius: sh.blurRadius, offset: sh.offset)]
        : const <Shadow>[];

    final lines = <Widget>[];
    if (guest != null) {
      lines.add(Text('Dear ${guest.name},',
          style: TextStyle(fontFamily: _kSerif, color: Colors.white, fontSize: 30, fontWeight: FontWeight.w500, height: 1.15, shadows: shadows)));
      // Half the name size, always one line (shrinks to fit rather than wrap or cut).
      lines.add(FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Welcome to $_kResortName',
              maxLines: 1, softWrap: false, style: TextStyle(color: Colors.white, fontSize: 15, shadows: shadows))));
      if (room.isNotEmpty && t > 0) {
        lines.add(Opacity(
            opacity: t,
            child: Text('Room $room', style: TextStyle(color: Colors.white, fontSize: 13, shadows: shadows))));
      }
    } else {
      if (t < 1) {
        lines.add(Opacity(
          opacity: 1 - t,
          child: const Text('Welcome to $_kResortName',
              style: TextStyle(fontFamily: _kSerif, color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500)),
        ));
      }
      // Empty room: the corner still shows which room this is.
      if (room.isNotEmpty && t > 0) {
        lines.add(Opacity(
            opacity: t,
            child: Text('Room $room',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500, shadows: shadows))));
      }
    }
    if (lines.isEmpty) return const SizedBox.shrink();

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

  /// [r] runs 0 to 1 as the welcome panel is dismissed: the clock block glides in
  /// from the right, the dock rises from the bottom, then the ticker fades in.
  Widget _homeUi(AmadiSettings settings, bool online, WeatherService weather, double r) {
    double phase(double a, double b) => Curves.easeOutCubic.transform(((r - a) / (b - a)).clamp(0.0, 1.0));
    // Never fully 0: at 1/255 the parts are still drawn (invisibly) during the
    // welcome, so artwork, text and shaders are ready before the animation starts.
    const warm = 0.005;
    final clock = phase(0.30, 0.80);
    final dock = phase(0.40, 0.90);
    final ticker = phase(0.75, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 32, 48, 28),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Opacity(
              opacity: clock < warm ? warm : clock,
              child: Transform.translate(
                offset: Offset(140 * (1 - clock), 0),
                child: RepaintBoundary(child: _clockAndWeather(online, weather, settings.weatherPlace)),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(opacity: ticker < warm ? warm : ticker, child: const RepaintBoundary(child: _Ticker())),
                const SizedBox(height: 18),
                Opacity(
                  opacity: dock < warm ? warm : dock,
                  child: Transform.translate(
                    offset: Offset(0, 160 * (1 - dock)),
                    child: RepaintBoundary(child: _Dock(firstFocus: _firstTileFocus, onOpenSettings: _openSettings)),
                  ),
                ),
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
            style: const TextStyle(fontFamily: 'Roboto', color: Colors.white, fontSize: 46, fontWeight: FontWeight.w500, height: 1, shadows: _kShadow)),
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(DateFormat('EEEE, d MMMM').format(_now), style: const TextStyle(color: Colors.white, fontSize: 14, shadows: _kShadow)),
          const SizedBox(width: 8),
          Icon(online ? Icons.wifi : Icons.wifi_off,
              size: 16, color: Colors.white, shadows: _kShadow),
        ]),
        if (weather.tempC != null) ...[
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(weather.icon, size: 22, color: Colors.white, shadows: _kShadow),
            const SizedBox(width: 6),
            Text('${weather.tempC}°C',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500, shadows: _kShadow)),
            const SizedBox(width: 8),
            Text([weather.description, place].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(color: Colors.white, fontSize: 12, shadows: _kShadow)),
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
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(items[i][1],
                      maxLines: 1,
                      style: const TextStyle(color: _kText, fontSize: 20, fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AmadiSettingsPage(onShowWelcome: _showWelcome)));
    if (mounted) _firstTileFocus.requestFocus();
  }

  /// Staff type the passcode on the remote's number keys while on the home screen.
  String _typed = '';
  DateTime _lastDigit = DateTime.fromMillisecondsSinceEpoch(0);

  bool _handleDigit(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final label = event.logicalKey.keyLabel;
    final digit = label.length == 1 && '0123456789'.contains(label)
        ? label
        : (label.startsWith('Numpad ') && label.length == 8 ? label.substring(7) : null);
    if (digit == null) return false;
    final now = DateTime.now();
    if (now.difference(_lastDigit) > const Duration(seconds: 4)) _typed = '';
    _lastDigit = now;
    _typed = (_typed + digit);
    if (_typed.length > kSettingsPasscode.length) _typed = _typed.substring(_typed.length - kSettingsPasscode.length);
    if (_typed == kSettingsPasscode) {
      _typed = '';
      _openSettings();
    }
    return true;
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
    for (var i = 1; i < kDockSlots.length; i++) FocusNode(debugLabel: 'amadi-dock-$i'),
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
    final apps = context.watch<AppsService>().applications;
    final settings = context.watch<AmadiSettings>();
    final slots = settings.youtubeOnly ? kDockSlots.where((s) => s.id == 'youtube').toList() : kDockSlots;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x40FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x59FFFFFF), width: 1),
      ),
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        // Tiles keep the four-app width; fewer apps sit centred.
        child: LayoutBuilder(builder: (context, c) {
          final n = kDockSlots.length;
          final tileW = (c.maxWidth - 12 * (n - 1)) / n;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < slots.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                SizedBox(
                  width: tileW,
                  child: _AppTile(
                    slot: slots[i],
                    app: resolveDockApp(slots[i], apps, settings),
                    focusNode: _nodes[i],
                    onArrow: (e) => _move(i, e),
                  ),
                ),
              ],
            ],
          );
        }),
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
  String? _refreshedPkg;

  /// Shows cached artwork straight away; asks Android once per launcher start
  /// for fresh artwork (picks up app updates) and saves it to disk.
  void _refresh(AppsService apps, String pkg) {
    if (_refreshedPkg == pkg) return;
    _refreshedPkg = pkg;
    () async {
      try {
        final banner = await apps.getAppBanner(pkg);
        if (banner.isNotEmpty) {
          await DockIconCache.store(pkg, banner, true);
        } else {
          final icon = await apps.getAppIcon(pkg);
          if (icon.isNotEmpty) await DockIconCache.store(pkg, icon, false);
        }
      } catch (_) {}
      if (mounted) setState(() {});
    }();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final appsService = context.read<AppsService>();
    final loading = !appsService.initialized;
    // Before the app list has loaded, draw what this tile showed last time.
    final pkg = app?.packageName ?? (loading ? DockIconCache.lastPackage[widget.slot.id] : null);
    if (app != null) {
      DockIconCache.rememberSlot(widget.slot.id, app.packageName);
      _refresh(appsService, app.packageName);
    }
    final cached = pkg == null ? null : DockIconCache.mem[pkg];
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
        child: cached != null
            ? (cached.$2
                ? Image.memory(cached.$1, fit: BoxFit.cover, gaplessPlayback: true)
                // Phone apps only have a square icon: show it centred on black.
                : Container(
                    color: Colors.black,
                    padding: const EdgeInsets.all(10),
                    child: Image.memory(cached.$1, fit: BoxFit.contain, gaplessPlayback: true),
                  ))
            : Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.slot.label, style: const TextStyle(color: Color(0xFF2C2C2A), fontSize: 14)),
                  if (app == null && !loading)
                    const Text('Not installed', style: TextStyle(color: Color(0xFF888780), fontSize: 11)),
                ]),
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
      AnimationController(vsync: this, animationBehavior: AnimationBehavior.preserve, duration: const Duration(seconds: 5))..forward();

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
                "Sign in with your own account to watch. For your privacy, you'll be signed out automatically after checkout.",
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


/// One message at a time from the TV Tickr sheet, fading every 8 seconds.
class _Ticker extends StatefulWidget {
  const _Ticker();
  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
      vsync: this, animationBehavior: AnimationBehavior.preserve, duration: const Duration(milliseconds: 700), value: 1);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _next());
  }

  Future<void> _next() async {
    final n = context.read<TickerService>().messages.length;
    if (n < 2 || !mounted) return;
    await _fade.reverse();
    if (!mounted) return;
    setState(() => _index = (_index + 1) % n);
    await _fade.forward();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fade.dispose();
    super.dispose();
  }

  static IconData _iconFor(String m) {
    final t = m.toLowerCase();
    if (t.contains('breakfast') || t.contains('lunch') || t.contains('dinner') || t.contains('restaurant menu')) {
      return Icons.free_breakfast_outlined;
    }
    if (t.contains('housekeeping') || t.contains('clean')) return Icons.cleaning_services_outlined;
    if (t.contains('checkout') || t.contains('check-out') || t.contains('check out')) return Icons.logout;
    if (t.contains('dial') || t.contains('call') || t.contains('phone')) return Icons.phone_outlined;
    if (t.contains('wifi') || t.contains('wi-fi')) return Icons.wifi;
    if (t.contains('pool') || t.contains('beach')) return Icons.beach_access_outlined;
    return Icons.info_outline;
  }

  @override
  Widget build(BuildContext context) {
    final msgs = context.watch<TickerService>().messages;
    if (msgs.isEmpty) return const SizedBox(height: 44);
    final i = _index % msgs.length;
    final msg = msgs[i];
    return SizedBox(
      height: 44,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: _fade,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_iconFor(msg), color: Colors.white, size: 22, shadows: _kShadow),
            const SizedBox(width: 10),
            Flexible(
              child: Text(msg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500, shadows: _kShadow)),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        if (msgs.length > 1)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var d = 0; d < msgs.length; d++)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: d == i ? Colors.white : Colors.white38,
                ),
              ),
          ]),
      ]),
    );
  }
}


/// Soft dark gradients at the top and bottom so white text stays readable on
/// bright wallpapers.
class _Scrims extends StatelessWidget {
  const _Scrims();
  @override
  Widget build(BuildContext context) {
    return const Stack(fit: StackFit.expand, children: [
      Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          heightFactor: 0.38,
          widthFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x73000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: 0.45,
          widthFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0x66000000), Color(0x00000000)],
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
