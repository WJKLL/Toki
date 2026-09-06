// 连线校验规则单测(阶段2):锁定/自环/同对去重/判断出口唯一。
import 'package:flutter_test/flutter_test.dart';
import 'package:xiangjugong/core/flow/flow_connect_rules.dart';

void main() {
  group('denyConnect', () {
    test('端点锁定拒绝', () {
      expect(
        denyConnect(
          sourceLocked: true,
          targetLocked: false,
          isSelf: false,
          samePairExists: false,
          sourceIsDecision: false,
        ),
        contains('锁定'),
      );
      expect(
        denyConnect(
          sourceLocked: false,
          targetLocked: true,
          isSelf: false,
          samePairExists: false,
          sourceIsDecision: false,
        ),
        contains('锁定'),
      );
    });

    test('自环拒绝', () {
      expect(
        denyConnect(
          sourceLocked: false,
          targetLocked: false,
          isSelf: true,
          samePairExists: false,
          sourceIsDecision: false,
        ),
        contains('自身'),
      );
    });

    test('同对重复拒绝(步骤源通用文案)', () {
      expect(
        denyConnect(
          sourceLocked: false,
          targetLocked: false,
          isSelf: false,
          samePairExists: true,
          sourceIsDecision: false,
        ),
        contains('已有连线'),
      );
    });

    test('判断出口唯一:同目标分支拒绝(差异化文案)', () {
      final String? reason = denyConnect(
        sourceLocked: false,
        targetLocked: false,
        isSelf: false,
        samePairExists: true,
        sourceIsDecision: true,
      );
      expect(reason, contains('分支'));
    });

    test('合法连线放行(null)', () {
      expect(
        denyConnect(
          sourceLocked: false,
          targetLocked: false,
          isSelf: false,
          samePairExists: false,
          sourceIsDecision: false,
        ),
        isNull,
      );
      expect(
        denyConnect(
          sourceLocked: false,
          targetLocked: false,
          isSelf: false,
          samePairExists: false,
          sourceIsDecision: true,
        ),
        isNull,
      );
    });
  });

  group('denyConnectStart', () {
    test('锁定节点不可拉线;未锁定放行', () {
      expect(denyConnectStart(sourceLocked: true), contains('锁定'));
      expect(denyConnectStart(sourceLocked: false), isNull);
    });
  });
}
