import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../../core/constants/app_constants.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  bool _loading = false;
  String? _error;
  String? _token;
  Color _themeColor = const Color(0xFF1A73E8);
  double _fontSize = 14.0;
  double _brightness = 1.0;

  Color get themeColor => _themeColor;
  double get fontSize => _fontSize;
  double get brightness => _brightness;
  UserModel? get user => _user;
  bool get loading => _loading;
  String? get error => _error;
  String? get token => _token;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isEmployee => _user?.isEmployee ?? true;

  void updateTheme({Color? color, double? fontSize, double? brightness}) {
    if (color != null) _themeColor = color;
    if (fontSize != null) _fontSize = fontSize;
    if (brightness != null) _brightness = brightness;
    notifyListeners();
  }

  void updateUser(UserModel user) {
    _user = user;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService.login(email, password);
      _token = data['token'];
      await ApiService.saveToken(data['token']);
      _user = UserModel.fromJson(data['user']);
      _loading = false;
      notifyListeners();
      await setOnline();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(
      String name, String email, String password, String role, String dept,
      {String userRole = 'employee'}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService.register(name, email, password, role, dept,
          userRole: userRole);
      _token = data['token'];
      await ApiService.saveToken(data['token']);
      _user = UserModel.fromJson(data['user']);
      _loading = false;
      notifyListeners();
      await setOnline();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await setOffline();
    await ApiService.logout();
    _user = null;
    _token = null;
    notifyListeners();
  }

  Future<void> setOnline() => _updateStatus('online');
  Future<void> setOffline() => _updateStatus('offline');

  Future<void> _updateStatus(String status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey);
      if (token == null) return;
      await http
          .patch(
            Uri.parse('${AppConstants.apiUrl}/users/status'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token'
            },
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.tokenKey);
    if (token == null) return;
    try {
      _token = token;
      _user = await ApiService.getMe();
      notifyListeners();
      await setOnline();
    } catch (_) {
      await ApiService.clearToken();
    }
  }
}
