/*
 * Amadi additions to Arc Launcher (GPL-3.0-or-later).
 * Reads the guest sheet (Room Number, Title, Guest Name, Check-in, Check-out).
 */
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'amadi_settings.dart';

class Guest {
  final String title;
  final String name;
  const Guest(this.title, this.name);
  String get display => [title, name].where((s) => s.trim().isNotEmpty).join(' ').trim();
}

class GuestService extends ChangeNotifier {
  final AmadiSettings settings;
  Guest? _guest;
  String _status = 'Not checked yet';
  DateTime? _lastFetch;
  Timer? _timer;

  GuestService(this.settings) {
    // Show the last known guest straight away (the TV may restart the launcher
    // while an app is open).
    if (settings.cachedGuest.isNotEmpty && settings.cachedGuestRoom == settings.roomNumber) {
      _guest = Guest('', settings.cachedGuest);
    }
    refresh();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());
  }

  Guest? get guest => _guest;
  String get status => _status;
  DateTime? get lastFetch => _lastFetch;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    final room = settings.roomNumber;
    if (room.isEmpty) {
      _setGuest(null, 'Room number not set');
      return;
    }
    try {
      final custom = settings.guestUrl;
      final uri = custom.isNotEmpty
          ? Uri.parse(custom)
          : Uri.https('docs.google.com', '/spreadsheets/d/${settings.sheetId}/gviz/tq',
              {'tqx': 'out:csv', 'sheet': 'Rooms', 'range': 'A2:W'});
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.body.trimLeft().startsWith('<')) {
        _setGuest(_guest, 'Sheet not readable (is it shared by link?)');
        return;
      }
      final rows = parseCsv(res.body);
      _lastFetch = DateTime.now();
      final g = pickGuest(rows, room, DateTime.now(), settings.checkoutTime);
      await settings.setCachedGuest(g?.name ?? '');
      await settings.setCachedGuestRoom(room);
      _setGuest(g, 'OK');
    } catch (e) {
      // Keep the previous guest when offline.
      _setGuest(_guest, 'Offline: $e');
    }
  }

  void _setGuest(Guest? g, String status) {
    _guest = g;
    _status = status;
    notifyListeners();
  }

  /// Finds the guest for [room]. Handles a plain table (Room, Name[, Check-in, Check-out])
  /// and the front office Rooms grid, which repeats Room/First Name blocks side by side.
  @visibleForTesting
  static Guest? pickGuest(List<List<String>> rows, String room, DateTime now, String checkoutTime) {
    if (rows.isEmpty) return null;
    final want = room.trim().toLowerCase();
    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    final roomCols = <int>[];
    for (var i = 0; i < header.length; i++) {
      if (header[i] == 'room' || header[i] == 'room number' || header[i] == 'room no') roomCols.add(i);
    }
    if (roomCols.isEmpty) roomCols.add(0);
    final cIn = header.indexWhere((h) => h.contains('check-in') || h.contains('checkin'));
    final cOut = header.indexWhere((h) => h.contains('check-out') || h.contains('checkout'));
    final outParts = checkoutTime.split(':');
    final outH = int.tryParse(outParts.first) ?? 11;
    final outM = outParts.length > 1 ? int.tryParse(outParts[1]) ?? 0 : 0;

    for (final r in rows.skip(1)) {
      String at(int i) => i >= 0 && i < r.length ? r[i].trim() : '';
      for (final rc in roomCols) {
        var roomVal = at(rc).toLowerCase();
        if (roomVal.endsWith('.0')) roomVal = roomVal.substring(0, roomVal.length - 2);
        if (roomVal != want) continue;
        final name = at(rc + 1);
        if (name.isEmpty) continue;
        if (cIn >= 0 && cOut >= 0 && roomCols.length == 1) {
          final dIn = parseDate(at(cIn));
          final dOut = parseDate(at(cOut));
          if (dIn == null || dOut == null) continue;
          final end = DateTime(dOut.year, dOut.month, dOut.day, outH, outM);
          if (now.isBefore(dIn) || !now.isBefore(end)) continue;
        }
        return Guest('', sentenceCase(name));
      }
    }
    return null;
  }

  /// "AMAN" / "aman" -> "Aman".
  static String sentenceCase(String s) {
    final t = s.trim().toLowerCase();
    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
  }

  /// Accepts dd/mm/yyyy, dd-mm-yyyy, dd.mm.yyyy and yyyy-mm-dd.
  @visibleForTesting
  static DateTime? parseDate(String s) {
    s = s.trim().split(' ').first;
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
    if (iso != null) {
      return DateTime(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
    }
    final dmy = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$').firstMatch(s);
    if (dmy != null) {
      var y = int.parse(dmy[3]!);
      if (y < 100) y += 2000;
      final m = int.parse(dmy[2]!), d = int.parse(dmy[1]!);
      if (m < 1 || m > 12 || d < 1 || d > 31) return null;
      return DateTime(y, m, d);
    }
    return null;
  }

  @visibleForTesting
  static List<List<String>> parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        row.add(field.toString());
        field.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(c);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}
