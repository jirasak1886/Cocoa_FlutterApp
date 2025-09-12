// lib/screens/inspection_history_page.dart
import 'package:flutter/material.dart';
import 'package:cocoa_app/api/field_api.dart';
import 'package:cocoa_app/api/inspection_api.dart';

class InspectionHistoryPage extends StatefulWidget {
  const InspectionHistoryPage({super.key});

  @override
  State<InspectionHistoryPage> createState() => _InspectionHistoryPageState();
}

class _InspectionHistoryPageState extends State<InspectionHistoryPage> {
  String _group = 'month'; // 'month' | 'year'
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  int? _fieldId;
  int? _zoneId;

  bool _loading = false;
  List<Map<String, dynamic>> _fields = [];
  List<Map<String, dynamic>> _zones = [];

  // ✅ เปลี่ยนจาก _groups (ที่รอ res['groups']) ให้เราสร้างเองจาก res['buckets']
  List<Map<String, dynamic>> _groups = [];

  // โหลดคำแนะนำปุ๋ยต่อกลุ่ม
  final Map<String, bool> _fertLoading = {};
  final Map<String, List<Map<String, dynamic>>> _fertByKey = {};
  static const int _maxRecsFetch = 20;

  @override
  void initState() {
    super.initState();
    _loadFields();
    _loadHistory();
  }

  static const _thaiMonths = [
    '',
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];
  String _mLabel(int m) => (m >= 1 && m <= 12) ? _thaiMonths[m] : '-';

