// lib/screens/zone_map_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';
import 'package:cocoa_app/api/field_api.dart';

class ZoneMapScreen extends StatefulWidget {
  const ZoneMapScreen({super.key});

  @override
  State<ZoneMapScreen> createState() => _ZoneMapScreenState();
}

class _ZoneMapScreenState extends State<ZoneMapScreen> {
  final MapController _map = MapController();

  int _zoneId = 0;
  String _zoneName = '';
  String _fieldName = '';

  bool _loading = true;
  bool _closeRing = false;
  bool _editMode = true; // แตะเพื่อเพิ่ม/ย้ายจุด

  final List<LatLng> _points = <LatLng>[];
  LatLng? _center;

  // ใช้ OSM แบบไม่ต้องใช้ API key
  static const String _tileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _zoneId = (args['zone_id'] as num?)?.toInt() ?? 0;
        _zoneName = (args['zone_name']?.toString() ?? '').trim();
        _fieldName = (args['field_name']?.toString() ?? '').trim();
      }
      _loadZone();
    });
  }

  Future<void> _loadZone() async {
    if (_zoneId == 0) {
      setState(() => _loading = false);
      return;
    }
    try {
      final r = await FieldApiService.getMarks(_zoneId);
      if (r['success'] == true) {
        final items = List<Map<String, dynamic>>.from(r['data'] ?? []);
        items.sort(
          (a, b) => (a['tree_no'] as num).toInt().compareTo(
            (b['tree_no'] as num).toInt(),
          ),
        );
        _points
          ..clear()
          ..addAll(
            items.map(
              (m) => LatLng(
                (m['latitude'] as num).toDouble(),
                (m['longitude'] as num).toDouble(),
              ),
            ),
          );
        if (_points.isNotEmpty) {
          _center = _centroid(_points);
          _fitTo(_points);
        }
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  LatLng _centroid(List<LatLng> pts) {
    if (pts.isEmpty) return const LatLng(13.736, 100.523);
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
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

  void _onTapMap(TapPosition tapPos, LatLng latlng) {
    if (!_editMode) return;
    setState(() => _points.add(latlng));
  }

  void _removePoint(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบหมุดนี้?'),
        content: const Text('ยืนยันการลบพิกัดต้นไม้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (ok == true) setState(() => _points.removeAt(index));
  }

  Future<void> _save() async {
    if (_zoneId == 0) return;
    setState(() => _loading = true);
    try {
      final marks = <Map<String, dynamic>>[];
      for (int i = 0; i < _points.length; i++) {
        marks.add({
          'tree_no': i + 1,
          'latitude': _points[i].latitude,
          'longitude': _points[i].longitude,
        });
      }
      final result = await FieldApiService.replaceMarks(
        zoneId: _zoneId,
        marks: marks,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['success'] == true
                ? 'บันทึกพิกัดโซนสำเร็จ'
                : (result['message'] ?? 'บันทึกล้มเหลว'),
          ),
          backgroundColor: result['success'] == true
              ? Colors.green
              : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ผิดพลาด: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _zoneName.isNotEmpty
        ? 'โซน: $_zoneName (${_fieldName.isNotEmpty ? _fieldName : '-'})'
        : 'แผนที่โซน';

    final initial =
        _center ??
        (_points.isNotEmpty ? _points.first : const LatLng(13.736, 100.523));

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: _editMode ? 'ปิดโหมดแก้ไข' : 'เปิดโหมดแก้ไข',
            onPressed: () => setState(() => _editMode = !_editMode),
            icon: Icon(_editMode ? Icons.edit : Icons.edit_off),
          ),
          IconButton(
            tooltip: _closeRing ? 'เส้นแบบเปิด' : 'ปิดปลายเป็นรูปหลายเหลี่ยม',
            onPressed: () => setState(() => _closeRing = !_closeRing),
            icon: Icon(_closeRing ? Icons.pentagon : Icons.blur_linear),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: initial,
                          initialZoom: 18,
                          onTap: _onTapMap,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            maxZoom: 20,
                            userAgentPackageName: 'cocoa_app',
                            tileProvider: NetworkTileProvider(),
                            // เลือก “แบบกันเหนียว” (ใช้ได้ทั้ง v5/v6)
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

                          if (_points.length >= 2)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _closeRing && _points.length >= 3
                                      ? [..._points, _points.first]
                                      : _points,
                                  strokeWidth: 3,
                                  color: Colors.orange,
                                ),
                              ],
                            ),
                          if (_points.isNotEmpty)
                            DragMarkers(
                              markers: [
                                for (int i = 0; i < _points.length; i++)
                                  DragMarker(
                                    point: _points[i],
                                    size: const Size(32, 32),
                                    builder: (ctx, pos, isDragging) =>
                                        const Icon(
                                          Icons.location_on,
                                          size: 32,
                                          color: Colors.red,
                                        ),
                                    onDragEnd: (details, newPos) {
                                      setState(() => _points[i] = newPos);
                                    },
                                    onLongPress: (_) => _removePoint(i),
                                  ),
                              ],
                            ),
                        ],
                      ),

                      // แสดงเครดิต OSM ตรงมุมขวาล่าง (เลี่ยงใช้ attributionBuilder)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.45),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              '© OpenStreetMap contributors',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // แผงรายการพิกัด
                _CoordsPanel(
                  title: 'พิกัดโซน (${_points.length})',
                  items: _points,
                  onCopy: (text) =>
                      Clipboard.setData(ClipboardData(text: text)),
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
                  onPressed: () => _fitTo(
                    _points.isNotEmpty
                        ? _points
                        : (_center != null ? [_center!] : []),
                  ),
                  label: const Text('ซูมให้พอดี'),
                  icon: const Icon(Icons.center_focus_strong),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'undo',
                  onPressed: _points.isEmpty
                      ? null
                      : () => setState(() => _points.removeLast()),
                  label: const Text('ย้อนจุดล่าสุด'),
                  icon: const Icon(Icons.undo),
                  backgroundColor: _points.isEmpty ? Colors.grey : null,
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'clear',
                  onPressed: _points.isEmpty
                      ? null
                      : () => setState(() => _points.clear()),
                  label: const Text('ล้างทั้งหมด'),
                  icon: const Icon(Icons.clear_all),
                  backgroundColor: _points.isEmpty ? Colors.grey : Colors.red,
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'save',
                  onPressed: _points.isNotEmpty ? _save : null,
                  label: const Text('บันทึกพิกัด'),
                  icon: const Icon(Icons.save),
                  backgroundColor: _points.isNotEmpty
                      ? Colors.green
                      : Colors.grey,
                ),
              ],
            ),
    );
  }
}

class _CoordsPanel extends StatelessWidget {
  final String title;
  final List<LatLng> items;
  final void Function(String) onCopy;

  const _CoordsPanel({
    super.key,
    required this.title,
    required this.items,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final text = items
        .map(
          (p) =>
              '${p.latitude.toStringAsFixed(7)}, ${p.longitude.toStringAsFixed(7)}',
        )
        .join('\n');

    return Material(
      elevation: 2,
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'คัดลอกพิกัดทั้งหมด',
              onPressed: items.isEmpty ? null : () => onCopy(text),
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
      ),
    );
  }
}
