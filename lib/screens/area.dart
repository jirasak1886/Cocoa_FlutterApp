// lib/screens/field_management.dart
import 'package:cocoa_app/api/field_api.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;

class FieldManagement extends StatefulWidget {
  const FieldManagement({Key? key}) : super(key: key);

  @override
  State<FieldManagement> createState() => _FieldManagementState();
}

class _FieldManagementState extends State<FieldManagement> {
  List<Map<String, dynamic>> fields = [];
  bool isLoading = true;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFields();
  }

  Future<void> _loadFields() async {
    setState(() => isLoading = true);

    final result = await FieldApiService.getFieldsWithZones();

    setState(() {
      isLoading = false;
      if (result['success']) {
        fields = List<Map<String, dynamic>>.from(result['data'] ?? []);
      }
    });

    if (!result['success']) {
      _showMessage(result['message'] ?? 'โหลดข้อมูลไม่สำเร็จ', isError: true);
    }
  }

  List<Map<String, dynamic>> get filteredFields {
    if (searchQuery.isEmpty) return fields;
    return fields.where((field) {
      final name = field['field_name']?.toString().toLowerCase() ?? '';
      return name.contains(searchQuery.toLowerCase());
    }).toList();
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  void _showFieldForm([Map<String, dynamic>? field]) {
    showDialog(
      context: context,
      builder: (context) =>
          _FieldFormDialog(field: field, onSaved: _loadFields),
    );
  }

  void _showZoneForm(
    int fieldId,
    String fieldName, [
    Map<String, dynamic>? zone,
  ]) {
    showDialog(
      context: context,
      builder: (context) => _ZoneFormDialog(
        fieldId: fieldId,
        fieldName: fieldName,
        zone: zone,
        onSaved: _loadFields,
      ),
    );
  }

  Future<void> _deleteField(Map<String, dynamic> field) async {
    final confirm = await _showConfirmDialog(
      'ลบแปลง ${field['field_name']}?',
      'การลบจะไม่สามารถย้อนกลับได้',
    );
    if (!confirm) return;

    final result = await FieldApiService.deleteField(field['field_id']);
    _showMessage(
      result['success'] ? 'ลบสำเร็จ' : (result['message'] ?? 'ลบไม่สำเร็จ'),
      isError: !result['success'],
    );
    if (result['success']) _loadFields();
  }

  Future<void> _deleteZone(Map<String, dynamic> zone) async {
    final confirm = await _showConfirmDialog(
      'ลบโซน ${zone['zone_name']}?',
      'การลบจะไม่สามารถย้อนกลับได้',
    );
    if (!confirm) return;

    final result = await FieldApiService.deleteZone(zone['zone_id']);
    _showMessage(
      result['success'] ? 'ลบสำเร็จ' : (result['message'] ?? 'ลบไม่สำเร็จ'),
      isError: !result['success'],
    );
    if (result['success']) _loadFields();
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการแปลง'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFields),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'ค้นหาแปลง...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
              onChanged: (value) => setState(() => searchQuery = value),
            ),
          ),

          // Fields List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredFields.isEmpty
                ? const Center(
                    child: Text('ไม่มีแปลง', style: TextStyle(fontSize: 16)),
                  )
                : RefreshIndicator(
                    onRefresh: _loadFields,
                    child: ListView.builder(
                      itemCount: filteredFields.length,
                      itemBuilder: (context, index) {
                        final field = FieldApiService.safeFieldData(
                          filteredFields[index],
                        );
                        final zones = List.from(
                          filteredFields[index]['zones'] ?? [],
                        );
                        final vc = (field['vertex_count'] ?? 0) as int;

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.green.shade100,
                              child: const Icon(
                                Icons.agriculture,
                                color: Colors.green,
                              ),
                            ),
                            title: Text(field['field_name']),
                            subtitle: Text(
                              '${field['size_square_meter']} ตร.ม. • ${zones.length} โซน${vc > 0 ? ' • $vc จุด' : ''}',
                            ),
                            trailing: PopupMenuButton(
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, color: Colors.blue),
                                      SizedBox(width: 8),
                                      Text('แก้ไข'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'add_zone',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.add_location,
                                        color: Colors.green,
                                      ),
                                      SizedBox(width: 8),
                                      Text('เพิ่มโซน'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('ลบ'),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                switch (value) {
                                  case 'edit':
                                    _showFieldForm(filteredFields[index]);
                                    break;
                                  case 'add_zone':
                                    _showZoneForm(
                                      field['field_id'],
                                      field['field_name'],
                                    );
                                    break;
                                  case 'delete':
                                    _deleteField(field);
                                    break;
                                }
                              },
                            ),
                            // แสดงโซน + centroid lat/lng ของ marks
                            children: zones.map((zone) {
                              final safeZone = FieldApiService.safeZoneData(
                                zone,
                              );
                              return _ZoneTile(
                                zone: safeZone,
                                onEdit: () => _showZoneForm(
                                  field['field_id'],
                                  field['field_name'],
                                  zone,
                                ),
                                onDelete: () => _deleteZone(safeZone),
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFieldForm(),
        backgroundColor: Colors.green,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ===== Zone list item with Lat/Lng (centroid of marks) =====
class _ZoneTile extends StatefulWidget {
  final Map<String, dynamic> zone;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ZoneTile({
    required this.zone,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ZoneTile> createState() => _ZoneTileState();
}

class _ZoneTileState extends State<_ZoneTile> {
  bool _loading = true;
  String? _latLngText; // "({lat}, {lng})" หรือ "ไม่มีพิกัด"

  @override
  void initState() {
    super.initState();
    _loadMarksAndBuildLatLng();
  }

  Future<void> _loadMarksAndBuildLatLng() async {
    try {
      final res = await FieldApiService.getMarks(widget.zone['zone_id']);
      if (res['success'] == true) {
        final marks = List<Map<String, dynamic>>.from(res['data'] ?? []);
        if (marks.isNotEmpty) {
          double lat = 0, lng = 0;
          for (final m in marks) {
            lat += (m['latitude'] as num).toDouble();
            lng += (m['longitude'] as num).toDouble();
          }
          lat /= marks.length;
          lng /= marks.length;
          _latLngText =
              '(${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})';
        } else {
          _latLngText = 'ไม่มีพิกัด';
        }
      } else {
        _latLngText = 'ไม่มีพิกัด';
      }
    } catch (_) {
      _latLngText = 'ไม่มีพิกัด';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = widget.zone;
    final subtitle = StringBuffer()..write('${z['num_trees']} ต้น');
    if (_loading) {
      subtitle.write(' • กำลังโหลดพิกัด…');
    } else if (_latLngText != null) {
      subtitle.write(' • $_latLngText');
    }

    return ListTile(
      leading: const Icon(Icons.location_on, color: Colors.orange),
      title: Text(z['zone_name']),
      subtitle: Text(subtitle.toString()),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
            onPressed: widget.onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}

// ===== Field Form Dialog =====
class _FieldFormDialog extends StatefulWidget {
  final Map<String, dynamic>? field;
  final VoidCallback onSaved;

  const _FieldFormDialog({this.field, required this.onSaved});

  @override
  State<_FieldFormDialog> createState() => _FieldFormDialogState();
}

class _FieldFormDialogState extends State<_FieldFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _sizeController = TextEditingController();

  // ศูนย์กลางแปลง (คำนวณจากหลายจุด → read-only)
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  bool _isLoading = false;
  bool _gettingLoc = false;

  /// พิกัดหลายจุดของแปลง
  final List<Map<String, double>> _gpsPoints = [];

  @override
  void initState() {
    super.initState();
    if (widget.field != null) {
      final f = FieldApiService.safeFieldData(widget.field!);
      _nameController.text = f['field_name'];
      _sizeController.text = f['size_square_meter'].toString();
      _loadExistingVertices(f['field_id']);
    }
  }

  Future<void> _loadExistingVertices(int fieldId) async {
    final res = await FieldApiService.getFieldDetails(fieldId);
    if (res['success'] == true && res['data'] != null) {
      final data = Map<String, dynamic>.from(res['data']);
      final vertices = List<Map<String, dynamic>>.from(
        data['vertices'] ?? const [],
      );
      if (vertices.isNotEmpty) {
        _gpsPoints.clear();
        for (final v in vertices) {
          final lat = (v['latitude'] as num?)?.toDouble();
          final lng = (v['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            _gpsPoints.add({'lat': lat, 'lng': lng});
          }
        }
        final c = _centroid(_gpsPoints);
        _latController.text = c['lat']!.toStringAsFixed(7);
        _lngController.text = c['lng']!.toStringAsFixed(7);
        if (mounted) setState(() {});
      }
    }
  }

  // ========== Geolocator helpers ==========
  Future<bool> _ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('กรุณาเปิด Location Services'),
          action: SnackBarAction(
            label: 'เปิดการตั้งค่า',
            onPressed: Geolocator.openLocationSettings,
          ),
        ),
      );
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        _toast('จำเป็นต้องอนุญาตตำแหน่ง', error: true);
        return false;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('สิทธิ์ตำแหน่งถูกปฏิเสธแบบถาวร'),
          action: SnackBarAction(
            label: 'เปิด App Settings',
            onPressed: Geolocator.openAppSettings,
          ),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _addPointFromGPS() async {
    if (_gettingLoc) return;
    if (!await _ensureLocationReady()) return;
    try {
      setState(() => _gettingLoc = true);
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      setState(() {
        _gpsPoints.add({'lat': p.latitude, 'lng': p.longitude});
        final c = _centroid(_gpsPoints);
        _latController.text = c['lat']!.toStringAsFixed(7);
        _lngController.text = c['lng']!.toStringAsFixed(7);
      });
      _toast('เพิ่มจุดที่ ${_gpsPoints.length} สำเร็จ');
    } catch (e) {
      _toast('อ่านตำแหน่งไม่สำเร็จ: $e', error: true);
    } finally {
      if (mounted) setState(() => _gettingLoc = false);
    }
  }

  Map<String, double> _centroid(List<Map<String, double>> pts) {
    if (pts.isEmpty) return {'lat': 0, 'lng': 0};
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p['lat']!;
      lng += p['lng']!;
    }
    return {'lat': lat / pts.length, 'lng': lng / pts.length};
  }

  void _removePoint(int index) {
    setState(() {
      _gpsPoints.removeAt(index);
      if (_gpsPoints.isEmpty) {
        _latController.text = '';
        _lngController.text = '';
        return;
      }
      final c = _centroid(_gpsPoints);
      _latController.text = c['lat']!.toStringAsFixed(7);
      _lngController.text = c['lng']!.toStringAsFixed(7);
    });
  }

  void _clearPoints() {
    setState(() {
      _gpsPoints.clear();
      _latController.text = '';
      _lngController.text = '';
    });
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

  // ========== Save ==========
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final vertices = _gpsPoints
        .map((p) => {'latitude': p['lat'], 'longitude': p['lng']})
        .toList();

    Map<String, dynamic> result;
    try {
      if (widget.field != null) {
        result = await FieldApiService.updateField(
          fieldId: widget.field!['field_id'],
          fieldName: _nameController.text.trim(),
          sizeSquareMeter: _sizeController.text.trim(),
          vertices: vertices,
        );
      } else {
        result = await FieldApiService.createField(
          fieldName: _nameController.text.trim(),
          sizeSquareMeter: _sizeController.text.trim(),
          vertices: vertices,
        );
      }
    } catch (e) {
      result = {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }

    setState(() => _isLoading = false);

    if (result['success']) {
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    }

    _toast(
      result['success']
          ? 'บันทึกสำเร็จ'
          : (result['message'] ?? 'บันทึกล้มเหลว'),
      error: !result['success'],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.field != null ? 'แก้ไขแปลง' : 'เพิ่มแปลงใหม่'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อแปลง',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v?.isEmpty == true ? 'กรุณาใส่ชื่อ' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _sizeController,
                decoration: const InputDecoration(
                  labelText: 'ขนาด (ตร.ม.)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v?.isEmpty == true) return 'กรุณาใส่ขนาด';
                  final d = double.tryParse(v!);
                  if (d == null) return 'ใส่ตัวเลข';
                  if (d <= 0) return 'ต้องมากกว่า 0';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ศูนย์กลาง (อ่านอย่างเดียว)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'ละติจูด (ศูนย์กลาง-คำนวณ)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lngController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'ลองจิจูด (ศูนย์กลาง-คำนวณ)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.my_location),
                      label: Text(
                        _gettingLoc ? 'กำลังอ่านตำแหน่ง…' : 'เพิ่มจุดจาก GPS',
                      ),
                      onPressed: _isLoading || _gettingLoc
                          ? null
                          : _addPointFromGPS,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_gpsPoints.isNotEmpty)
                    OutlinedButton(
                      onPressed: _isLoading ? null : _clearPoints,
                      child: const Text('ล้างจุดทั้งหมด'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'จำนวนจุดที่เพิ่ม: ${_gpsPoints.length} จุด',
                  style: TextStyle(
                    color: _gpsPoints.isEmpty
                        ? Colors.grey
                        : Colors.green.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_gpsPoints.isNotEmpty) const SizedBox(height: 8),
              if (_gpsPoints.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: -8,
                    children: _gpsPoints.asMap().entries.map((e) {
                      final i = e.key;
                      final p = e.value;
                      return Chip(
                        label: Text(
                          '#${i + 1} (${p['lat']!.toStringAsFixed(5)}, ${p['lng']!.toStringAsFixed(5)})',
                        ),
                        deleteIcon: const Icon(Icons.close),
                        onDeleted: _isLoading ? null : () => _removePoint(i),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('บันทึก'),
        ),
      ],
    );
  }
}

// ===== Zone Form Dialog =====
class _ZoneFormDialog extends StatefulWidget {
  final int fieldId;
  final String fieldName;
  final Map<String, dynamic>? zone;
  final VoidCallback onSaved;

  const _ZoneFormDialog({
    required this.fieldId,
    required this.fieldName,
    this.zone,
    required this.onSaved,
  });

  @override
  State<_ZoneFormDialog> createState() => _ZoneFormDialogState();
}

class _ZoneFormDialogState extends State<_ZoneFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _treesController = TextEditingController();

  bool _isLoading = false;

  // เก็บรายการ marks ที่ผู้ใช้กดเพิ่มจาก GPS
  final List<Map<String, dynamic>> _marks = [];
  bool _marksLoaded = false;

  // ขอบเขตแปลงแบบวงกลมจาก centroid(vertices) + พื้นที่ตร.ม.
  double? _centerLat, _centerLng, _radiusMeters;

  // ค่ากำกับ
  bool _enforceBoundary = false;
  static const double _boundarySlack = 1.15;
  static const double _minRadiusMeters = 50.0;
  static const double _fallbackLat = 13.736717;
  static const double _fallbackLng = 100.523186;

  @override
  void initState() {
    super.initState();
    if (widget.zone != null) {
      final zone = FieldApiService.safeZoneData(widget.zone!);
      _nameController.text = zone['zone_name'];
      _treesController.text = zone['num_trees'].toString();
      _loadExistingMarks(zone['zone_id']);
    } else {
      _treesController.text = '0';
    }
    _loadFieldBoundary();
  }

  bool get _isBoundaryActive {
    final hasCenter = _centerLat != null && _centerLng != null;
    final notOrigin =
        hasCenter && (_centerLat!.abs() > 0.0001 || _centerLng!.abs() > 0.0001);
    return hasCenter &&
        notOrigin &&
        _radiusMeters != null &&
        _radiusMeters! > 0;
  }

  Future<void> _loadExistingMarks(int zoneId) async {
    try {
      final res = await FieldApiService.getMarks(zoneId);
      if (res['success'] == true) {
        final items = List<Map<String, dynamic>>.from(res['data'] ?? []);
        _marks
          ..clear()
          ..addAll(
            items.map(
              (m) => {
                'tree_no': (m['tree_no'] as num).toInt(),
                'latitude': (m['latitude'] as num).toDouble(),
                'longitude': (m['longitude'] as num).toDouble(),
              },
            ),
          );
        _treesController.text = _marks.length.toString();
      }
    } catch (_) {
      // ignore
    } finally {
      _marksLoaded = true;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadFieldBoundary() async {
    final res = await FieldApiService.getFieldDetails(widget.fieldId);
    if (res['success'] == true && res['data'] != null) {
      final data = Map<String, dynamic>.from(res['data']);
      final vertices = List<Map<String, dynamic>>.from(
        data['vertices'] ?? const [],
      );
      final sizeSqm =
          double.tryParse((data['size_square_meter'] ?? '0').toString()) ?? 0.0;

      if (vertices.isNotEmpty) {
        final pts = <Map<String, double>>[];
        for (final v in vertices) {
          final lat = (v['latitude'] as num?)?.toDouble();
          final lng = (v['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) pts.add({'lat': lat, 'lng': lng});
        }
        final c = _centroid(pts);
        _centerLat = c['lat'];
        _centerLng = c['lng'];
      }

      if (_centerLat != null && _centerLng != null && sizeSqm > 0) {
        _radiusMeters = math.sqrt(sizeSqm / math.pi); // r = sqrt(area/pi)
        if (_radiusMeters! < _minRadiusMeters) _radiusMeters = _minRadiusMeters;
      } else {
        _radiusMeters = null;
      }

      if (mounted) setState(() {});
    }
  }

  Map<String, double> _centroid(List<Map<String, double>> pts) {
    if (pts.isEmpty) return {'lat': 0, 'lng': 0};
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p['lat']!;
      lng += p['lng']!;
    }
    return {'lat': lat / pts.length, 'lng': lng / pts.length};
  }

  Future<bool> _ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('กรุณาเปิด Location Services'),
            action: SnackBarAction(
              label: 'เปิดการตั้งค่า',
              onPressed: Geolocator.openLocationSettings,
            ),
          ),
        );
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _toast('จำเป็นต้องอนุญาตเข้าถึงตำแหน่งเพื่อวางต้นไม้', error: true);
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('สิทธิ์ตำแหน่งถูกปฏิเสธแบบถาวร'),
            action: SnackBarAction(
              label: 'เปิด App Settings',
              onPressed: Geolocator.openAppSettings,
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    return true;
  }

  Future<void> _addMarkFromGPS() async {
    if (!await _ensureLocationReady()) return;

    try {
      setState(() => _isLoading = true);
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      if (_enforceBoundary && _isBoundaryActive) {
        final dist = _distanceMeters(
          _centerLat!,
          _centerLng!,
          pos.latitude,
          pos.longitude,
        );
        if (dist > _radiusMeters! * _boundarySlack) {
          _toast(
            'ตำแหน่งอยู่นอกขอบเขตแปลง (ห่างศูนย์กลาง ~${dist.toStringAsFixed(1)} m)',
            error: true,
          );
          setState(() => _isLoading = false);
          return;
        }
      }

      setState(() {
        _marks.add({
          'tree_no': _marks.length + 1,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
        });
        _treesController.text = _marks.length.toString();
        _isLoading = false;
      });
      _toast('เพิ่มตำแหน่งแล้ว ${_marks.length} ต้น');
    } catch (e) {
      setState(() => _isLoading = false);
      _toast('อ่านตำแหน่งไม่สำเร็จ: $e', error: true);
    }
  }

  // ปุ่มทดสอบ: เพิ่มตำแหน่งตัวอย่าง
  void _addSampleMark() {
    final lat = _centerLat ?? _fallbackLat;
    final lng = _centerLng ?? _fallbackLng;
    setState(() {
      _marks.add({
        'tree_no': _marks.length + 1,
        'latitude': lat,
        'longitude': lng,
      });
      _treesController.text = _marks.length.toString();
    });
    _toast('เพิ่มตำแหน่งตัวอย่างแล้ว ${_marks.length} ต้น');
  }

  void _removeMark(int index) {
    setState(() {
      _marks.removeAt(index);
      for (var i = 0; i < _marks.length; i++) {
        _marks[i]['tree_no'] = i + 1;
      }
      _treesController.text = _marks.length.toString();
    });
  }

  void _clearMarks() {
    setState(() {
      _marks.clear();
      _treesController.text = '0';
    });
  }

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earth = 6371000.0; // m
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earth * c;
  }

  double _deg2rad(double d) => d * math.pi / 180.0;

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    Map<String, dynamic> result;

    if (widget.zone != null) {
      final trees = int.tryParse(_treesController.text) ?? 0;
      // 1) อัปเดตชื่อ/จำนวนต้น
      result = await FieldApiService.updateZone(
        zoneId: widget.zone!['zone_id'],
        zoneName: _nameController.text.trim(),
        numTrees: trees < 0 ? 0 : trees,
      );

      // 2) แทนที่ marks ทั้งชุด
      if (result['success'] == true) {
        final putRes = await FieldApiService.replaceMarks(
          zoneId: widget.zone!['zone_id'],
          marks: _marks,
        );
        if (putRes['success'] != true) {
          _toast(
            'อัปเดตพิกัดไม่สำเร็จ: ${putRes['message'] ?? putRes['error'] ?? 'unknown'}',
            error: true,
          );
        }
      }
    } else {
      if (_marks.isNotEmpty) {
        result = await FieldApiService.createZoneWithMarks(
          fieldId: widget.fieldId,
          zoneName: _nameController.text.trim(),
          marks: _marks,
        );
      } else {
        final trees = int.tryParse(_treesController.text) ?? 0;
        result = await FieldApiService.createZone(
          fieldId: widget.fieldId,
          zoneName: _nameController.text.trim(),
          numTrees: trees < 0 ? 0 : trees,
        );
      }
    }

    setState(() => _isLoading = false);

    if (result['success']) {
      widget.onSaved();
      Navigator.pop(context);
    }

    _toast(
      result['success']
          ? 'บันทึกสำเร็จ'
          : (result['message'] ?? 'บันทึกล้มเหลว'),
      error: !result['success'],
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.zone != null;
    return AlertDialog(
      title: Text(editing ? 'แก้ไขโซน' : 'เพิ่มโซนใหม่'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'แปลง: ${widget.fieldName}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อโซน',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v?.isEmpty == true ? 'กรุณาใส่ชื่อโซน' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _treesController,
                decoration: const InputDecoration(
                  labelText: 'จำนวนต้นไม้',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v?.isEmpty == true) return 'กรุณาใส่จำนวนต้น';
                  final num = int.tryParse(v!);
                  if (num == null || num < 0)
                    return 'ใส่จำนวนที่ถูกต้อง (>= 0)';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // ปุ่มเพิ่ม mark
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.my_location),
                      label: const Text('เพิ่มตำแหน่งจาก GPS'),
                      onPressed: _isLoading ? null : _addMarkFromGPS,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.bolt_outlined),
                      label: const Text('เพิ่มตำแหน่งตัวอย่าง'),
                      onPressed: _isLoading ? null : _addSampleMark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // สวิตช์บังคับขอบเขต
              SwitchListTile(
                title: const Text('บังคับให้อยู่ในขอบเขตแปลง'),
                subtitle: Text(
                  _isBoundaryActive && _radiusMeters != null
                      ? 'รัศมี ~${_radiusMeters!.toStringAsFixed(0)} m • เผื่อ ${((_boundarySlack - 1) * 100).toStringAsFixed(0)}%'
                      : 'ยังไม่มีพิกัด/พื้นที่ของแปลง',
                ),
                value: _enforceBoundary,
                onChanged: (v) => setState(() => _enforceBoundary = v),
              ),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ตำแหน่งจาก GPS: ${_marks.length} ต้น'
                  '${_isBoundaryActive && _radiusMeters != null ? " • ขอบเขตรัศมี ~${_radiusMeters!.toStringAsFixed(0)} m" : ""}',
                  style: TextStyle(
                    color: _marks.isNotEmpty
                        ? Colors.green.shade700
                        : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              if (editing && !_marksLoaded)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                ),

              if (_marks.isNotEmpty) const SizedBox(height: 8),
              if (_marks.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: -8,
                    children: _marks.asMap().entries.map((e) {
                      final i = e.key;
                      final m = e.value;
                      return Chip(
                        label: Text(
                          '#${i + 1} (${(m['latitude'] as double).toStringAsFixed(5)}, ${(m['longitude'] as double).toStringAsFixed(5)})',
                        ),
                        deleteIcon: const Icon(Icons.close),
                        onDeleted: _isLoading ? null : () => _removeMark(i),
                      );
                    }).toList(),
                  ),
                ),
              if (_marks.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading ? null : _clearMarks,
                    child: const Text('ล้างตำแหน่งทั้งหมด'),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('บันทึก'),
        ),
      ],
    );
  }
}
