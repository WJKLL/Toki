// test/widget_test.dart
// 冒烟测试：应用外壳可启动、默认路由渲染首页（P-01-01）。
// 覆盖 PROJECT_SPEC §13 SOP 步骤 8 的 Widget 测试门禁（阶段一）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xiangjugong/data/repositories/agreement_repository_impl.dart';
import 'package:xiangjugong/data/repositories/settings_repository_impl.dart';
import 'package:xiangjugong/domain/repositories/agreement_repository.dart';
import 'package:xiangjugong/main.dart';
import 'package:xiangjugong/presentation/providers/agreement_provider.dart';
import 'package:xiangjugong/presentation/providers/settings_providers.dart';
import 'package:xiangjugong/presentation/widgets/c34_responsive_card_grid.dart';
import 'package:xiangjugong/presentation/widgets/cards/card_summary.dart';

void main() {
  testWidgets('P-01-01 首页冒烟：外壳启动并渲染首页', (tester) async {
    // v1.20.0+：协议卡仓储需 override 且预置「已同意当前版本」直通 Gate。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'user_agreement_accepted': true,
      'user_agreement_version': kAgreementVersion,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsRepositoryImpl repository = SettingsRepositoryImpl(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repository),
          agreementRepositoryProvider.overrideWithValue(
            AgreementRepositoryImpl(prefs),
          ),
        ],
        child: const XiangJuGongApp(),
      ),
    );
    // 等待路由首帧与主题注入完成。
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // 首页存在（应用名 + 摘要卡 + 卡片网格；v1.26.0:断言锚点从已下线
    // 的旧首页入口('色彩调色板')更新为当前首页结构)。
    // v1.30.0:应用更名 Toki。
    expect(find.text('Toki'), findsWidgets);
    expect(find.byType(C27HomeSummary), findsOneWidget);
    expect(find.byType(C34ResponsiveCardGrid), findsOneWidget);

    // 清理：防抖 Timer 不得泄漏（S-02 dispose 校验）。
    repository.dispose();
  });
}
