import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gelanggang.dart';

/// Storage Service — manages local persistent storage.
/// Stores the active gelanggang (similar to Pinia persist in Nuxt).
class StorageService {
  static const String _keyActiveGelanggang = 'active_gelanggang';

  /// Save active gelanggang to local storage
  static Future<void> saveActiveGelanggang(Gelanggang gelanggang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActiveGelanggang, jsonEncode(gelanggang.toJson()));
  }

  /// Load active gelanggang from local storage
  static Future<Gelanggang?> loadActiveGelanggang() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyActiveGelanggang);
    if (jsonStr == null) return null;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return Gelanggang.fromJson(map);
    } catch (e) {
      return null;
    }
  }

  /// Clear active gelanggang from local storage
  static Future<void> clearActiveGelanggang() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyActiveGelanggang);
  }
}
