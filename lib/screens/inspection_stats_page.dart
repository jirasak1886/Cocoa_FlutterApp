// lib/screens/inspection_stats_page.dart
import 'package:flutter/material.dart';
import 'package:cocoa_app/api/inspection_api.dart';
import 'package:cocoa_app/api/field_api.dart';

class InspectionStatsPage extends StatefulWidget {
  final String? initialGroup; // 'month' | 'year'
  final int? initialYear;
  final int? initialMonth;
  final int? initialFieldId;
  final int? initialZoneId;

  const InspectionStatsPage({
    super.key,
    this.initialGroup,
    this.initialYear,
    this.initialMonth,
    this.initialFieldId,
    this.initialZoneId,
  });

  @override
  State<InspectionStatsPage> createState() => _InspectionStatsPageState();
}

class _InspectionStatsPageState extends State<InspectionStatsPage> {
  String _group = 'month';
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  int? _fieldId;
  int? _zoneId;

  bool _loading = false;

  // filters
  List<Map<String, dynamic>> _fields = [];
  List<Map<String, dynamic>> _zones = [];

  // data
  List<Map<String, dynamic>> _buckets =
      []; // [{bucket:'2025-09', inspections:int, findings:int}]
  List<Map<String, dynamic>> _topNutrients =
      []; // [{nutrient_code:'K', cnt:int}]

  // KPI
  int _totalInspections = 0;
  int _totalFindings = 0;

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

  @override
  void initState() {
    super.initState();
    // init from arguments
    _group = (widget.initialGroup == 'year') ? 'year' : 'month';
    _year = widget.initialYear ?? _year;
    _month = widget.initialMonth ?? _month;
    _fieldId = widget.initialFieldId;
    _zoneId = widget.initialZoneId;

    _loadFields(); // โหลดรายการแปลงก่อน
    _loadStats(); // โหลดสถิติ
  }

  String _mLabel(int m) => (m >= 1 && m <= 12) ? _thaiMonths[m] : '-';

