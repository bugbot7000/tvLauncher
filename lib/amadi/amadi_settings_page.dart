/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Passcode-protected hotel settings.
 */
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'amadi_bridge.dart';
import 'amadi_home.dart' show resolveDockApp;
import 'amadi_settings.dart';
import 'guest_service.dart';
import 'weather_service.dart';

final FLauncherChannel _channel = FLauncherChannel();

Future<bool> showPasscodeDialog(BuildContext context) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => const _PasscodeDialog());
  return ok ?? false;
}

class _PasscodeDialog extends StatefulWidget {
  const _PasscodeDialog();
  @override
  State<_PasscodeDialog> createState() => _PasscodeDialogState();
}

class _PasscodeDialogState extends State<_PasscodeDialog> {
  String _entered = '';
  String? _error;

  void _add(String d) {
    if (_entered.length >= 4) return;
    setState(() {
      _error = null;
      _entered += d;
    });
    if (_entered.length == 4) {
      if (_entered == kSettingsPasscode) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = 'Wrong code';
          _entered = '';
        });
      }
    }
  }

  void _clear() => setState(() {
        _entered = '';
        _error = null;
      });

  static final Map<LogicalKeyboardKey, String> _digitKeys = {
    LogicalKeyboardKey.digit0: '0', LogicalKeyboardKey.digit1: '1', LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3', LogicalKeyboardKey.digit4: '4', LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6', LogicalKeyboardKey.digit7: '7', LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9', LogicalKeyboardKey.numpad0: '0', LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2', LogicalKeyboardKey.numpad3: '3', LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5', LogicalKeyboardKey.numpad6: '6', LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8', LogicalKeyboardKey.numpad9: '9',
  };

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'C', '0', '<'];
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && _digitKeys.containsKey(event.logicalKey)) {
          _add(_digitKeys[event.logicalKey]!);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        title: const Text('Staff settings'),
        content: SizedBox(
          width: 260,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    margin: const EdgeInsets.all(6),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _entered.length ? Colors.white : Colors.transparent,
                      border: Border.all(color: Colors.white70),
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 20,
              child: Text(_error ?? '', style: const TextStyle(color: Color(0xFFF09595))),
            ),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.8,
              children: [
                for (var i = 0; i < keys.length; i++)
                  OutlinedButton(
                    autofocus: i == 0,
                    onPressed: () {
                      final k = keys[i];
                      if (k == 'C') {
                        _clear();
                      } else if (k == '<') {
                        Navigator.of(context).pop(false);
                      } else {
                        _add(k);
                      }
                    },
                    child: Text(keys[i] == '<' ? 'Close' : keys[i], style: const TextStyle(fontSize: 18)),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class AmadiSettingsPage extends StatefulWidget {
  const AmadiSettingsPage({super.key});
  @override
  State<AmadiSettingsPage> createState() => _AmadiSettingsPageState();
}

class _AmadiSettingsPageState extends State<AmadiSettingsPage> with WidgetsBindingObserver {
  String? _wifiResult;
  Map<String, dynamic> _owner = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadOwner();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AmadiBridge.setSettingsHidden(true);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android settings: hide it from guests again.
    if (state == AppLifecycleState.resumed) {
      AmadiBridge.setSettingsHidden(true);
      _loadOwner();
    }
  }

  Future<void> _loadOwner() async {
    final m = await AmadiBridge.ownerStatus();
    if (mounted) setState(() => _owner = m);
  }

  /// Unhides Android settings just long enough for staff to use it.
  Future<void> _openSystem(Future<void> Function() open) async {
    await AmadiBridge.setSettingsHidden(false);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await open();
  }

  Future<void> _editText(String title, String current, Future<void> Function(String) save,
      {bool obscure = false, TextInputType keyboard = TextInputType.text}) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            obscureText: obscure,
            keyboardType: keyboard,
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (result != null) await save(result);
  }

  Future<void> _pickDockApp(DockSlot slot) async {
    final apps = context.read<AppsService>().applications;
    final settings = context.read<AmadiSettings>();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('App for ${slot.label}'),
        content: SizedBox(
          width: 420,
          height: 420,
          child: ListView(children: [
            ListTile(
              autofocus: true,
              title: const Text('Detect automatically'),
              onTap: () => Navigator.of(ctx).pop(''),
            ),
            for (final App a in apps)
              ListTile(
                title: Text(a.name),
                subtitle: Text('${a.packageName}  ${a.version}'),
                onTap: () => Navigator.of(ctx).pop(a.packageName),
              ),
          ]),
        ),
      ),
    );
    if (picked == null) return;
    await settings.setDockPackage(slot.id, picked.isEmpty ? null : picked);
  }

  String _lastSignOut() {
    final ms = _owner['lastSignOut'];
    if (ms is! int || ms == 0) return 'not yet';
    return DateFormat('d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(title, style: const TextStyle(color: Color(0xFF9FE1CB), fontSize: 13)),
      );

  Widget _row(String title, String value, VoidCallback onTap, {bool autofocus = false}) => ListTile(
        autofocus: autofocus,
        title: Text(title),
        subtitle: value.isEmpty ? null : Text(value),
        trailing: const Icon(Icons.chevron_right),
        focusColor: Colors.white24,
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AmadiSettings>();
    final guests = context.watch<GuestService>();
    final apps = context.watch<AppsService>().applications;
    final last = guests.lastFetch;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(title: const Text('Hotel settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
        children: [
          _section('Guest checkout'),
          ListTile(
            autofocus: true,
            leading: const Icon(Icons.logout),
            title: const Text('Log guest out of all streaming apps'),
            subtitle: Text('YouTube, Netflix, Prime Video and JioHotstar. Also runs daily at 11:30 AM. Last: ${_lastSignOut()}'),
            focusColor: Colors.white24,
            onTap: () async {
              final ok = await AmadiBridge.signOutNow();
              await _loadOwner();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? 'Signed out of all streaming apps'
                    : 'Could not sign out. Check that network debugging is on and allowed for this app.'),
              ));
            },
          ),
          _section('This TV'),
          _row('Room number', s.roomNumber.isEmpty ? 'Not set' : s.roomNumber,
              () => _editText('Room number (also sets the TV name, e.g. 212 TV)', s.roomNumber, s.setRoomNumber)),
          _row(
            'Guest name',
            '${guests.guest?.display ?? 'No guest checked in'}  ·  ${guests.status}'
                '${last == null ? '' : '  ·  checked ${DateFormat('h:mm a').format(last)}'}',
            () => guests.refresh(),
          ),

          _section('Wi-Fi'),
          _row('Default network', s.wifiSsid, () => _editText('Wi-Fi network name', s.wifiSsid, s.setWifiSsid)),
          _row('Default network password', s.wifiPassword.isEmpty ? 'None (open network)' : '••••••••',
              () => _editText('Wi-Fi password', s.wifiPassword, s.setWifiPassword, obscure: true)),
          _row('Connect to default network now', _wifiResult ?? '', () async {
            final r = await AmadiBridge.connectWifi(s.wifiSsid, s.wifiPassword);
            setState(() => _wifiResult = switch (r) {
                  'connected-request' => 'Connecting…',
                  'suggested' => 'Sent to Android. Accept the prompt if one appears.',
                  'disabled' => 'Wi-Fi is off. Turn it on in Wi-Fi settings.',
                  'invalid' => 'Set a network name first.',
                  _ => r,
                });
          }),
          _row('Open Wi-Fi settings', '', () => _openSystem(() => _channel.openWifiSettings())),

          _section('Date and time'),
          _row('Open date and time settings', 'Time is set automatically from the internet when available',
              () => _openSystem(() => _channel.launchActivityFromAction('android.settings.DATE_SETTINGS'))),

          _section('Hotel information on screen'),
          _row('Breakfast', s.breakfast, () => _editText('Breakfast', s.breakfast, s.setBreakfast)),
          _row('Housekeeping', s.housekeeping, () => _editText('Housekeeping', s.housekeeping, s.setHousekeeping)),
          _row('Front desk', s.frontDesk, () => _editText('Front desk', s.frontDesk, s.setFrontDesk)),
          _row('Restaurant', s.restaurant, () => _editText('Restaurant', s.restaurant, s.setRestaurant)),
          _row('Guest name clears at (checkout time, 24h)', s.checkoutTime,
              () => _editText('Checkout time (HH:MM, 24h)', s.checkoutTime, s.setCheckoutTime)),

          _section('Weather'),
          _row('Place name', s.weatherPlace, () => _editText('Place name', s.weatherPlace, s.setWeatherPlace)),
          _row('Location (latitude, longitude)', '${s.weatherLat}, ${s.weatherLon}', () async {
            await _editText('Latitude, longitude', '${s.weatherLat}, ${s.weatherLon}', (v) async {
              final parts = v.split(',');
              if (parts.length == 2) await s.setWeatherLatLon(parts[0], parts[1]);
            });
            if (mounted) context.read<WeatherService>().refresh();
          }),

          _section('Dock apps'),
          for (final slot in kDockSlots)
            _row(slot.label, resolveDockApp(slot, apps, s)?.name ?? 'Not installed', () => _pickDockApp(slot)),

          _section('System'),
          _row('Guest sheet ID', s.sheetId, () => _editText('Google Sheet ID', s.sheetId, s.setSheetId)),
          _row('Guest data link (optional)', s.guestUrl.isEmpty ? 'Not set, reading the sheet directly' : s.guestUrl,
              () => _editText('Guest data link', s.guestUrl, s.setGuestUrl)),
          _row('Make this the default home screen', '',
              () => _channel.launchActivityFromAction('android.settings.HOME_SETTINGS')),
          _row('Open Android settings', '', () => _openSystem(() => _channel.openSettings())),
          _section('Maintenance'),
          _row('Remove device owner (maintenance only)',
              'Turns off daily sign-out, home lock and settings hiding', () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Remove device owner?'),
                content: const Text('Daily sign-out, the home screen lock and hiding of Android settings will stop until it is set up again over ADB.'),
                actions: [
                  TextButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove')),
                ],
              ),
            );
            if (ok == true) {
              await AmadiBridge.removeOwner();
              await _loadOwner();
            }
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
