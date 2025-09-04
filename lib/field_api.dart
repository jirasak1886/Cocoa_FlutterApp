// field_api_service.dart (aligned with routes/field_zone.py)
import 'package:cocoa_app/auth_api.dart';
import 'api_server.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

class FieldApiService {
  static String get baseUrl => ApiServer.currentBaseUrl;
  static Map<String, String> get _headers => ApiServer.defaultHeaders;
  static bool get _hasAuth => ApiServer.hasAuthToken;

  // ---------- helpers ----------
  static Map<String, dynamic> _ok([dynamic data, String? message]) => {
    'success': true,
    if (data != null) 'data': data,
    if (message != null) 'message': message,
  };
  static Map<String, dynamic> _err(
    String error,
    String message, {
    int? code,
    bool login = false,
    dynamic data,
  }) => {
    'success': false,
    'error': error,
    'message': message,
    if (code != null) 'status_code': code,
    if (login) 'requires_login': true,
    if (data != null) 'data': data,
  };
  static bool _badId(int v) => v <= 0;
  static bool _blank(String v) => v.trim().isEmpty;

  // ---------- core request ----------
  static Future<Map<String, dynamic>> _makeRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? data,
  }) async {
    try {
      if (!_hasAuth) await AuthApiService.initAuth();
      if (!_hasAuth) {
        return _err('unauthorized', 'ไม่พบ Token การยืนยันตัวตน', login: true);
      }

      final uri = Uri.parse('$baseUrl$endpoint');
      http.Response r;
      switch (method) {
        case 'GET':
          r = await http
              .get(uri, headers: _headers)
              .timeout(const Duration(seconds: 30));
          break;
        case 'POST':
          r = await http
              .post(
                uri,
                headers: _headers,
                body: data != null ? json.encode(data) : null,
              )
              .timeout(const Duration(seconds: 30));
          break;
        case 'PUT':
          r = await http
              .put(
                uri,
                headers: _headers,
                body: data != null ? json.encode(data) : null,
              )
              .timeout(const Duration(seconds: 30));
          break;
        case 'DELETE':
          r = await http
              .delete(uri, headers: _headers)
              .timeout(const Duration(seconds: 30));
          break;
        default:
          return _err('unsupported_method', 'ไม่รองรับ HTTP method: $method');
      }

      if (r.statusCode == 401) {
        await AuthApiService.clearAuth();
        return _err(
          'token_expired',
          'Token หมดอายุ กรุณาเข้าสู่ระบบใหม่',
          login: true,
          code: 401,
        );
      }
      if (r.statusCode == 403) {
        return _err('forbidden', 'ไม่มีสิทธิ์ในการเข้าถึงข้อมูลนี้', code: 403);
      }

      if (r.statusCode >= 200 && r.statusCode < 300) {
        try {
          final decoded = json.decode(r.body);
          return decoded is Map<String, dynamic> ? decoded : _ok(decoded);
        } catch (_) {
          return _ok(r.body, 'สำเร็จ');
        }
      }

      // client/server error
      try {
        final body = json.decode(r.body) as Map<String, dynamic>;
        return {
          'success': false,
          ...body,
          'status_code': r.statusCode,
          'message': body['message'] ?? 'HTTP ${r.statusCode}',
        };
      } catch (_) {
        return _err(
          r.statusCode < 500 ? 'client_error' : 'server_error',
          'HTTP ${r.statusCode}',
          code: r.statusCode,
        );
      }
    } catch (e) {
      if (kDebugMode) print('❌ API Error: $e');
      return _err('network_error', 'เกิดข้อผิดพลาดในการเชื่อมต่อ: $e');
    }
  }

  // ---------- auth utils ----------
  static bool requiresLogin(Map<String, dynamic> res) =>
      res['requires_login'] == true ||
      res['error'] == 'token_expired' ||
      res['error'] == 'unauthorized';

  static Future<Map<String, dynamic>> forceLogout([String? msg]) async {
    await AuthApiService.clearAuth();
    return _err('force_logout', msg ?? 'กรุณาเข้าสู่ระบบใหม่', login: true);
  }

  // ---------- fields ----------
  static Future<Map<String, dynamic>> getFields() async {
    // GET /api/fields  → data: [{ field_id, field_name, size_square_meter, created_at, vertex_count }]
    final r = await _makeRequest('GET', '/api/fields');
    if (r['success'] == true && r['data'] == null) r['data'] = [];
    return r;
  }

  static Future<Map<String, dynamic>> getFieldDetails(int id) async =>
      _badId(id)
      ? _err('validation_error', 'Field ID ไม่ถูกต้อง', data: null)
      : _makeRequest('GET', '/api/fields/$id'); // → includes vertices[]

  static Future<Map<String, dynamic>> createField({
    required String fieldName,
    required String sizeSquareMeter,
    List<Map<String, dynamic>>? vertices, // [{latitude/lat, longitude/lng}]
  }) {
    if (_blank(fieldName)) {
      return Future.value(_err('validation_error', 'กรุณาใส่ชื่อแปลง'));
    }
    if (_blank(sizeSquareMeter)) {
      return Future.value(_err('validation_error', 'กรุณาใส่ขนาดพื้นที่'));
    }
    final size = double.tryParse(sizeSquareMeter);
    if (size == null || size <= 0) {
      return Future.value(
        _err('validation_error', 'ขนาดพื้นที่ต้องมากกว่า 0 (หน่วยตร.ม.)'),
      );
    }
    // payload ตาม server: ไม่ส่ง latitude/longitude ใน field; ส่ง vertices ได้
    final payload = <String, dynamic>{
      'field_name': fieldName.trim(),
      'size_square_meter': sizeSquareMeter,
      if (vertices != null && vertices.isNotEmpty) 'vertices': vertices,
    };
    return _makeRequest('POST', '/api/fields', data: payload);
  }

  static Future<Map<String, dynamic>> updateField({
    required int fieldId,
    required String fieldName,
    required String sizeSquareMeter,
    List<Map<String, dynamic>>? vertices, // แทนที่ทั้งชุดถ้าส่งมา
  }) {
    if (_badId(fieldId)) {
      return Future.value(_err('validation_error', 'Field ID ไม่ถูกต้อง'));
    }
    if (_blank(fieldName)) {
      return Future.value(_err('validation_error', 'กรุณาใส่ชื่อแปลง'));
    }
    if (_blank(sizeSquareMeter)) {
      return Future.value(_err('validation_error', 'กรุณาใส่ขนาดพื้นที่'));
    }
    final size = double.tryParse(sizeSquareMeter);
    if (size == null || size <= 0) {
      return Future.value(
        _err('validation_error', 'ขนาดพื้นที่ต้องมากกว่า 0 (หน่วยตร.ม.)'),
      );
    }
    final payload = <String, dynamic>{
      'field_name': fieldName.trim(),
      'size_square_meter': sizeSquareMeter,
      if (vertices != null) 'vertices': vertices, // ส่ง list ว่าง = ลบ vertices
    };
    return _makeRequest('PUT', '/api/fields/$fieldId', data: payload);
  }

  static Future<Map<String, dynamic>> deleteField(int id) => _badId(id)
      ? Future.value(_err('validation_error', 'Field ID ไม่ถูกต้อง'))
      : _makeRequest('DELETE', '/api/fields/$id');

  // ---------- zones ----------
  static Future<Map<String, dynamic>> getZones(int fieldId) async {
    if (_badId(fieldId)) {
      return _err('invalid_field_id', 'Field ID ไม่ถูกต้อง', data: []);
    }
    final r = await _makeRequest('GET', '/api/fields/$fieldId/zones');
    if (r['success'] == true && r['data'] == null) r['data'] = [];
    return r;
  }

  static Future<Map<String, dynamic>> getZoneDetails(int id) async => _badId(id)
      ? _err('validation_error', 'Zone ID ไม่ถูกต้อง', data: null)
      : _makeRequest('GET', '/api/zones/$id');

  static Future<Map<String, dynamic>> createZone({
    required int fieldId,
    required String zoneName,
    required int numTrees,
  }) {
    if (_badId(fieldId)) {
      return Future.value(_err('validation_error', 'Field ID ไม่ถูกต้อง'));
    }
    if (_blank(zoneName)) {
      return Future.value(_err('validation_error', 'กรุณาใส่ชื่อโซน'));
    }
    if (numTrees < 0) {
      return Future.value(_err('validation_error', 'จำนวนต้นไม้ต้องไม่ติดลบ'));
    }
    final data = {
      'field_id': fieldId,
      'zone_name': zoneName.trim(),
      'num_trees': numTrees,
    };
    return _makeRequest('POST', '/api/zones', data: data);
  }

  /// สร้างโซนพร้อม marks หลายรายการ
  static Future<Map<String, dynamic>> createZoneWithMarks({
    required int fieldId,
    required String zoneName,
    required List<Map<String, dynamic>>
    marks, // [{tree_no, latitude, longitude}]
  }) {
    if (_badId(fieldId) || _blank(zoneName)) {
      return Future.value(_err('validation_error', 'Field/Zone ไม่ถูกต้อง'));
    }
    if (marks.isEmpty) {
      return Future.value(
        _err('validation_error', 'ต้องมี marks อย่างน้อย 1 รายการ'),
      );
    }
    final data = {
      'field_id': fieldId,
      'zone_name': zoneName.trim(),
      'num_trees': marks.length,
      'marks': marks,
    };
    return _makeRequest('POST', '/api/zones', data: data);
  }

  static Future<Map<String, dynamic>> updateZone({
    required int zoneId,
    required String zoneName,
    required int numTrees,
  }) {
    if (_badId(zoneId)) {
      return Future.value(_err('validation_error', 'Zone ID ไม่ถูกต้อง'));
    }
    if (_blank(zoneName)) {
      return Future.value(_err('validation_error', 'กรุณาใส่ชื่อโซน'));
    }
    if (numTrees < 0) {
      return Future.value(_err('validation_error', 'จำนวนต้นไม้ต้องไม่ติดลบ'));
    }
    return _makeRequest(
      'PUT',
      '/api/zones/$zoneId',
      data: {'zone_name': zoneName.trim(), 'num_trees': numTrees},
    );
  }

  static Future<Map<String, dynamic>> deleteZone(int id) => _badId(id)
      ? Future.value(_err('validation_error', 'Zone ID ไม่ถูกต้อง'))
      : _makeRequest('DELETE', '/api/zones/$id');

  // ---------- marks (mark_zone) ----------
  static Future<Map<String, dynamic>> getMarks(int zoneId) async {
    if (_badId(zoneId)) {
      return _err('validation_error', 'Zone ID ไม่ถูกต้อง', data: []);
    }
    final r = await _makeRequest('GET', '/api/zones/$zoneId/marks');
    if (r['success'] == true && r['data'] == null) r['data'] = [];
    return r;
  }

  static Future<Map<String, dynamic>> createMark({
    required int zoneId,
    required int treeNo,
    required double latitude,
    required double longitude,
  }) {
    if (_badId(zoneId) || treeNo <= 0) {
      return Future.value(
        _err('validation_error', 'Zone ID/Tree No ไม่ถูกต้อง'),
      );
    }
    return _makeRequest(
      'POST',
      '/api/zones/$zoneId/marks',
      data: {'tree_no': treeNo, 'latitude': latitude, 'longitude': longitude},
    );
  }

  static Future<Map<String, dynamic>> createMarksBulk({
    required int zoneId,
    required List<Map<String, dynamic>> marks,
  }) {
    if (_badId(zoneId)) {
      return Future.value(_err('validation_error', 'Zone ID ไม่ถูกต้อง'));
    }
    if (marks.isEmpty) {
      return Future.value(
        _err('validation_error', 'ไม่มีข้อมูล marks ที่จะเพิ่ม'),
      );
    }
    final valid = marks.every(
      (m) =>
          m.containsKey('tree_no') &&
          m.containsKey('latitude') &&
          m.containsKey('longitude'),
    );
    if (!valid) {
      return Future.value(
        _err('validation_error', 'marks ต้องมี tree_no, latitude, longitude'),
      );
    }
    return _makeRequest(
      'POST',
      '/api/zones/$zoneId/marks',
      data: {'marks': marks},
    );
  }

  // ฝั่งเซิร์ฟเวอร์ยังไม่มี endpoint สำหรับอัปเดต/ลบ mark
  static Future<Map<String, dynamic>> updateMark({
    required int zoneId,
    required int markId,
    required int treeNo,
    required double latitude,
    required double longitude,
  }) {
    return Future.value(
      _err(
        'unsupported',
        'เซิร์ฟเวอร์ยังไม่รองรับการอัปเดต mark (PUT /api/zones/{zone_id}/marks/{mark_id})',
      ),
    );
  }

  static Future<Map<String, dynamic>> deleteMark({
    required int zoneId,
    required int markId,
  }) {
    return Future.value(
      _err(
        'unsupported',
        'เซิร์ฟเวอร์ยังไม่รองรับการลบ mark (DELETE /api/zones/{zone_id}/marks/{mark_id})',
      ),
    );
  }

  static Future<Map<String, dynamic>> getZoneWithMarks(int zoneId) async {
    final z = await getZoneDetails(zoneId);
    if (!z['success']) return z;
    final m = await getMarks(zoneId);
    final data = Map<String, dynamic>.from(z['data'] ?? {});
    data['marks'] = m['success'] ? (m['data'] ?? []) : [];
    data['mark_count'] = (data['marks'] as List).length;
    return _ok(data);
  }

  static Map<String, dynamic> safeFieldData(Map<String, dynamic>? f) => {
    'field_id': f?['field_id'] ?? f?['id'] ?? 0,
    'field_name': f?['field_name'] ?? f?['name'] ?? 'ไม่มีชื่อ',
    'size_square_meter': f?['size_square_meter'] ?? f?['size'] ?? '0',
    'vertex_count': f?['vertex_count'] ?? 0, // จาก GET /api/fields
    'created_at': f?['created_at'],
    'updated_at': f?['updated_at'],
  };

  static Map<String, dynamic> safeZoneData(Map<String, dynamic>? z) => {
    'zone_id': z?['zone_id'] ?? z?['id'] ?? 0,
    'zone_name': z?['zone_name'] ?? z?['name'] ?? 'ไม่มีชื่อ',
    'num_trees': z?['num_trees'] ?? 0,
    'field_id': z?['field_id'] ?? 0,
    'inspection_count': z?['inspection_count'] ?? 0,
    'created_at': z?['created_at'],
    'updated_at': z?['updated_at'],
  };

  // ---------- batch / stats ----------
  static Future<Map<String, dynamic>> createMultipleZones({
    required int fieldId,
    required List<Map<String, dynamic>> zones,
  }) async {
    if (_badId(fieldId)) {
      return _err('validation_error', 'Field ID ไม่ถูกต้อง', data: []);
    }
    if (zones.isEmpty) {
      return _err('validation_error', 'ไม่มีข้อมูลโซนที่จะสร้าง', data: []);
    }
    final results = <Map<String, dynamic>>[], errors = <String>[];
    for (final z in zones) {
      final r = await createZone(
        fieldId: fieldId,
        zoneName: (z['zone_name'] ?? '').toString(),
        numTrees: (z['num_trees'] ?? 0) as int,
      );
      r['success']
          ? results.add(r['data'] ?? {})
          : errors.add('${z['zone_name']}: ${r['message']}');
    }
    return {
      'success': errors.isEmpty,
      'message': errors.isEmpty
          ? 'สร้างโซนทั้งหมดสำเร็จ'
          : 'สร้างโซนบางส่วนไม่สำเร็จ',
      'data': results,
      'errors': errors,
      'successful_count': results.length,
      'error_count': errors.length,
    };
  }

  static Future<Map<String, dynamic>> searchFields(String q) async {
    final r = await getFields();
    if (!r['success']) return r;
    final fields = List<Map<String, dynamic>>.from(r['data'] ?? []);
    final filtered = fields
        .where(
          (f) => (f['field_name'] ?? '').toString().toLowerCase().contains(
            q.toLowerCase(),
          ),
        )
        .toList();
    return _ok(filtered)..addAll({'total_count': filtered.length, 'query': q});
  }

  static Future<Map<String, dynamic>> getFieldsStatistics() async {
    final all = await getFieldsWithZones();
    if (!all['success']) return all;
    final fields = List<Map<String, dynamic>>.from(all['data'] ?? []);
    int zones = 0, trees = 0, withGeom = 0;
    double area = 0;
    for (final f in fields) {
      final z = List<Map<String, dynamic>>.from(f['zones'] ?? []);
      zones += z.length;
      for (final e in z) {
        trees += (e['num_trees'] ?? 0) as int;
      }
      area += double.tryParse((f['size_square_meter'] ?? '0').toString()) ?? 0;
      // ถือว่ามี geometry ถ้า vertex_count > 0 หรือถ้า endpoint details มี vertices
      final vc = (f['vertex_count'] ?? 0) as int;
      if (vc > 0) withGeom++;
    }
    return _ok({
      'total_fields': fields.length,
      'total_zones': zones,
      'total_trees': trees,
      'total_area_square_meters': area,
      'total_area_rai': (area / 1600).toStringAsFixed(2),
      'fields_with_geometry': withGeom,
      'fields_without_geometry': (fields.length - withGeom),
      'average_zones_per_field': fields.isNotEmpty
          ? (zones / fields.length).toStringAsFixed(1)
          : '0',
      'average_trees_per_zone': zones > 0
          ? (trees / zones).toStringAsFixed(1)
          : '0',
    })..addAll({'timestamp': DateTime.now().toIso8601String()});
  }

  static Future<Map<String, dynamic>> getFieldsWithZones() async {
    final fr = await getFields();
    if (!fr['success']) return fr;
    final fields = List<Map<String, dynamic>>.from(fr['data'] ?? []);
    for (final f in fields) {
      final id = f['field_id'];
      f['zones'] = (id is int && id > 0)
          ? (await getZones(id))['data'] ?? []
          : [];
    }
    return _ok(fields);
  }

  // ---------- health/debug ----------
  static Future<Map<String, dynamic>> testConnection() async {
    if (!_hasAuth) {
      return _err('no_token', '❌ ไม่พบ Token การยืนยันตัวตน', login: true);
    }
    final r = await getFields();
    if (r['success']) {
      return _ok(null, '✅ การเชื่อมต่อและ JWT ใช้งานได้')..addAll({
        'token_valid': true,
        'server_responsive': true,
        'server_url': baseUrl,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
    if (requiresLogin(r)) {
      return _err(
        'token_expired',
        'Token หมดอายุ กรุณาเข้าสู่ระบบใหม่',
        login: true,
      );
    }
    return _err(r['error'] ?? 'unknown', r['message'] ?? 'ผิดพลาด');
  }

  static Future<Map<String, dynamic>> pingServer() async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/health'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      return _ok({
        'status_code': res.statusCode,
        'server_url': baseUrl,
        'response_time': DateTime.now().toIso8601String(),
      })..addAll({'success': res.statusCode == 200, 'server_responsive': true});
    } catch (e) {
      return _err('ping_failed', 'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้: $e')
        ..addAll({'server_url': baseUrl, 'server_responsive': false});
    }
  }

  static void reset() {
    if (kDebugMode) print('🔄 FieldApiService reset');
  }

  static bool isSuccess(Map<String, dynamic> r) => r['success'] == true;
  static String getErrorMessage(Map<String, dynamic> r) =>
      r['message'] ?? r['error'] ?? 'Unknown error';
  static dynamic getData(Map<String, dynamic> r) => r['data'];

  static Map<String, dynamic> getDebugInfo() => {
    'service_name': 'FieldApiService',
    'base_url': baseUrl,
    'has_auth': _hasAuth,
    'version': '2.3.0-aligned',
    'last_updated': DateTime.now().toIso8601String(),
    'supported_endpoints': [
      'GET /api/fields',
      'POST /api/fields',
      'PUT /api/fields/{id}',
      'DELETE /api/fields/{id}',
      'GET /api/fields/{id}',
      'GET /api/fields/{id}/zones',
      'POST /api/zones',
      'PUT /api/zones/{id}',
      'DELETE /api/zones/{id}',
      'GET /api/zones/{id}',
      'GET /api/zones/{zone_id}/marks',
      'POST /api/zones/{zone_id}/marks',
      // update/delete mark: not supported by server yet
    ],
  };
}
