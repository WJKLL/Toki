// lib/presentation/features/about/page_p01_03_about_page.dart
// 编号：P-01-03 关于页（F-04 关于模块）
// 🔧 修改（v1.4.2 / T22）：接入 C-23 内容推动折叠标题栏（与首页/设置页交互统一），
//   顶栏为 CustomScrollView 首个 sliver（大标题"关于"左对齐 1:1 上移消失、
//   小标题"关于"折叠居中滑入）；内容改 SliverList 惰性构建。
// 功耗要点：静态页 0 ticker、0 网络（§11.1 / 1-6 功耗检查点）；C-23 为
//   SliverPersistentHeader 滚动驱动（无 AnimationController），TickerMode(false)
//   安全保留；全 const 构建。
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/u03_blur_policy.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/c03_group_card.dart';
import '../../../core/widgets/mini_toast.dart';
import '../../providers/platform_providers.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c22_backdrop_heartbeat.dart';
import '../../widgets/c28_downsampled_capture.dart';
import '../../widgets/c22_content_through_floating_bottom_bar.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c26_more_menu.dart';

class PageP0103AboutPage extends ConsumerStatefulWidget {
  const PageP0103AboutPage({super.key});

  @override
  ConsumerState<PageP0103AboutPage> createState() => _PageP0103AboutPageState();
}

class _PageP0103AboutPageState extends ConsumerState<PageP0103AboutPage> {
  /// v1.13.0：关于从一级页（底栏）改为二级页（顶部更多菜单进入），leading = 返回。
  late final Widget _backButton = C21CapsuleIconButton(
    key: const ValueKey('about.back'),
    icon: appIcon('chevronBackward'),
    tooltip: '返回',
    onTap: () => Navigator.of(context).maybePop(),
  );

  // ── C-25（v1.12.3）：顶部毛玻璃快照源 + 折叠滚动行为 ──
  /// 页面级顶部快照（U-03 门控创建/释放；null = 降级纯 surface）。
  MiuixLayerBackdrop? _topBackdrop;

  /// 顶部折叠滚动行为（MiuixTopAppBar + MiuixScrollBehaviorListener 联动）。
  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

  /// U-03 裁决创建/释放顶部快照（build 中调用，幂等）。
  void _syncTopBackdrop(bool enabled) {
    if (enabled && _topBackdrop == null) {
      _topBackdrop = MiuixLayerBackdrop();
    } else if (!enabled && _topBackdrop != null) {
      _topBackdrop!.dispose();
      _topBackdrop = null;
    }
  }

