// lib/core/excel/excel_timetable_parser.dart
// 编号：S-18 Excel 课表解析器（v1.17.0，P-06 大课表导入）
// 职责：用 excel_plus（纯 Dart，Android/Web 一致）解析教务系统导出的
//   .xls/.xlsx 课表 → 课程列表（ParsedCourse，不含 id，由 provider 合并生成）。
// 兼容的课表模板（已用真实文件验证）：
//   - 表头行：左侧「节次」+ 周一~周日列（星期表头为合并单元格，每星期
//     列宽不固定，如周一~五跨 3 列、周六日跨 4 列 → 按合并范围动态识别）；
//   - 数据行：行标签「1-2节」~「15-16节」仅供参考，实际节次以单元格内
//     「(01,02节)」标注为准（模板存在行与节次偏移，必须解析标注）；
//   - 课程单元格：`课程名★周次(节次)★教室★班级`，一个单元格可含多课程
//     （换行分隔，如周五 3-4 节两门课）。
import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';

import '../../domain/entities/course.dart';

/// Excel 解析出的课程数据（不含 id / week 三态 —— 导入统一按具体周次显示）。
typedef ParsedCourse = ({
  String name,
  int day,
  int start,
  int len,
  List<int> weeks,
  int colorValue,
  String? location,
  String? teacher,
});

/// S-18 Excel 课表解析器（纯静态方法）。
class ExcelTimetableParser {
  ExcelTimetableParser._();

  static const int _maxPeriod = 16;
  static const int _maxWeek = 30;
  static const List<String> _dayNames = <String>[
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日',
  ];