  int _asInt(dynamic v, [int def = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? def;
    return def;
  }

  List<Map<String, dynamic>> _asListOfMap(dynamic v) {
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return [];
  }

  String _fmtDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _loadFields() async {
    final res = await FieldApiService.getFields();
    if (!mounted) return;
    if (res['success'] == true) {
      final List data = res['data'] ?? [];
      _fields = data
          .map(
            (e) => FieldApiService.safeFieldData(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      if (_fieldId != null && _fields.any((f) => f['field_id'] == _fieldId)) {
        await _loadZones(_fieldId!);
      } else {
        _fieldId = null;
        _zones = [];
        _zoneId = null;
      }
      setState(() {});
    }
  }

  Future<void> _loadZones(int fieldId) async {
    final res = await FieldApiService.getZonesByField(fieldId);
    if (!mounted) return;
    if (res['success'] == true) {
      final List data = res['data'] ?? [];
      _zones = data
          .map(
            (e) => FieldApiService.safeZoneData(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      if (_zoneId != null && !_zones.any((z) => z['zone_id'] == _zoneId)) {
        _zoneId = null;
      }
      setState(() {});
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _groups = [];
    });

    late DateTime from;
    late DateTime to;
    if (_group == 'year') {
      from = DateTime(_year, 1, 1);
      to = DateTime(_year, 12, 31);
    } else {
      final lastDay = DateTime(_year, _month + 1, 0).day;
      from = DateTime(_year, _month, 1);
      to = DateTime(_year, _month, lastDay);
    }

    final res = await InspectionApi.getHistory(
      group: _group,
      from: _fmtDate(from),
      to: _fmtDate(to),
      fieldId: _fieldId,
      zoneId: _zoneId,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (res['success'] == true) {
      // ✅ แปลง response ปัจจุบัน (buckets/top_nutrients) → groups ที่ UI ใช้
      final List buckets = res['buckets'] ?? [];
      final List tops = res['top_nutrients'] ?? [];
      final groupType = (res['group'] ?? _group).toString();

      final out = <Map<String, dynamic>>[];
      for (final b in buckets) {
        final m = Map<String, dynamic>.from(b as Map);
        final bucket = (m['bucket'] ?? '').toString(); // "YYYY" หรือ "YYYY-MM"
        int year = _year;
        int? month;

        final parts = bucket.split('-');
        if (parts.isNotEmpty) {
          year = int.tryParse(parts[0]) ?? _year;
          if (parts.length > 1) {
            month = int.tryParse(parts[1]) ?? _month;
          }
        }

        out.add({
          'key': bucket, // ใช้สำหรับ map โหลดคำแนะนำ
          'label': bucket,
          'year': year,
          if (groupType == 'month' && month != null) 'month': month,
          'inspections': _asInt(m['inspections'], 0),
          'findings': _asInt(m['findings'], 0),
          // แนบ top ของช่วงเดิม (ถ้ามีหลาย bucket/ช่วง อาจอยากเรียก API แยกตามช่วงภายหลัง)
          'top_nutrients': tops,
        });
      }

      setState(() {
        _groups = out;
      });
    } else {
      _toast('โหลดประวัติไม่สำเร็จ: ${res['error'] ?? 'unknown'}');
    }
  }

  Future<void> _loadFertsForGroup(Map<String, dynamic> g) async {
    final key = (g['key'] ?? '').toString();
    if (key.isEmpty) return;

    int? year;
    int? month;
    if (_group == 'year') {
      year = _asInt(g['year'], _year);
    } else {
      year = _asInt(g['year'], _year);
      month = _asInt(g['month'], _month);
    }

    setState(() => _fertLoading[key] = true);

    // 1) ดึงรายการรอบในช่วง
    final lr = await InspectionApi.listInspections(
      page: 1,
      pageSize: 100,
      year: year,
      month: month,
      fieldId: _fieldId,
      zoneId: _zoneId,
    );

    if (!mounted) return;

    final List items =
        (lr['items'] ?? lr['data'] ?? lr['inspections'] ?? []) as List;

    // 2) ไล่ดึง recommendation ต่อ inspection (จำกัด _maxRecsFetch)
    final recs = <Map<String, dynamic>>[];
    for (final it in items.take(_maxRecsFetch)) {
      final m = Map<String, dynamic>.from(it as Map);
      final id = _asInt(
        m['inspection_id'] ?? m['id'] ?? m['inspectionId'] ?? 0,
      );
      if (id <= 0) continue;

      final rr = await InspectionApi.getRecommendations(inspectionId: id);
      if (rr['success'] == true) {
        final List d = rr['data'] ?? rr['recommendations'] ?? [];
        // ✅ ไม่แปลงเป็น schema เก่า แต่ใช้ฟิลด์จริงจาก backend
        recs.addAll(d.map((e) => Map<String, dynamic>.from(e as Map)));
      }
    }

    _fertByKey[key] = recs;
    _fertLoading[key] = false;
    if (mounted) setState(() {});
  }

  // ===== UI parts =====
  Widget _buildHeader() {
    final now = DateTime.now();
    final years = List<int>.generate(6, (i) => now.year - i);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Line 1: group selector
            Row(
              children: [
                const Text('มุมมอง:'),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('รายเดือน'),
                  selected: _group == 'month',
                  onSelected: (v) {
                    if (!v) return;
                    setState(() => _group = 'month');
                    _loadHistory();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('รายปี'),
                  selected: _group == 'year',
                  onSelected: (v) {
                    if (!v) return;
                    setState(() => _group = 'year');
                    _loadHistory();
                  },
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loading ? null : _loadHistory,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'โหลดข้อมูล',
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Line 2: year + (month)
            Row(
              children: [
                // Year
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _year,
                    items: years
                        .map(
                          (y) => DropdownMenuItem(value: y, child: Text('$y')),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _year = v);
                      _loadHistory();
                    },
                    decoration: const InputDecoration(
                      labelText: 'ปี',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Month
                if (_group == 'month')
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _month,
                      items: List.generate(12, (i) => i + 1)
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text('${_mLabel(m)} ($m)'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _month = v);
                        _loadHistory();
                      },
                      decoration: const InputDecoration(
                        labelText: 'เดือน',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Line 3: Field + Zone
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _fieldId,
                    items: _fields
                        .map(
                          (f) => DropdownMenuItem<int>(
                            value: f['field_id'] as int,
                            child: Text('${f['field_name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) async {
                      setState(() {
                        _fieldId = v;
                        _zoneId = null;
                        _zones = [];
                      });
                      if (v != null) await _loadZones(v);
                      _loadHistory();
                    },
                    decoration: const InputDecoration(
                      labelText: 'แปลง (ตัวเลือก)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _zoneId,
                    items: _zones
                        .map(
                          (z) => DropdownMenuItem<int>(
                            value: z['zone_id'] as int,
                            child: Text('${z['zone_name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (_fieldId == null)
                        ? null
                        : (v) {
                            setState(() => _zoneId = v);
                            _loadHistory();
                          },
                    decoration: const InputDecoration(
                      labelText: 'โซน (ตัวเลือก)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> g) {
    final key = (g['key'] ?? '').toString();
    final y = _asInt(g['year'], _year);
    final m = _asInt(g['month'], _month);
    final label =
        (g['label'] ??
                (_group == 'year'
                    ? '$y'
                    : '$y-${m.toString().padLeft(2, '0')}'))
            .toString();

    final inspections = _asInt(g['inspections'], 0);
    final findings = _asInt(g['findings'], 0);
    final tops = _asListOfMap(g['top_nutrients']);

    final recsLoading = _fertLoading[key] == true;
    final recs = _fertByKey[key] ?? [];

    return Card(
      child: ExpansionTile(
        title: Text(label),
        subtitle: Text('รอบตรวจ: $inspections • findings: $findings'),
        trailing: IconButton(
          tooltip: 'โหลดคำแนะนำปุ๋ยของช่วงนี้',
          icon: const Icon(Icons.spa_outlined),
          onPressed: recsLoading ? null : () => _loadFertsForGroup(g),
        ),
        children: [
          if (tops.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: tops.map((t) {
                    final c = (t['code'] ?? t['nutrient_code'] ?? '-')
                        .toString();
                    // ✅ รองรับทั้ง 'count' และ 'cnt'
                    final cnt = _asInt(t['count'] ?? t['cnt'], 0);
                    return Chip(
                      label: Text('$c • $cnt'),
                      backgroundColor: Colors.orange[50],
                      shape: StadiumBorder(
                        side: BorderSide(color: Colors.orange[200]!),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          const Divider(height: 1),
          if (recsLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (!recsLoading && recs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '— ยังไม่มีคำแนะนำปุ๋ยสำหรับช่วงนี้ —',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          if (recs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: recs.map((r) {
                  final nutrient = (r['nutrient_code'] ?? r['nutrient'] ?? '-')
                      .toString();
                  // ✅ ใช้ฟิลด์จริงจาก backend
                  final fertName =
                      (r['fert_name'] ??
                              r['fertilizer'] ??
                              r['product_name'] ??
                              '-')
                          .toString();
                  final form = (r['formulation'] ?? '').toString();
                  final rate =
                      (r['rate_per_area'] ?? r['dosage'] ?? r['dose'] ?? '-')
                          .toString();
                  final method = (r['application_method'] ?? '').toString();
                  final status = (r['status'] ?? 'suggested').toString();

                  final productLabel = form.isNotEmpty
                      ? '$fertName ($form)'
                      : fertName;
                  final sub = [
                    if (rate.isNotEmpty) 'อัตรา: $rate',
                    if (method.isNotEmpty) method,
                    status,
                  ].join(' • ');

                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.spa_outlined),
                    title: Text('$nutrient • $productLabel'),
                    subtitle: Text(sub),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติการตรวจ'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadHistory,
            icon: const Icon(Icons.refresh),
            tooltip: 'โหลดข้อมูล',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (!_loading && _groups.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                '— ไม่พบข้อมูล —',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          if (_groups.isNotEmpty) ..._groups.map(_buildGroupCard),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
