import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheHelper {
  static late SharedPreferences sharedPreferences;
  static Future<void> init() async {
    sharedPreferences = await SharedPreferences.getInstance();
  }

  static dynamic getData(String key) {
    return sharedPreferences.get(key);
  }

  static Future<bool> removeData(String key) async {
    return await sharedPreferences.remove(key);
  }

  static Future<bool> saveData({required String key, required dynamic value}) {
    if (value is String) {
      return sharedPreferences.setString(key, value);
    } else if (value is int) {
      return sharedPreferences.setInt(key, value);
    } else if (value is double) {
      return sharedPreferences.setDouble(key, value);
    } else if (value is List<String>) {
      return sharedPreferences.setStringList(key, value);
    } else if (value is List<dynamic>) {
      return sharedPreferences.setString(key, jsonEncode(value));
    } else {
      return sharedPreferences.setBool(key, value);
    }
  }
  static Future<bool> clearAllData() async {
    return await sharedPreferences.clear();
  }
}