  /// 解析 Excel 课表字节 → 课程列表。模板不兼容抛 [FormatException]。
  static List<ParsedCourse> parse(Uint8List bytes) {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('无法解析 Excel 文件：$e');
    }
    final Sheet? sheet = _firstSheet(excel);
    if (sheet == null || sheet.maxRows == 0) {
      throw const FormatException('文件中没有可用的工作表');
    }
    return _parseSheet(sheet);
  }

  /// 取第一个有数据的 sheet。
  static Sheet? _firstSheet(Excel excel) {
    for (final Sheet s in excel.tables.values) {
      if (s.maxRows > 0) return s;
    }
    return null;
  }

  /// 「星期一」→ 1 …「星期日」→ 7；不匹配 → null。
  static int? _dayIndex(String text) {
    final int i = _dayNames.indexOf(text);
    return i < 0 ? null : i + 1;
  }

  /// 单元格值 → 去空白文本（空/无值单元格 → null）。
  static String? _cellText(Data? cell) {
    final CellValue? value = cell?.value;
    if (value == null) return null;
    return value.toString().trim();
  }

  static List<ParsedCourse> _parseSheet(Sheet sheet) {
    final List<List<Data?>> rows = sheet.rows;

    // ── 1. 定位表头行：含「节次」且至少一个星期名 ──
    int headerRow = -1;
    for (int r = 0; r < rows.length; r++) {
      bool hasPeriod = false;
      bool hasDay = false;
      for (final Data? d in rows[r]) {
        final String t = (d?.value?.toString() ?? '').trim();
        if (t == '节次') hasPeriod = true;
        if (_dayIndex(t) != null) hasDay = true;
      }
      if (hasPeriod && hasDay) {
        headerRow = r;
        break;
      }
    }
    if (headerRow < 0) {
      throw const FormatException('未找到表头行（需包含「节次」与星期列）');
    }

    // ── 2. 表头行合并单元格 → 星期列范围（day → [startCol, endCol]，0-based）──
    final Map<int, List<int>> dayCols = <int, List<int>>{};
    for (final String span in sheet.spannedItems) {
      final List<String> ends = span.split(':');
      if (ends.length != 2) continue;
      final CellIndex a = CellIndex.indexByString(ends[0]);
      final CellIndex b = CellIndex.indexByString(ends[1]);
      if (a.rowIndex != headerRow) continue;
      final List<Data?> headerCells = rows[headerRow];
      final Data? headData = a.columnIndex < headerCells.length
          ? headerCells[a.columnIndex]
          : null;
      final String? head = _cellText(headData);
      final int? day = _dayIndex(head ?? '');
      if (day == null) continue;
      dayCols[day] = <int>[a.columnIndex, b.columnIndex];
    }
    if (dayCols.length < 7) {
      throw FormatException('表头星期列识别不完整（识别到 ${dayCols.length}/7）');
    }

    // ── 3. 扫描数据行，按星期区域取非空单元格 ──
    final List<ParsedCourse> out = <ParsedCourse>[];
    for (int r = headerRow + 1; r < rows.length; r++) {
      for (int day = 1; day <= 7; day++) {
        final List<int> cols = dayCols[day]!;
        final List<Data?> row = rows[r];
        for (int c = cols[0]; c <= cols[1] && c < row.length; c++) {
          final Data? cell = row[c];
          final String? text = _cellText(cell);
          if (text == null || text.isEmpty) continue;
          // 一个单元格可含多课程（换行分隔）。
          for (final String seg in text.split('\n')) {
            final ParsedCourse? pc = _parseCourseCell(seg.trim(), day);
            if (pc != null) out.add(pc);
          }
        }
      }
    }
    if (out.isEmpty) {
      throw const FormatException('未解析到任何课程');
    }
    return out;
  }

  /// 单课程单元格：`课程名★周次(节次)★教室★班级`（★ 分段可选）。
  static ParsedCourse? _parseCourseCell(String text, int day) {
    if (text.isEmpty) return null;
    final List<String> parts = text.split('★');
    final String name = parts[0].trim();
    if (name.isEmpty) return null;

    int start = 1;
    int len = 1;
    List<int> weeks = const <int>[];
    if (parts.length >= 2) {
      final (int s, int l) = _parsePeriods(parts[1]);
      start = s;
      len = l;
      weeks = _parseWeeks(parts[1]);
    }
    final String? location = parts.length >= 3 && parts[2].trim().isNotEmpty
        ? parts[2].trim()
        : null;
    final String? teacher = parts.length >= 4 && parts[3].trim().isNotEmpty
        ? parts[3].trim()
        : null;

    return (
      name: name,
      day: day,
      start: start,
      len: len,
      weeks: weeks,
      colorValue: Course.autoColor(name),
      location: location,
      teacher: teacher,
    );
  }

  /// 提取节次标注：`(01,02节)` → (start=1, len=2)；`(06,07,08节)` → (6, 3)。
  /// 无标注 → (1, 1)。节次假定连续（教务模板如此）。
  static (int, int) _parsePeriods(String raw) {
    final RegExp re = RegExp(r'\((\d{1,2}(?:\s*,\s*\d{1,2})*)\s*节?\)');
    final Match? m = re.firstMatch(raw);
    if (m == null) return (1, 1);
    final List<int> vals = <int>[];
    for (final String n in m.group(1)!.split(RegExp(r'\s*,\s*'))) {
      final int? v = int.tryParse(n.trim());
      if (v != null && v >= 1 && v <= _maxPeriod) vals.add(v);
    }
    if (vals.isEmpty) return (1, 1);
    return (vals.first, vals.length.clamp(1, 4));
  }

  /// 解析周次：`1-5,7-16` → [1..5,7..16]；`3` → [3]；无 → []（1..30 升序去重）。
  static List<int> _parseWeeks(String raw) {
    final String cleaned = raw.replaceAll(RegExp(r'\([^)]*\)'), '');
    final List<int> weeks = <int>[];
    for (final String part in cleaned.split(',')) {
      final String p = part.trim();
      if (p.isEmpty) continue;
      final Match? range = RegExp(r'^(\d{1,2})\s*[-~]\s*(\d{1,2})$')
          .firstMatch(p);
      if (range != null) {
        final int a = int.parse(range.group(1)!);
        final int b = int.parse(range.group(2)!);
        for (int w = a; w <= b; w++) {
          if (w >= 1 && w <= _maxWeek) weeks.add(w);
        }
      } else {
        final int? w = int.tryParse(p);
        if (w != null && w >= 1 && w <= _maxWeek) weeks.add(w);
      }
    }
    final List<int> unique = <int>[];
    for (final int w in weeks) {
      if (!unique.contains(w)) unique.add(w);
    }
    unique.sort();
    return unique;
  }
}
