import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:excel/excel.dart' as exc;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hive/hive.dart';
import 'dart:io';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/offline_sync_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  bool _isExporting = false;

  Future<void> _exportToExcel(List<Map<String, dynamic>> docs) async {
    setState(() => _isExporting = true);
    try {
      var excel = exc.Excel.createExcel();
      exc.Sheet sheetObject = excel['Attendance Log'];
      excel.setDefaultSheet('Attendance Log');

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      sheetObject.appendRow([
        exc.TextCellValue('Date'),
        exc.TextCellValue('Time'),
        exc.TextCellValue('Name'),
        exc.TextCellValue('Roll No.'),
        exc.TextCellValue('Branch'),
        exc.TextCellValue('Year'),
        exc.TextCellValue('Status'),
      ]);

      for (var data in docs) {
        DateTime datetime;
        if (data['timestamp'] is Timestamp) {
          datetime = (data['timestamp'] as Timestamp).toDate();
        } else if (data['timestamp'] is String) {
          datetime = DateTime.parse(data['timestamp']);
        } else {
          datetime = DateTime.now();
        }

        sheetObject.appendRow([
          exc.TextCellValue(DateFormat.yMMMd().format(datetime)),
          exc.TextCellValue(DateFormat.Hms().format(datetime)),
          exc.TextCellValue(data['name']?.toString() ?? 'N/A'),
          exc.TextCellValue(data['roll_no']?.toString() ?? 'N/A'),
          exc.TextCellValue(data['branch']?.toString() ?? 'N/A'),
          exc.TextCellValue(data['year']?.toString() ?? 'N/A'),
          exc.TextCellValue(data['status']?.toString() ?? 'Present'),
        ]);
      }

      var fileBytes = excel.save();
      if (fileBytes == null) throw "Failed to generate Excel file.";

      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/attendance_log_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File(filePath);

      await file.writeAsBytes(fileBytes, flush: true);

      if (mounted) {
        final params = ShareParams(
          files: [XFile(filePath, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
          text: 'Attendance Log Export - ${DateFormat.yMMMd().add_Hms().format(DateTime.now())}',
        );
        await SharePlus.instance.share(params);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Export failed: $e", style: const TextStyle(color: AppTheme.textDark))),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ─── MASSIVE FIX 1: Removed Outer Scaffold to prevent Double AppBars ───
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('attendance')
          .orderBy('timestamp', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppTheme.bgLight,
            appBar: _buildAppBar(context, []),
            body: _buildLoading(),
          );
        }

        List<Map<String, dynamic>> combinedDocs = [];
        
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            combinedDocs.add(doc.data() as Map<String, dynamic>);
          }
        }

        try {
          final queue = Hive.box(OfflineSyncService.attendanceQueueBoxName);
          for (var log in queue.values) {
            combinedDocs.add(Map<String, dynamic>.from(log));
          }
        } catch (_) {}

        if (combinedDocs.isEmpty) {
          return Scaffold(
            backgroundColor: AppTheme.bgLight,
            appBar: _buildAppBar(context, []),
            body: _buildEmpty(context),
          );
        }

        Map<String, Map<String, List<Map<String, dynamic>>>> groupedData = {};
        List<FlSpot> chartSpots = [];
        List<String> chartDates = [];

        int dayIndex = 0;
        String currentDateStr = "";
        int dailyCount = 0;

        for (var data in combinedDocs) {
          DateTime datetime;
          if (data['timestamp'] is Timestamp) {
            datetime = (data['timestamp'] as Timestamp).toDate();
          } else if (data['timestamp'] is String) {
            datetime = DateTime.parse(data['timestamp']);
          } else {
            datetime = DateTime.now();
          }

          String date = DateFormat.yMMMd().format(datetime);
          String chartDate = DateFormat('MM/dd').format(datetime);
          String branch = data['branch'] ?? 'Unknown Branch';
          String year = data['year'] ?? 'Unknown Year';
          String branchYear = "$branch - $year";

          groupedData.putIfAbsent(date, () => {});
          groupedData[date]!.putIfAbsent(branchYear, () => []);
          groupedData[date]![branchYear]!.add(data);

          if (currentDateStr != chartDate) {
            if (currentDateStr.isNotEmpty) {
              chartSpots.add(FlSpot(dayIndex.toDouble(), dailyCount.toDouble()));
              chartDates.add(currentDateStr);
              dayIndex++;
            }
            currentDateStr = chartDate;
            dailyCount = 1;
          } else {
            dailyCount++;
          }
        }
        if (currentDateStr.isNotEmpty) {
          chartSpots.add(FlSpot(dayIndex.toDouble(), dailyCount.toDouble()));
          chartDates.add(currentDateStr);
        }

        final sortedDates = groupedData.keys.toList().reversed.toList();
        final totalDays = groupedData.keys.length;

        return Scaffold(
          backgroundColor: AppTheme.bgLight,
          appBar: _buildAppBar(context, combinedDocs),
          body: Stack(
            children: [
              Column(
                children: [
                  _buildSummaryStrip(combinedDocs.length, totalDays),
                  if (chartSpots.length > 1) _buildCyberChart(chartSpots, chartDates),
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 32.h),
                      itemCount: sortedDates.length,
                      itemBuilder: (context, index) {
                        String date = sortedDates[index];
                        var branches = groupedData[date]!;
                        int totalForDay = branches.values.fold(0, (sum, list) => sum + list.length);

                        return _DateBlock(
                          date: date,
                          branches: branches,
                          totalForDay: totalForDay,
                          index: index,
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (_isExporting)
                Container(
                  color: Colors.white.withValues(alpha: 0.8),
                  child: const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue)),
                )
            ],
          ),
        );
      },
    );
  }

  Widget _buildCyberChart(List<FlSpot> spots, List<String> dates) {
    return Container(
      height: 160.h,
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      padding: EdgeInsets.only(right: 20.w, top: 20.h, bottom: 10.h),
      decoration: AppTheme.subtleCard(),
      child: LineChart(
        LineChartData(
          // ─── MASSIVE FIX 2: Explicitly styling the touch tooltip digits white ───
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    spot.y.toInt().toString(),
                    const TextStyle(
                      color: Colors.white, // Forces the digit to be perfectly white
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          // ───────────────────────────────────────────────────────────────────────
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            getDrawingHorizontalLine: (value) => FlLine(color: AppTheme.borderSubtle, strokeWidth: 1),
            getDrawingVerticalLine: (value) => FlLine(color: AppTheme.borderSubtle, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= 0 && value.toInt() < dates.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 5.0),
                      child: Text(dates[value.toInt()], style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                reservedSize: 28,
                getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          borderData: FlBorderData(show: true, border: const Border(bottom: BorderSide(color: AppTheme.borderSubtle), left: BorderSide(color: AppTheme.borderSubtle))),
          minX: 0,
          maxX: (dates.length - 1).toDouble(),
          minY: 0,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppTheme.primaryBlue,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppTheme.primaryBlue.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, List<Map<String, dynamic>> docs) {
    return AppBar(
      backgroundColor: AppTheme.surfaceLight,
      elevation: 0, // Dropped to 0 so the bottom line handles the border
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textDark, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("ATTENDANCE LOGS", style: TextStyle(color: AppTheme.textDark, fontSize: 16.sp, fontWeight: FontWeight.bold)),
          Text("HISTORICAL RECORDS", style: TextStyle(color: AppTheme.primaryBlue, fontSize: 10.sp, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.download_rounded, color: AppTheme.primaryBlue),
          tooltip: "Export to Excel",
          onPressed: () => _exportToExcel(docs),
        ),
        SizedBox(width: 10.w),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: AppTheme.borderSubtle, // Ensures clean light theme separator
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: AppTheme.primaryBlue, strokeWidth: 3)),
          SizedBox(height: 16.h),
          Text("FETCHING RECORDS...", style: TextStyle(color: AppTheme.primaryBlue, fontSize: 12.sp, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_off_rounded, size: 56.sp, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          SizedBox(height: 16.h),
          Text("NO RECORDS FOUND", style: TextStyle(color: AppTheme.textDark, fontSize: 18.sp, fontWeight: FontWeight.bold)),
          SizedBox(height: 8.h),
          Text("Attendance logs will appear here", style: TextStyle(color: AppTheme.textSecondary, fontSize: 14.sp)),
        ],
      ),
    );
  }

  Widget _buildSummaryStrip(int totalEntries, int totalDays) {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: AppTheme.subtleCard(),
      child: Row(
        children: [
          _StatChip(label: "TOTAL ENTRIES", value: totalEntries.toString(), color: AppTheme.primaryBlue),
          Container(width: 1, height: 32.h, color: AppTheme.borderSubtle, margin: EdgeInsets.symmetric(horizontal: 16.w)),
          _StatChip(label: "DAYS LOGGED", value: totalDays.toString(), color: AppTheme.warningAmber),
          Container(width: 1, height: 32.h, color: AppTheme.borderSubtle, margin: EdgeInsets.symmetric(horizontal: 16.w)),
          _StatChip(label: "AVG / DAY", value: totalDays > 0 ? (totalEntries / totalDays).toStringAsFixed(1) : "0", color: AppTheme.successGreen),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 20.sp, fontWeight: FontWeight.w800, height: 1)),
          SizedBox(height: 4.h),
          Text(label, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: 9.sp, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _DateBlock extends StatefulWidget {
  final String date;
  final Map<String, List<Map<String, dynamic>>> branches;
  final int totalForDay;
  final int index;

  const _DateBlock({required this.date, required this.branches, required this.totalForDay, required this.index});

  @override
  State<_DateBlock> createState() => _DateBlockState();
}

class _DateBlockState extends State<_DateBlock> with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: EdgeInsets.only(top: 12.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppTheme.surfaceLight,
        border: Border.all(color: _expanded ? AppTheme.primaryBlue : AppTheme.borderSubtle, width: _expanded ? 1.5 : 1),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              child: Row(
                children: [
                  Container(
                    width: 40.w, height: 40.w,
                    decoration: BoxDecoration(color: AppTheme.primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.calendar_today_rounded, color: AppTheme.primaryBlue, size: 18),
                  ),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.date.toUpperCase(), style: TextStyle(color: AppTheme.textDark, fontSize: 14.sp, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        SizedBox(height: 2.h),
                        Text("${widget.branches.length} branch${widget.branches.length != 1 ? 'es' : ''}", style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.sp, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(color: AppTheme.primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text("${widget.totalForDay}", style: TextStyle(color: AppTheme.primaryBlue, fontSize: 12.sp, fontWeight: FontWeight.w800)),
                  ),
                  SizedBox(width: 12.w),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary, size: 22.sp),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(color: AppTheme.borderSubtle, height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 12.h),
              child: Column(
                children: widget.branches.keys.map((branchKey) => _BranchSection(branchKey: branchKey, students: widget.branches[branchKey]!)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BranchSection extends StatefulWidget {
  final String branchKey;
  final List<Map<String, dynamic>> students;

  const _BranchSection({required this.branchKey, required this.students});

  @override
  State<_BranchSection> createState() => _BranchSectionState();
}

class _BranchSectionState extends State<_BranchSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: EdgeInsets.only(top: 8.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: AppTheme.bgLight,
        border: Border.all(color: _expanded ? AppTheme.secondaryBlue : AppTheme.borderSubtle),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              child: Row(
                children: [
                  Container(
                    width: 30.w, height: 30.w,
                    decoration: BoxDecoration(color: AppTheme.secondaryBlue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.folder_rounded, color: AppTheme.secondaryBlue, size: 16),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(child: Text(widget.branchKey, style: TextStyle(color: AppTheme.textDark, fontSize: 12.sp, fontWeight: FontWeight.w600))),
                  Container(
                    width: 28.w, height: 28.w,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.secondaryBlue.withValues(alpha: 0.1)),
                    child: Center(child: Text("${widget.students.length}", style: TextStyle(color: AppTheme.secondaryBlue, fontSize: 11.sp, fontWeight: FontWeight.bold))),
                  ),
                  SizedBox(width: 8.w),
                  AnimatedRotation(turns: _expanded ? 0.5 : 0, duration: const Duration(milliseconds: 150), child: Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary, size: 18.sp)),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(color: AppTheme.borderSubtle, height: 1, indent: 12.w, endIndent: 12.w),
            Column(
              children: widget.students.asMap().entries.map((entry) {
                final idx = entry.key;
                final student = entry.value;
                final isLast = idx == widget.students.length - 1;
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                  decoration: BoxDecoration(border: isLast ? null : Border(bottom: BorderSide(color: AppTheme.borderSubtle))),
                  child: Row(
                    children: [
                      SizedBox(width: 24.w, child: Text("${idx + 1}", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.sp, fontWeight: FontWeight.bold))),
                      SizedBox(width: 8.w),
                      Container(
                        width: 32.w, height: 32.w,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.successGreen.withValues(alpha: 0.15)),
                        child: Center(child: Text((student['name'] ?? '?').toString().substring(0, 1).toUpperCase(), style: TextStyle(color: AppTheme.successGreen, fontSize: 14.sp, fontWeight: FontWeight.bold))),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(student['name'] ?? 'Unknown Student', style: TextStyle(color: AppTheme.textDark, fontSize: 13.sp, fontWeight: FontWeight.w600)),
                            SizedBox(height: 2.h),
                            Text("Roll No: ${student['roll_no'] ?? 'N/A'}", style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.sp)),
                          ],
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                        decoration: BoxDecoration(color: AppTheme.successGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, color: AppTheme.successGreen, size: 12.sp),
                            SizedBox(width: 4.w),
                            Text("PRESENT", style: TextStyle(color: AppTheme.successGreen, fontSize: 9.sp, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}