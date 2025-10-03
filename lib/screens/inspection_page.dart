// lib/screens/inspection_page.dart
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'package:cocoa_app/api/inspection_api.dart';
import 'package:cocoa_app/api/api_server.dart';
import 'package:cocoa_app/api/field_api.dart';

class InspectionPage extends StatefulWidget {
  const InspectionPage({super.key});

  @override
  State<InspectionPage> createState() => _InspectionPageState();
}

class _InspectionPageState extends State<InspectionPage> {
  int? _selectedFieldId;
  int? _selectedZoneId;
  final _notesCtrl = TextEditingController();

  List<Map<String, dynamic>> _fields = [];
  List<Map<String, dynamic>> _zones = [];

  int? _inspectionId;
  int? _roundNo;
  int _uploadedCount = 0;

  bool _busy = false;
  bool _isConnected = false;
  String _status = 'กำลังตรวจสอบการเชื่อมต่อ...';
  String _lastConnectionCheck = '';
  List<PlatformFile> _picked = [];
  Map<String, dynamic>? _detail;

  bool _recsLoading = false;
  List<Map<String, dynamic>> _recs = [];

  List<Map<String, dynamic>> _analyzeResults = [];

  static const int maxFileSize = 20 * 1024 * 1024;
  static const List<String> allowedTypes = [
    'jpg',
    'jpeg',
    'png',
    'bmp',
    'webp',
  ];
  static const int maxImagesPerRound = 5;

  final ImagePicker _imgPicker = ImagePicker();

  T? _pick<T>(Map<String, dynamic> res, String key) {
    if (res.containsKey(key)) return res[key] as T?;
    final data = res['data'];
    if (data is Map<String, dynamic>) return data[key] as T?;
    return null;
  }

  bool get _canAddRound =>
      _isConnected &&
      !_busy &&
      _selectedFieldId != null &&
      _selectedZoneId != null;

  void _handleAddRoundPressed() {
    if (_busy) return;
    if (!_isConnected) {
      _toast('ไม่ได้เชื่อมต่อกับเซิร์ฟเวอร์', isError: true);
      return;
    }
    if (_selectedFieldId == null) {
      _toast('กรุณาเลือกแปลง', isError: true);
      return;
    }
    if (_selectedZoneId == null) {
      _toast('กรุณาเลือกโซน', isError: true);
      return;
    }
    _startRound(newRound: true);
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  String _imageUrl(String rel) {
    final base = ApiServer.currentBaseUrl.replaceAll(RegExp(r'\/+$'), '');
    final relNorm = rel.startsWith('/') ? rel.substring(1) : rel;
    return '$base/static/uploads/$relNorm';
  }

  List<Map<String, dynamic>> _predsForImage(String imagePathOrRel) {
    final imgName = imagePathOrRel.split(RegExp(r'[\\/]+')).last;
    final hit = _analyzeResults.where((m) {
      final p = (m['image'] ?? '').toString();
      final last = p.split(RegExp(r'[\\/]+')).last;
      return last == imgName;
    }).toList();
    if (hit.isEmpty) return const [];
    final preds = (hit.first['preds'] as List?) ?? const [];
    return preds.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<PlatformFile> _xfileToPlatformFile(XFile xf) async {
    final name = xf.name.isNotEmpty
        ? xf.name
        : xf.path.split(RegExp(r'[\\/]+')).last;
    if (kIsWeb) {
      final bytes = await xf.readAsBytes();
      return PlatformFile(name: name, size: bytes.length, bytes: bytes);
    } else {
      final f = File(xf.path);
      final size = await f.length();
      return PlatformFile(name: name, size: size, path: xf.path);
    }
  }

  Future<void> _takePhoto() async {
    if (_inspectionId == null) {
      _toast('กรุณาเริ่มรอบก่อน', isError: true);
      return;
    }
    final remain = (maxImagesPerRound - (_uploadedCount + _picked.length))
        .clamp(0, maxImagesPerRound);
    if (remain == 0) {
      _toast('อัปโหลดได้สูงสุด $maxImagesPerRound รูปต่อรอบ', isError: true);
      return;
    }
    try {
      final XFile? shot = await _imgPicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 2048,
        maxHeight: 2048,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (shot == null) return;
      final pf = await _xfileToPlatformFile(shot);
      final ok = await _validateImages([pf]);
      if (!ok) return;
      setState(() => _picked.add(pf));
      _toast('เพิ่มรูปจากกล้องสำเร็จ 1 ไฟล์');
    } catch (e) {
      _showErrorDialog('ถ่ายภาพไม่สำเร็จ', 'สาเหตุ: $e');
    }
  }

  Future<void> _checkConnectionWithRetry({int maxRetries = 3}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        final conn = await ApiServer.checkConnection();
        if (!mounted) return;
        if (conn['success'] == true) {
          setState(() {
            _isConnected = true;
            _lastConnectionCheck = DateTime.now().toString().substring(0, 19);
          });
          return;
        }
      } catch (_) {
        if (!mounted) return;
        if (i == maxRetries - 1) {
          setState(() {
            _isConnected = false;
            _status =
                'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้ กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต';
          });
          _showErrorDialog(
            'ปัญหาการเชื่อมต่อ',
            'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้ กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ตและลองใหม่อีกครั้ง',
          );
        }
        if (i < maxRetries - 1) {
          await Future.delayed(Duration(seconds: i + 1));
        }
      }
    }
  }

