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
      final uri = Uri.https('docs.google.com', '/spreadsheets/d/${settings.sheetId}/gviz/tq', {'tqx': 'out:csv'});
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.body.trimLeft().startsWith('<')) {
        _setGuest(_guest, 'Sheet not readable (is it shared by link?)');
        return;
      }
      final rows = parseCsv(res.body);
      _lastFetch = DateTime.now();
      _setGuest(pickGuest(rows, room, DateTime.now(), settings.checkoutTime), 'OK');
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

  @visibleForTesting
  static Guest? pickGuest(List<List<String>> rows, String room, DateTime now, String checkoutTime) {
    if (rows.isEmpty) return null;
    final header = rows.first.map((h) => h.toLowerCase()).toList();
    int col(String key, int fallback) {
      final i = header.indexWhere((h) => h.contains(key));
      return i >= 0 ? i : fallback;
    }

    final cRoom = col('room', 0), cTitle = col('title', 1), cName = col('name', 2);
    final cIn = col('check-in', 3) , cOut = col('check-out', 4);
    final outParts = checkoutTime.split(':');
    final outH = int.tryParse(outParts.first) ?? 11;
    final outM = outParts.length > 1 ? int.tryParse(outParts[1]) ?? 0 : 0;

    Guest? found;
    for (final r in rows.skip(1)) {
      String at(int i) => i < r.length ? r[i].trim() : '';
      if (at(cRoom).toLowerCase() != room.toLowerCase()) continue;
      final name = at(cName);
      if (name.isEmpty) continue;
      final dIn = parseDate(at(cIn));
      final dOut = parseDate(at(cOut));
      if (dIn == null || dOut == null) continue;
      final end = DateTime(dOut.year, dOut.month, dOut.day, outH, outM);
      if (!now.isBefore(dIn) && now.isBefore(end)) {
        found = Guest(at(cTitle), name);
      }
    }
    return found;
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
