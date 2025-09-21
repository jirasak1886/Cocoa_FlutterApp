// lib/screens/map_editor_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:cocoa_app/api/field_api.dart';

// ===== Enum วางไว้นอกคลาส =====
enum MapEditMode { field, zone }

class MapEditorScreen extends StatefulWidget {
  const MapEditorScreen({super.key});

  @override
  State<MapEditorScreen> createState() => _MapEditorScreenState();
}

class _MapEditorScreenState extends State<MapEditorScreen> {
  final MapController _map = MapController();

  int _fieldId = 0;
  String _fieldName = '';
  double _fieldSize = 0; // ✅ เก็บขนาดเดิมไว้ส่งตอนบันทึก

  bool _loading = true;

  MapEditMode _mode = MapEditMode.field;

  final List<LatLng> _fieldVertices = [];

  List<Map<String, dynamic>> _zones = [];
  int? _activeZoneId;

  final List<LatLng> _activeZonePoints = [];

  final Map<int, List<LatLng>> _otherZones = {};

  final Map<int, Color> _zoneColors = {};

  static const String _tileUrlOsm =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const LatLng _fallback = LatLng(13.736, 100.523);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _fieldId = (args['field_id'] as num?)?.toInt() ?? 0;
        _fieldName = (args['field_name']?.toString() ?? '').trim();
      }
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _loadFieldVertices();
      await _loadZonesAndMarks();

      if (_zones.isNotEmpty) {
        _activeZoneId ??= (_zones.first['zone_id'] as num).toInt();
        await _loadActiveZoneMarks();
      }

      if (_fieldVertices.isNotEmpty) {
        _fitTo(_fieldVertices);
      } else if (_activeZonePoints.isNotEmpty) {
        _fitTo(_activeZonePoints);
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- ยืนยันลบ/ล้างทั้งหมด (ฟังก์ชันใช้ซ้ำ) ----------
  Future<bool> _confirmDeleteAll({
    required String title,
    required String message,
    String confirmText = 'ลบทั้งหมด',
    String cancelText = 'ยกเลิก',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _confirmAndClearCurrentMode() async {
    // ไม่มีอะไรให้ล้างก็ไม่ถาม
    if (_mode == MapEditMode.field && _fieldVertices.isEmpty) return;
    if (_mode == MapEditMode.zone && _activeZonePoints.isEmpty) return;

    final ok = await _confirmDeleteAll(
      title: _mode == MapEditMode.field
          ? 'ล้างจุดในโหมดแปลง?'
          : 'ล้างจุดในโหมดโซน?',
      message:
          'ต้องการลบจุดทั้งหมดในโหมดนี้หรือไม่ (การลบไม่สามารถย้อนกลับได้)',
    );
    if (!ok) return;

    setState(() {
      if (_mode == MapEditMode.field) {
        _fieldVertices.clear();
      } else {
        _activeZonePoints.clear();
      }
    });
    _toast('ล้างจุดในโหมดนี้แล้ว');
  }
  // -----------------------------------------------------------

  // โหลดเส้นขอบแปลง + ขนาด
  Future<void> _loadFieldVertices() async {
    _fieldVertices.clear();
    if (_fieldId == 0) return;
    final r = await FieldApiService.getFieldDetails(_fieldId);
    if (r['success'] == true && r['data'] != null) {
      final data = Map<String, dynamic>.from(r['data']);
      _fieldName = (data['field_name'] ?? _fieldName).toString();
      _fieldSize = (data['size_square_meter'] is num)
          ? (data['size_square_meter'] as num).toDouble()
          : double.tryParse(data['size_square_meter']?.toString() ?? '0') ??
                0.0;

      final vertices = List<Map<String, dynamic>>.from(data['vertices'] ?? []);
      for (final v in vertices) {
        final lat = (v['latitude'] as num?)?.toDouble();
        final lng = (v['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) _fieldVertices.add(LatLng(lat, lng));
      }
    }
  }

  Future<void> _loadZonesAndMarks() async {
    _zones = [];
    _otherZones.clear();
    _zoneColors.clear();

    final rf = await FieldApiService.getFieldsWithZones();
    if (rf['success'] == true) {
      final arr = List<Map<String, dynamic>>.from(rf['data'] ?? []);
      final found = arr.firstWhere(
        (f) => (f['field_id'] as num?)?.toInt() == _fieldId,
        orElse: () => {},
      );
      final zones = List<Map<String, dynamic>>.from(found['zones'] ?? []);
      _zones = zones;
    }

    for (final z in _zones) {
      final zid = (z['zone_id'] as num).toInt();
      _zoneColors[zid] = _colorForZone(zid);

      final rm = await FieldApiService.getMarks(zid);
      final pts = <LatLng>[];
      if (rm['success'] == true) {
        final items = List<Map<String, dynamic>>.from(rm['data'] ?? []);
        items.sort(
          (a, b) => (a['tree_no'] as num).toInt().compareTo(
            (b['tree_no'] as num).toInt(),
          ),
        );
        for (final m in items) {
          final lat = (m['latitude'] as num?)?.toDouble();
          final lng = (m['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) pts.add(LatLng(lat, lng));
        }
      }
      _otherZones[zid] = pts;
    }
  }

  Future<void> _loadActiveZoneMarks() async {
    _activeZonePoints.clear();
    final zid = _activeZoneId;
    if (zid == null) return;
    final r = await FieldApiService.getMarks(zid);
    if (r['success'] == true) {
      final items = List<Map<String, dynamic>>.from(r['data'] ?? []);
      items.sort(
        (a, b) => (a['tree_no'] as num).toInt().compareTo(
          (b['tree_no'] as num).toInt(),
        ),
      );
      for (final m in items) {
        final lat = (m['latitude'] as num?)?.toDouble();
        final lng = (m['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) _activeZonePoints.add(LatLng(lat, lng));
      }
    }
  }

  void _fitTo(List<LatLng> pts) {
    if (pts.isEmpty) return;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    if ((maxLat - minLat).abs() < 1e-9 && (maxLng - minLng).abs() < 1e-9) {
      const d = 0.0007;
      minLat -= d;
      maxLat += d;
      minLng -= d;
      maxLng += d;
    }
    final bounds = LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
    _map.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(36)),
    );
  }

  Color _colorForZone(int zoneId) {
    final hue = (zoneId * 57) % 360;
    final hsl = HSLColor.fromAHSL(1.0, hue.toDouble(), 0.75, 0.50);
    return hsl.toColor();
  }

  void _onTap(TapPosition _, LatLng p) {
    if (_mode == MapEditMode.field) {
      setState(() => _fieldVertices.add(p));
    } else {
      if (_activeZoneId == null) return;
      setState(() => _activeZonePoints.add(p));
    }
  }

  Future<void> _saveField() async {
    if (_fieldId == 0) return;
    final vertices = _fieldVertices
        .map((e) => {'latitude': e.latitude, 'longitude': e.longitude})
        .toList();
    final r = await FieldApiService.updateField(
      fieldId: _fieldId,
      fieldName: _fieldName,
      sizeSquareMeter: _fieldSize.toString(), // ✅ ส่งค่าเดิม ไม่ใช่ค่าว่าง
      vertices: vertices,
    );
    _toast(
      r['success'] == true
          ? 'บันทึกพิกัดแปลงสำเร็จ'
          : (r['message'] ?? 'บันทึกแปลงไม่สำเร็จ'),
      error: r['success'] != true,
    );
  }

  Future<void> _saveZone() async {
    final zid = _activeZoneId;
    if (zid == null) return;
    final marks = <Map<String, dynamic>>[];
    for (int i = 0; i < _activeZonePoints.length; i++) {
      marks.add({
        'tree_no': i + 1,
        'latitude': _activeZonePoints[i].latitude,
        'longitude': _activeZonePoints[i].longitude,
      });
    }
    final r = await FieldApiService.replaceMarks(zoneId: zid, marks: marks);
    _toast(
      r['success'] == true
          ? 'บันทึกพิกัดโซนสำเร็จ'
          : (r['message'] ?? 'บันทึกโซนไม่สำเร็จ'),
      error: r['success'] != true,
    );
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _fieldName.isNotEmpty ? 'แผนที่: $_fieldName' : 'แผนที่แปลง';

    final activeColor = _activeZoneId != null
        ? (_zoneColors[_activeZoneId!] ?? Colors.orange)
        : Colors.orange;

    final initialCenter = _fieldVertices.isNotEmpty
        ? _fieldVertices.first
        : (_activeZonePoints.isNotEmpty ? _activeZonePoints.first : _fallback);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<MapEditMode>(
              value: _mode,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              dropdownColor: Colors.white,
              onChanged: (v) => setState(() => _mode = v ?? MapEditMode.field),
              items: const [
                DropdownMenuItem(
                  value: MapEditMode.field,
                  child: Text('โหมดแปลง (เส้นดำ/เขียว)'),
                ),
                DropdownMenuItem(
                  value: MapEditMode.zone,
                  child: Text('โหมดโซน (ตามสีโซน)'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_mode == MapEditMode.zone)
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _activeZoneId,
                hint: const Text('เลือกโซน'),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                dropdownColor: Colors.white,
                onChanged: (zid) async {
                  setState(() => _activeZoneId = zid);
                  await _loadActiveZoneMarks();
                  if (mounted) setState(() {});
                },
                items: _zones.map((z) {
                  final zid = (z['zone_id'] as num).toInt();
                  final name = z['zone_name']?.toString() ?? 'zone';
                  final color = _zoneColors[zid] ?? _colorForZone(zid);
                  return DropdownMenuItem<int>(
                    value: zid,
                    child: Row(
                      children: [
                        _colorDot(color),
                        const SizedBox(width: 8),
                        Text(name),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: initialCenter,
                    initialZoom: 18,
                    onTap: _onTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrlOsm,
                      maxZoom: 19,
                      userAgentPackageName: 'cocoa_app',
                      tileProvider: NetworkTileProvider(),
                      errorTileCallback: (tile, error, stackTrace) {
                        try {
                          final dyn = tile as dynamic;
                          final z = (dyn.z ?? dyn.coords?.z) ?? '?';
                          final x = (dyn.x ?? dyn.coords?.x) ?? '?';
                          final y = (dyn.y ?? dyn.coords?.y) ?? '?';
                          debugPrint('Tile error z$z/x$x/y$y: $error');
                        } catch (_) {
                          debugPrint('Tile error: $error');
                        }
                      },
                    ),

                    // --- เส้นแปลง: ขอบ "สีดำ" + เส้นใน "สีเขียว" ---
                    if (_fieldVertices.length >= 2) ...[
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _fieldVertices,
                            strokeWidth: 5, // ขอบดำหนา
                            color: Colors.black,
                          ),
                        ],
                      ),
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _fieldVertices,
                            strokeWidth: 3, // เส้นเขียวทับ
                            color: Colors.green,
                          ),
                        ],
                      ),
                    ],
                    if (_fieldVertices.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          for (final p in _fieldVertices)
                            Marker(
                              point: p,
                              width: 32,
                              height: 32,
                              child: const Icon(
                                Icons.place,
                                color: Colors.green,
                                size: 28,
                              ),
                            ),
                        ],
                      ),

                    // --- เส้นโซนอื่น ๆ (โปร่ง 50%) ---
                    if (_otherZones.isNotEmpty)
                      PolylineLayer(
                        polylines: _otherZones.entries
                            .where((e) => e.key != _activeZoneId)
                            .where((e) => e.value.length >= 2)
                            .map((e) {
                              final c =
                                  (_zoneColors[e.key] ?? _colorForZone(e.key))
                                      .withOpacity(0.5);
                              return Polyline(
                                points: e.value,
                                strokeWidth: 2,
                                color: c,
                              );
                            })
                            .toList(),
                      ),

                    // --- โซนที่เลือก (สีโซน) ---
                    if (_activeZonePoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _activeZonePoints,
                            strokeWidth: 3.5,
                            color: activeColor,
                          ),
                        ],
                      ),
                    if (_activeZonePoints.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          for (final p in _activeZonePoints)
                            Marker(
                              point: p,
                              width: 34,
                              height: 34,
                              child: Icon(
                                Icons.location_on,
                                color: activeColor,
                                size: 30,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),

                // Legend
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _legendBadge(color: Colors.black, label: 'เส้นขอบแปลง'),
                      const SizedBox(height: 4),
                      _legendBadge(color: Colors.green, label: 'ขอบเขตแปลง'),
                      const SizedBox(height: 6),
                      _legendBadge(color: activeColor, label: 'โซนที่เลือก'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '© OpenStreetMap contributors',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: _loading
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'fit',
                  onPressed: () {
                    if (_mode == MapEditMode.field) {
                      _fitTo(_fieldVertices);
                    } else {
                      if (_activeZonePoints.isNotEmpty) {
                        _fitTo(_activeZonePoints);
                      } else if (_fieldVertices.isNotEmpty) {
                        _fitTo(_fieldVertices);
                      }
                    }
                  },
                  icon: const Icon(Icons.center_focus_strong),
                  label: const Text('ซูมให้พอดี'),
                ),
                const SizedBox(height: 8),

                FloatingActionButton.extended(
                  heroTag: 'undo',
                  onPressed: () {
                    setState(() {
                      if (_mode == MapEditMode.field) {
                        if (_fieldVertices.isNotEmpty) {
                          _fieldVertices.removeLast();
                        }
                      } else {
                        if (_activeZonePoints.isNotEmpty) {
                          _activeZonePoints.removeLast();
                        }
                      }
                    });
                  },
                  icon: const Icon(Icons.undo),
                  label: const Text('ย้อนจุดล่าสุด'),
                ),
                const SizedBox(height: 8),

                // ✅ ใช้ยืนยันก่อนล้าง
                FloatingActionButton.extended(
                  heroTag: 'clear',
                  onPressed: _confirmAndClearCurrentMode,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('ล้างจุดในโหมดนี้'),
                  backgroundColor: Colors.red,
                ),
                const SizedBox(height: 8),

                FloatingActionButton.extended(
                  heroTag: 'save',
                  onPressed: () async {
                    if (_mode == MapEditMode.field) {
                      await _saveField();
                    } else {
                      await _saveZone();
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: Text(
                    _mode == MapEditMode.field ? 'บันทึกแปลง' : 'บันทึกโซน',
                  ),
                  backgroundColor: Colors.green,
                ),
              ],
            ),
    );
  }

  Widget _legendBadge({required Color color, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 18, height: 4, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _colorDot(Color c) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: c,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.black12),
    ),
  );
}
