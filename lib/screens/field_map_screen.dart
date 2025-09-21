// lib/screens/field_map_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:cocoa_app/api/field_api.dart'; // ← ใช้โหลด vertices ของแปลง

class FieldMapScreen extends StatefulWidget {
  const FieldMapScreen({super.key});

  @override
  State<FieldMapScreen> createState() => _FieldMapScreenState();
}

class _FieldMapScreenState extends State<FieldMapScreen> {
  final MapController _map = MapController();

  int _fieldId = 0;
  String _fieldName = '';

  final List<LatLng> _points = [];
  bool _loading = true;

  static const LatLng _fallback = LatLng(13.736, 100.523); // BKK
  static const String _tileUrlOsm =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  void initState() {
    super.initState();
    // อ่าน arguments หลัง build แรก
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        _fieldId = (args['field_id'] as num?)?.toInt() ?? 0;
        _fieldName = (args['field_name']?.toString() ?? '').trim();
      }
      await _loadFieldVertices();
      if (mounted) setState(() => _loading = false);

      // ถ้ามีพิกัดให้ fit กล้อง
      if (_points.isNotEmpty) _fitTo(_points);
    });
  }

  Future<void> _loadFieldVertices() async {
    _points.clear();
    if (_fieldId == 0) return;

    try {
      final res = await FieldApiService.getFieldDetails(_fieldId);
      if (res['success'] == true && res['data'] != null) {
        final data = Map<String, dynamic>.from(res['data']);
        final vertices = List<Map<String, dynamic>>.from(
          data['vertices'] ?? [],
        );
        for (final v in vertices) {
          final lat = (v['latitude'] as num?)?.toDouble();
          final lng = (v['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            _points.add(LatLng(lat, lng));
          }
        }
      }
    } catch (e) {
      debugPrint('load vertices error: $e');
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
      const d = 0.0007; // กันกรณีมีจุดเดียว
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

  @override
  Widget build(BuildContext context) {
    final title = _fieldName.isNotEmpty
        ? 'แผนที่แปลง: $_fieldName'
        : 'แผนที่แปลง';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              setState(() => _loading = true);
              await _loadFieldVertices();
              setState(() => _loading = false);
              if (_points.isNotEmpty) _fitTo(_points);
            },
          ),
          IconButton(
            tooltip: 'ซูมให้พอดี',
            onPressed: _points.isEmpty ? null : () => _fitTo(_points),
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _points.isNotEmpty
                        ? _points.first
                        : _fallback,
                    initialZoom: 17,
                  ),
                  children: [
                    // ✅ flutter_map 7.x: อย่าใช้ const กับ NetworkTileProvider
                    TileLayer(
                      urlTemplate: _tileUrlOsm,
                      maxZoom: 19,
                      userAgentPackageName: 'cocoa_app',
                      tileProvider: NetworkTileProvider(),
                      // ✅ flutter_map 7.x: tile มี .z/.x/.y
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

                    // วาดเส้นรอบแปลง ถ้ามีพิกัด >= 2 จุด
                    if (_points.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _points,
                            strokeWidth: 3,
                            color: Colors.green,
                          ),
                        ],
                      ),

                    // ปักหมุดมุมแปลง ถ้ามีจุด
                    if (_points.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          for (final p in _points)
                            Marker(
                              point: p,
                              width: 34,
                              height: 34,
                              child: const Icon(
                                Icons.place,
                                size: 28,
                                color: Colors.green,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),

                // เครดิต OSM
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
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
                ),
              ],
            ),
    );
  }
}
