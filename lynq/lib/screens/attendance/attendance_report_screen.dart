import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:excel/excel.dart' as xls;
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../shared/widgets/glass_card.dart';

/// Shows per-day attendance for an event and allows exporting to Excel.
class AttendanceReportScreen extends StatefulWidget {
  final int eventId;
  final String eventTitle;
  final int numDays;

  const AttendanceReportScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.numDays,
  });

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isExporting = false;
  // day_number (1-based) → list of attendee rows
  Map<int, List<Map<String, dynamic>>> _attendanceByDay = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.numDays, vsync: this);
    _loadAttendance();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAttendance() async {
    setState(() => _isLoading = true);
    try {
      // Step 1: fetch attendance rows for this event
      final attendanceRows = await Supabase.instance.client
          .from('attendance')
          .select('user_id, day_number, scan_time')
          .eq('event_id', widget.eventId)
          .order('day_number', ascending: true)
          .order('scan_time', ascending: true);

      final rows = (attendanceRows as List).cast<Map<String, dynamic>>();

      // Step 2: fetch user details for all unique user_ids
      final userIds = rows.map((r) => r['user_id'] as String).toSet().toList();
      Map<String, Map<String, dynamic>> usersMap = {};
      if (userIds.isNotEmpty) {
        final usersRows = await Supabase.instance.client
            .from('profiles')
            .select('id, name, roll_number, branch, year, email')
            .inFilter('id', userIds);
        for (final u in (usersRows as List)) {
          usersMap[u['id'] as String] = u as Map<String, dynamic>;
        }
      }

      // Step 3: group by day_number
      final Map<int, List<Map<String, dynamic>>> grouped = {};
      for (final row in rows) {
        final day = (row['day_number'] as int?) ?? 1;
        final userId = row['user_id'] as String;
        final user = usersMap[userId];
        grouped.putIfAbsent(day, () => []);
        grouped[day]!.add({
          'name':        user?['name']        ?? 'Unknown',
          'roll_number': user?['roll_number'] ?? '-',
          'branch':      user?['branch']      ?? '-',
          'year':        user?['year']?.toString() ?? '-',
          'email':       user?['email']       ?? '-',
          'time':        row['scan_time'] as String?,
        });
      }

      setState(() {
        _attendanceByDay = grouped;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading attendance: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportToExcel() async {
    setState(() => _isExporting = true);
    try {
      final excel = xls.Excel.createExcel();

      for (int day = 1; day <= widget.numDays; day++) {
        final sheet = excel['Day $day'];

        // Header row style
        final headerStyle = xls.CellStyle(
          bold: true,
          backgroundColorHex: xls.ExcelColor.fromHexString('#1A73E8'),
          fontColorHex: xls.ExcelColor.fromHexString('#FFFFFF'),
        );

        final headers = ['#', 'Name', 'Roll Number', 'Branch', 'Year', 'Email', 'Time Scanned'];
        for (int col = 0; col < headers.length; col++) {
          final cell = sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
          cell.value = xls.TextCellValue(headers[col]);
          cell.cellStyle = headerStyle;
        }

        final rows = _attendanceByDay[day] ?? [];
        for (int r = 0; r < rows.length; r++) {
          final row = rows[r];
          String timeStr = '-';
          if (row['time'] != null) {
            final dt = DateTime.tryParse(row['time']!);
            if (dt != null) {
              timeStr = DateFormat('dd MMM yyyy hh:mm a').format(dt.toLocal());
            }
          }
          final values = [
            '${r + 1}',
            row['name'] ?? '-',
            row['roll_number'] ?? '-',
            row['branch'] ?? '-',
            row['year'] ?? '-',
            row['email'] ?? '-',
            timeStr,
          ];
          for (int col = 0; col < values.length; col++) {
            sheet.cell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: r + 1))
                .value = xls.TextCellValue(values[col]);
          }
        }

        // Auto-width columns
        sheet.setColumnWidth(0, 6);
        sheet.setColumnWidth(1, 24);
        sheet.setColumnWidth(2, 18);
        sheet.setColumnWidth(3, 16);
        sheet.setColumnWidth(4, 8);
        sheet.setColumnWidth(5, 28);
        sheet.setColumnWidth(6, 22);
      }

      // Set Day 1 as default and remove the default empty sheet
      excel.setDefaultSheet('Day 1');
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final bytes = excel.save();
      if (bytes == null) throw Exception('Failed to generate Excel file');

      final dir = await getTemporaryDirectory();
      final safeName = widget.eventTitle
          .replaceAll(RegExp(r'[^\w\s\-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      final file = File('${dir.path}/${safeName}_attendance.xlsx');
      await file.writeAsBytes(bytes);
      await OpenFile.open(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F111A) : const Color(0xFFF8FAF8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance Report',
              style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              widget.eventTitle,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (!_isLoading)
            IconButton(
              onPressed: _loadAttendance,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
            ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_isExporting)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              onPressed: _exportToExcel,
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Export to Excel (.xlsx)',
            ),
        ],
        bottom: widget.numDays > 1
            ? TabBar(
                controller: _tabController,
                isScrollable: widget.numDays > 4,
                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
                tabs: List.generate(widget.numDays, (i) {
                  final count = _attendanceByDay[i + 1]?.length ?? 0;
                  return Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Day ${i + 1}'),
                        if (!_isLoading && count > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.secondary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: GoogleFonts.inter(
                                  fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.darkGreen),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              )
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.numDays == 1
              ? _buildDayView(1)
              : TabBarView(
                  controller: _tabController,
                  children: List.generate(widget.numDays, (i) => _buildDayView(i + 1)),
                ),
    );
  }

  Widget _buildDayView(int day) {
    final rows = _attendanceByDay[day] ?? [];

    if (rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_off_outlined, size: 72, color: Colors.grey.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              widget.numDays > 1
                  ? 'No attendance recorded for Day $day'
                  : 'No attendance recorded yet',
              style: GoogleFonts.inter(color: Colors.grey, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan member QR codes to mark attendance',
              style: GoogleFonts.inter(color: Colors.grey.withValues(alpha: 0.5), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${rows.length} attendee${rows.length != 1 ? 's' : ''}',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600, color: AppTheme.secondary, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: rows.length,
            itemBuilder: (ctx, i) {
              final row = rows[i];
              final timeStr = row['time'] != null
                  ? DateFormat('hh:mm a').format(DateTime.parse(row['time']!).toLocal())
                  : '-';
              final name = row['name'] as String? ?? '?';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppTheme.secondary.withValues(alpha: 0.15),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: GoogleFonts.spaceGrotesk(
                              color: AppTheme.secondary, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            Text(
                              '${row['roll_number']} · ${row['branch']}',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(timeStr,
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey)),
                          Text(
                            '#${i + 1}',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: Colors.grey.withValues(alpha: 0.4)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
