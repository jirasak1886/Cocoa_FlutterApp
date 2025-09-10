// lib/api/inspection_api.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import 'api_server.dart';

class InspectionApi {
  /// เริ่มรอบตรวจ
  static Future<Map<String, dynamic>> startInspection({
    required int fieldId,
    required int zoneId,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'field_id': fieldId,
        'zone_id': zoneId,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      };
      return await ApiServer.post('/api/inspections/start', body);
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  /// อัปโหลดรูป ≤ 5 แบบ multipart
  static Future<Map<String, dynamic>> uploadImages({
    required int inspectionId,
    required List<PlatformFile> images,
  }) async {
    try {
      // เตรียมไฟล์จาก PlatformFile (bytes/path)
      final files =
          <({List<int> bytes, String filename, String? contentType})>[];
      final take = images.take(5).toList();

      for (final pf in take) {
        final name = pf.name;
        String? mime;

        // เดา MIME จาก bytes ก่อน ถ้าไม่มี ลองจากชื่อไฟล์
        if (pf.bytes != null && pf.bytes!.isNotEmpty) {
          mime = lookupMimeType(name, headerBytes: pf.bytes!);
        }
        mime ??= lookupMimeType(name);

        if (!kIsWeb && pf.path != null) {
          // มี path → จะให้ไปใช้ postMultipart จาก path ก็ได้
          // แต่เพื่อความคงที่ เราอ่านเป็น bytes ถ้ามี
          if (pf.bytes != null && pf.bytes!.isNotEmpty) {
            files.add((bytes: pf.bytes!, filename: name, contentType: mime));
          } else {
            // ถ้าไม่มี bytes ในบางแพลตฟอร์ม ให้ข้าม (หรือจะอ่านไฟล์จาก path มาเป็น bytes เองก็ได้)
            continue;
          }
        } else {
          final bytes = pf.bytes;
          if (bytes == null || bytes.isEmpty) continue;
          files.add((bytes: bytes, filename: name, contentType: mime));
        }
      }

      return await ApiServer.postMultipartBytes(
        '/api/inspections/$inspectionId/images',
        files: files,
      );
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  /// สั่งรันโมเดลวิเคราะห์รูป
  static Future<Map<String, dynamic>> runAnalyze(int inspectionId) async {
    try {
      return await ApiServer.post('/api/inspections/$inspectionId/analyze', {});
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  /// รายการล่าสุด (เรียกง่าย ๆ)
  static Future<Map<String, dynamic>> getLatestInspections() async {
    try {
      return await ApiServer.get('/api/inspections');
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  /// รายละเอียดรอบตรวจ
  static Future<Map<String, dynamic>> getInspectionDetail(
    int inspectionId,
  ) async {
    try {
      return await ApiServer.get('/api/inspections/$inspectionId');
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  // ========= คำแนะนำปุ๋ย =========

  /// ดึงคำแนะนำปุ๋ยของรอบตรวจ (named param)
  static Future<Map<String, dynamic>> getRecommendations({
    required int inspectionId,
  }) async {
    try {
      return await ApiServer.get(
        '/api/inspections/$inspectionId/recommendations',
      );
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  /// อัปเดตสถานะคำแนะนำ: suggested | applied | skipped
  /// applied จะส่ง applied_date เป็น 'YYYY-MM-DD'
  static Future<Map<String, dynamic>> updateRecommendationStatus({
    required int recommendationId,
    required String status,
    String? appliedDate,
  }) async {
    try {
      final body = <String, dynamic>{
        'status': status,
        if (appliedDate != null) 'applied_date': appliedDate,
      };
      return await ApiServer.patch(
        '/api/inspections/recommendations/$recommendationId',
        body,
      );
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  // ========= ประวัติ / สถิติ =========

  /// สรุปประวัติแบบ bucket รายเดือน/รายปี พร้อม top nutrients
  static Future<Map<String, dynamic>> getHistory({
    String group = 'month', // 'month' | 'year'
    String? from,
    String? to,
    int? fieldId,
    int? zoneId,
  }) async {
    try {
      final q = <String, String>{'group': group};
      if (from != null) q['from'] = from;
      if (to != null) q['to'] = to;
      if (fieldId != null) q['field_id'] = '$fieldId';
      if (zoneId != null) q['zone_id'] = '$zoneId';

      final url = Uri.parse(
        '${ApiServer.currentBaseUrl}/api/inspections/history',
      ).replace(queryParameters: q);
      final res = await http.get(url, headers: ApiServer.defaultHeaders);
      return ApiServer.handleResponse(res);
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  /// รายการรอบตรวจแบบแบ่งหน้า/ตัวกรอง (ไว้โชว์ตาราง หรือดึง rec ต่อช่วง)
  static Future<Map<String, dynamic>> listInspections({
    int page = 1,
    int pageSize = 20,
    int? year,
    int? month,
    int? fieldId,
    int? zoneId,
  }) async {
    try {
      final q = <String, String>{
        'page': '$page',
        'page_size': '$pageSize',
        if (year != null) 'year': '$year',
        if (month != null) 'month': '$month',
        if (fieldId != null) 'field_id': '$fieldId',
        if (zoneId != null) 'zone_id': '$zoneId',
      };
      final url = Uri.parse(
        '${ApiServer.currentBaseUrl}/api/inspections',
      ).replace(queryParameters: q);
      final res = await http.get(url, headers: ApiServer.defaultHeaders);
      return ApiServer.handleResponse(res);
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }
}