  Future<void> _boot() async {
    await _checkConnectionWithRetry();
    if (_isConnected) {
      await _loadFields();
    }
  }

  Future<bool> _validateImages(List<PlatformFile> files) async {
    for (final file in files) {
      final extension = file.extension?.toLowerCase();
      if (extension == null || !allowedTypes.contains(extension)) {
        _showErrorDialog(
          'ชนิดไฟล์ไม่รองรับ',
          'ไฟล์ ${file.name} เป็นชนิดไฟล์ที่ไม่รองรับ\nชนิดไฟล์ที่รองรับ: ${allowedTypes.join(', ')}',
        );
        return false;
      }
      if (file.size > maxFileSize) {
        _showErrorDialog(
          'ไฟล์ใหญ่เกินไป',
          'ไฟล์ ${file.name} มีขนาด ${(file.size / (1024 * 1024)).toStringAsFixed(1)} MB\nขนาดสูงสุดที่อนุญาต: ${maxFileSize ~/ (1024 * 1024)} MB',
        );
        return false;
      }
      if (kIsWeb) {
        if (file.bytes == null || file.bytes!.isEmpty) {
          _showErrorDialog(
            'ไฟล์เสียหาย',
            'ไฟล์ ${file.name} ไม่มีข้อมูล กรุณาเลือกไฟล์ใหม่',
          );
          return false;
        }
      } else {
        final hasBytes = file.bytes != null && file.bytes!.isNotEmpty;
        final hasPath = file.path != null && file.path!.isNotEmpty;
        if (!hasBytes && !hasPath) {
          _showErrorDialog(
            'ไฟล์ไม่พร้อม',
            'ไฟล์ ${file.name} ไม่พบข้อมูลหรือที่อยู่ไฟล์',
          );
          return false;
        }
      }
    }
    return true;
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[600]),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green[600]),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadFields() async {
    if (!_isConnected) {
      _toast('ไม่ได้เชื่อมต่อกับเซิร์ฟเวอร์');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await FieldApiService.getFields();
      if (!mounted) return;

      if (res['success'] == true) {
        final List data = res['data'] ?? [];
        _fields = data
            .map(
              (m) =>
                  FieldApiService.safeFieldData(Map<String, dynamic>.from(m)),
            )
            .toList();

        if (_selectedFieldId == null ||
            !_fields.any((f) => f['field_id'] == _selectedFieldId)) {
          _selectedFieldId = null;
          _zones = [];
          _selectedZoneId = null;
        }
        setState(() {});
      } else {
        _showErrorDialog(
          'ข้อผิดพลาด',
          'โหลดรายชื่อแปลงไม่สำเร็จ: ${res['error'] ?? 'ไม่ทราบสาเหตุ'}',
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('ข้อผิดพลาด', 'เกิดข้อผิดพลาดในการโหลดข้อมูล: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadZones(int fieldId) async {
    setState(() {
      _busy = true;
      _zones = [];
      _selectedZoneId = null;
    });
    try {
      final res = await FieldApiService.getZonesByField(fieldId);
      if (!mounted) return;

      if (res['success'] == true) {
        final List data = res['data'] ?? [];
        _zones = data
            .map(
              (m) => FieldApiService.safeZoneData(Map<String, dynamic>.from(m)),
            )
            .toList();
        setState(() {});
      } else {
        _showErrorDialog(
          'ข้อผิดพลาด',
          'โหลดโซนของแปลงไม่สำเร็จ: ${res['error'] ?? 'ไม่ทราบสาเหตุ'}',
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('ข้อผิดพลาด', 'เกิดข้อผิดพลาดในการโหลดโซน: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onSelectField(int? fieldId) {
    setState(() {
      _selectedFieldId = fieldId;
    });
    if (fieldId != null) _loadZones(fieldId);
  }

  void _onSelectZone(int? zoneId) => setState(() => _selectedZoneId = zoneId);

  void _toast(String m, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _startRound({bool newRound = false}) async {
    FocusScope.of(context).unfocus();

    if (!_isConnected) {
      _toast('ไม่ได้เชื่อมต่อกับเซิร์ฟเวอร์', isError: true);
      return;
    }
    if (_selectedFieldId == null) {
      _toast('กรุณาเลือกแปลง', isError: true);
      return;
    }
    if (_selectedZoneId == null) {
      _toast('กรุณาเลือกโซน', isError: true);
      return;
    }

    setState(() {
      _busy = true;
      _status = 'กำลังเริ่มรอบตรวจ...';
      _inspectionId = null;
      _roundNo = null;
      _uploadedCount = 0;
      _picked.clear();
      _detail = null;
      _recs = [];
      _analyzeResults = [];
    });

    try {
      final res = await InspectionApi.startInspection(
        fieldId: _selectedFieldId!,
        zoneId: _selectedZoneId!,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        newRound: newRound,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        final id = _pick<int>(res, 'inspection_id');
        final roundNo = _pick<int>(res, 'round_no');
        final idem = (res['idempotent'] == true);

        setState(() {
          _inspectionId = id;
          _roundNo = roundNo;
          _status = idem
              ? 'เปิดรอบเดิมแล้ว (inspection_id=$id, round=$roundNo)'
              : 'เริ่มรอบสำเร็จ (inspection_id=$id, round=$roundNo)';
        });

        await _refreshDetail();
        await _loadRecs();

        if (!idem) {
          _showSuccessDialog('สำเร็จ', 'เริ่มรอบตรวจใหม่แล้ว รอบที่ $roundNo');
        } else {
          _toast(
            'มีรอบที่กำลังดำเนินการอยู่แล้ว (เปิดรอบเดิมให้)',
            isError: false,
          );
        }
      } else {
        final error = res['error'] ?? 'ไม่ทราบสาเหตุ';
        _showErrorDialog('ไม่สามารถเริ่มรอบตรวจได้', 'สาเหตุ: $error');
        setState(() => _status = 'เริ่มรอบไม่สำเร็จ');
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('ข้อผิดพลาด', 'เกิดข้อผิดพลาดในการเริ่มรอบตรวจ: $e');
        setState(() => _status = 'เกิดข้อผิดพลาด');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImages() async {
    if (_inspectionId == null) {
      _toast('กรุณาเริ่มรอบก่อน', isError: true);
      return;
    }
    final remain = (maxImagesPerRound - (_uploadedCount + _picked.length))
        .clamp(0, maxImagesPerRound);
    if (remain == 0) {
      _toast('อัปโหลดได้สูงสุด $maxImagesPerRound รูปต่อรอบ', isError: true);
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        withData: kIsWeb,
        allowedExtensions: allowedTypes,
      );
      if (result == null || result.files.isEmpty) return;

      final filesToAdd = result.files.take(remain).toList();

      if (await _validateImages(filesToAdd)) {
        setState(() => _picked.addAll(filesToAdd));
        _toast('เลือกไฟล์สำเร็จ ${filesToAdd.length} ไฟล์');
      }
    } catch (e) {
      _showErrorDialog('ข้อผิดพลาด', 'ไม่สามารถเลือกไฟล์ได้: $e');
    }
  }

  Future<void> _uploadImages() async {
    if (_inspectionId == null) {
      _toast('ยังไม่มี inspection_id', isError: true);
      return;
    }
    if (_picked.isEmpty) {
      _toast('ยังไม่เลือกรูป', isError: true);
      return;
    }
    if (!await _validateImages(_picked)) return;

    setState(() {
      _busy = true;
      _status = 'กำลังอัปโหลดรูป... (${_picked.length} ไฟล์)';
    });

    try {
      final res = await InspectionApi.uploadImages(
        inspectionId: _inspectionId!,
        images: _picked,
      );

      if (!mounted) return;

      int accepted = 0;
      int? quotaRemain;

      if (res['batches'] is List) {
        for (final b in (res['batches'] as List)) {
          if (b is Map && b['success'] == true) {
            if (b['accepted'] is int) {
              accepted += b['accepted'] as int;
            } else if (b['saved'] is List) {
              accepted += (b['saved'] as List).length;
            }
            if (b['quota_remain'] is int) {
              quotaRemain = b['quota_remain'] as int;
            }
          }
        }
      } else {
        List saved = [];
        if (res['saved'] is List) saved = res['saved'];
        if (res['quota_remain'] is int) quotaRemain = res['quota_remain'];
        accepted = saved.length;
      }

      if (res['success'] == true || accepted > 0) {
        setState(() {
          _status = 'อัปโหลดสำเร็จ';
          _uploadedCount += accepted;
          _picked.clear();
        });
        await _refreshDetail();

        final remain = quotaRemain ?? (maxImagesPerRound - _uploadedCount);
        _showSuccessDialog(
          'อัปโหลดสำเร็จ',
          'อัปโหลดไฟล์สำเร็จ $accepted ไฟล์\nเหลือโควตา ${remain < 0 ? 0 : remain} ไฟล์',
        );
      } else {
        final code = res['error'] ?? 'unknown';
        String errorMessage = 'อัปโหลดล้มเหลว: $code';

        if (code == 'quota_full') {
          final exist = _pick<int>(res, 'exist') ?? 0;
          final max = _pick<int>(res, 'max') ?? maxImagesPerRound;
          errorMessage = 'ครบโควตาแล้ว: มีรูปอยู่แล้ว $exist/$max';
        } else if (code == 'payload_too_large') {
          errorMessage = 'ไฟล์ใหญ่เกินไป กรุณาย่อขนาดไฟล์ก่อนอัปโหลด';
        } else if (code == 'unsupported_media') {
          errorMessage = 'ชนิดไฟล์ไม่รองรับ กรุณาเลือกไฟล์รูปภาพที่รองรับ';
        }

        _showErrorDialog('อัปโหลดไม่สำเร็จ', errorMessage);
        setState(() => _status = 'อัปโหลดล้มเหลว');
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('ข้อผิดพลาด', 'เกิดข้อผิดพลาดในการอัปโหลด: $e');
        setState(() => _status = 'เกิดข้อผิดพลาด');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshDetail() async {
    if (_inspectionId == null) return;
    try {
      final d = await InspectionApi.getInspectionDetail(_inspectionId!);
      if (!mounted) return;

      if (d['success'] == true) {
        final data = (d['data'] is Map<String, dynamic>)
            ? d['data'] as Map<String, dynamic>
            : d;
        final images = (data['images'] as List?) ?? const [];
        final quota = (data['quota'] as Map?) ?? const {};
        final used = (quota is Map && quota['used'] is int)
            ? quota['used'] as int
            : images.length;

        setState(() {
          _detail = data;
          _uploadedCount = used;
        });
      } else {
        _toast(
          'ไม่สามารถโหลดรายละเอียดได้: ${d['error'] ?? 'ไม่ทราบสาเหตุ'}',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted)
        _toast('เกิดข้อผิดพลาดในการโหลดรายละเอียด: $e', isError: true);
    }
  }

  Future<void> _runAnalyze() async {
    if (_inspectionId == null) {
      _toast('กรุณาเริ่มรอบก่อน', isError: true);
      return;
    }

    if (_uploadedCount == 0) {
      try {
        final d = await InspectionApi.getInspectionDetail(_inspectionId!);
        final dd = (d['data'] is Map<String, dynamic>) ? d['data'] : d;
        final serverCount = (dd['images'] as List?)?.length ?? 0;
        if (serverCount == 0) {
          _showErrorDialog(
            'ไม่มีรูปภาพ',
            'ยังไม่มีรูปในรอบนี้\nกรุณาอัปโหลดอย่างน้อย 1 รูปก่อนสั่งวิเคราะห์',
          );
          return;
        }
        _uploadedCount = serverCount;
      } catch (e) {
        _toast('ไม่สามารถตรวจสอบจำนวนรูปได้: $e', isError: true);
        return;
      }
    }

    setState(() {
      _busy = true;
      _status = 'กำลังสั่งตรวจโมเดล...';
      _detail = null;
    });

    try {
      final res = await InspectionApi.runAnalyze(_inspectionId!);
      final List rr = (res['results'] as List?) ?? const [];
      setState(() {
        _analyzeResults = rr
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });

      if (!mounted) return;

      if (res['success'] == true) {
        await _refreshDetail();
        await _loadRecs();

        if (!mounted) return;

        final findings =
            (_detail?['findings'] as List?) ??
            (_detail?['inspection']?['findings'] as List?) ??
            [];
        final warns = (res['warnings'] as List?) ?? [];

        setState(() {
          _status =
              'เสร็จสิ้น: พบ ${findings.length} รายการ'
              '${warns.isNotEmpty ? " (warnings: ${warns.length})" : ""}';
        });

        _showSuccessDialog(
          'วิเคราะห์สำเร็จ',
          'ตรวจพบความผิดปกติ ${findings.length} รายการ\n'
              '${warns.isNotEmpty ? "คำเตือน: ${warns.length} รายการ" : ""}',
        );
      } else {
        final error = res['error'] ?? 'ไม่ทราบสาเหตุ';
        _showErrorDialog('วิเคราะห์ไม่สำเร็จ', 'สาเหตุ: $error');
        setState(() => _status = 'ตรวจไม่สำเร็จ');
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('ข้อผิดพลาด', 'เกิดข้อผิดพลาดในการวิเคราะห์: $e');
        setState(() => _status = 'เกิดข้อผิดพลาด');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadRecs() async {
    if (_inspectionId == null) return;

    setState(() {
      _recs = [];
      _recsLoading = true;
    });

    try {
      final res = await InspectionApi.getRecommendations(
        inspectionId: _inspectionId!,
      );
      if (!mounted) return;

      if (res['success'] == true) {
        final root = (res['data'] ?? res['recommendations']);
        final List data = root is List ? root : [];
        setState(() {
          _recs = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      } else {
        _toast(
          'ไม่สามารถโหลดคำแนะนำได้: ${res['error'] ?? 'ไม่ทราบสาเหตุ'}',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) _toast('เกิดข้อผิดพลาดในการโหลดคำแนะนำ: $e', isError: true);
    } finally {
      if (mounted) setState(() => _recsLoading = false);
    }
  }

  Future<void> _updateRecStatus({
    required int recommendationId,
    required String status,
    String? appliedDate,
  }) async {
    try {
      final r = await InspectionApi.updateRecommendationStatus(
        recommendationId: recommendationId,
        status: status,
        appliedDate: appliedDate,
      );
      if (!mounted) return;
      if (r['success'] == true) {
        _toast('อัปเดตสถานะสำเร็จ');
        await _loadRecs();
      } else {
        _showErrorDialog(
          'อัปเดตไม่สำเร็จ',
          'ไม่สามารถอัปเดตสถานะได้: ${r['error'] ?? 'ไม่ทราบสาเหตุ'}',
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('ข้อผิดพลาด', 'เกิดข้อผิดพลาดในการอัปเดตสถานะ: $e');
      }
    }
  }

  Widget _buildStyledCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
  }) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      padding: padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 5,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildStyledDropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    required String labelText,
    required IconData icon,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: Icon(icon, color: Colors.green[600]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.green[500]!, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      isExpanded: true,
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildStyledButton({
    required VoidCallback? onPressed,
    required Widget child,
    required IconData icon,
    bool isPrimary = false,
    bool isSecondary = false,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: child,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary
              ? Colors.green
              : (isSecondary ? Colors.green[50] : Colors.white),
          foregroundColor: isPrimary
              ? Colors.white
              : (isSecondary ? Colors.green[700] : Colors.green[600]),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isPrimary
                ? BorderSide.none
                : BorderSide(color: Colors.green[300]!),
          ),
          elevation: isPrimary ? 2 : 1,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isConnected ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isConnected ? Colors.green[200]! : Colors.red[200]!,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isConnected ? Icons.wifi : Icons.wifi_off,
            color: _isConnected ? Colors.green[600] : Colors.red[600],
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isConnected ? 'เชื่อมต่อแล้ว' : 'ไม่ได้เชื่อมต่อ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _isConnected ? Colors.green[700] : Colors.red[700],
                  ),
                ),
                if (_lastConnectionCheck.isNotEmpty)
                  Text(
                    'ตรวจสอบล่าสุด: $_lastConnectionCheck',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          if (!_isConnected)
            IconButton(
              onPressed: _busy ? null : () => _checkConnectionWithRetry(),
              icon: const Icon(Icons.refresh),
              tooltip: 'ลองเชื่อมต่อใหม่',
              color: Colors.red[600],
            ),
        ],
      ),
    );
  }

  // ===== Helper: ดึงสูตรปุ๋ยจากสตริง (0-0-50, 13-13-21+Mg, MgSO4) =====
  String? _extractFormulaClient(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final re = RegExp(
      r'(\d{1,2}-\d{1,2}-\d{1,2}(?:\+\s*Mg)?)|MgSO4',
      caseSensitive: false,
    );
    final m = re.firstMatch(s);
    return m?.group(0);
  }

  // =======================
  // RECOMMENDATION TILE (code + name_th + description)
  // =======================
  Widget _buildRecTile(Map r) {
    final status = (r['status'] ?? 'suggested').toString();
    final recId = (r['recommendation_id'] ?? r['id'] ?? 0) as int;

    final nameTh = (r['fert_name_th'] ?? '').toString().trim(); // name_th
    final descTh = (r['fert_description'] ?? '')
        .toString()
        .trim(); // description
    final prodName = (r['fert_name'] ?? r['product_name'] ?? '')
        .toString()
        .trim();
    final recText = (r['recommendation_text'] ?? '').toString().trim();
    final nutTh = (r['nutrient_name_th'] ?? '').toString().trim();

    // สูตรปุ๋ย: ใช้จาก backend ก่อน ถ้าไม่มีให้ดึงจากข้อความ
    String code = (r['formulation'] ?? '').toString().trim();
    if (code.isEmpty) {
      code =
          _extractFormulaClient(recText) ??
          _extractFormulaClient(prodName) ??
          '';
    }

    final String title = prodName.isNotEmpty
        ? prodName
        : (nameTh.isNotEmpty ? nameTh : 'คำแนะนำ');

    IconData icon;
    Color color;
    switch (status) {
      case 'applied':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'skipped':
        icon = Icons.skip_next;
        color = Colors.orange;
        break;
      default:
        icon = Icons.pending;
        color = Colors.blueGrey;
    }

    TextStyle bold(Color c) => TextStyle(fontWeight: FontWeight.w800, color: c);

    // ป้ายสูตร
    Widget? formulaPill;
    if (code.isNotEmpty) {
      formulaPill = Container(
        margin: const EdgeInsets.only(top: 6, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.teal[50],
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.teal[200]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.science, size: 14, color: Colors.teal),
            SizedBox(width: 6),
          ],
        ),
      );
      // เติมตัวหนังสือไว้ด้านขวาไอคอน
      formulaPill = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          formulaPill,
          const SizedBox(width: 0),
          Container(
            margin: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text(
              code,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.teal,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (formulaPill != null) formulaPill,
            if (nameTh.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(nameTh, style: bold(Colors.green[800]!)),
              ),
            if (nutTh.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'ธาตุที่แก้: $nutTh',
                  style: TextStyle(color: Colors.teal[700], fontSize: 12),
                ),
              ),
            if (descTh.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(descTh, style: TextStyle(color: Colors.grey[800])),
              ),
            if (recText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  recText,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) =>
              _updateRecStatus(recommendationId: recId, status: v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'applied', child: Text('ทำแล้ว (Applied)')),
            PopupMenuItem(value: 'skipped', child: Text('ข้าม (Skipped)')),
            PopupMenuItem(value: 'suggested', child: Text('รอทำ (Suggested)')),
          ],
          icon: const Icon(Icons.more_horiz),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final findings =
        (_detail?['findings'] as List?) ??
        (_detail?['inspection']?['findings'] as List?) ??
        [];
    final images =
        (_detail?['images'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('ตรวจสอบโรคใบโกโก้'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'รีโหลดแปลง',
            onPressed: _busy ? null : _loadFields,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _canAddRound ? _handleAddRoundPressed : null,
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มรอบ'),
        backgroundColor: _canAddRound ? Colors.green : Colors.grey,
        foregroundColor: Colors.white,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildStyledCard(
                child: Column(
                  children: [
                    Icon(
                      Icons.science_outlined,
                      size: 48,
                      color: Colors.green[600],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ระบบตรวจสอบโรคใบโกโก้',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    _buildConnectionStatus(),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            _status,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // เลือกแปลง/โซน
              _buildStyledCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'เลือกแปลงและโซน',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildStyledDropdown<int>(
                      value: _selectedFieldId,
                      items: _fields
                          .map(
                            (f) => DropdownMenuItem<int>(
                              value: f['field_id'] as int,
                              child: Text('${f['field_name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (_busy || !_isConnected)
                          ? null
                          : _onSelectField,
                      labelText: 'เลือกแปลง',
                      icon: Icons.agriculture,
                    ),
                    const SizedBox(height: 16),
                    _buildStyledDropdown<int>(
                      value: _selectedZoneId,
                      items: _zones
                          .map(
                            (z) => DropdownMenuItem<int>(
                              value: z['zone_id'] as int,
                              child: Text('${z['zone_name']}'),
                            ),
                          )
                          .toList(),
                      onChanged:
                          (_busy || !_isConnected || _selectedFieldId == null)
                          ? null
                          : _onSelectZone,
                      labelText: 'เลือกโซน',
                      icon: Icons.location_on,
                    ),
                  ],
                ),
              ),

              // ปุ่มต่าง ๆ
              _buildStyledCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'การดำเนินการ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildStyledButton(
                          onPressed: (!_busy && _isConnected)
                              ? () => _startRound()
                              : null,
                          icon: Icons.flag,
                          isPrimary: true,
                          child: const Text('เริ่มรอบตรวจ'),
                        ),
                        _buildStyledButton(
                          onPressed:
                              (_inspectionId == null ||
                                  !_isConnected ||
                                  _uploadedCount >= maxImagesPerRound)
                              ? null
                              : _pickImages,
                          icon: Icons.photo_library,
                          isSecondary: true,
                          child: Text('เลือกรูป (≤$maxImagesPerRound)'),
                        ),
                        _buildStyledButton(
                          onPressed:
                              (_inspectionId == null ||
                                  !_isConnected ||
                                  _uploadedCount >= maxImagesPerRound)
                              ? null
                              : _takePhoto,
                          icon: Icons.photo_camera_outlined,
                          isSecondary: true,
                          child: const Text('ถ่ายภาพ'),
                        ),
                        _buildStyledButton(
                          onPressed:
                              (_inspectionId == null ||
                                  _picked.isEmpty ||
                                  !_isConnected)
                              ? null
                              : _uploadImages,
                          icon: Icons.cloud_upload,
                          isSecondary: true,
                          child: const Text('อัปโหลดรูป'),
                        ),
                        _buildStyledButton(
                          onPressed: (_inspectionId == null || !_isConnected)
                              ? null
                              : _runAnalyze,
                          icon: Icons.science_outlined,
                          isPrimary: true,
                          child: const Text('สั่งตรวจโมเดล'),
                        ),
                        if (_inspectionId != null)
                          _buildStyledButton(
                            onPressed: !_isConnected ? null : _refreshDetail,
                            icon: Icons.refresh,
                            child: const Text('รีเฟรชรายละเอียด'),
                          ),
                        if (_inspectionId != null)
                          _buildStyledButton(
                            onPressed: !_isConnected ? null : _loadRecs,
                            icon: Icons.spa_outlined,
                            child: const Text('ดึงคำแนะนำปุ๋ย'),
                          ),
                      ],
                    ),
                    if (_inspectionId != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ข้อมูลรอบตรวจปัจจุบัน',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Inspection ID: $_inspectionId | Round: ${_roundNo ?? "-"} | Uploaded: $_uploadedCount/$maxImagesPerRound',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // รูปที่ยังไม่อัปโหลด
              if (_picked.isNotEmpty)
                _buildStyledCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'รูปที่เลือก (ยังไม่อัปโหลด)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: List.generate(_picked.length, (i) {
                          final pf = _picked[i];
                          final bytes = pf.bytes;
                          final sizeKB = (pf.size / 1024).round();
                          return Stack(
                            alignment: Alignment.topRight,
                            children: [
                              Container(
                                width: 120,
                                height: 120,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Colors.grey.shade200,
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: (bytes != null && bytes.isNotEmpty)
                                          ? Image.memory(
                                              bytes,
                                              fit: BoxFit.cover,
                                            )
                                          : (pf.path != null
                                                ? Image.file(
                                                    File(pf.path!),
                                                    fit: BoxFit.cover,
                                                  )
                                                : const Center(
                                                    child: Icon(
                                                      Icons.image_not_supported,
                                                      color: Colors.grey,
                                                    ),
                                                  )),
                                    ),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.only(
                                          bottomLeft: Radius.circular(12),
                                          bottomRight: Radius.circular(12),
                                        ),
                                      ),
                                      child: Text(
                                        '${sizeKB}KB',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: () =>
                                        setState(() => _picked.removeAt(i)),
                                    style: IconButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(24, 24),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),

              // แกลเลอรี่ + ผลตรวจรายรูป
              if (images.isNotEmpty)
                _buildStyledCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.image_search, color: Colors.green[600]),
                          const SizedBox(width: 8),
                          Text(
                            'ผลตรวจจับรายรูป (ทุกภาพในรอบนี้)',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_analyzeResults.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.grey[600]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'ยังไม่มีผลตรวจจับรายรูป • กรุณากด "สั่งตรวจโมเดล" หลังอัปโหลดรูปครบ',
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_analyzeResults.isNotEmpty)
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: images.map((img) {
                            final rel = (img['image_path'] ?? '').toString();
                            final url = _imageUrl(rel);
                            final preds = _predsForImage(rel);

                            final hasNormal = preds.any((p) {
                              final cls = (p['class'] ?? '')
                                  .toString()
                                  .toLowerCase();
                              return cls == 'normal' ||
                                  cls == 'nomal' ||
                                  cls == 'healthy' ||
                                  cls == 'none';
                            });

                            return Container(
                              width: 220,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                                color: Colors.white,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(12),
                                      topRight: Radius.circular(12),
                                    ),
                                    child: AspectRatio(
                                      aspectRatio: 4 / 3,
                                      child: Image.network(
                                        url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: Colors.grey[200],
                                          child: const Center(
                                            child: Icon(
                                              Icons.broken_image,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          rel.split('/').last,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        if (hasNormal)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 6,
                                            ),
                                            margin: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green[50],
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.green[200]!,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.check_circle,
                                                  color: Colors.green,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    'ใบปกติ (normal)',
                                                    style: TextStyle(
                                                      color: Colors.green[800],
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (preds.isEmpty)
                                          Text(
                                            '— ไม่พบวัตถุ / หรือ < 0.25',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                        if (preds.isNotEmpty)
                                          ...preds.map((p) {
                                            final cls = '${p['class'] ?? '-'}';
                                            // ไม่แสดงเปอร์เซ็นต์ความเชื่อมั่นแล้ว
                                            return Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 4,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.green[50],
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.green[200]!,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.check_circle,
                                                    size: 16,
                                                    color: Colors.green,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      cls,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            Colors.green[800],
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),

              // สรุปตามธาตุ
              if (_detail != null)
                _buildStyledCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.assessment,
                            color: Colors.green[600],
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'ผลการตรวจ (สรุปตามธาตุอาหาร)',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (findings.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info, color: Colors.blue[600]),
                              const SizedBox(width: 8),
                              const Text('ไม่พบความผิดปกติ'),
                            ],
                          ),
                        ),
                      if (findings.isNotEmpty)
                        Column(
                          children: findings.map((raw) {
                            final m = raw as Map<String, dynamic>;
                            final code = m['nutrient_code'] ?? m['code'] ?? '-';
                            final sev = m['severity'] ?? '-';

                            Color severityColor = Colors.orange;
                            IconData severityIcon = Icons.eco_outlined;
                            switch (sev.toString().toLowerCase()) {
                              case 'severe':
                                severityColor = Colors.red;
                                severityIcon = Icons.error_outline;
                                break;
                              case 'moderate':
                                severityColor = Colors.orange;
                                severityIcon = Icons.warning_outlined;
                                break;
                              case 'mild':
                                severityColor = Colors.yellow;
                                severityIcon = Icons.info_outline;
                                break;
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: severityColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: severityColor.withOpacity(0.3),
                                ),
                              ),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: severityColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    severityIcon,
                                    color: severityColor,
                                  ),
                                ),
                                title: Text(
                                  '$code • $sev',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: severityColor,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),

              // คำแนะนำปุ๋ย: แสดง code + name_th + description
              if (_inspectionId != null)
                _buildStyledCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.spa_outlined, color: Colors.green[600]),
                          const SizedBox(width: 8),
                          Text(
                            'คำแนะนำปุ๋ยสำหรับรอบนี้',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'รีเฟรช',
                            onPressed: (_recsLoading || !_isConnected)
                                ? null
                                : _loadRecs,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_recsLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      if (!_recsLoading)
                        Builder(
                          builder: (_) {
                            if (_recs.isEmpty) {
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '— ยังไม่มีคำแนะนำจากรอบนี้ —',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              );
                            }
                            final tiles = _recs
                                .map((e) => _buildRecTile(e))
                                .toList();
                            return Column(children: tiles);
                          },
                        ),
                    ],
                  ),
                ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
