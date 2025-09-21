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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
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

  void _showFieldCoordinates(Map<String, dynamic> field) {
    showDialog(
      context: context,
      builder: (context) =>
          _FieldCoordinatesDialog(field: field, onSaved: _loadFields),
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

  void _showZoneCoordinates(Map<String, dynamic> zone, String fieldName) {
    showDialog(
      context: context,
      builder: (context) => _ZoneCoordinatesDialog(
        zone: zone,
        fieldName: fieldName,
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
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการแปลง'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFields,
            tooltip: 'รีเฟรช',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'ค้นหาแปลง...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              onChanged: (value) => setState(() => searchQuery = value),
            ),
          ),

          // Fields List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredFields.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.agriculture_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          searchQuery.isEmpty
                              ? 'ยังไม่มีแปลง'
                              : 'ไม่พบแปลงที่ค้นหา',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadFields,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: filteredFields.length,
                      itemBuilder: (context, index) {
                        final field = FieldApiService.safeFieldData(
                          filteredFields[index],
                        );
                        final zones = List.from(
                          filteredFields[index]['zones'] ?? [],
                        );
                        final vertexCount = (field['vertex_count'] ?? 0) as int;

                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ExpansionTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.agriculture,
                                  color: Colors.green.shade700,
                                ),
                              ),
                              title: Text(
                                field['field_name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 8,
                                  children: [
                                    _InfoChip(
                                      icon: Icons.square_foot,
                                      label:
                                          '${field['size_square_meter']} ตร.ม.',
                                    ),
                                    _InfoChip(
                                      icon: Icons.location_on,
                                      label: '${zones.length} โซน',
                                    ),
                                    if (vertexCount > 0)
                                      _InfoChip(
                                        icon: Icons.place,
                                        label: '$vertexCount จุด',
                                      ),
                                  ],
                                ),
                              ),
                              trailing: _FieldActionButton(
                                field: field,
                                rawField: filteredFields[index],
                                onEdit: () =>
                                    _showFieldForm(filteredFields[index]),
                                onCoordinates: () => _showFieldCoordinates(
                                  filteredFields[index],
                                ),
                                onAddZone: () => _showZoneForm(
                                  field['field_id'],
                                  field['field_name'],
                                ),
                                onDelete: () => _deleteField(field),
                              ),
                              children: zones.map((zone) {
                                final safeZone = FieldApiService.safeZoneData(
                                  zone,
                                );
                                return _ZoneTile(
                                  zone: safeZone,
                                  fieldName: field['field_name'],
                                  fieldId: field['field_id'],
                                  onEdit: () => _showZoneForm(
                                    field['field_id'],
                                    field['field_name'],
                                    zone,
                                  ),
                                  onCoordinates: () => _showZoneCoordinates(
                                    safeZone,
                                    field['field_name'],
                                  ),
                                  onDelete: () => _deleteZone(safeZone),
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFieldForm(),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มแปลง'),
      ),
    );
  }
}

// ===== Helper Widgets =====
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

class _FieldActionButton extends StatelessWidget {
  final Map<String, dynamic> field;
  final Map<String, dynamic> rawField;
  final VoidCallback onEdit;
  final VoidCallback onCoordinates;
  final VoidCallback onAddZone;
  final VoidCallback onDelete;

  const _FieldActionButton({
    required this.field,
    required this.rawField,
    required this.onEdit,
    required this.onCoordinates,
    required this.onAddZone,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, color: Colors.blue.shade600),
              const SizedBox(width: 12),
              const Text('แก้ไขข้อมูล'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'coordinates',
          child: Row(
            children: [
              Icon(Icons.map, color: Colors.purple.shade600),
              const SizedBox(width: 12),
              const Text('จัดการพิกัด'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'map',
          child: Row(
            children: [
              Icon(Icons.map, color: Colors.purple.shade600, size: 18),
              const SizedBox(width: 8),
              const Text('ดูแผนที่แปลง'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'add_zone',
          child: Row(
            children: [
              Icon(Icons.add_location, color: Colors.green.shade600),
              const SizedBox(width: 12),
              const Text('เพิ่มโซน'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red.shade600),
              const SizedBox(width: 12),
              const Text('ลบแปลง'),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
            break;
          case 'coordinates':
            onCoordinates();
            break;
          case 'map':
            Navigator.of(context, rootNavigator: true).pushNamed(
              '/map-editor',
              arguments: {
                'field_id': field['field_id'],
                'field_name': field['field_name'],
              },
            );
            break;
          case 'add_zone':
            onAddZone();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
    );
  }
}

// ===== Zone Tile =====
class _ZoneTile extends StatefulWidget {
  final Map<String, dynamic> zone;
  final String fieldName;
  final int fieldId;
  final VoidCallback onEdit;
  final VoidCallback onCoordinates;
  final VoidCallback onDelete;

  const _ZoneTile({
    required this.zone,
    required this.fieldName,
    required this.fieldId,
    required this.onEdit,
    required this.onCoordinates,
    required this.onDelete,
  });

  @override
  State<_ZoneTile> createState() => _ZoneTileState();
}

class _ZoneTileState extends State<_ZoneTile> {
  bool _loading = true;
  String? _latLngText;

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
    final zone = widget.zone;

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.orange.shade200),
        ),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.location_on,
              color: Colors.orange.shade700,
              size: 20,
            ),
          ),
          title: Text(
            zone['zone_name'],
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 8,
              children: [
                _InfoChip(icon: Icons.park, label: '${zone['num_trees']} ต้น'),
                if (_loading)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_latLngText != null)
                  _InfoChip(icon: Icons.gps_fixed, label: _latLngText!),
              ],
            ),
          ),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, color: Colors.blue.shade600, size: 18),
                    const SizedBox(width: 8),
                    const Text('แก้ไขข้อมูล'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'coordinates',
                child: Row(
                  children: [
                    Icon(
                      Icons.my_location,
                      color: Colors.green.shade600,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text('จัดการพิกัด'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'map',
                child: Row(
                  children: [
                    Icon(Icons.map, color: Colors.purple.shade600, size: 18),
                    const SizedBox(width: 8),
                    const Text('ดูแผนที่โซน'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red.shade600, size: 18),
                    const SizedBox(width: 8),
                    const Text('ลบโซน'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  widget.onEdit();
                  break;
                case 'coordinates':
                  widget.onCoordinates();
                  break;
                case 'map':
                  Navigator.of(context, rootNavigator: true).pushNamed(
                    '/map-editor',
                    arguments: {
                      'field_id': widget.fieldId,
                      'field_name': widget.fieldName,
                    },
                  );
                  break;
                case 'delete':
                  widget.onDelete();
                  break;
              }
            },
          ),
        ),
      ),
    );
  }
}

// ===== Simple Field Form Dialog =====
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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.field != null) {
      final f = FieldApiService.safeFieldData(widget.field!);
      _nameController.text = f['field_name'];
      _sizeController.text = f['size_square_meter'].toString();
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    Map<String, dynamic> result;
    try {
      if (widget.field != null) {
        // ✅ ไม่ส่ง vertices เลย (กันการลบพิกัด)
        result = await FieldApiService.updateField(
          fieldId: widget.field!['field_id'],
          fieldName: _nameController.text.trim(),
          sizeSquareMeter: _sizeController.text.trim(),
        );
      } else {
        // ✅ ไม่ส่ง vertices ถ้ายังไม่มี
        result = await FieldApiService.createField(
          fieldName: _nameController.text.trim(),
          sizeSquareMeter: _sizeController.text.trim(),
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
    final isTablet = MediaQuery.of(context).size.width > 600;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isTablet ? 400 : double.infinity,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.field != null ? Icons.edit : Icons.add,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.field != null ? 'แก้ไขแปลง' : 'เพิ่มแปลงใหม่',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'ชื่อแปลง',
                  prefixIcon: const Icon(Icons.agriculture),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (v) =>
                    v?.trim().isEmpty == true ? 'กรุณาใส่ชื่อแปลง' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _sizeController,
                decoration: InputDecoration(
                  labelText: 'ขนาดพื้นที่ (ตร.ม.)',
                  prefixIcon: const Icon(Icons.square_foot),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v?.trim().isEmpty == true) return 'กรุณาใส่ขนาดพื้นที่';
                  final d = double.tryParse(v!.trim());
                  if (d == null) return 'กรุณาใส่ตัวเลข';
                  if (d <= 0) return 'ขนาดต้องมากกว่า 0';
                  return null;
                },
              ),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue.shade600),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'พิกัดของแปลงสามารถเพิ่มได้ภายหลังผ่านเมนู "จัดการพิกัด"',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('ยกเลิก'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _isLoading ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text('บันทึก'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== Field Coordinates Dialog (UPDATED: เพิ่มพิมพ์พิกัดเอง + แก้/ลบ) =====
class _FieldCoordinatesDialog extends StatefulWidget {
  final Map<String, dynamic> field;
  final VoidCallback onSaved;

  const _FieldCoordinatesDialog({required this.field, required this.onSaved});

  @override
  State<_FieldCoordinatesDialog> createState() =>
      _FieldCoordinatesDialogState();
}

class _FieldCoordinatesDialogState extends State<_FieldCoordinatesDialog> {
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  bool _isLoading = false;
  bool _gettingLoc = false;

  final List<Map<String, double>> _points = [];

  final _manLatCtl = TextEditingController();
  final _manLngCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExistingVertices();
  }

  Future<void> _loadExistingVertices() async {
    final field = FieldApiService.safeFieldData(widget.field);
    final res = await FieldApiService.getFieldDetails(field['field_id']);
    if (res['success'] == true && res['data'] != null) {
      final data = Map<String, dynamic>.from(res['data']);
      final vertices = List<Map<String, dynamic>>.from(data['vertices'] ?? []);
      _points.clear();
      for (final v in vertices) {
        final lat = (v['latitude'] as num?)?.toDouble();
        final lng = (v['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          _points.add({'lat': lat, 'lng': lng});
        }
      }
      _updateCentroid();
      if (mounted) setState(() {});
    }
  }

  void _updateCentroid() {
    if (_points.isEmpty) {
      _latController.text = '';
      _lngController.text = '';
      return;
    }
    double lat = 0, lng = 0;
    for (final p in _points) {
      lat += p['lat']!;
      lng += p['lng']!;
    }
    lat /= _points.length;
    lng /= _points.length;
    _latController.text = lat.toStringAsFixed(7);
    _lngController.text = lng.toStringAsFixed(7);
  }

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
        _points.add({'lat': p.latitude, 'lng': p.longitude});
        _updateCentroid();
      });
      _toast('เพิ่มจุดที่ ${_points.length} สำเร็จ');
    } catch (e) {
      _toast('อ่านตำแหน่งไม่สำเร็จ: $e', error: true);
    } finally {
      if (mounted) setState(() => _gettingLoc = false);
    }
  }

  void _addPointManual() {
    final lat = double.tryParse(_manLatCtl.text.trim());
    final lng = double.tryParse(_manLngCtl.text.trim());
    if (lat == null || lng == null) {
      _toast('กรุณากรอกละติจูด/ลองจิจูดให้ถูกต้อง', error: true);
      return;
    }
    setState(() {
      _points.add({'lat': lat, 'lng': lng});
      _manLatCtl.clear();
      _manLngCtl.clear();
      _updateCentroid();
    });
    _toast('เพิ่มพิกัดแล้ว');
  }

  void _editPoint(int index) {
    final item = _points[index];
    final latCtl = TextEditingController(text: item['lat']!.toStringAsFixed(7));
    final lngCtl = TextEditingController(text: item['lng']!.toStringAsFixed(7));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('แก้ไขพิกัดของแปลง'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: latCtl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'ละติจูด'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: lngCtl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'ลองจิจูด'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              final newLat = double.tryParse(latCtl.text.trim());
              final newLng = double.tryParse(lngCtl.text.trim());
              if (newLat == null || newLng == null) {
                _toast('ข้อมูลไม่ถูกต้อง', error: true);
                return;
              }
              setState(() {
                _points[index] = {'lat': newLat, 'lng': newLng};
                _updateCentroid();
              });
              Navigator.pop(context);
              _toast('บันทึกการแก้ไขแล้ว');
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  void _removePoint(int index) {
    setState(() {
      _points.removeAt(index);
      _updateCentroid();
    });
  }

  void _clearPoints() {
    setState(() {
      _points.clear();
      _updateCentroid();
    });
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);

    final vertices = _points
        .map((p) => {'latitude': p['lat'], 'longitude': p['lng']})
        .toList();

    Map<String, dynamic> result;
    try {
      final field = FieldApiService.safeFieldData(widget.field);
      result = await FieldApiService.updateField(
        fieldId: field['field_id'],
        fieldName: field['field_name'],
        sizeSquareMeter: field['size_square_meter'].toString(),
        vertices: vertices, // ตั้งใจแทนที่พิกัดทั้งชุด
      );
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
          ? 'บันทึกพิกัดสำเร็จ'
          : (result['message'] ?? 'บันทึกล้มเหลว'),
      error: !result['success'],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final field = FieldApiService.safeFieldData(widget.field);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isTablet ? 520 : double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.map, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'จัดการพิกัดแปลง: ${field['field_name']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ฟอร์มเพิ่มพิกัดเอง
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('เพิ่มพิกัดขอบเขตแปลง (พิมพ์เอง)'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manLatCtl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'ละติจูด',
                            prefixIcon: Icon(Icons.explore),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _manLngCtl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'ลองจิจูด',
                            prefixIcon: Icon(Icons.explore_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _isLoading ? null : _addPointManual,
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('เพิ่มพิกัด'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ปุ่มเพิ่มจาก GPS + สถานะ
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _gettingLoc
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(
                      _gettingLoc ? 'กำลังอ่าน...' : 'เพิ่มจุดจาก GPS',
                    ),
                    onPressed: _isLoading || _gettingLoc
                        ? null
                        : _addPointFromGPS,
                  ),
                ),
                const SizedBox(width: 12),
                if (_points.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.clear_all),
                    label: const Text('ล้างทั้งหมด'),
                    onPressed: _isLoading ? null : _clearPoints,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // ศูนย์กลางโดยประมาณ (อ่านอย่างเดียว)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'ละติจูด (ศูนย์กลางโดยประมาณ)',
                      prefixIcon: const Icon(Icons.gps_fixed),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lngController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'ลองจิจูด (ศูนย์กลางโดยประมาณ)',
                      prefixIcon: const Icon(Icons.gps_fixed),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (_points.isNotEmpty) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _points.length,
                    itemBuilder: (context, index) {
                      final p = _points[index];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.green.shade100,
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                        title: Text(
                          '${p['lat']!.toStringAsFixed(5)}, ${p['lng']!.toStringAsFixed(5)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              color: Colors.blue.shade600,
                              tooltip: 'แก้ไขพิกัดนี้',
                              onPressed: _isLoading
                                  ? null
                                  : () => _editPoint(index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              color: Colors.red.shade600,
                              tooltip: 'ลบตำแหน่งนี้',
                              onPressed: _isLoading
                                  ? null
                                  : () => _removePoint(index),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: const Text('ยกเลิก'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isLoading ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text('บันทึกพิกัด'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Simple Zone Form Dialog =====
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

  @override
  void initState() {
    super.initState();
    if (widget.zone != null) {
      final zone = FieldApiService.safeZoneData(widget.zone!);
      _nameController.text = zone['zone_name'];
      _treesController.text = zone['num_trees'].toString();
    } else {
      _treesController.text = '0';
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    Map<String, dynamic> result;

    final trees = int.tryParse(_treesController.text) ?? 0;

    try {
      if (widget.zone != null) {
        result = await FieldApiService.updateZone(
          zoneId: widget.zone!['zone_id'],
          zoneName: _nameController.text.trim(),
          numTrees: trees < 0 ? 0 : trees,
        );
      } else {
        result = await FieldApiService.createZone(
          fieldId: widget.fieldId,
          zoneName: _nameController.text.trim(),
          numTrees: trees < 0 ? 0 : trees,
        );
      }
    } catch (e) {
      result = {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
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
    final isTablet = MediaQuery.of(context).size.width > 600;
    final editing = widget.zone != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isTablet ? 400 : double.infinity,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    editing ? Icons.edit : Icons.add_location,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      editing ? 'แก้ไขโซน' : 'เพิ่มโซนใหม่',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.agriculture,
                      color: Colors.green.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'แปลง: ${widget.fieldName}',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'ชื่อโซน',
                  prefixIcon: const Icon(Icons.location_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (v) =>
                    v?.trim().isEmpty == true ? 'กรุณาใส่ชื่อโซน' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _treesController,
                decoration: InputDecoration(
                  labelText: 'จำนวนต้นไม้',
                  prefixIcon: const Icon(Icons.park),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v?.trim().isEmpty == true) return 'กรุณาใส่จำนวนต้น';
                  final num = int.tryParse(v!.trim());
                  if (num == null || num < 0) {
                    return 'ใส่จำนวนที่ถูกต้อง (>= 0)';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue.shade600),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'พิกัดของโซนสามารถเพิ่มได้ภายหลังผ่านเมนู "จัดการพิกัด"',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('ยกเลิก'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _isLoading ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text('บันทึก'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== Zone Coordinates Dialog (UPDATED: พิมพ์เอง + tree_no = หมายเลขต้น) =====
class _ZoneCoordinatesDialog extends StatefulWidget {
  final Map<String, dynamic> zone;
  final String fieldName;
  final VoidCallback onSaved;

  const _ZoneCoordinatesDialog({
    required this.zone,
    required this.fieldName,
    required this.onSaved,
  });

  @override
  State<_ZoneCoordinatesDialog> createState() => _ZoneCoordinatesDialogState();
}

class _ZoneCoordinatesDialogState extends State<_ZoneCoordinatesDialog> {
  bool _isLoading = false;
  final List<Map<String, dynamic>> _marks = [];
  bool _marksLoaded = false;

  final _treeNoCtl = TextEditingController();
  final _latCtl = TextEditingController();
  final _lngCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExistingMarks();
  }

  Future<void> _loadExistingMarks() async {
    try {
      final zone = FieldApiService.safeZoneData(widget.zone);
      final res = await FieldApiService.getMarks(zone['zone_id']);
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
      }
    } catch (_) {
      // ignore
    } finally {
      _marksLoaded = true;
      if (mounted) setState(() {});
    }
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
        _toast('จำเป็นต้องอนุญาตเข้าถึงตำแหน่ง', error: true);
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

  int _nextTreeNo() {
    if (_marks.isEmpty) return 1;
    final maxNo = _marks
        .map((e) => (e['tree_no'] as int))
        .fold<int>(0, (prev, el) => el > prev ? el : prev);
    return maxNo + 1;
  }

  bool _existsTreeNo(int treeNo) {
    return _marks.any((m) => (m['tree_no'] as int) == treeNo);
  }

  Future<void> _addMarkFromGPS() async {
    if (!await _ensureLocationReady()) return;

    try {
      setState(() => _isLoading = true);
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      int treeNo = int.tryParse(_treeNoCtl.text.trim()) ?? _nextTreeNo();
      if (_existsTreeNo(treeNo)) {
        while (_existsTreeNo(treeNo)) treeNo++;
      }

      setState(() {
        _marks.add({
          'tree_no': treeNo,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
        });
        _isLoading = false;
      });
      _toast('เพิ่มตำแหน่งแล้ว (tree_no $treeNo)');
    } catch (e) {
      setState(() => _isLoading = false);
      _toast('อ่านตำแหน่งไม่สำเร็จ: $e', error: true);
    }
  }

  void _addMarkManual() {
    final lat = double.tryParse(_latCtl.text.trim());
    final lng = double.tryParse(_lngCtl.text.trim());
    if (lat == null || lng == null) {
      _toast('กรุณากรอกละติจูด/ลองจิจูดให้ถูกต้อง', error: true);
      return;
    }
    int treeNo = int.tryParse(_treeNoCtl.text.trim()) ?? _nextTreeNo();
    if (_existsTreeNo(treeNo)) {
      _toast('tree_no นี้ถูกใช้แล้ว กรุณาเลือกหมายเลขอื่น', error: true);
      return;
    }
    setState(() {
      _marks.add({'tree_no': treeNo, 'latitude': lat, 'longitude': lng});
      _treeNoCtl.clear();
      _latCtl.clear();
      _lngCtl.clear();
    });
    _toast('เพิ่มตำแหน่งแล้ว (tree_no $treeNo)');
  }

  void _editMark(int index) {
    final m = _marks[index];
    final treeNoCtl = TextEditingController(
      text: (m['tree_no'] as int).toString(),
    );
    final latCtl = TextEditingController(
      text: (m['latitude'] as double).toStringAsFixed(7),
    );
    final lngCtl = TextEditingController(
      text: (m['longitude'] as double).toStringAsFixed(7),
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('แก้ไขตำแหน่งต้นโกโก้'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: treeNoCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'tree_no (หมายเลขต้น)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: latCtl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'ละติจูด'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: lngCtl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'ลองจิจูด'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              final newTreeNo = int.tryParse(treeNoCtl.text.trim());
              final newLat = double.tryParse(latCtl.text.trim());
              final newLng = double.tryParse(lngCtl.text.trim());
              if (newTreeNo == null || newLat == null || newLng == null) {
                _toast('ข้อมูลไม่ถูกต้อง', error: true);
                return;
              }
              final dup = _marks.any(
                (e) => e != m && (e['tree_no'] as int) == newTreeNo,
              );
              if (dup) {
                _toast('tree_no นี้ถูกใช้แล้ว', error: true);
                return;
              }
              setState(() {
                _marks[index] = {
                  'tree_no': newTreeNo,
                  'latitude': newLat,
                  'longitude': newLng,
                };
              });
              Navigator.pop(context);
              _toast('บันทึกการแก้ไขแล้ว');
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  void _removeMark(int index) {
    setState(() {
      _marks.removeAt(index);
    });
  }

  void _clearMarks() {
    setState(() => _marks.clear());
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);

    final zone = FieldApiService.safeZoneData(widget.zone);
    final result = await FieldApiService.replaceMarks(
      zoneId: zone['zone_id'],
      marks: _marks,
    );

    setState(() => _isLoading = false);

    if (result['success']) {
      widget.onSaved();
      Navigator.pop(context);
    }

    _toast(
      result['success']
          ? 'บันทึกพิกัดสำเร็จ'
          : (result['message'] ?? 'บันทึกล้มเหลว'),
      error: !result['success'],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final zone = FieldApiService.safeZoneData(widget.zone);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: isTablet ? 520 : double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.my_location, color: Colors.orange.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'จัดการพิกัดโซน: ${zone['zone_name']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.agriculture,
                    color: Colors.green.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'แปลง: ${widget.fieldName}',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            // ปุ่มเพิ่มจาก GPS + สถานะ
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(
                      _isLoading
                          ? 'กำลังอ่านตำแหน่ง...'
                          : 'เพิ่มตำแหน่งจาก GPS',
                    ),
                    onPressed: _isLoading ? null : _addMarkFromGPS,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (_marks.isNotEmpty)
                  TextButton.icon(
                    onPressed: _isLoading ? null : _clearMarks,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('ล้างทั้งหมด'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _marks.isEmpty
                    ? Colors.grey.shade100
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _marks.isEmpty
                      ? Colors.grey.shade300
                      : Colors.green.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _marks.isEmpty
                        ? Icons.location_disabled
                        : Icons.location_on,
                    color: _marks.isEmpty
                        ? Colors.grey.shade600
                        : Colors.green.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ตำแหน่งที่บันทึกไว้: ${_marks.length} จุด (หมายเหตุ: tree_no = หมายเลขต้น ไม่ใช่จำนวนจุด)',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: _marks.isEmpty
                            ? Colors.grey.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_marks.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (!_marksLoaded)
                const LinearProgressIndicator(minHeight: 2)
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _marks.length,
                      itemBuilder: (context, index) {
                        final mark = _marks[index];
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Center(
                              child: Text(
                                '${mark['tree_no']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            '${(mark['latitude'] as double).toStringAsFixed(5)}, ${(mark['longitude'] as double).toStringAsFixed(5)}',
                            style: const TextStyle(fontSize: 13),
                          ),

                          trailing: Wrap(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: _isLoading
                                    ? null
                                    : () => _editMark(index),
                                color: Colors.blue.shade600,
                                tooltip: 'แก้ไขตำแหน่งนี้',
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _isLoading
                                    ? null
                                    : () => _removeMark(index),
                                color: Colors.red.shade600,
                                tooltip: 'ลบตำแหน่งนี้',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: const Text('ยกเลิก'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isLoading ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text('บันทึกพิกัด'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
