/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 */
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'amadi_bridge.dart';

/// Dock slots in display order. Each slot has a default name matcher used to
/// find the app automatically; staff can override it in Hotel settings.
class DockSlot {
  final String id;
  final String label;
  final String package;
  final List<String> nameMatches;
  const DockSlot(this.id, this.label, this.package, this.nameMatches);
}

const List<DockSlot> kDockSlots = [
  DockSlot('youtube', 'YouTube', 'com.google.android.youtube.tv', ['youtube']),
  DockSlot('netflix', 'Netflix', 'com.netflix.ninja', ['netflix']),
  DockSlot('prime', 'Prime Video', 'com.amazon.amazonvideo.livingroom', ['prime video', 'primevideo', 'amazon video']),
  DockSlot('hotstar', 'JioHotstar', 'in.startv.hotstar', ['hotstar']),
];

const String kSettingsPasscode = '2580';
const String kDefaultSheetId = '1907vOmNeuiRroHDYzcmXfz-iiv_MSmO4xDxoeSG57Q8';

class AmadiSettings extends ChangeNotifier {
  final SharedPreferences _prefs;
  AmadiSettings(this._prefs);

  String _s(String key, String def) => _prefs.getString('amadi_$key') ?? def;
  Future<void> _set(String key, String value) async {
    await _prefs.setString('amadi_$key', value);
    notifyListeners();
  }

  String get roomNumber => _s('room', '');
  Future<void> setRoomNumber(String v) async {
    await _set('room', v.trim());
    if (v.trim().isNotEmpty) await AmadiBridge.setDeviceName('${v.trim()} TV');
  }

  String get sheetId => _s('sheet_id', kDefaultSheetId);
  Future<void> setSheetId(String v) => _set('sheet_id', v.trim());

  /// Optional web address that returns guest data as CSV (e.g. the front office
  /// sheet's Apps Script). When empty the sheet is read directly by its ID.
  String get guestUrl => _s('guest_url', '');
  Future<void> setGuestUrl(String v) => _set('guest_url', v.trim());

  String get checkoutTime => _s('checkout_time', '11:00');
  Future<void> setCheckoutTime(String v) => _set('checkout_time', v.trim());

  String get breakfast => _s('breakfast', '8:30 to 10:30 AM');
  Future<void> setBreakfast(String v) => _set('breakfast', v.trim());

  String get housekeeping => _s('housekeeping', 'Until 5 PM');
  Future<void> setHousekeeping(String v) => _set('housekeeping', v.trim());

  String get frontDesk => _s('front_desk', 'Dial 99');
  Future<void> setFrontDesk(String v) => _set('front_desk', v.trim());

  String get restaurant => _s('restaurant', 'Dial 77');
  Future<void> setRestaurant(String v) => _set('restaurant', v.trim());

  String get wifiSsid => _s('wifi_ssid', 'Amadi guest');
  Future<void> setWifiSsid(String v) => _set('wifi_ssid', v.trim());

  String get wifiPassword => _s('wifi_password', '');
  Future<void> setWifiPassword(String v) => _set('wifi_password', v);

  String get weatherPlace => _s('weather_place', 'Goa');
  Future<void> setWeatherPlace(String v) => _set('weather_place', v.trim());

  double get weatherLat => double.tryParse(_s('weather_lat', '15.55')) ?? 15.55;
  double get weatherLon => double.tryParse(_s('weather_lon', '73.75')) ?? 73.75;
  Future<void> setWeatherLatLon(String lat, String lon) async {
    if (double.tryParse(lat.trim()) != null) await _prefs.setString('amadi_weather_lat', lat.trim());
    if (double.tryParse(lon.trim()) != null) await _prefs.setString('amadi_weather_lon', lon.trim());
    notifyListeners();
  }

  /// Package chosen by staff for a dock slot, or null to auto-detect.
  String? dockPackage(String slotId) => _prefs.getString('amadi_dock_$slotId');
  Future<void> setDockPackage(String slotId, String? pkg) async {
    if (pkg == null) {
      await _prefs.remove('amadi_dock_$slotId');
    } else {
      await _prefs.setString('amadi_dock_$slotId', pkg);
    }
    notifyListeners();
  }
}
