// lib/core/widgets/mini_toast.dart
// 说明:轻量短提示(MIUI 风格底部小胶囊)—— OverlayEntry 实现:
//   入场 150ms(上滑 6px + 淡入)→ 停留 1300ms → 退场 150ms 淡出 → 移除。
// 背景:工程为 MiuixScaffold 自绘脚手架(非 Material Scaffold),Material
//   SnackBar 无处挂载 —— 轻提示走根 Overlay,任何 Miuix 页面可用。
// 功耗:瞬时动画(controller + 单次 Timer),结束后 entry 移除、零 ticker;
//   静态胶囊颜色深浅色主题通用(黑 80% 底 + 白字)。
import 'dart:async';

import 'package:flutter/widgets.dart';

const Duration _kToastIn = Duration(milliseconds: 150);
const Duration _kToastHold = Duration(milliseconds: 1300);
const Duration _kToastOut = Duration(milliseconds: 150);

/// 展示一条短提示(自动消失;重复调用各自独立,互不排队)。
void showMiniToast(BuildContext context, String message) {
  final OverlayState overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (BuildContext context) =>
        _MiniToastHost(message: message, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _MiniToastHost extends StatefulWidget {
  const _MiniToastHost({required this.message, required this.onDone});

  final String message;
  final VoidCallback onDone;

  @override
  State<_MiniToastHost> createState() => _MiniToastHostState();
}

class _MiniToastHostState extends State<_MiniToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kToastIn,
    reverseDuration: _kToastOut,
  )..addStatusListener(_onStatus);
  late final Animation<double> _anim = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    // 入场完成 + 停留时长后退出。
    _hold = Timer(_kToastIn + _kToastHold, () {
      if (mounted) _controller.reverse();
    });
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      widget.onDone();
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      // 悬浮于内容底部(底栏/安全区之上)。
      bottom: MediaQuery.paddingOf(context).bottom + 88,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(_anim),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xCC1C1C1E), // 黑 80% 胶囊(两主题通用)
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
