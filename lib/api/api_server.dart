// lib/api/api_server.dart
import 'package:cocoa_app/utils/variable.dart'; // <- baseUrl & alternativeUrls
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// === Helper type สำหรับอัปโหลดแบบ bytes (ใช้กับ Web/กรณีไม่มี path) ===
class UploadByteFile {
  final List<int> bytes;
  final String filename;
  final String? contentType;
  const UploadByteFile({
    required this.bytes,
    required this.filename,
    this.contentType,
  });
}

class ApiServer {
  // ======================== CONFIG =========================
  static const bool _LOG_FULL_TOKEN_IN_DEBUG = false;
  static const String _kPrefsBaseUrl = 'api_base_url';

  // ======================== STATE ==========================
  static String? _jwtToken;
  static String? _currentBaseUrl = baseUrl; // เริ่มจากค่าใน variable.dart

  // ======================== INIT ===========================
  /// เรียกใน main() ก่อน runApp เพื่อโหลด baseUrl ที่เคยจำไว้
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kPrefsBaseUrl);
      if (saved != null && saved.trim().isNotEmpty) {
        _currentBaseUrl = saved.trim();
      } else {
        _currentBaseUrl = baseUrl;
      }
      if (kDebugMode) {
        print('🧭 ApiServer.init → default:$baseUrl | using: $_currentBaseUrl');
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ ApiServer.init error: $e');
    }
  }

  // ======================== URL ============================
  static Future<void> setBaseUrl(String url) async {
    _currentBaseUrl = url.trim();
    if (kDebugMode) print('🌐 Base URL set to: $_currentBaseUrl');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsBaseUrl, _currentBaseUrl!);
    } catch (e) {
      if (kDebugMode) print('⚠️ save baseUrl failed: $e');
    }
  }

  static String get currentBaseUrl => _currentBaseUrl ?? baseUrl;

  // ======================== TOKEN ==========================
  static void updateAuthHeaders(String token) {
    var t = token.trim();
    if (t.toLowerCase().startsWith('bearer ')) {
      t = t.substring(7).trim();
    }
    _jwtToken = t;
    if (kDebugMode) print('🔑 JWT Token updated');
  }

  static void clearAuthHeaders() {
    _jwtToken = null;
    if (kDebugMode) print('🗑️ JWT Token cleared');
  }

  static bool get hasAuthToken => _jwtToken != null && _jwtToken!.isNotEmpty;
  static String? get currentToken => _jwtToken;

  static String tokenPreview({int head = 20, int tail = 10}) {
    final t = _jwtToken;
    if (t == null || t.isEmpty) return '<null>';
    if (_LOG_FULL_TOKEN_IN_DEBUG && kDebugMode) return t;
    if (t.length <= head + tail) return t;
    return '${t.substring(0, head)}...${t.substring(t.length - tail)}';
  }

  static void printCurrentToken() {
    final label = _LOG_FULL_TOKEN_IN_DEBUG && kDebugMode
        ? '(full)'
        : '(preview)';
    if (kDebugMode) print('🔐 Current JWT $label: ${tokenPreview()}');
  }

  // ====================== HEADERS ==========================
  static Map<String, String> get defaultHeaders {
    final headers = <String, String>{'Accept': 'application/json'};
    if (hasAuthToken) {
      headers['Authorization'] = 'Bearer ${_jwtToken!.trim()}';
    }
    return headers;
  }

  static Map<String, String> get jsonHeaders => {
    ...defaultHeaders,
    'Content-Type': 'application/json',
  };

  static Map<String, String> jsonHeadersWith({Map<String, String>? extra}) {
    return {...jsonHeaders, if (extra != null) ...extra};
  }

  static Map<String, String> jsonHeadersExact(String token) {
    final t = token.trim().toLowerCase().startsWith('bearer ')
        ? token.trim().substring(7).trim()
        : token.trim();
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $t',
    };
  }

  // =================== RESPONSE PARSING =====================
  static Map<String, dynamic> handleResponse(http.Response response) {
    final ok = response.statusCode >= 200 && response.statusCode < 300;

    if (kDebugMode) {
      final bodyPrev = utf8.decode(response.bodyBytes, allowMalformed: true);
      final preview = bodyPrev.length > 800
          ? '${bodyPrev.substring(0, 800)}...'
          : bodyPrev;
      print('📤 Response Status: ${response.statusCode}');
      print('📄 Response Body (preview): $preview');
    }

    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('application/json')) {
      try {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          return {
            'success': decoded.containsKey('success') ? decoded['success'] : ok,
            'status': response.statusCode,
            ...decoded,
          };
        } else {
          return {
            'success': ok,
            'status': response.statusCode,
            'data': decoded,
          };
        }
      } catch (e) {
        return {
          'success': false,
          'status': response.statusCode,
          'error': 'response_parse_error',
          'message': 'ไม่สามารถประมวลผลข้อมูลจากเซิร์ฟเวอร์ได้: $e',
          'raw_response': utf8.decode(response.bodyBytes, allowMalformed: true),
        };
      }
    }

    return {
      'success': ok,
      'status': response.statusCode,
      'message': utf8.decode(response.bodyBytes, allowMalformed: true),
      'raw_response': true,
    };
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
    // รวม current + alternativeUrls (จาก utils/variable.dart) และตัดซ้ำ
    final tried = <String>{};
    final candidates =
        <String>[
          if (_currentBaseUrl != null) _currentBaseUrl!,
          ...alternativeUrls,
        ].where((u) {
          final keep = !tried.contains(u);
          tried.add(u);
          return keep;
        }).toList();

    for (final url in candidates) {
      try {
        final response = await http
            .get(Uri.parse('$url/health'))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          _currentBaseUrl = url;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_kPrefsBaseUrl, _currentBaseUrl!);
          } catch (_) {}
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

  static Future<Map<String, dynamic>> patch(
    String endpoint,
    Map<String, dynamic> data,
  ) async => _httpRequest('PATCH', endpoint, data: data);

  static Future<Map<String, dynamic>> delete(String endpoint) async =>
      _httpRequest('DELETE', endpoint);

  static Future<Map<String, dynamic>> postWithHeaders(
    String endpoint,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  }) async {
    try {
      if (kDebugMode) {
        print('🚀 POST (custom headers): $currentBaseUrl$endpoint');
        print('📦 Data: $data');
        print('🧾 Extra headers (merged): $headers');
      }
      final uri = Uri.parse('$currentBaseUrl$endpoint');
      final response = await http
          .post(
            uri,
            headers: jsonHeadersWith(extra: headers),
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 60));
      return handleResponse(response);
    } catch (e) {
      return handleError(e);
    }
  }

  static Future<Map<String, dynamic>> postWithExactHeaders(
    String endpoint,
    Map<String, dynamic> data, {
    required Map<String, String> exactHeaders,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      if (kDebugMode) {
        print('🚀 POST (EXACT headers): $currentBaseUrl$endpoint');
        print('📦 Data: $data');
        print('🧾 Headers (exact): $exactHeaders');
      }
      final uri = Uri.parse('$currentBaseUrl$endpoint');
      final response = await http
          .post(uri, headers: exactHeaders, body: json.encode(data))
          .timeout(timeout);
      return handleResponse(response);
    } catch (e) {
      return handleError(e);
    }
  }

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
                headers: jsonHeaders,
                body: data != null ? json.encode(data) : null,
              )
              .timeout(const Duration(seconds: 60));
          break;
        case 'PUT':
          response = await http
              .put(
                uri,
                headers: jsonHeaders,
                body: data != null ? json.encode(data) : null,
              )
              .timeout(const Duration(seconds: 60));
          break;
        case 'PATCH':
          response = await http
              .patch(
                uri,
                headers: jsonHeaders,
                body: data != null ? json.encode(data) : null,
              )
              .timeout(const Duration(seconds: 60));
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
      // auto-fallback หา server ตัวที่ตอบสนอง
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

  // ============== MULTIPART (UPLOAD FILES: File path) ======
  static Future<Map<String, dynamic>> postMultipart(
    String endpoint, {
    Map<String, String>? fields,
    List<File>? files,
    String fileFieldName = 'images',
  }) async {
    try {
      final url = Uri.parse('$currentBaseUrl$endpoint');
      final req = http.MultipartRequest('POST', url);

      if (kDebugMode) print('🖼️ Multipart upload → $endpoint');

      req.headers.addAll(defaultHeaders);

      if (fields != null && fields.isNotEmpty) {
        req.fields.addAll(fields);
      }

      final List<File> safeFiles = (files ?? <File>[])
          .where((f) => f.existsSync())
          .toList();
      final toUpload = safeFiles.take(5).toList(); // limit 5

      if (kDebugMode) print('🖼️ Files (path) count: ${toUpload.length}');

      for (final f in toUpload) {
        req.files.add(await http.MultipartFile.fromPath(fileFieldName, f.path));
      }

      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final res = await http.Response.fromStream(streamed);
      return handleResponse(res);
    } catch (e) {
      return handleError(e);
    }
  }

  // ============== MULTIPART (UPLOAD BYTES) =================
  static String _guessMimeFromName(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.bmp')) return 'image/bmp';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  static Future<Map<String, dynamic>> postMultipartBytes(
    String endpoint, {
    Map<String, String>? fields,
    required List<({List<int> bytes, String filename, String? contentType})>
    files,
    String fileFieldName = 'images',
  }) async {
    try {
      final url = Uri.parse('$currentBaseUrl$endpoint');
      final req = http.MultipartRequest('POST', url);

      if (kDebugMode) print('🖼️ Multipart (bytes) upload → $endpoint');

      req.headers.addAll(defaultHeaders);

      if (fields != null && fields.isNotEmpty) {
        req.fields.addAll(fields);
      }

      final limited = files.take(5).toList(); // limit 5
      if (kDebugMode) print('🖼️ Files (bytes) count: ${limited.length}');

      for (final f in limited) {
        final mime = (f.contentType ?? _guessMimeFromName(f.filename));
        final parts = mime.split('/');
        final type = parts.first;
        final sub = parts.length > 1 ? parts.last : 'octet-stream';
        req.files.add(
          http.MultipartFile.fromBytes(
            fileFieldName,
            f.bytes,
            filename: f.filename,
            contentType: MediaType(type, sub),
          ),
        );
      }

      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final res = await http.Response.fromStream(streamed);
      return handleResponse(res);
    } catch (e) {
      return handleError(e);
    }
  }

  /// Convenience: BYTES
  static Future<Map<String, dynamic>> uploadInspectionImagesBytes({
    required int inspectionId,
    required List<UploadByteFile> files,
    String fieldName = 'images',
    Map<String, String>? fields,
  }) async {
    if (files.isEmpty) {
      return {
        'success': false,
        'error': 'no_files',
        'message': 'No files to upload',
      };
    }

    final payload =
        <({List<int> bytes, String filename, String? contentType})>[];
    for (final f in files) {
      payload.add((
        bytes: f.bytes,
        filename: f.filename,
        contentType: f.contentType,
      ));
    }

    return await postMultipartBytes(
      '/api/inspections/$inspectionId/images',
      fields: fields,
      files: payload,
      fileFieldName: fieldName,
    );
  }

  /// Convenience: FILE PATH
  static Future<Map<String, dynamic>> uploadInspectionImagesFiles({
    required int inspectionId,
    required List<File> files,
    String fieldName = 'images',
    Map<String, String>? fields,
  }) async {
    if (files.isEmpty) {
      return {
        'success': false,
        'error': 'no_files',
        'message': 'No files to upload',
      };
    }
    return await postMultipart(
      '/api/inspections/$inspectionId/images',
      fields: fields,
      files: files,
      fileFieldName: fieldName,
    );
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
          '🔴 ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้\n\n• URL ที่ลอง: '
          '${alternativeUrls.join(', ')}\n',
      'attempted_urls': alternativeUrls,
      'suggestions': _getErrorSuggestions('connection_error'),
    };
  }

  static Map<String, dynamic> _handleSuccessfulConnection(
    http.Response response,
  ) {
    if (kDebugMode) {
      print('✅ Server connected: ${response.statusCode}');
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final preview = body.length > 800 ? '${body.substring(0, 800)}...' : body;
      print('📄 Server response (preview): $preview');
    }
    try {
      final data = json.decode(utf8.decode(response.bodyBytes));
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

  // =================== Extras (optional) ====================
  static Future<Map<String, dynamic>> getWithQuery(
    String endpoint, {
    Map<String, String>? query,
  }) async {
    try {
      final uri = Uri.parse(
        '$currentBaseUrl$endpoint',
      ).replace(queryParameters: query);
      final r = await http
          .get(uri, headers: defaultHeaders)
          .timeout(const Duration(seconds: 30));
      return handleResponse(r);
    } catch (e) {
      return handleError(e);
    }
  }

  // =================== AUTH SHORTCUTS =======================
  static Future<Map<String, dynamic>> authLogin({
    required String username,
    required String password,
  }) {
    return post('/api/auth/login', {
      'username': username,
      'password': password,
    });
  }

  static Future<Map<String, dynamic>> authRegister({
    required String username,
    required String userTel,
    required String userEmail,
    required String password,
    required String confirmPassword,
    required String name,
  }) {
    return post('/api/auth/register', {
      'username': username,
      'user_tel': userTel,
      'user_email': userEmail,
      'password': password,
      'confirm_password': confirmPassword,
      'name': name,
    });
  }

  // ============== PASSWORD RESET (EMAIL OTP) ===============
  static Future<Map<String, dynamic>> requestPasswordReset(String email) {
    return post('/api/auth/request-password-reset', {
      'identifier': email.trim().toLowerCase(),
    });
  }

  static Future<Map<String, dynamic>> verifyPasswordReset({
    required String email,
    required String otp,
  }) {
    return post('/api/auth/verify-reset', {
      'identifier': email.trim().toLowerCase(),
      'otp': otp.trim(),
    });
  }

  static Future<Map<String, dynamic>> resetPassword({
    required String tempToken,
    required String newPassword,
  }) {
    if (kDebugMode) {
      final prev = tempToken.length > 15
          ? '${tempToken.substring(0, 15)}...'
          : tempToken;
      print('🔐 Reset password with tempToken: $prev');
    }
    return postWithExactHeaders('/api/auth/reset-password', {
      'new_password': newPassword,
    }, exactHeaders: jsonHeadersExact(tempToken));
  }
}
