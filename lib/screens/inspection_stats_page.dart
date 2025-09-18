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

  // current period data
  List<Map<String, dynamic>> _buckets = []; // [{bucket, inspections, findings}]
  List<Map<String, dynamic>> _topNutrients = []; // [{nutrient_code, cnt}]
  int _totalInspections = 0;
  int _totalFindings = 0;

  // previous period (for MoM/YoY)
  int _prevTotalInspections = 0;
  int _prevTotalFindings = 0;

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
    _group = (widget.initialGroup == 'year') ? 'year' : 'month';
    _year = widget.initialYear ?? _year;
    _month = widget.initialMonth ?? _month;
    _fieldId = widget.initialFieldId;
    _zoneId = widget.initialZoneId;

    _loadFields();
    _loadStats();
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

  String _fmtPct(num v, {int digits = 1}) {
    return '${(v * 100).toStringAsFixed(digits)}%';
  }

  double _safeDiv(num a, num b) => (b == 0) ? 0.0 : (a / b);

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

  // ---------- Load stats (current + previous period) ----------
  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _buckets = [];
      _topNutrients = [];
      _totalFindings = 0;
      _totalInspections = 0;
      _prevTotalFindings = 0;
      _prevTotalInspections = 0;
    });

    // 1) ช่วงเวลาปัจจุบัน
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

    final curRes = await InspectionApi.getHistory(
      group: _group,
      from: _fmtDate(from),
      to: _fmtDate(to),
      fieldId: _fieldId,
      zoneId: _zoneId,
    );

    // 2) ช่วงเวลาก่อนหน้า (month-1 หรือ year-1)
    late DateTime pFrom;
    late DateTime pTo;
    if (_group == 'year') {
      pFrom = DateTime(_year - 1, 1, 1);
      pTo = DateTime(_year - 1, 12, 31);
    } else {
      final prev = DateTime(_year, _month, 1).subtract(const Duration(days: 1));
      final lastDay = DateTime(prev.year, prev.month + 1, 0).day;
      pFrom = DateTime(prev.year, prev.month, 1);
      pTo = DateTime(prev.year, prev.month, lastDay);
    }

    final prevRes = await InspectionApi.getHistory(
      group: _group,
      from: _fmtDate(pFrom),
      to: _fmtDate(pTo),
      fieldId: _fieldId,
      zoneId: _zoneId,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    // ----- Map current -----
    if (curRes['success'] == true) {
      final List rawBuckets =
          (curRes['buckets'] ?? curRes['groups'] ?? []) as List;
      final List rawTops = (curRes['top_nutrients'] ?? []) as List;

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
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('โหลดสถิติไม่สำเร็จ: ${curRes['error'] ?? 'unknown'}'),
        ),
      );
    }

    // ----- Map previous -----
    if (prevRes['success'] == true) {
      final List rawBuckets =
          (prevRes['buckets'] ?? prevRes['groups'] ?? []) as List;
      final buckets = rawBuckets
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _prevTotalInspections = buckets.fold<int>(
        0,
        (sum, b) => sum + _asInt(b['inspections']),
      );
      _prevTotalFindings = buckets.fold<int>(
        0,
        (sum, b) => sum + _asInt(b['findings']),
      );
    }
    setState(() {});
  }

  // ---------- UI ----------

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

  Color _trendColor(double v) {
    // findings/round มากขึ้น = เสี่ยงขึ้น ⇒ แดง, ลดลง ⇒ เขียว
    if (v > 0.05) return Colors.red;
    if (v < -0.05) return Colors.green;
    return Colors.orange;
  }

  Widget _trendBadge(double change) {
    final arrow = change > 0 ? '▲' : (change < 0 ? '▼' : '—');
    final text = '${(change * 100).toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _trendColor(change).withOpacity(0.08),
        border: Border.all(color: _trendColor(change).withOpacity(0.25)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$arrow $text',
        style: TextStyle(color: _trendColor(change), fontSize: 12),
      ),
    );
  }

  Widget _buildDecisionPanel() {
    final curRate = _safeDiv(_totalFindings, _totalInspections);
    final prevRate = _safeDiv(_prevTotalFindings, _prevTotalInspections);
    final delta = curRate - prevRate;

    // ระดับความเสี่ยงตาม Findings/รอบ
    String risk = 'ปกติ';
    Color color = Colors.green;
    if (curRate >= 1.2) {
      risk = 'วิกฤต';
      color = Colors.red;
    } else if (curRate >= 0.7) {
      risk = 'เสี่ยงสูง';
      color = Colors.orange;
    } else if (curRate >= 0.3) {
      risk = 'เริ่มเสี่ยง';
      color = Colors.amber;
    }

    final tips = <String>[
      if (curRate >= 0.7) 'เร่ง “สั่งตรวจโมเดล” เพิ่มเติมในโซนที่พบถี่',
      if (curRate >= 0.7) 'วางแผนใส่ปุ๋ยตามธาตุยอดฮิตในช่วงนี้',
      if (curRate < 0.7 && curRate >= 0.3)
        'ติดตามแนวโน้ม 2–3 สัปดาห์ พร้อมตรวจซ้ำ',
      if (curRate < 0.3) 'คงความถี่การตรวจเดิม และดูสถิติรายโซน',
    ];

    return Card(
      color: color.withOpacity(0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.policy_outlined, color: color),
                const SizedBox(width: 8),
                Text(
                  'สรุปเพื่อการตัดสินใจ',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                _trendBadge(delta),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Kpi(
                  title: 'จำนวนรอบตรวจ',
                  value: '$_totalInspections',
                  icon: Icons.fact_check_outlined,
                ),
                _Kpi(
                  title: 'Findings ทั้งหมด',
                  value: '$_totalFindings',
                  icon: Icons.bug_report_outlined,
                ),
                _Kpi(
                  title: 'Findings/รอบ',
                  value: curRate.toStringAsFixed(2),
                  icon: Icons.calculate_outlined,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Chip(
                  label: Text('ระดับความเสี่ยง: $risk'),
                  backgroundColor: color.withOpacity(0.12),
                  shape: StadiumBorder(
                    side: BorderSide(color: color.withOpacity(0.35)),
                  ),
                  labelStyle: TextStyle(color: color.withOpacity(0.9)),
                ),
                const SizedBox(width: 8),
                Text(
                  'เทียบช่วงก่อนหน้า: ${_fmtPct(delta.abs(), digits: 1)} ${delta >= 0 ? "สูงขึ้น" : "ลดลง"}',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
            if (tips.isNotEmpty) ...[
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: tips.map((t) => Text('• $t')).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniBar({required int value, required int max}) {
    final w = (max <= 0) ? 0.0 : (value / max);
    return LayoutBuilder(
      builder: (context, c) {
        final width = (c.maxWidth * w).clamp(0.0, c.maxWidth);
        return Stack(
          children: [
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: width,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.green[400],
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBucketsTable() {
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
      (m, b) => (_asInt(b['inspections']) > m) ? _asInt(b['inspections']) : m,
    );
    final maxFin = _buckets.fold<int>(
      0,
      (m, b) => (_asInt(b['findings']) > m) ? _asInt(b['findings']) : m,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'สรุปรายช่วง',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 44,
                columns: const [
                  DataColumn(label: Text('ช่วงเวลา')),
                  DataColumn(label: Text('Inspections')),
                  DataColumn(label: Text('Findings')),
                  DataColumn(label: Text('Find/Ins')),
                  DataColumn(label: Text('Mini Bar')),
                ],
                rows: _buckets.map((b) {
                  final label = (b['bucket'] ?? b['label'] ?? '').toString();
                  final ins = _asInt(b['inspections'], 0);
                  final fin = _asInt(b['findings'], 0);
                  final rate = _safeDiv(fin, ins);
                  return DataRow(
                    cells: [
                      DataCell(Text(label)),
                      DataCell(Text('$ins')),
                      DataCell(Text('$fin')),
                      DataCell(Text(rate.toStringAsFixed(2))),
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: _miniBar(
                            value: fin,
                            max: maxFin > 0 ? maxFin : 1,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _HBar(
                    value: _totalInspections,
                    max: (maxIns > 0 ? maxIns : 1),
                    caption: 'รวม Inspections',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HBar(
                    value: _totalFindings,
                    max: (maxFin > 0 ? maxFin : 1),
                    caption: 'รวม Findings',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNutrientsTable() {
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

    final totalCnt = _topNutrients.fold<int>(
      0,
      (s, r) => s + _asInt(r['cnt'], 0),
    );
    final maxCnt = _topNutrients.fold<int>(0, (m, r) {
      final c = _asInt(r['cnt'], 0);
      return c > m ? c : m;
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'ธาตุที่พบมากสุด',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 44,
                columns: const [
                  DataColumn(label: Text('Nutrient')),
                  DataColumn(label: Text('จำนวน')),
                  DataColumn(label: Text('สัดส่วน')),
                  DataColumn(label: Text('Mini Bar')),
                ],
                rows: _topNutrients.map((t) {
                  final code = (t['nutrient_code'] ?? t['code'] ?? '-')
                      .toString();
                  final cnt = _asInt(t['cnt'], 0);
                  final share = _safeDiv(cnt, (totalCnt == 0 ? 1 : totalCnt));
                  return DataRow(
                    cells: [
                      DataCell(Text(code)),
                      DataCell(Text('$cnt')),
                      DataCell(Text(_fmtPct(share))),
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: _miniBar(
                            value: cnt,
                            max: maxCnt > 0 ? maxCnt : 1,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
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
            _buildDecisionPanel(),
            const SizedBox(height: 12),
            _buildBucketsTable(),
            const SizedBox(height: 12),
            _buildTopNutrientsTable(),
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
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.green[100],
            child: Icon(icon, color: Colors.green[800], size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
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
    );
  }
}

/// กราฟแท่งแนวนอนอย่างง่าย
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
