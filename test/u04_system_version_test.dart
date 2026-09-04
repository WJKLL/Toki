// test/u04_system_version_test.dart
// 🐛 修复（BUG-001 / T13）：真实 Android API Level 探测的纯函数回归测试。
// 覆盖：RELEASE 字符串 → API Level 映射表（含 Android 17 → 37 的澎湃OS4 场景、
//       Android 12L 特殊映射、未知版本返回 null）；纯函数零平台通道依赖。
import 'package:flutter_test/flutter_test.dart';

import 'package:xiangjugong/core/utils/u04_platform_utils.dart';

void main() {
  group('U-04 apiLevelFromRelease（BUG-001 版本识别映射）', () {
    test('Android 17（澎湃OS 4 基座）→ API 37', () {
      expect(U04PlatformUtils.apiLevelFromRelease('17'), 37);
    });

    test('完整映射表（10 → 29 … 17 → 37，Android 13 = 33）', () {
      const Map<String, int> expected = <String, int>{
        '10': 29,
        '11': 30,
        '12': 31,
        '13': 33, // 注意：Android 13 = API 33（32 为 12L）
        '14': 34,
        '15': 35,
        '16': 36,
        '17': 37,
      };
      expected.forEach((release, api) {
        expect(
          U04PlatformUtils.apiLevelFromRelease(release),
          api,
          reason: 'RELEASE "$release" 应映射到 API $api',
        );
      });
    });

    test('Android 12L → API 32（特殊分支）', () {
      expect(U04PlatformUtils.apiLevelFromRelease('12L'), 32);
      expect(U04PlatformUtils.apiLevelFromRelease('12.1'), 32); // 12L 别名
    });

    test('未知 / 空字符串 → null（安全降级）', () {
      expect(U04PlatformUtils.apiLevelFromRelease(''), isNull);
      expect(U04PlatformUtils.apiLevelFromRelease('abc'), isNull);
      expect(U04PlatformUtils.apiLevelFromRelease('99'), isNull); // 超出映射表
    });
  });
}