  int _asInt(dynamic v, [int def = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? def;
    return def;
  }

  String _fmtDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  Future<void> _loadFields() async {
    final res = await FieldApiService.getFields();
    if (!mounted) return;
    if (res['success'] == true) {
      final List data = res['data'] ?? [];
      _fields = data
          .whereType<Map>()
          .map(
            (e) => FieldApiService.safeFieldData(Map<String, dynamic>.from(e)),
          )
          .toList();
      if (_fieldId != null) {
        await _loadZones(_fieldId!);
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
          .whereType<Map>()
          .map(
            (e) => FieldApiService.safeZoneData(Map<String, dynamic>.from(e)),
          )
          .toList();
      if (_zoneId != null && !_zones.any((z) => z['zone_id'] == _zoneId)) {
        _zoneId = null;
      }
      setState(() {});
    }
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _buckets = [];
      _topNutrients = [];
      _totalFindings = 0;
      _totalInspections = 0;
    });

    // ช่วงเวลา
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
      // รองรับทั้งโครงสร้างใหม่ (buckets/top_nutrients) หรือ groups (จาก utility normalized)
      final List rawBuckets = (res['buckets'] ?? res['groups'] ?? []) as List;
      final List rawTops = (res['top_nutrients'] ?? []) as List;

      _buckets = rawBuckets
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      _topNutrients = rawTops
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      _totalInspections = _buckets.fold<int>(
        0,
        (sum, b) => sum + _asInt(b['inspections']),
      );
      _totalFindings = _buckets.fold<int>(
        0,
        (sum, b) => sum + _asInt(b['findings']),
      );

      setState(() {});
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('โหลดสถิติไม่สำเร็จ: ${res['error'] ?? 'unknown'}'),
          ),
        );
      }
    }
  }

  // ===== UI =====

  Widget _buildFiltersCard() {
    final now = DateTime.now();
    final years = List<int>.generate(6, (i) => now.year - i);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
                    _loadStats();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('รายปี'),
                  selected: _group == 'year',
                  onSelected: (v) {
                    if (!v) return;
                    setState(() => _group = 'year');
                    _loadStats();
                  },
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loading ? null : _loadStats,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'โหลดข้อมูล',
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                      _loadStats();
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
                        _loadStats();
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
                      _loadStats();
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
                            _loadStats();
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

  Widget _buildKpiCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _Kpi(
              title: 'จำนวนรอบตรวจ',
              value: _totalInspections.toString(),
              icon: Icons.fact_check_outlined,
            ),
            const SizedBox(width: 12),
            _Kpi(
              title: 'จำนวน findings',
              value: _totalFindings.toString(),
              icon: Icons.bug_report_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBucketsCard() {
    if (_buckets.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '— ยังไม่มีข้อมูลในช่วงที่เลือก —',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }

    final maxIns = _buckets.fold<int>(
      0,
      (m, b) => b['inspections'] is int
          ? (b['inspections'] as int > m ? b['inspections'] as int : m)
          : m,
    );
    final maxFind = _buckets.fold<int>(
      0,
      (m, b) => b['findings'] is int
          ? (b['findings'] as int > m ? b['findings'] as int : m)
          : m,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'การตรวจและ Findings ตามช่วงเวลา',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._buckets.map((b) {
              final label = (b['bucket'] ?? b['label'] ?? '')
                  .toString(); // "YYYY" หรือ "YYYY-MM"
              final ins = _asInt(b['inspections'], 0);
              final fin = _asInt(b['findings'], 0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(label)),
                        Text(
                          'ตรวจ: $ins • f: $fin',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _HBar(
                      value: ins,
                      max: (maxIns > 0 ? maxIns : 1),
                      caption: 'Inspections',
                    ),
                    const SizedBox(height: 4),
                    _HBar(
                      value: fin,
                      max: (maxFind > 0 ? maxFind : 1),
                      caption: 'Findings',
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNutrientsCard() {
    if (_topNutrients.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '— ไม่พบสารอาหารเด่นในช่วงที่เลือก —',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }

    final maxCnt = _topNutrients.fold<int>(0, (m, r) {
      final c = _asInt(r['cnt'], 0);
      return c > m ? c : m;
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'สารอาหารที่พบมากสุด',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _topNutrients.map((t) {
                final code = (t['nutrient_code'] ?? t['code'] ?? '-')
                    .toString();
                final cnt = _asInt(t['cnt'], 0);
                return Chip(
                  label: Text('$code • $cnt'),
                  backgroundColor: Colors.orange[50],
                  shape: StadiumBorder(
                    side: BorderSide(color: Colors.orange[200]!),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            ..._topNutrients.map((t) {
              final code = (t['nutrient_code'] ?? t['code'] ?? '-').toString();
              final cnt = _asInt(t['cnt'], 0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(code),
                    const SizedBox(height: 4),
                    _HBar(
                      value: cnt,
                      max: (maxCnt > 0 ? maxCnt : 1),
                      caption: '$cnt ครั้ง',
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สถิติการตรวจ'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadStats,
            icon: const Icon(Icons.refresh),
            tooltip: 'โหลดข้อมูล',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildFiltersCard(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (!_loading) ...[
            _buildKpiCard(),
            const SizedBox(height: 12),
            _buildBucketsCard(),
            const SizedBox(height: 12),
            _buildTopNutrientsCard(),
            const SizedBox(height: 40),
          ],
        ],
      ),
    );
  }
}

// ===== Widgets ย่อย =====

class _Kpi extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _Kpi({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade100),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.green[100],
              child: Icon(icon, color: Colors.green[800]),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// กราฟแท่งแนวนอนอย่างง่าย (ไม่ใช้แพ็กเกจเสริม)
class _HBar extends StatelessWidget {
  final int value;
  final int max;
  final String caption;

  const _HBar({required this.value, required this.max, required this.caption});

  @override
  Widget build(BuildContext context) {
    final ratio = (max <= 0) ? 0.0 : (value / max);
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth * ratio).clamp(0.0, c.maxWidth);
        return Stack(
          children: [
            Container(
              height: 12,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              width: w,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.green[400],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    ' $caption ',
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
