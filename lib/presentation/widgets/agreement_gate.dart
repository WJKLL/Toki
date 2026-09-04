// lib/presentation/widgets/agreement_gate.dart
// 编号:P-07 开屏用户协议门(Gate,v1.20.0;浮层本体见 C-31)
// 说明:包住整个应用壳(MainShell),是「同意前」的唯一守门:
//   - agreementProvider == false(已同意当前版本)→ 本组件零开销直通 child;
//   - true(首启/版本变更)→ 屏蔽主界面交互(IgnorePointer)并显示 C-31 协议卡;
//   - C-31 为 deferred 懒加载库:需要展示时才 loadLibrary,首帧不解析;
//   - 同意 → 卡片收起动画完成后 accept() 落盘 → provider 复位 → 本组件卸载浮层;
//   - 退出(仅 Android 展示按钮)→ SystemNavigator.pop();Web 无退出按钮。
import 'dart:async' show unawaited;

import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/agreement_provider.dart';
import '../providers/platform_providers.dart';
import 'c31_agreement_card.dart' deferred as agreement_card;

/// 协议门:包裹 [child](整个 MainShell),按需叠加 C-31 浮层。
class AgreementGate extends ConsumerStatefulWidget {
  const AgreementGate({super.key, required this.child, this.backdrop});

  final Widget child;

  /// 主界面快照源(毛玻璃背景;null → C-31 内部降级半透明)。
  final MiuixBackdrop? backdrop;

  @override
  ConsumerState<AgreementGate> createState() => _AgreementGateState();
}

class _AgreementGateState extends ConsumerState<AgreementGate> {
  bool _libLoading = false;
  bool _libReady = false;

  /// 需要展示时异步加载 C-31 deferred 库(本地库,通常同帧完成)。
  void _ensureLoaded() {
    if (_libLoading || _libReady) return;
    _libLoading = true;
    unawaited(
      agreement_card.loadLibrary().then((void _) {
        if (mounted) setState(() => _libReady = true);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool needs = ref.watch(agreementProvider);
    if (!needs) return widget.child;

    // 需要协议:主界面交互全程屏蔽(点击/滚动都不穿透遮罩)。
    final Widget locked = IgnorePointer(ignoring: true, child: widget.child);
    _ensureLoaded();
    if (!_libReady) {
      // 库加载瞬间(本地库 <1 帧):仅锁交互,无遮罩,避免闪烁。
      return locked;
    }
    final PlatformInfo platform = ref.watch(platformInfoProvider);
    return Stack(
      children: <Widget>[
        Positioned.fill(child: locked),
        Positioned.fill(
          child: agreement_card.C31AgreementCard(
            backdrop: widget.backdrop,
            showExit: !platform.isWeb, // Web 浏览器无法自关标签页 → 只留同意。
            onAgree: () {
              // 收起动画已完成;落盘失败不阻塞进入(下次启动会重弹)。
              unawaited(ref.read(agreementProvider.notifier).accept());
            },
            onExit: SystemNavigator.pop,
          ),
        ),
      ],
    );
  }
}
