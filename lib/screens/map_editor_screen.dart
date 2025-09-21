// lib/screens/map_editor_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cocoa_app/api/field_api.dart';

// ===== สำคัญ: enum ต้องอยู่นอกคลาส (ห้ามประกาศในคลาส) =====
enum EditMode { field, zone }

class MapEditorScreen extends StatefulWidget {
  const MapEditorScreen({super.key});

  @override
  State<MapEditorScreen> createState() => _MapEditorScreenState();
}

class _MapEditorScreenState extends State<MapEditorScreen> {
  final MapController _map = MapController();

  int _fieldId = 0;
  String _fieldName = '';
  double? _fieldSizeSqm; // เก็บขนาดพื้นที่ของแปลงเพื่อส่งกลับเวลา save

  bool _loading = true;
  EditMode _mode = EditMode.field;

  /// จุดเส้นรอบแปลง (สีเขียว)
  final List<LatLng> _fieldVertices = [];

  /// รายชื่อโซน และโซนที่กำลังแก้ไข
  List<Map<String, dynamic>> _zones = [];
  int? _activeZoneId;

  /// จุดของโซนที่กำลังแก้ไข (สีส้ม)
  final List<LatLng> _activeZonePoints = [];

  /// โซนอื่น ๆ (เส้นส้มอ่อน แสดงเฉย ๆ)
  final Map<int, List<LatLng>> _otherZones = {}; // zoneId -> points

  static const String _tileUrlOsm =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const LatLng _fallback = LatLng(13.736, 100.523);

