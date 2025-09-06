// api_server.dart
import 'package:cocoa_app/utils/variable.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiServer {
  // ======================== CONFIG =========================
  // static const String baseUrl = 'http://127.0.0.1:5000';

  static const List<String> alternativeUrls = [
    'http://127.0.0.1:5000',
    'http://localhost:5000',
    'http://10.0.2.2:5000', // Android emulator
  ];

  // แสดง token แบบเต็มใน debug log หรือไม่ (ไม่แนะนำให้เปิด)
  static const bool _LOG_FULL_TOKEN_IN_DEBUG = false;

  // ======================== STATE ==========================
  static String? _jwtToken;
  static String? _currentBaseUrl = baseUrl;

  // ======================== URL ============================
  static void setBaseUrl(String url) {
    _currentBaseUrl = url;
    if (kDebugMode) {
      print('🌐 Base URL set to: $_currentBaseUrl');
    }
  }

  static String get currentBaseUrl => _currentBaseUrl ?? baseUrl;

  // ======================== TOKEN ==========================
  static void updateAuthHeaders(String token) {
    _jwtToken = token;
    if (kDebugMode) print('🔑 JWT Token updated');
  }

  static void clearAuthHeaders() {
    _jwtToken = null;
    if (kDebugMode) print('🗑️ JWT Token cleared');
  }

  static bool get hasAuthToken => _jwtToken != null && _jwtToken!.isNotEmpty;
  static String? get currentToken => _jwtToken;

  /// คืนค่า token แบบย่อเพื่อความปลอดภัยในการ log
  static String tokenPreview({int head = 20, int tail = 10}) {
    final t = _jwtToken;
    if (t == null || t.isEmpty) return '<null>';
    if (_LOG_FULL_TOKEN_IN_DEBUG && kDebugMode) return t;
    if (t.length <= head + tail) return t;
    return '${t.substring(0, head)}...${t.substring(t.length - tail)}';
  }

  /// พิมพ์ token ปัจจุบัน (เต็มเฉพาะเมื่อเปิด _LOG_FULL_TOKEN_IN_DEBUG และอยู่ใน debug)
  static void printCurrentToken() {
    final label = _LOG_FULL_TOKEN_IN_DEBUG && kDebugMode
        ? '(full)'
        : '(preview)';
    if (kDebugMode) {
      print('🔐 Current JWT $label: ${tokenPreview()}');
    }
  }

  // ====================== HEADERS ==========================
  static Map<String, String> get defaultHeaders {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      // หมายเหตุ: อย่าใส่ CORS headers ฝั่ง client (ควรอยู่ที่เซิร์ฟเวอร์ Flask)
    };

    if (hasAuthToken) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }
    return headers;
  }

  // =================== RESPONSE PARSING =====================
  static Map<String, dynamic> handleResponse(http.Response response) {
    try {
      final contentType = response.headers['content-type'] ?? '';

      if (kDebugMode) {
        final body = response.body;
        final preview = body.length > 800
            ? '${body.substring(0, 800)}...'
            : body;
        print('📤 Response Status: ${response.statusCode}');
        print('📄 Response Body (preview): $preview');
      }

      if (contentType.contains('application/json')) {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
        return {'success': true, 'data': decoded};
      } else {
        return {
          'success': response.statusCode >= 200 && response.statusCode < 300,
          'message': response.body,
          'raw_response': true,
        };
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error parsing response: $e');
        print('📝 Raw response: ${response.body}');
      }
      return {
        'success': false,
        'error': 'response_parse_error',
        'message': 'ไม่สามารถประมวลผลข้อมูลจากเซิร์ฟเวอร์ได้: $e',
        'raw_response': response.body,
      };
    }
  }

  // ===================== ERROR HANDLING =====================
  static Map<String, dynamic> handleError(dynamic error) {
    if (kDebugMode) {
      print('❌ API Error: $error');
      print('❌ Error Type: ${error.runtimeType}');
    }

    String message = 'เกิดข้อผิดพลาดในการเชื่อมต่อ';
    String errorType = 'unknown_error';

    if (error.toString().contains('Failed to fetch')) {
      message =
          '❌ ปัญหา CORS หรือเซิร์ฟเวอร์ปิดอยู่\n\n'
          '🔧 แนวทางแก้ไข:\n'
          '1. ตรวจสอบเซิร์ฟเวอร์ทำงานที่ http://127.0.0.1:5000\n'
          '2. เพิ่ม CORS headers ใน Flask: from flask_cors import CORS; CORS(app)\n'
          '3. ตรวจสอบ Firewall/Antivirus';
      errorType = 'cors_or_server_error';
    } else if (error is SocketException) {
      message =
          '🌐 ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้\n\n'
          '📋 กรุณาตรวจสอบ:\n'
          '• เซิร์ฟเวอร์ Flask ทำงานอยู่หรือไม่\n'
          '• ที่อยู่เซิร์ฟเวอร์: $_currentBaseUrl\n'
          '• การเชื่อมต่ออินเทอร์เน็ต\n'
          '• Firewall settings';
      errorType = 'connection_error';
    } else if (error is HttpException) {
      message = 'เกิดข้อผิดพลาดในการส่งข้อมูล HTTP';
      errorType = 'http_error';
    } else if (error is FormatException) {
      message = 'รูปแบบข้อมูลไม่ถูกต้อง';
      errorType = 'format_error';
    } else if (error.toString().contains('TimeoutException')) {
      message =
          '⏱️ การเชื่อมต่อใช้เวลานานเกินไป\nเซิร์ฟเวอร์อาจทำงานช้า กรุณาลองใหม่';
      errorType = 'timeout_error';
    }

    return {
      'success': false,
      'error': errorType,
      'message': message,
      'details': error.toString(),
      'suggestions': _getErrorSuggestions(errorType),
    };
  }

  static List<String> _getErrorSuggestions(String errorType) {
    switch (errorType) {
      case 'cors_or_server_error':
        return [
          'ติดตั้ง: pip install flask-cors',
          'เพิ่มโค้ด: CORS(app) ใน Flask',
          'ตรวจสอบ URL: http://127.0.0.1:5000/health',
        ];
      case 'connection_error':
      default:
        return ['ลองรีเฟรชแอป', 'ตรวจสอบการเชื่อมต่อ'];
    }
  }

  // ==================== DISCOVERY ===========================
  static Future<String?> findWorkingServer() async {
    for (String url in alternativeUrls) {
      try {
        final response = await http
            .get(Uri.parse('$url/health'))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          _currentBaseUrl = url;
          if (kDebugMode) print('✅ Found working server at: $url');
          return url;
        }
      } catch (e) {
        if (kDebugMode) print('❌ $url not working: $e');
      }
    }
    return null;
  }

  // ==================== HTTP WRAPPER ========================
  static Future<Map<String, dynamic>> get(String endpoint) async =>
      _httpRequest('GET', endpoint);

  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data,
  ) async => _httpRequest('POST', endpoint, data: data);

  static Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> data,
  ) async => _httpRequest('PUT', endpoint, data: data);

  static Future<Map<String, dynamic>> delete(String endpoint) async =>
      _httpRequest('DELETE', endpoint);

  static Future<Map<String, dynamic>> _httpRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? data,
  }) async {
    try {
      if (kDebugMode) {
        print('🚀 $method Request: $currentBaseUrl$endpoint');
        if (data != null) print('📦 Data: $data');
        print('🔑 Has Auth: $hasAuthToken | Bearer ${tokenPreview()}');
        final authHeader = defaultHeaders['Authorization'];
        print('🧾 Authorization header: $authHeader');
      }

      http.Response response;
      final uri = Uri.parse('$currentBaseUrl$endpoint');

      switch (method) {
        case 'GET':
          response = await http
              .get(uri, headers: defaultHeaders)
              .timeout(const Duration(seconds: 30));
          break;
        case 'POST':
          response = await http
              .post(
                uri,
                headers: defaultHeaders,
                body: data != null ? json.encode(data) : null,
              )
              .timeout(const Duration(seconds: 30));
          break;
        case 'PUT':
          response = await http
              .put(
                uri,
                headers: defaultHeaders,
                body: data != null ? json.encode(data) : null,
              )
              .timeout(const Duration(seconds: 30));
          break;
        case 'DELETE':
          response = await http
              .delete(uri, headers: defaultHeaders)
              .timeout(const Duration(seconds: 30));
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }
      return handleResponse(response);
    } catch (e) {
      if (e.toString().contains('Failed to fetch') || e is SocketException) {
        if (kDebugMode) print('🔄 Trying to find alternative server...');
        final workingServer = await findWorkingServer();
        if (workingServer != null && workingServer != currentBaseUrl) {
          return _httpRequest(method, endpoint, data: data);
        }
      }
      return handleError(e);
    }
  }

  // =================== CONNECTION CHECK =====================
  static Future<Map<String, dynamic>> checkConnection() async {
    if (kDebugMode) print('🔍 Checking server connection...');
    try {
      final response = await http
          .get(
            Uri.parse('$currentBaseUrl/health'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return _handleSuccessfulConnection(response);
      }
    } catch (_) {}

    final workingServer = await findWorkingServer();
    if (workingServer != null) {
      try {
        final response = await http
            .get(
              Uri.parse('$workingServer/health'),
              headers: {'Accept': 'application/json'},
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          return _handleSuccessfulConnection(response);
        }
      } catch (_) {}
    }
    return {
      'success': false,
      'connected': false,
      'message':
          '🔴 ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้\n\n• URL ที่ลอง: ${alternativeUrls.join(', ')}\n',
      'attempted_urls': alternativeUrls,
      'suggestions': _getErrorSuggestions('connection_error'),
    };
  }

  static Map<String, dynamic> _handleSuccessfulConnection(
    http.Response response,
  ) {
    if (kDebugMode) {
      print('✅ Server connected: ${response.statusCode}');
      final body = response.body;
      final preview = body.length > 800 ? '${body.substring(0, 800)}...' : body;
      print('📄 Server response (preview): $preview');
    }
    try {
      final data = json.decode(response.body);
      return {
        'success': true,
        'connected': true,
        'server_info': data,
        'message': '✅ เชื่อมต่อเซิร์ฟเวอร์สำเร็จ\nURL: $currentBaseUrl',
        'server_url': currentBaseUrl,
      };
    } catch (_) {
      return {
        'success': true,
        'connected': true,
        'message':
            '✅ เชื่อมต่อเซิร์ฟเวอร์สำเร็จ\nURL: $currentBaseUrl\n(ไม่สามารถอ่านข้อมูลเพิ่มเติมได้)',
        'server_url': currentBaseUrl,
      };
    }
  }

  // ===================== SERVER INFO =======================
  static Future<Map<String, dynamic>> getServerInfo() async {
    try {
      final response = await http
          .get(
            Uri.parse('$currentBaseUrl/'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      return handleResponse(response);
    } catch (e) {
      return handleError(e);
    }
  }

  // ======================= DEBUG ===========================
  static Map<String, dynamic> getDebugInfo() {
    return {
      'current_base_url': currentBaseUrl,
      'has_auth_token': hasAuthToken,
      'token_preview': tokenPreview(),
      'alternative_urls': alternativeUrls,
      'headers': defaultHeaders,
    };
  }
}
