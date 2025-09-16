// auth_api.dart
import 'package:cocoa_app/api/api_server.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthApiService {
  static String? _jwtToken;
  static DateTime? _tokenExpiry;
  static const int tokenDurationDays = 30;

  static Timer? _validationTimer;
  static DateTime? _lastActivity;

  // ==================== UTIL: JWT EXP PARSER ====================
  static DateTime _expiryFromTokenOrDefault(String token) {
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payloadJson = utf8.decode(
          base64Url.decode(base64Url.normalize(parts[1])),
        );
        final payload = json.decode(payloadJson) as Map<String, dynamic>;
        final exp = payload['exp'];
        if (exp is int) {
          return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        }
      }
    } catch (_) {}
    return DateTime.now().add(const Duration(days: tokenDurationDays));
  }

  // ==================== TOKEN MANAGEMENT ====================
  static Future<void> _saveTokenToPrefs() async {
    if (_jwtToken != null && _tokenExpiry != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', _jwtToken!);
      await prefs.setString('token_expiry', _tokenExpiry!.toIso8601String());
      if (kDebugMode) {
        print('💾 JWT Token saved to storage');
        print('⏰ Expiry: $_tokenExpiry');
      }
    }
  }

  static Future<void> _loadTokenFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final expiryString = prefs.getString('token_expiry');

      if (token != null && expiryString != null) {
        final expiry = DateTime.parse(expiryString);
        if (DateTime.now().isBefore(expiry)) {
          _jwtToken = token;
          _tokenExpiry = expiry;
          _lastActivity = DateTime.now();

          // อัปเดต ApiServer headers
          ApiServer.updateAuthHeaders(_jwtToken!);
          _startValidationTimer();

          if (kDebugMode) {
            print('🔄 JWT Token restored successfully');
            print('⏰ Expires at: $expiry');
            print(
              '📅 Days remaining: ${expiry.difference(DateTime.now()).inDays}',
            );
          }
        } else {
          if (kDebugMode) print('❌ Stored token expired, clearing...');
          await _clearTokenFromPrefs();
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error loading token: $e');
      await _clearTokenFromPrefs();
    }
  }

  static Future<void> _clearTokenFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('token_expiry');
    _stopValidationTimer();
  }

  static bool _isTokenExpired() {
    if (_tokenExpiry == null) return true;
    final now = DateTime.now();
    final isExpired = now.isAfter(_tokenExpiry!);
    if (kDebugMode && isExpired) {
      print('❌ Token expired: $_tokenExpiry');
      print('🕐 Current time: $now');
    }
    return isExpired;
  }

  // ✅ ตั้ง token จากภายนอก (เช่น คัดลอกมาวาง) และ decode exp อัตโนมัติ
  static Future<void> setTokenFromExternal(String rawToken) async {
    try {
      final token = rawToken.startsWith('Bearer ')
          ? rawToken.substring(7).trim()
          : rawToken.trim();

      _jwtToken = token;
      _tokenExpiry = _expiryFromTokenOrDefault(token);

      ApiServer.updateAuthHeaders(_jwtToken!);
      await _saveTokenToPrefs();
      _startValidationTimer();

      if (kDebugMode) {
        print('✅ External JWT applied. Expires at: $_tokenExpiry');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ setTokenFromExternal error: $e');
      }
      rethrow;
    }
  }

  // ==================== TIMER ====================
  static void _startValidationTimer() {
    _stopValidationTimer();
    _validationTimer = Timer.periodic(const Duration(hours: 1), (timer) async {
      await _validateToken();
    });
    if (kDebugMode) {
      print('🔄 Token validation timer started (1 hour intervals)');
    }
  }

  static void _stopValidationTimer() {
    _validationTimer?.cancel();
    _validationTimer = null;
  }

  static Future<void> _validateToken() async {
    try {
      if (_jwtToken == null || _isTokenExpired()) {
        _stopValidationTimer();
        await clearAuth();
        return;
      }

      final response = await http
          .get(
            Uri.parse('${ApiServer.currentBaseUrl}/api/auth/validate'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _lastActivity = DateTime.now();
          if (kDebugMode) print('💚 Token validation successful');
        }
      } else if (response.statusCode == 401) {
        if (kDebugMode) {
          print('❌ Token validation failed: ${response.body}');
        }
        await clearAuth();
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Token validation error: $e');
      }
    }
  }

  // ==================== HEADER ====================
  static Map<String, String> _getAuthHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_jwtToken != null) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }
    return headers;
  }

  // ==================== AUTH METHODS ====================
  static Future<Map<String, dynamic>> login(
    String username,
    String password,
  ) async {
    try {
      print(ApiServer.currentBaseUrl);
      final response = await http
          .post(
            Uri.parse('${ApiServer.currentBaseUrl}/api/auth/login'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        print('🔐 Login attempt for: $username');
        print('📤 Response status: ${response.statusCode}');
        print('📝 Response body: ${response.body}');
      }

      final responseData = json.decode(response.body);
      if (response.statusCode == 200 && responseData['success'] == true) {
        String? token;
        Map<String, dynamic>? userData;
        if (responseData['data'] != null) {
          token = responseData['data']['token'];
          userData = responseData['data']['user'];
        } else {
          token = responseData['token'];
          userData = responseData['user'];
        }

        if (token != null && token.isNotEmpty) {
          _jwtToken = token;
          _tokenExpiry = _expiryFromTokenOrDefault(token);
          _lastActivity = DateTime.now();

          ApiServer.updateAuthHeaders(_jwtToken!);
          await _saveTokenToPrefs();
          _startValidationTimer();

          if (kDebugMode) {
            print('🔑 JWT Token received and stored successfully');
            print('⏰ Token expires at: $_tokenExpiry');
          }

          return {
            'success': true,
            'message': responseData['message'] ?? 'เข้าสู่ระบบสำเร็จ',
            'user': userData,
            'token': token,
          };
        } else {
          if (kDebugMode) {
            print('❌ No token found in response');
            print('📝 Full response: $responseData');
          }
          return {'success': false, 'message': 'ไม่พบ token ในการตอบกลับ'};
        }
      }

      return {
        'success': false,
        'message':
            responseData['error'] ??
            responseData['message'] ??
            'เข้าสู่ระบบล้มเหลว',
      };
    } catch (e) {
      if (kDebugMode) print('❌ Login error: $e');
      return {'success': false, 'message': 'เกิดข้อผิดพลาดในการเชื่อมต่อ'};
    }
  }

  static Future<Map<String, dynamic>> register(
    String username,
    String userTel,
    String password,
    String confirmPassword,
    String name,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiServer.currentBaseUrl}/api/auth/register'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({
              'username': username,
              'user_tel': userTel,
              'password': password,
              'confirm_password': confirmPassword,
              'name': name,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final responseData = json.decode(response.body);
      if (response.statusCode == 201 && responseData['success'] == true) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'ลงทะเบียนสำเร็จ',
          'user': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message':
              responseData['error'] ??
              responseData['message'] ??
              'ลงทะเบียนล้มเหลว',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'เกิดข้อผิดพลาดในการเชื่อมต่อ'};
    }
  }

  static Future<Map<String, dynamic>> logout() async {
    try {
      await clearAuth();
      return {'success': true, 'message': 'ออกจากระบบสำเร็จ'};
    } catch (e) {
      await clearAuth();
      return {'success': true, 'message': 'ออกจากระบบสำเร็จ'};
    }
  }

  static Future<Map<String, dynamic>> checkAuth() async {
    try {
      if (_jwtToken == null) {
        await _loadTokenFromPrefs();
      }
      if (_isTokenExpired()) {
        if (kDebugMode) print('❌ Token expired locally');
        await clearAuth();
        return {
          'success': false,
          'authenticated': false,
          'message': 'Token หมดอายุแล้ว',
        };
      }

      final response = await http
          .get(
            Uri.parse('${ApiServer.currentBaseUrl}/api/auth/validate'),
            headers: _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true &&
            responseData['authenticated'] == true) {
          _lastActivity = DateTime.now();
          await _saveTokenToPrefs();

          return {
            'success': true,
            'authenticated': true,
            'user': responseData['user'],
            'remainingDays': _tokenExpiry != null
                ? _tokenExpiry!.difference(DateTime.now()).inDays
                : 0,
            'remainingHours': _tokenExpiry != null
                ? _tokenExpiry!.difference(DateTime.now()).inHours
                : 0,
          };
        }
      }

      await clearAuth();
      return {
        'success': false,
        'authenticated': false,
        'message': 'Token ไม่ถูกต้อง',
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ Check auth error: $e');
      }
      return {
        'success': false,
        'authenticated': false,
        'message': 'เกิดข้อผิดพลาดในการเชื่อมต่อ',
      };
    }
  }

  // ==================== PROFILE ====================
  static Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? userTel,
    String? username,
  }) async {
    try {
      String _t(String s) => s.trim();

      final payload = <String, dynamic>{
        if (name != null && _t(name).isNotEmpty) 'name': _t(name),
        if (userTel != null && _t(userTel).isNotEmpty) 'user_tel': _t(userTel),
        if (username != null && _t(username).isNotEmpty)
          'username': _t(username),
      };

      // ป้องกันยิงว่าง ๆ
      if (payload.isEmpty) {
        return {
          'success': false,
          'error': 'nothing_to_update_client',
          'message': 'กรุณากรอกอย่างน้อย 1 ช่องก่อนบันทึก',
        };
      }

      final r = await http.put(
        Uri.parse('${ApiServer.currentBaseUrl}/api/auth/profile'),
        headers: ApiServer.jsonHeaders, // ✅ ต้องเป็น JSON header
        body: jsonEncode(payload),
      );

      final body = ApiServer.handleResponse(r);
      return body;
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
    String? confirmPassword,
  }) async {
    final payload = <String, dynamic>{
      'current_password': currentPassword.trim(),
      'new_password': newPassword.trim(),
      'confirm_password': (confirmPassword ?? newPassword).trim(),
    };

    try {
      // เส้นทางหลัก
      var resp = await http
          .put(
            Uri.parse('${ApiServer.currentBaseUrl}/api/auth/profile/password'),
            headers: ApiServer.jsonHeaders, // ✅ JSON header สำคัญมาก
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      var body = ApiServer.handleResponse(resp);

      // Fallback เส้นทาง alias
      if (resp.statusCode == 404 || body['error'] == 'not_found') {
        resp = await http
            .put(
              Uri.parse('${ApiServer.currentBaseUrl}/api/auth/change-password'),
              headers: ApiServer.jsonHeaders,
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 30));
        body = ApiServer.handleResponse(resp);
      }

      return body;
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  // ==================== HELPERS ====================
  static Future<void> clearAuth() async {
    if (kDebugMode) print('🗑️ Clearing JWT authentication...');
    _jwtToken = null;
    _tokenExpiry = null;
    _lastActivity = null;
    _stopValidationTimer();
    await _clearTokenFromPrefs();
    ApiServer.clearAuthHeaders();
    if (kDebugMode) print('✅ JWT Authentication cleared successfully');
  }

  static bool hasAuth() =>
      _jwtToken != null && _jwtToken!.isNotEmpty && !_isTokenExpired();

  static String? getCurrentToken() => hasAuth() ? _jwtToken : null;

  static int getTokenRemainingDays() {
    if (_tokenExpiry == null) return 0;
    final days = _tokenExpiry!.difference(DateTime.now()).inDays;
    return days > 0 ? days : 0;
  }

  static int getTokenRemainingHours() {
    if (_tokenExpiry == null) return 0;
    final hours = _tokenExpiry!.difference(DateTime.now()).inHours;
    return hours > 0 ? hours : 0;
  }

  static int getTokenRemainingMinutes() {
    if (_tokenExpiry == null) return 0;
    final minutes = _tokenExpiry!.difference(DateTime.now()).inMinutes;
    return minutes > 0 ? minutes : 0;
  }

  static Future<void> initAuth() async => _loadTokenFromPrefs();

  static Future<void> validateToken() async {
    _lastActivity = DateTime.now();
    await _validateToken();
  }

  static bool isTokenWarning() {
    if (_tokenExpiry == null) return false;
    final remaining = _tokenExpiry!.difference(DateTime.now());
    return remaining.inHours <= 24;
  }

  static void debugAuth() {
    if (kDebugMode) {
      print('=== JWT AUTH DEBUG INFO ===');
      print('Token: ${_jwtToken?.substring(0, 20)}...');
      print('Expiry: $_tokenExpiry');
      print('Last Activity: $_lastActivity');
      print('Has Auth: ${hasAuth()}');
      print('Is Expired: ${_isTokenExpired()}');
      print('Remaining Days: ${getTokenRemainingDays()}');
      print('==========================');
    }
  }
}