  @override
  void initState() {
    super.initState();
    // รับ args: { field_id, field_name }
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
      // ignore/log
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFieldVertices() async {
    _fieldVertices.clear();
    if (_fieldId == 0) return;
    final r = await FieldApiService.getFieldDetails(_fieldId);
    if (r['success'] == true && r['data'] != null) {
      final data = Map<String, dynamic>.from(r['data']);

      // เก็บ size_square_meter ไว้ส่งกลับเวลาอัปเดต (กัน 400)
      final s = data['size_square_meter'];
      if (s is num) {
        _fieldSizeSqm = s.toDouble();
      } else if (s is String) {
        _fieldSizeSqm = double.tryParse(s);
      }

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

    // ใช้ fields-with-zones เพื่อดึงโซนทั้งหมดของแปลงนี้
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

    // โหลดพิกัดของทุกโซน (ใช้ในชั้น "เส้นของโซนอื่น ๆ")
    for (final z in _zones) {
      final zid = (z['zone_id'] as num).toInt();
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
        if (lat != null && lng != null) {
          _activeZonePoints.add(LatLng(lat, lng));
        }
      }
    }
  }

  // ====== camera fit ======
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
    // กันกรณีจุดเดียว
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

  // ====== map tap ======
  void _onTap(TapPosition _, LatLng p) {
    setState(() {
      if (_mode == EditMode.field) {
        _fieldVertices.add(p);
      } else {
        if (_activeZoneId == null) return;
        _activeZonePoints.add(p);
      }
    });
  }

  // ====== save ======
  Future<void> _saveField() async {
    if (_fieldId == 0) return;

    // กัน API ที่ต้องการอย่างน้อย 3 จุด (รูปหลายเหลี่ยม)
    if (_fieldVertices.length < 3) {
      _toast('โปรดปักหมุดอย่างน้อย 3 จุดก่อนบันทึก', error: true);
      return;
    }

    // ถ้าต้องการให้ polygon ปิด (จุดแรก = จุดสุดท้าย) ให้ปลดคอมเมนต์ด้านล่าง
    // if (_fieldVertices.first != _fieldVertices.last) {
    //   _fieldVertices.add(_fieldVertices.first);
    // }

    final vertices = _fieldVertices
        .map((e) => {'latitude': e.latitude, 'longitude': e.longitude})
        .toList();

    final r = await FieldApiService.updateField(
      fieldId: _fieldId,
      fieldName: _fieldName,
      // แก้บั๊ก 400: ห้ามส่งค่าว่าง ให้ส่งค่าที่อ่านได้จาก getFieldDetails
      sizeSquareMeter: (_fieldSizeSqm ?? 0).toString(),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          // สลับโหมด Field/Zone
          DropdownButtonHideUnderline(
            child: DropdownButton<EditMode>(
              value: _mode,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              dropdownColor: Colors.white,
              onChanged: (v) => setState(() => _mode = v ?? EditMode.field),
              items: const [
                DropdownMenuItem(
                  value: EditMode.field,
                  child: Text('โหมดแปลง (สีเขียว)'),
                ),
                DropdownMenuItem(
                  value: EditMode.zone,
                  child: Text('โหมดโซน (สีส้ม)'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // เลือกโซนเมื่ออยู่โหมด zone
          if (_mode == EditMode.zone)
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
                items: _zones
                    .map(
                      (z) => DropdownMenuItem<int>(
                        value: (z['zone_id'] as num).toInt(),
                        child: Text(z['zone_name']?.toString() ?? 'zone'),
                      ),
                    )
                    .toList(),
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
                    initialCenter: _fieldVertices.isNotEmpty
                        ? _fieldVertices.first
                        : (_activeZonePoints.isNotEmpty
                              ? _activeZonePoints.first
                              : _fallback),
                    initialZoom: 18,
                    onTap: _onTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrlOsm,
                      maxZoom: 19,
                      userAgentPackageName: 'cocoa_app',
                      // สำคัญ: ห้ามใส่ const ตรงนี้
                      tileProvider: NetworkTileProvider(),
                      // ถ้าต้องการ performance เว็บให้ใช้แพ็กเกจ cancellable แทน:
                      // tileProvider: kIsWeb
                      //     ? CancellableNetworkTileProvider()
                      //     : NetworkTileProvider(),
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

                    // --- เส้นแปลง (สีเขียว) ---
                    if (_fieldVertices.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _fieldVertices,
                            strokeWidth: 3,
                            color: Colors.green,
                          ),
                        ],
                      ),
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

                    // --- เส้นของ "โซนอื่น ๆ" (เส้นส้มอ่อน) ---
                    if (_otherZones.isNotEmpty)
                      PolylineLayer(
                        polylines: _otherZones.entries
                            .where((e) => e.key != _activeZoneId)
                            .where((e) => e.value.length >= 2)
                            .map(
                              (e) => Polyline(
                                points: e.value,
                                strokeWidth: 2,
                                color: Colors.orange.withOpacity(0.5),
                              ),
                            )
                            .toList(),
                      ),

                    // --- เส้น + หมุดของ "โซนที่แก้ไขอยู่" (สีส้มชัด) ---
                    if (_activeZonePoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _activeZonePoints,
                            strokeWidth: 3,
                            color: Colors.orange,
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
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.orange,
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
                      _legendBadge(color: Colors.green, label: 'ขอบเขตแปลง'),
                      const SizedBox(height: 6),
                      _legendBadge(color: Colors.orange, label: 'เส้นโซน'),
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
                // Fit
                FloatingActionButton.extended(
                  heroTag: 'fit',
                  onPressed: () {
                    if (_mode == EditMode.field) {
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

                // Undo
                FloatingActionButton.extended(
                  heroTag: 'undo',
                  onPressed: () {
                    setState(() {
                      if (_mode == EditMode.field) {
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

                // Clear
                FloatingActionButton.extended(
                  heroTag: 'clear',
                  onPressed: () {
                    setState(() {
                      if (_mode == EditMode.field) {
                        _fieldVertices.clear();
                      } else {
                        _activeZonePoints.clear();
                      }
                    });
                  },
                  icon: const Icon(Icons.clear_all),
                  label: const Text('ล้างจุดในโหมดนี้'),
                  backgroundColor: Colors.red,
                ),
                const SizedBox(height: 8),

                // Save
                FloatingActionButton.extended(
                  heroTag: 'save',
                  onPressed: () async {
                    if (_mode == EditMode.field) {
                      await _saveField();
                    } else {
                      await _saveZone();
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: Text(
                    _mode == EditMode.field ? 'บันทึกแปลง' : 'บันทึกโซน',
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
}
