// lib/api/inspection_api.dart
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'api_server.dart';

class InspectionApi {
  // =================== รอบตรวจ (inspection) ===================

  static Future<Map<String, dynamic>> startInspection({
    required int fieldId,
    required int zoneId,
    String? notes,
    bool newRound = false,
  }) async {
    try {
      final body = <String, dynamic>{
        'field_id': fieldId,
        'zone_id': zoneId,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (newRound) 'new_round': true,
      };
      return await ApiServer.post('/api/inspections/start', body);
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

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

  static Future<Map<String, dynamic>> getInspectionDetail(
    int inspectionId,
  ) async {
    try {
      return await ApiServer.get('/api/inspections/$inspectionId');
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  static Future<Map<String, dynamic>> getLatestInspections() async {
    try {
      return await ApiServer.get('/api/inspections');
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  // =================== วิเคราะห์รูป (model) ===================

  static Future<Map<String, dynamic>> runAnalyze(int inspectionId) async {
    try {
      return await ApiServer.post('/api/inspections/$inspectionId/analyze', {});
    } catch (e) {
      return ApiServer.handleError(e);
    }
  }

  // =================== อัปโหลดรูปภาพ ===================

  static Future<Map<String, dynamic>> uploadImagesOnce({
    required int inspectionId,
    required List<PlatformFile> images,
    String fieldName = 'images',
  }) async {
    try {
      final List<UploadByteFile> byteItems = [];
      final List<File> filePathItems = [];

      for (final pf in images.take(5)) {
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

      if (byteItems.isEmpty && filePathItems.isEmpty) {
        return {'success': false, 'message': 'No files to upload'};
      }

      if (byteItems.isNotEmpty) {
        return await ApiServer.uploadInspectionImagesBytes(
          inspectionId: inspectionId,
          files: byteItems,
          fieldName: fieldName,
        );
      } else {
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

          final quotaRemain = res['quota_remain'] is int
              ? res['quota_remain'] as int
              : null;
          if (quotaRemain != null && quotaRemain <= 0)
            break; // ✅ quota เต็ม หยุด
        } else {
          totalFailed += 1;
          final err = (res['error'] ?? '').toString();
          if (err == 'quota_full') break; // ✅ server แจ้ง quota เต็ม หยุด
        }
      }

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
