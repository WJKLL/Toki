// test/ledger_icon_bounds_test.dart
// 临时自检：打印 C-45 每个图标的几何包围盒（视口 24×24），
// 用于核对是否有越界 / 过小 / 空路径的图标。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/core/widgets/ledger_icons.dart';
import 'package:xiangjugong/domain/entities/ledger_category.dart';

void main() {
  test('ledger icon bounds', () {
    final List<String> lines = <String>[];
    for (final LedgerCategory c in defaultLedgerCategories()) {
      final MiuixVectorIcon icon = ledgerIcon(c.id);
      Rect? total;
      for (final MiuixVectorPath p in icon.paths) {
        final Rect b = p.build().getBounds();
        total = total == null ? b : total.expandToInclude(b);
      }
      lines.add('${c.id.padRight(24)} $total');
    }
    // ignore: avoid_print
    print('\n${lines.join('\n')}');
  });
}
