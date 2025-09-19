// lib/api/auth_api.dart
import 'dart:async';
import 'dart:convert';
import 'package:cocoa_app/api/api_server.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
    } catch (_) {
      /* ignore */
    }
    // fallback ถ้า parse ไม่ได้
    return DateTime.now().add(const Duration(days: tokenDurationDays));
  }

  // ==================== TOKEN MANAGEMENT ====================
  static Future<void> _saveTokenToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', _jwtToken ?? '');
      await prefs.setString(
        'token_expiry',
        (_tokenExpiry ??
                DateTime.now().add(const Duration(days: tokenDurationDays)))
            .toIso8601String(),
      );
      if (kDebugMode) {
        print('💾 JWT saved');
        print('⏰ Expiry: $_tokenExpiry');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Save token error: $e');
    }
  }

  static Future<void> _loadTokenFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final expiryStr = prefs.getString('token_expiry');

      if (token == null || token.isEmpty) {
        await _clearTokenFromPrefs();
        return;
      }

      DateTime expiry;
      if (expiryStr != null && expiryStr.isNotEmpty) {
        try {
          expiry = DateTime.parse(expiryStr);
        } catch (_) {
          expiry = _expiryFromTokenOrDefault(token);
        }
      } else {
        expiry = _expiryFromTokenOrDefault(token);
      }

      if (DateTime.now().isBefore(expiry)) {
        _jwtToken = token;
        _tokenExpiry = expiry;
        _lastActivity = DateTime.now();
        ApiServer.updateAuthHeaders(_jwtToken!);
        _startValidationTimer();
        if (kDebugMode) {
          print('🔄 JWT restored');
          print('⏰ Expires at: $_tokenExpiry');
        }
      } else {
        if (kDebugMode) print('❌ Stored token expired');
        await _clearTokenFromPrefs();
      }
    } catch (e) {
      if (kDebugMode) print('❌ Load token error: $e');
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
    return DateTime.now().isAfter(_tokenExpiry!);
  }

  // ✅ ตั้ง token จากภายนอก (เช่น temp_token หรือคัดลอกมา)
  static Future<void> setTokenFromExternal(String rawToken) async {
    try {
      var token = rawToken.trim();
      if (token.toLowerCase().startsWith('bearer ')) {
        token = token.substring(7).trim();
      }
      _jwtToken = token;
      _tokenExpiry = _expiryFromTokenOrDefault(token);
      ApiServer.updateAuthHeaders(_jwtToken!);
      await _saveTokenToPrefs();
      _startValidationTimer();
      if (kDebugMode) {
        print('✅ External JWT applied. Expires at: $_tokenExpiry');
      }
    } catch (e) {
      if (kDebugMode) print('❌ setTokenFromExternal error (ignored): $e');
    }
  }

  // ==================== TIMER ====================
  static void _startValidationTimer() {
    _stopValidationTimer();
    _validationTimer = Timer.periodic(const Duration(hours: 1), (timer) async {
      await _validateToken();
    });
    if (kDebugMode) print('🔄 Token validation timer started');
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

      // ✅ ใช้ ApiServer wrapper เพื่อลดความเสี่ยง header/URL เพี้ยน
      final resp = await ApiServer.get('/api/auth/validate');

      if ((resp['status'] ?? 0) == 200 && (resp['success'] == true)) {
        _lastActivity = DateTime.now();
        if (kDebugMode) print('💚 Token validation OK');
        return;
      }

      if ((resp['status'] ?? 0) == 401) {
        final err = (resp['error'] ?? '').toString();
        if (['invalid_token', 'token_expired', 'token_revoked'].contains(err)) {
          if (kDebugMode) print('❌ Token invalid ($err) → clear');
          await clearAuth();
        } else {
          if (kDebugMode) print('⚠️ 401 ($err) but keep token for now');
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Token validation error: $e');
      // network ผิดพลาด: อย่าล้าง token
    }
  }

  // ==================== HEADER ====================
  static Map<String, String> _getAuthHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_jwtToken != null && _jwtToken!.isNotEmpty) {
      var t = _jwtToken!.trim();
      if (t.toLowerCase().startsWith('bearer ')) {
        t = t.substring(7).trim();
      }
      headers['Authorization'] = 'Bearer $t';
    }
    return headers;
  }

  // ==================== AUTH METHODS ====================
  static Future<Map<String, dynamic>> login(
    String username,
    String password,
  ) async {
    try {
      final res = await ApiServer.authLogin(
        username: username,
        password: password,
      );

      if (kDebugMode) {
        print('🔐 Login attempt for: $username');
        print('📤 Response: $res');
      }

      if (res['success'] == true && (res['token'] != null)) {
        // ✅ normalize token ตั้งแต่ต้น (กัน Bearer ซ้อน/ช่องว่าง)
        var token = (res['token'] as String).trim();
        if (token.toLowerCase().startsWith('bearer ')) {
          token = token.substring(7).trim();
        }

        _jwtToken = token;
        _tokenExpiry = _expiryFromTokenOrDefault(token);
        _lastActivity = DateTime.now();

        ApiServer.updateAuthHeaders(_jwtToken!);
        await _saveTokenToPrefs();

        // ✅ กัน race: เว้นจังหวะสั้นๆ ก่อนที่หน้าถัดไปจะยิง validate
        await Future.delayed(const Duration(milliseconds: 50));

        _startValidationTimer();

        return {
          'success': true,
          'message': res['message'] ?? 'เข้าสู่ระบบสำเร็จ',
          'user': res['user'],
          'token': token,
        };
      }

      return {
        'success': false,
        'message': res['message'] ?? 'เข้าสู่ระบบล้มเหลว',
      };
    } catch (e) {
      if (kDebugMode) print('❌ Login error: $e');
      return {'success': false, 'message': 'เกิดข้อผิดพลาดในการเชื่อมต่อ'};
    }
  }

  /// รองรับ user_email (ต้องส่ง)
  static Future<Map<String, dynamic>> register(
    String username,
    String userTel,
    String userEmail,
    String password,
    String confirmPassword,
    String name,
  ) async {
    try {
      final res = await ApiServer.authRegister(
        username: username,
        userTel: userTel,
        userEmail: userEmail,
        password: password,
        confirmPassword: confirmPassword,
        name: name,
      );

      if (res['success'] == true) {
        return {
          'success': true,
          'message': res['message'] ?? 'ลงทะเบียนสำเร็จ',
          'user': res['data'],
        };
      } else {
        return {
          'success': false,
          'message': res['message'] ?? 'ลงทะเบียนล้มเหลว',
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
    } catch (_) {
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

      // ✅ ใช้ ApiServer.get เพื่อให้ header/baseUrl สอดคล้อง
      var resp = await ApiServer.get('/api/auth/validate');

      if ((resp['status'] ?? 0) == 200 &&
          resp['success'] == true &&
          (resp['authenticated'] == true || resp['ok'] == true)) {
        _lastActivity = DateTime.now();
        await _saveTokenToPrefs();

        return {
          'success': true,
          'authenticated': true,
          'user': resp['user'],
          'remainingDays': _tokenExpiry != null
              ? _tokenExpiry!.difference(DateTime.now()).inDays
              : 0,
          'remainingHours': _tokenExpiry != null
              ? _tokenExpiry!.difference(DateTime.now()).inHours
              : 0,
        };
      }

      // ✅ กัน race: ถ้าได้ 401 โดยไม่มีเหตุผลชัดเจน ให้ retry 1 ครั้งหลังหน่วงสั้นๆ
      if ((resp['status'] ?? 0) == 401) {
        final err = (resp['error'] ?? '').toString();
        if (![
          'invalid_token',
          'token_expired',
          'token_revoked',
        ].contains(err)) {
          await Future.delayed(const Duration(milliseconds: 200));
          resp = await ApiServer.get('/api/auth/validate');

          if ((resp['status'] ?? 0) == 200 && resp['success'] == true) {
            _lastActivity = DateTime.now();
            await _saveTokenToPrefs();
            return {
              'success': true,
              'authenticated': true,
              'user': resp['user'],
              'remainingDays': _tokenExpiry != null
                  ? _tokenExpiry!.difference(DateTime.now()).inDays
                  : 0,
              'remainingHours': _tokenExpiry != null
                  ? _tokenExpiry!.difference(DateTime.now()).inHours
                  : 0,
            };
          }
        }

        // ถ้าเป็น error ที่ใช้ต่อไม่ได้จริง ค่อย clear
        if (['invalid_token', 'token_expired', 'token_revoked'].contains(err)) {
          await clearAuth();
          return {
            'success': false,
            'authenticated': false,
            'message': 'Token ไม่ถูกต้อง',
          };
        }
      }

      return {
        'success': false,
        'authenticated': false,
        'message': 'ตรวจสอบสิทธิ์ไม่สำเร็จ',
      };
    } catch (e) {
      if (kDebugMode) print('❌ Check auth error: $e');
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
    String? userEmail,
  }) async {
    try {
      String _t(String s) => s.trim();

      final payload = <String, dynamic>{
        if (name != null && _t(name).isNotEmpty) 'name': _t(name),
        if (userTel != null && _t(userTel).isNotEmpty) 'user_tel': _t(userTel),
        if (username != null && _t(username).isNotEmpty)
          'username': _t(username),
        if (userEmail != null && _t(userEmail).isNotEmpty)
          'user_email': _t(userEmail),
      };

      if (payload.isEmpty) {
        return {
          'success': false,
          'error': 'nothing_to_update_client',
          'message': 'กรุณากรอกอย่างน้อย 1 ช่องก่อนบันทึก',
        };
      }

      final r = await http.put(
        Uri.parse('${ApiServer.currentBaseUrl}/api/auth/profile'),
        headers: _getAuthHeaders(),
        body: jsonEncode(payload),
      );

      return ApiServer.handleResponse(r);
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
            headers: _getAuthHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      var body = ApiServer.handleResponse(resp);

      // Fallback เส้นทาง alias
      if (resp.statusCode == 404 || body['error'] == 'not_found') {
        resp = await http
            .put(
              Uri.parse('${ApiServer.currentBaseUrl}/api/auth/change-password'),
              headers: _getAuthHeaders(),
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

  // ==================== PASSWORD RESET (EMAIL OTP) ====================
  /// 1) ส่ง OTP ไปอีเมล (แอปจงใจตอบ ok เสมอ)
  static Future<Map<String, dynamic>> requestPasswordReset({
    required String email,
  }) async {
    try {
      final res = await ApiServer.requestPasswordReset(
        email.trim().toLowerCase(),
      );
      return {
        'success': res['ok'] == true || res['success'] == true,
        'message': (res['ok'] == true)
            ? 'ถ้ามีอีเมลนี้ในระบบ จะได้รับ OTP ภายในไม่กี่นาที'
            : (res['message'] ?? 'ส่งคำขอแล้ว'),
      };
    } catch (_) {
      return {'success': false, 'message': 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้'};
    }
  }

  /// 2) ยืนยัน OTP → ได้ temp_token
  static Future<Map<String, dynamic>> verifyPasswordReset({
    required String email,
    required String otp,
  }) async {
    try {
      final res = await ApiServer.verifyPasswordReset(email: email, otp: otp);
      if (res['ok'] == true && res['temp_token'] != null) {
        return {'success': true, 'tempToken': res['temp_token']};
      }
      return {
        'success': false,
        'message': res['message'] ?? 'รหัสยืนยันไม่ถูกต้องหรือหมดอายุ',
      };
    } catch (_) {
      return {'success': false, 'message': 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้'};
    }
  }

  /// 3) ตั้งรหัสผ่านใหม่ (ใช้ temp_token)
  static Future<Map<String, dynamic>> resetPasswordWithTempToken({
    required String tempToken,
    required String newPassword,
  }) async {
    try {
      final res = await ApiServer.resetPassword(
        tempToken: tempToken,
        newPassword: newPassword,
      );
      if (res['ok'] == true || res['success'] == true) {
        return {'success': true, 'message': 'รีเซ็ตรหัสผ่านสำเร็จ'};
      }
      return {
        'success': false,
        'message': res['message'] ?? 'ไม่สามารถรีเซ็ตรหัสผ่านได้',
      };
    } catch (_) {
      return {'success': false, 'message': 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้'};
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
    if (kDebugMode) print('✅ JWT cleared');
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