  @override
  void dispose() {
    // ⚡ 功耗优化：顶部快照释放。
    _topBackdrop?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String version = ref.watch(appVersionProvider);
    // 🔧 v1.4.2（C-22 内容穿透）：悬浮底栏开启时，列表底部追加穿透安全间距。
    final double throughInset =
        ref.watch(appSettingsProvider).floatingBarEnabled
        ? C22ContentThroughFloatingBottomBar.contentBottomInset(context)
        : 0.0;
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    // v1.12.3（C-25）：顶部毛玻璃 U-03 裁决 + 快照幂等同步。
    final PlatformInfo platform = ref.watch(platformInfoProvider);
    final bool topBlurAllowed = U03BlurPolicy.allowBlur(
      userEnabled: ref.watch(appSettingsProvider.select((s) => s.blurEnabled)),
      isWeb: platform.isWeb,
      androidSdkInt: platform.androidSdkInt,
    );
    _syncTopBackdrop(topBlurAllowed);

    // v1.12.3：移除 TickerMode(false) —— MiuixTopAppBar 内部有小标题弹簧
    //   AnimationController，静音会冻结折叠动画；滚动量 = 折叠量纯函数，
    //   静止零 ticker（吸附动画 280ms 一次性）。
    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      topBar: C25FrostedTopBar(
        title: '关于',
        largeTitle: '关于',
        navigationIcon: _backButton,
        actions: <Widget>[
          // v1.13.0（C-26）：顶部更多菜单。
          C26MoreMenu(backdrop: _topBackdrop),
        ],
        scrollBehavior: _collapse,
        backdrop: _topBackdrop,
      ),
      content: (padding) {
        // v1.12.3：内容避让顶栏；快照画 surface 底色 + 采样 6 帧。
        final Widget list = ListView(
          // v1.18.x（T1）：列表按下即跟手（DragStartBehavior.down）。
          dragStartBehavior: DragStartBehavior.down,
          padding: EdgeInsets.only(
            top: 24 + padding.top,
            bottom: 24 + throughInset, // 🔧 C-22 内容穿透底部安全间距
          ),
          addAutomaticKeepAlives: false,
          children: <Widget>[
            // ── 应用标识（v1.39.0:真实应用图标替换泛化 tasks 图标）──
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 72,
                      height: 72,
                      // 深色/浅色底衬内不裁内容(launcher 图自带圆角背景)。
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => SizedBox(
                        width: 72,
                        height: 72,
                        child: MiuixIcon(
                          vector: appIcon('tasks'),
                          size: 48,
                          tint: colors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  MiuixText(
                    AppConstants.appName,
                    style: textStyles.title1,
                    color: colors.onBackground,
                  ),
                  const SizedBox(height: 4),
                  MiuixText(
                    'v$version',
                    style: textStyles.body2,
                    color: colors.onSurfaceVariantSummary,
                  ),
                ],
              ),
            ),
            // v1.39.0:信息行支持跳转(仓库/许可/发布/官网,外开浏览器)。
            const C03GroupCard(
              children: [
                _InfoRow(
                  label: '项目名称',
                  // v1.30.0:更名 Toki 后中英文同名,不再并列显示括号。
                  value: AppConstants.appName,
                ),
                C03IndentDivider(),
                _InfoRow(label: '开源许可', value: AppConstants.license),
                C03IndentDivider(),
                _InfoRow(
                  label: 'GitHub 仓库',
                  value: 'github.com/WJKLL/Toki',
                  url: AppConstants.projectUrl,
                ),
                C03IndentDivider(),
                _InfoRow(
                  label: '发布记录',
                  value: 'GitHub Releases',
                  url: AppConstants.changelogUrl,
                ),
                C03IndentDivider(),
                _InfoRow(
                  label: '官方网站',
                  value: 'toki.omjl.top',
                  url: AppConstants.homeUrl,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: MiuixText(
                '视觉蓝本：KernelSU-Style-UI-Kit（Miuix 风格分支）\n'
                '技术栈：Flutter · flutter_miuix · Riverpod · go_router',
                style: textStyles.body2,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
          ],
        );
        final Widget listWithBg = ColoredBox(
          color: colors.surface,
          child: list,
        );
        final Widget captured = _topBackdrop != null
            ? C28DownsampledCapture(
                backdrop: _topBackdrop!,
                child: CaptureHeartbeat(everyNFrames: 4, child: listWithBg),
              )
            : list;
        return Material(
          type: MaterialType.transparency,
          // 🔧 v1.0.7（布局稳定性）：Column + MainAxisAlignment.start 强制顶格。
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // v1.12.3：MiuixScrollBehaviorListener 桥接滚动折叠。
                child: MiuixScrollBehaviorListener(
                  behavior: _collapse,
                  child: captured,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 关于页信息行（静态 const；[url] 非空 → 整行可点外开浏览器 + 行尾箭头）。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.url});

  final String label;
  final String value;
  final String? url;

  Future<void> _open(BuildContext context) async {
    final Uri? uri = Uri.tryParse(url!);
    if (uri == null) return;
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showMiniToast(context, '无法打开链接');
  }

  @override
  Widget build(BuildContext context) {
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool tappable = url != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: tappable ? () => _open(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            MiuixText(label, style: textStyles.body1),
            const Spacer(),
            Flexible(
              child: MiuixText(
                value,
                style: textStyles.body2,
                color: tappable
                    ? colors.primary
                    : colors.onSurfaceVariantSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (tappable) ...[
              const SizedBox(width: 6),
              MiuixIcon(
                vector: appIcon('chevronForward'),
                size: 15,
                tint: colors.onSurfaceVariantSummary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
