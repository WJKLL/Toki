// test/ledger_icons_preview_test.dart
// 临时预览：把 C-45 记账图标集渲染成 golden PNG，用于人工核对自绘路径。
// 用法：flutter test --update-goldens test/ledger_icons_preview_test.dart
//   → test/goldens/ledger_icons.png
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/core/widgets/ledger_icons.dart';
import 'package:xiangjugong/domain/entities/ledger_category.dart';

void main() {
  testWidgets('ledger icons preview', (WidgetTester tester) async {
    final List<LedgerCategory> cats = defaultLedgerCategories();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: const ValueKey<String>('preview'),
            child: Container(
              color: const Color(0xFFF2F3F5),
              width: 560,
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final LedgerCategory c in cats)
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: MiuixIcon(
                          vector: ledgerIcon(c.id),
                          size: 30,
                          tint: Color(c.colorValue),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byKey(const ValueKey<String>('preview')),
      matchesGoldenFile('goldens/ledger_icons.png'),
    );
  });
}
