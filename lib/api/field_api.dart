// lib/api/field_api.dart
import 'api_server.dart';

class FieldApiService {
  // ===== Helpers to make data safe for UI =====
  static Map<String, dynamic> safeFieldData(Map raw) {
    return {
      'field_id': (raw['field_id'] as num?)?.toInt() ?? 0,
      'field_name': (raw['field_name'] ?? '').toString(),
      'size_square_meter': (raw['size_square_meter'] is num)
          ? (raw['size_square_meter'] as num).toDouble()
          : double.tryParse(raw['size_square_meter']?.toString() ?? '0') ?? 0.0,
      'vertex_count': (raw['vertex_count'] as num?)?.toInt() ?? 0,
    };
  }

  static Map<String, dynamic> safeZoneData(Map raw) {
    return {
      'zone_id': (raw['zone_id'] as num?)?.toInt() ?? 0,
      'zone_name': (raw['zone_name'] ?? '').toString(),
      'num_trees': (raw['num_trees'] as num?)?.toInt() ?? 0,
      'field_id': (raw['field_id'] as num?)?.toInt(),
      'inspection_count': (raw['inspection_count'] as num?)?.toInt() ?? 0,
    };
  }

  // ===== Fields =====
  static Future<Map<String, dynamic>> getFields() async {
    return ApiServer.get('/api/fields');
  }

  /// รวม zones ต่อ field ด้วยการยิงเพิ่มทีละ field
  static Future<Map<String, dynamic>> getFieldsWithZones() async {
    final fieldsRes = await getFields();
    if (fieldsRes['success'] != true) return fieldsRes;

    final List data = fieldsRes['data'] ?? [];
    final List<Map<String, dynamic>> result = [];
    for (final f in data) {
      final field = Map<String, dynamic>.from(f as Map);
      final fid = (field['field_id'] as num).toInt();
      final zRes = await getZonesByField(fid);
      field['zones'] = (zRes['success'] == true) ? (zRes['data'] ?? []) : [];
      result.add(field);
    }
    return {'success': true, 'data': result};
  }

  static Future<Map<String, dynamic>> getFieldDetails(int fieldId) async {
    return ApiServer.get('/api/fields/$fieldId');
  }

  static Future<Map<String, dynamic>> createField({
    required String fieldName,
    required String sizeSquareMeter,
    List<Map<String, dynamic>> vertices = const [],
  }) async {
    return ApiServer.post('/api/fields', {
      'field_name': fieldName,
      'size_square_meter': sizeSquareMeter,
      'vertices': vertices,
    });
  }

  static Future<Map<String, dynamic>> updateField({
    required int fieldId,
    required String fieldName,
    required String sizeSquareMeter,
    List<Map<String, dynamic>> vertices = const [],
  }) async {
    return ApiServer.put('/api/fields/$fieldId', {
      'field_name': fieldName,
      'size_square_meter': sizeSquareMeter,
      'vertices': vertices,
    });
  }

  static Future<Map<String, dynamic>> deleteField(int fieldId) async {
    return ApiServer.delete('/api/fields/$fieldId');
  }

  // ===== Zones =====
  static Future<Map<String, dynamic>> getZonesByField(int fieldId) async {
    return ApiServer.get('/api/fields/$fieldId/zones');
  }

  static Future<Map<String, dynamic>> createZone({
    required int fieldId,
    required String zoneName,
    required int numTrees,
  }) async {
    return ApiServer.post('/api/zones', {
      'field_id': fieldId,
      'zone_name': zoneName,
      'num_trees': numTrees,
    });
  }

  static Future<Map<String, dynamic>> createZoneWithMarks({
    required int fieldId,
    required String zoneName,
    required List<Map<String, dynamic>> marks,
  }) async {
    return ApiServer.post('/api/zones', {
      'field_id': fieldId,
      'zone_name': zoneName,
      'marks': marks,
    });
  }

  static Future<Map<String, dynamic>> updateZone({
    required int zoneId,
    required String zoneName,
    required int numTrees,
  }) async {
    return ApiServer.put('/api/zones/$zoneId', {
      'zone_name': zoneName,
      'num_trees': numTrees,
    });
  }

  static Future<Map<String, dynamic>> deleteZone(int zoneId) async {
    return ApiServer.delete('/api/zones/$zoneId');
  }

  // ===== Marks =====
  static Future<Map<String, dynamic>> getMarks(int zoneId) async {
    return ApiServer.get('/api/zones/$zoneId/marks');
  }

  static Future<Map<String, dynamic>> createMarksBulk({
    required int zoneId,
    required List<Map<String, dynamic>> marks,
  }) async {
    return ApiServer.post('/api/zones/$zoneId/marks', {'marks': marks});
  }

  /// ใช้แทนที่ marks ทั้งชุด (ต้องมี endpoint PUT ฝั่ง server แล้ว)
  static Future<Map<String, dynamic>> replaceMarks({
    required int zoneId,
    required List<Map<String, dynamic>> marks,
  }) async {
    return ApiServer.put('/api/zones/$zoneId/marks', {'marks': marks});
  }
}
