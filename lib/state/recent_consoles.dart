import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// a console the user has connected to before. the password is never stored
class SavedConsole {
  const SavedConsole(this.address, {this.port = 11443, this.username});

  final String address;
  final int port;
  final String? username;

  Map<String, dynamic> toJson() => {'address': address, 'port': port, if (username != null) 'username': username};

  factory SavedConsole.fromJson(Map<String, dynamic> j) =>
      SavedConsole(j['address'] as String, port: (j['port'] as num?)?.toInt() ?? 11443, username: j['username'] as String?);

  @override
  bool operator ==(Object other) => other is SavedConsole && other.address == address && other.port == port;

  @override
  int get hashCode => Object.hash(address, port);
}

class RecentConsoles {
  static const _key = 'recent_consoles';
  static const _max = 8;

  Future<List<SavedConsole>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return [for (final e in jsonDecode(raw) as List) SavedConsole.fromJson((e as Map).cast<String, dynamic>())];
    } catch (_) {
      return [];
    }
  }

  // newest first, one entry per address and port
  Future<List<SavedConsole>> remember(SavedConsole c) async {
    final all = [c, ...(await load()).where((e) => e != c)].take(_max).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode([for (final e in all) e.toJson()]));
    } catch (_) {}
    return all;
  }

  Future<List<SavedConsole>> forget(SavedConsole c) async {
    final all = (await load()).where((e) => e != c).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode([for (final e in all) e.toJson()]));
    } catch (_) {}
    return all;
  }
}
