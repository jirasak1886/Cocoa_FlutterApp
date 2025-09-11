// lib/api/inspection_api.dart
import 'dart:convert';
import 'dart:io' show File; // บน Web จะถูก ignore อัตโนมัติ
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'api_server.dart'; // มี UploadByteFile + เมธอดอัปโหลด

class InspectionApi {
  // =================== รอบตรวจ (inspection) ===================

  /// เริ่มรอบตรวจ
  /// - ถ้ามีรอบค้างสถานะ pending อยู่และ newRound=false => จะคืนรอบเดิม (idempotent=true)
  /// - ถ้าต้องการ "เริ่มรอบใหม่" ให้ส่ง newRound=true (backend จะปิดรอบค้างก่อนแล้วเปิดอันใหม่)
  static Future<Map<String, dynamic>> startInspection({
    required int fieldId,
    required int zoneId,
    String? notes,
    bool newRound = false, // << เพิ่มพารามิเตอร์
  }) async {
    try {
      final body = <String, dynamic>{
        'field_id': fieldId,
        'zone_id': zoneId,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (newRound) 'new_round': true, // << สำคัญ: ส่งไปที่ backend
      };
      return await ApiServer.post('/api/inspections/start', body);
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  /// helper สั้นๆ สำหรับ "เริ่มรอบใหม่" โดยตรง
  static Future<Map<String, dynamic>> startNewRound({
    required int fieldId,
    required int zoneId,
    String? notes,
  }) {
    return startInspection(
      fieldId: fieldId,
      zoneId: zoneId,
      notes: notes,
      newRound: true,
    );
  }

  /// รายละเอียดรอบตรวจ (รวม quota ใน data.quota: {max, used, remain})
  static Future<Map<String, dynamic>> getInspectionDetail(
    int inspectionId,
  ) async {
    try {
      return await ApiServer.get('/api/inspections/$inspectionId');
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  /// ดึงรายการล่าสุด (ใช้ listInspections แทนได้ถ้าต้องกรอง)
  static Future<Map<String, dynamic>> getLatestInspections() async {
    try {
      return await ApiServer.get('/api/inspections');
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  // =================== วิเคราะห์รูป (model) ===================

  /// สั่งให้เซิร์ฟเวอร์รันวิเคราะห์รูปของ inspection นี้ (backend ไปเรียก routes/detect.py)
  static Future<Map<String, dynamic>> runAnalyze(int inspectionId) async {
    try {
      return await ApiServer.post('/api/inspections/$inspectionId/analyze', {});
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  // =================== อัปโหลดรูปภาพ ===================
  // โควตา: "รอบละ" ≤ 5 รูป — อัปได้หลายคำขอในรอบเดียว แต่รวมแล้วต้องไม่เกิน 5

  /// (ครั้งเดียว) อัปโหลด ≤ 5 รูปจาก `PlatformFile` (รองรับ Web: bytes, Mobile/Desktop: path/bytes)
  static Future<Map<String, dynamic>> uploadImagesOnce({
    required int inspectionId,
    required List<PlatformFile> images,
    String fieldName = 'images',
  }) async {
    try {
      // เตรียมรายการไฟล์ที่พร้อมส่ง (หยิบมาไม่เกิน 5 ต่อคำขอ)
      final List<UploadByteFile> byteItems = [];
      final List<File> filePathItems = [];

      for (final pf in images.take(5)) {
        final name = pf.name;

        if (pf.bytes != null && pf.bytes!.isNotEmpty) {
          // bytes (เหมาะกับ Web)
          final guessed =
              lookupMimeType(name, headerBytes: pf.bytes!) ??
              lookupMimeType(name);
          byteItems.add(
            UploadByteFile(
              bytes: pf.bytes!,
              filename: name,
              contentType: guessed,
            ),
          );
        } else if (!kIsWeb && pf.path != null) {
          // path (Mobile/Desktop)
          filePathItems.add(File(pf.path!));
        }
      }

      if (byteItems.isEmpty && filePathItems.isEmpty) {
        return {'success': false, 'message': 'No files to upload'};
      }

      if (byteItems.isNotEmpty) {
        // ส่งแบบ bytes
        return await ApiServer.uploadInspectionImagesBytes(
          inspectionId: inspectionId,
          files: byteItems,
          fieldName: fieldName,
        );
      } else {
        // ส่งแบบไฟล์ path
        return await ApiServer.uploadInspectionImagesFiles(
          inspectionId: inspectionId,
          files: filePathItems,
          fieldName: fieldName,
        );
      }
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  /// (หลายชุดอัตโนมัติ) ถ้าเลือก > 5 รูป จะแบ่งเป็นหลายคำขอ ชุดละ ≤ 5 รูป แล้วอัปจนหมด
  /// จะ "หยุดทันที" เมื่อ quota ของ **รอบนี้** เต็ม (quota_remain==0) หรือเจอ error quota_full
  static Future<Map<String, dynamic>> uploadImagesBatches({
    required int inspectionId,
    required List<PlatformFile> images,
    String fieldName = 'images',
  }) async {
    try {
      if (images.isEmpty) {
        return {
          'success': false,
          'message': 'No files to upload',
          'batches': [],
        };
      }

      const int chunkSize = 5;
      final List<Map<String, dynamic>> batches = [];
      int totalAccepted = 0, totalSkipped = 0, totalFailed = 0;

      for (int i = 0; i < images.length; i += chunkSize) {
        final chunk = images.skip(i).take(chunkSize).toList();

        final List<UploadByteFile> byteItems = [];
        final List<File> filePathItems = [];

        for (final pf in chunk) {
          final name = pf.name;
          if (pf.bytes != null && pf.bytes!.isNotEmpty) {
            final guessed =
                lookupMimeType(name, headerBytes: pf.bytes!) ??
                lookupMimeType(name);
            byteItems.add(
              UploadByteFile(
                bytes: pf.bytes!,
                filename: name,
                contentType: guessed,
              ),
            );
          } else if (!kIsWeb && pf.path != null) {
            filePathItems.add(File(pf.path!));
          }
        }

        Map<String, dynamic> res;
        if (byteItems.isNotEmpty) {
          res = await ApiServer.uploadInspectionImagesBytes(
            inspectionId: inspectionId,
            files: byteItems,
            fieldName: fieldName,
          );
        } else {
          res = await ApiServer.uploadInspectionImagesFiles(
            inspectionId: inspectionId,
            files: filePathItems,
            fieldName: fieldName,
          );
        }

        batches.add(res);

        final ok = (res['success'] == true);
        if (ok) {
          final accepted =
              (res['accepted'] ??
                      (res['saved'] is List
                          ? (res['saved'] as List).length
                          : 0))
                  as int;
          totalAccepted += accepted;
          totalSkipped += (res['skipped'] is List
              ? (res['skipped'] as List).length
              : 0);

          // ✅ ถ้า server บอก quota เหลือ 0 ให้หยุด
          final quotaRemain = res['quota_remain'] is int
              ? res['quota_remain'] as int
              : null;
          if (quotaRemain != null && quotaRemain <= 0) {
            break;
          }
        } else {
          totalFailed += 1;

          // ✅ ถ้าเจอ quota_full จาก Server ให้หยุดทันที
          final err = (res['error'] ?? '').toString();
          if (err == 'quota_full') {
            break;
          }
        }
      }

      // success = true ถ้าอัปโหลดได้อย่างน้อยหนึ่งไฟล์ หรือไม่พบ error
      final overallSuccess = (totalAccepted > 0) || (totalFailed == 0);

      return {
        'success': overallSuccess,
        'batches': batches,
        'summary': {
          'total_batches': batches.length,
          'failed_batches': totalFailed,
          'accepted': totalAccepted,
          'skipped': totalSkipped,
        },
      };
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  /// เพื่อความเข้ากันได้กับโค้ดเดิม: `uploadImages(...)` จะเรียกแบบ “หลายชุด”
  static Future<Map<String, dynamic>> uploadImages({
    required int inspectionId,
    required List<PlatformFile> images,
  }) {
    return uploadImagesBatches(
      inspectionId: inspectionId,
      images: images,
      fieldName: 'images',
    );
  }

  // =================== คำแนะนำปุ๋ย (recommendations) ===================

  /// ดึงคำแนะนำปุ๋ยของรอบตรวจ
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
  /// ถ้า status == applied และไม่ส่ง appliedDate มาจะให้ฝั่งเซิร์ฟเวอร์ตั้งเป็นวันนี้
  static Future<Map<String, dynamic>> updateRecommendationStatus({
    required int recommendationId,
    required String status,
    String? appliedDate, // 'YYYY-MM-DD'
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

  // =================== ประวัติ/สถิติ ===================

  /// สรุปประวัติแบบ bucket รายเดือน/รายปี + top nutrients
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

  /// รายการ inspections แบบแบ่งหน้า/ตัวกรอง
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
