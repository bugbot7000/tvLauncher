/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Rotating messages from the front office sheet's "TV Tickr" tab.
 */
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'amadi_settings.dart';
import 'guest_service.dart';

class TickerService extends ChangeNotifier {
  final AmadiSettings settings;
  List<String> _messages = [];
  Timer? _timer;

  TickerService(this.settings) {
    _messages = settings.cachedTicker;
    if (_messages.isEmpty) _messages = _defaults();
    refresh();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());
  }

  List<String> get messages => _messages;

  List<String> _defaults() => [
        if (settings.breakfast.isNotEmpty) 'Breakfast is served ${settings.breakfast}',
        if (settings.housekeeping.isNotEmpty) 'Housekeeping is available ${settings.housekeeping.toLowerCase()}',
        'Checkout is at 11 AM',
        'Dial 99 for the front desk and 77 for the restaurant',
      ];

  Uri? _uri() {
    final g = settings.guestUrl;
    if (g.isEmpty) return null;
    final u = Uri.parse(g);
    final q = Map<String, String>.from(u.queryParameters)
      ..remove('tv')
      ..['tickr'] = '1';
    return u.replace(queryParameters: q);
  }

  Future<void> refresh() async {
    final uri = _uri();
    if (uri == null) return;
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.body.trimLeft().startsWith('<')) return;
      final rows = GuestService.parseCsv(res.body);
      final list = rows.skip(1).map((r) => r.isEmpty ? '' : r.first.trim()).where((m) => m.isNotEmpty).toList();
      if (list.isEmpty) return;
      _messages = list;
      await settings.setCachedTicker(list);
      notifyListeners();
    } catch (_) {
      // Keep the last messages when offline.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
