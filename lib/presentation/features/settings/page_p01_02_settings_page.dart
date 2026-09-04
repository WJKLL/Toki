// lib/presentation/features/settings/page_p01_02_settings_page.dart
// 编号：P-01-02 设置页（F-03 设置模块）
// 设置项：UI 模式（C-13 分段）· 主题与色彩入口 · Monet 开关 · 动效开关（毛玻璃+平滑动画,U-03）
//         · 悬浮底栏（C-12）· 页面缩放（C-15）· 其他入口（调色板/权限/关于）
// 组件：C-03 分组卡片、C-06 开关、C-07 下拉、C-13 分段选择器
// 🔧 修改（v1.4.1 / T20）：接入 C-23 内容推动折叠标题栏（与首页交互统一），
//   顶栏为 CustomScrollView 首个 sliver（大标题"设置"左对齐 1:1 上移消失、
//   小标题"设置"折叠居中滑入）；列表改 SliverList.builder 惰性构建。
// 功耗要点（§11.1 交互型页面）：
//   - 🔧 修复（v1.0.6）：本页为交互型页面（开关/分段/滑块），**禁止**整体
//     TickerMode(enabled:false) —— TickerMode 会静音子树内所有 ticker，
//     MiuixSwitch 圆点动画（_thumbPos）与 MiuixTabRow 指示器将被冻结，
//     表现为"功能生效但开关/高亮视觉不变"。交互控件动画为瞬时（≤300ms）
//     且结束时 ticker 立即回收，闲置期无帧开销，符合 §11.1 静态页目标。
//   - C-23 滚动期间仅 header 子树重绘（SliverPersistentHeader 内部驱动），
//     静止零 ticker；列表 SliverList.builder + addAutomaticKeepAlives: false（§11.3）。
//   - 每行 const 构造；build 不创建新对象；Consumer + select 精确订阅（§11.2.2）。
import 'package:flutter/gestures.dart' show DragStartBehavior;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/logging/log_export_service.dart';
import '../../../core/utils/u03_blur_policy.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/c03_group_card.dart';
import '../../../core/widgets/c05_warning_card.dart';
import '../../../domain/entities/app_settings.dart';
import '../../../domain/entities/daily_quote.dart';
import '../../providers/platform_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/steam_providers.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c22_backdrop_heartbeat.dart';
import '../../widgets/c28_downsampled_capture.dart';
import '../../widgets/c22_content_through_floating_bottom_bar.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c26_more_menu.dart';
import '../../widgets/c35_quote_option_sheet.dart';
import '../../widgets/c39_steam_key_sheet.dart';

class PageP0102SettingsPage extends ConsumerStatefulWidget {
  const PageP0102SettingsPage({super.key});

  @override
  ConsumerState<PageP0102SettingsPage> createState() =>
      _PageP0102SettingsPageState();
}

class _PageP0102SettingsPageState extends ConsumerState<PageP0102SettingsPage> {
  static const List<String> _uiModeLabels = <String>['跟随系统', '浅色', '深色'];
  static const List<AppUiMode> _uiModeValues = <AppUiMode>[
    AppUiMode.system,
    AppUiMode.light,
    AppUiMode.dark,
  ];

  /// 组内项统一紧凑内边距（static const，§11.2 静态配置）。
  static const EdgeInsets _itemMargin = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 14,
  );

  /// 🔧 修改（v1.4.1 / T20，v1.13.0 适配二级页）：顶栏 leading = 返回按钮。
  ///   v1.13.0：设置从一级页（底栏）改为二级页（顶部更多菜单进入），leading 改返回。
  late final Widget _backButton = C21CapsuleIconButton(
    key: const ValueKey('settings.back'),
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

  // ── v1.9.0（S-13/S-14）：日志导出状态 ──
  bool _exporting = false;
  String? _exportNotice; // 成功提示（对话框）
  String? _exportError; // 失败提示（对话框）

  // ── v1.27.0（C-35）：内容设置悬浮选择窗状态（'api'/'lang'/'style'/null）──
  String? _picker;

  // ── v1.34.0（P-08）：Steam 查询 UAPI 密钥弹层显隐 ──
  bool _steamKeySheet = false;

  /// 导出日志 + 性能摘要到公共 Download/（原生 MediaStore）。
  Future<void> _exportLogs() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _exportNotice = null;
      _exportError = null;
    });
    try {
      final String name = await LogExportService.instance.export(
        appVersion: AppConstants.appVersion,
        deviceInfo: kIsWeb
            ? 'Web'
            : '${Platform.operatingSystem} ${Platform.version}',
      );
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportNotice = '已保存到 Download/$name';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportError = '导出失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ⚡ 功耗优化：select 只订阅本页最小切片（uiMode/blurEnabled/…），
    //   页面缩放滑块拖动只重建本 Consumer（§11.2.2）。
    final AppSettings settings = ref.watch(appSettingsProvider);
    final AppSettingsController controller = ref.read(
      appSettingsProvider.notifier,
    );
    final bool effectiveBlur = ref.watch(effectiveBlurProvider);
    final String blurReason = ref.watch(blurReasonProvider);
    // v1.0.1：移动端（Android）禁用「页面缩放」拉条（仅 Web 生效）。
    final bool pageScaleEnabled = !ref.watch(platformInfoProvider).isAndroid;
    // 🔧 v1.4.1（C-22 内容穿透）：悬浮底栏开启时，列表底部追加穿透安全间距。
    final double throughInset = settings.floatingBarEnabled
        ? C22ContentThroughFloatingBottomBar.contentBottomInset(context)
        : 0.0;

    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final MiuixColors colors = MiuixTheme.of(context).colors;

    // v1.12.3（C-25）：顶部毛玻璃 U-03 裁决 + 快照幂等同步。
    final bool topBlurAllowed = U03BlurPolicy.allowBlur(
      userEnabled: settings.blurEnabled,
      isWeb: ref.watch(platformInfoProvider).isWeb,
      androidSdkInt: ref.watch(platformInfoProvider).androidSdkInt,
    );
    _syncTopBackdrop(topBlurAllowed);

    // 🔧 修复（v1.0.6）：交互型页面不得整体 TickerMode(false)——否则 MiuixSwitch
    //   圆点动画与 MiuixTabRow 指示器被静音冻结（"功能生效但视觉不变"根因）。
    //   交互控件动画瞬时（≤300ms），闲置期无 ticker 帧开销，功耗目标不受影响。
    return MiuixScaffold(
      // v1.12.3（C-25）：顶部毛玻璃标题栏（KernelSU TopAppBar 样式）。
      contentWindowInsets: EdgeInsets.zero,
      topBar: C25FrostedTopBar(
        title: '设置',
        largeTitle: '设置',
        navigationIcon: _backButton,
        actions: <Widget>[
          // v1.13.0（C-26）：顶部更多菜单。
          C26MoreMenu(backdrop: _topBackdrop),
        ],
        scrollBehavior: _collapse,
        backdrop: _topBackdrop,
      ),
      content: (padding) {
        // v1.12.3：内容避让顶栏（padding.top = topBar 高度）；快照画
        //   surface 底色（KernelSU drawRect 等价）+ 采样 6 帧（功耗优化）。
        final Widget list = ListView.builder(
          // v1.18.x（T1）：列表按下即跟手（DragStartBehavior.down）。
          dragStartBehavior: DragStartBehavior.down,
          padding: EdgeInsets.only(
            top: 12 + padding.top,
            bottom: 24 + throughInset, // 🔧 C-22 内容穿透底部安全间距
          ),
          addAutomaticKeepAlives: false,
          itemCount: 6,
          // v1.14.3：分组卡片间留 16 间距（避免挤在一起）。
          // v1.26.0:新增「内容设置」分组(每日一言 S-21,插在通用组后)。
          itemBuilder: (context, index) => switch (index) {
            0 => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildAppearanceGroup(context, settings, controller),
            ),
            1 => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildGeneralGroup(
                context,
                settings,
                controller,
                effectiveBlur,
                blurReason,
                pageScaleEnabled,
              ),
            ),
            2 => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildContentGroup(context, settings, controller),
            ),
            3 => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildOtherGroup(context),
            ),
            4 => const SizedBox(height: 8),
            _ => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: MiuixText(
                '部分设置在 Web 端自动降级（PROJECT_SPEC §11.7）',
                style: textStyles.body2,
                color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
              ),
            ),
          },
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
              // v1.9.0（S-13）：导出结果对话框（show 布尔驱动，常驻树）。
              MiuixOverlayDialog(
                show: _exportNotice != null || _exportError != null,
                title: _exportError != null ? '导出失败' : '导出成功',
                summary: _exportError ?? _exportNotice ?? '',
                content: const SizedBox.shrink(),
                onDismissRequest: () => setState(() {
                  _exportNotice = null;
                  _exportError = null;
                }),
              ),
              // v1.27.0（C-35）：内容设置悬浮选择窗(API/语言/风格共用)。
              _buildQuoteOptionSheet(context, settings, controller),
              // v1.34.0（P-08）：Steam 查询 UAPI 密钥弹层(输入/清除)。
              SteamKeySheet(
                show: _steamKeySheet,
                onDismissRequest: () => setState(() => _steamKeySheet = false),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 外观组 ──────────────────────────────────────────────

  Widget _buildAppearanceGroup(
    BuildContext context,
    AppSettings settings,
    AppSettingsController controller,
  ) {
    // 🔧 修复：高亮索引由状态实时推导（本方法在每次 ref.watch 重建时重新执行）。
    return C03GroupCard(
      children: [
        // C-13 分段选择器：UI 模式
        // 🔧 修复（P-01-02）：高亮索引 = uiMode 状态映射（indexOf），
        //   点击 → setUiMode → ref.watch(appSettingsProvider) 重建 → 高亮跟随状态；
        //   显式 Key 防止元素复用残留内部状态。
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiuixText(
                'UI 模式',
                style: MiuixTheme.of(context).textStyles.title4,
              ),
              const SizedBox(height: 10),
              MiuixTabRow(
                key: const ValueKey('uiMode'),
                tabs: _uiModeLabels,
                selectedTabIndex: _uiModeValues.indexOf(settings.uiMode),
                onTabSelected: (i) => controller.setUiMode(_uiModeValues[i]),
              ),
            ],
          ),
        ),
        const C03IndentDivider(),
        // 主题与色彩配置入口 → R-09
        MiuixArrowPreference(
          title: '主题与色彩',
          summary: '深色模式 · Monet 动态取色 · 种子色',
          startAction: MiuixIcon(
            vector: appIcon('tune'),
            size: 22,
            tint: MiuixTheme.of(context).colors.primary,
          ),
          insideMargin: _itemMargin,
          onClick: () => context.push('/settings/theme'),
        ),
        const C03IndentDivider(),
        // Monet 总开关（§10.2）
        // 🔧 修复（P-01-02）：显式 Key 固化元素身份——开关内部动画控制器
        //   （_thumbPos）在 initState 读取初始 value，若无 Key，分组重建/复用
        //   时可能残留旧位置；Key 确保 value 变化后 didUpdateWidget 必然触发。
        MiuixSwitchPreference(
          key: const ValueKey('switch.monet'),
          title: 'Monet 动态取色',
          summary: settings.monetEnabled
              ? '已启用（色板由 S-01 一次性生成并缓存）'
              : '使用 Miuix 默认色板',
          value: settings.monetEnabled,
          onChanged: controller.setMonetEnabled,
          insideMargin: _itemMargin,
        ),
      ],
    );
  }

  // ── 通用组 ──────────────────────────────────────────────

  Widget _buildGeneralGroup(
    BuildContext context,
    AppSettings settings,
    AppSettingsController controller,
    bool effectiveBlur,
    String blurReason,
    bool pageScaleEnabled,
  ) {
    // 降级警示：用户开启但平台能力不足（Web / Android<13）时显示（§11.7.4）。
    final bool degraded = settings.blurEnabled && !effectiveBlur;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        C03GroupCard(
          children: [
            // 动效总开关(v1.21.0 更名):原名「毛玻璃效果」——现同时控制
            //   毛玻璃(U-03 裁决;平台不支持时 UI 置灰说明 §11.7.4)与
            //   首页圆环平滑动画(关闭=低性能档,动画直接跳变)。
            // 🔧 修复(P-01-02):显式 Key 固化元素身份(见 switch.monet 注释)。
            MiuixSwitchPreference(
              key: const ValueKey('switch.blur'),
              title: '动效开关',
              summary: !settings.blurEnabled
                  ? '已关闭:毛玻璃与平滑动画均关(更省电)'
                  : (effectiveBlur ? '毛玻璃与平滑动效已开启' : '平滑动效已开启(毛玻璃降级,见下方提示)'),
              value: settings.blurEnabled,
              onChanged: controller.setBlurEnabled,
              insideMargin: _itemMargin,
            ),
            const C03IndentDivider(),
            // 悬浮底栏（C-12）
            // 🔧 修复（P-01-02）：开关经 AppSettingsController.setFloatingBarEnabled
            //   写入 S-01 状态 → P-01 外壳 ref.watch 重建 → C-12 悬浮形态生效；
            //   值由 S-02 持久化，重启恢复。显式 Key 固化元素身份。
            MiuixSwitchPreference(
              key: const ValueKey('switch.floating'),
              title: '悬浮底栏',
              summary: settings.floatingBarEnabled
                  ? '已开启（悬浮胶囊形态）'
                  : '已关闭（通栏形态）',
              value: settings.floatingBarEnabled,
              onChanged: controller.setFloatingBarEnabled,
              insideMargin: _itemMargin,
            ),
            const C03IndentDivider(),
            // 页面缩放（C-15，一次性 Transform，禁带动画）
            // v1.0.1：移动端（Android）禁用拉条——系统缩放修复（R-01 textScaler=1.0）
            // 后，页面缩放仅 Web 生效；禁用时强制 1.0（见 main_shell_page）。
            MiuixSliderPreference(
              title: '页面缩放',
              summary: pageScaleEnabled
                  ? '${(settings.pageScale * 100).round()}%'
                  : '移动端已禁用（仅 Web 可用）',
              value: settings.pageScale,
              min: AppSettings.kPageScaleMin,
              max: AppSettings.kPageScaleMax,
              steps: 8,
              enabled: pageScaleEnabled,
              insideMargin: _itemMargin,
              onValueChange: controller.setPageScale,
            ),
            const C03IndentDivider(),
            // 日志采集（S-13/S-14，v1.9.0）：默认关闭，关闭时零采集零开销（§11.8）。
            MiuixSwitchPreference(
              key: const ValueKey('switch.log'),
              title: '日志采集',
              summary: settings.logCaptureEnabled
                  ? '已开启（运行日志 + 帧性能采样）'
                  : '已关闭（零采集零开销）',
              value: settings.logCaptureEnabled,
              onChanged: controller.setLogCaptureEnabled,
              insideMargin: _itemMargin,
            ),
            const C03IndentDivider(),
            // 导出日志（S-13，v1.9.0）：序列化 → 原生 MediaStore → 公共 Download/。
            MiuixArrowPreference(
              title: '导出日志',
              summary: _exporting ? '导出中…' : '保存运行日志与性能采样到 Download/',
              startAction: MiuixIcon(
                vector: appIcon('share'),
                size: 22,
                tint: MiuixTheme.of(context).colors.primary,
              ),
              insideMargin: _itemMargin,
              onClick: _exportLogs,
            ),
          ],
        ),
        if (degraded) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: C05WarningCard(
              message: '毛玻璃：$blurReason',
              severity: C05WarningSeverity.warning,
            ),
          ),
        ],
      ],
    );
  }

  // ── v1.26.0/v1.27.0 内容设置组（S-21:开关 + API/语言/风格,浮窗选择）──

  Widget _buildContentGroup(
    BuildContext context,
    AppSettings settings,
    AppSettingsController controller,
  ) {
    final QuoteApi api = QuoteApi.fromKey(settings.quoteApi);
    final bool isUapi = api == QuoteApi.uapi;
    // 行显隐矩阵:
    // - 语言行:仅 UAPI(官方 source 中/英过滤;其它 API 语言固定);
    // - 风格行:多风格 API 显示;UAPI 非中文语言按语言源随机 → 隐藏。
    final bool langRow = isUapi;
    final bool styleRow =
        api.supportsStyles && (!isUapi || settings.quoteLang == 'zh');
    return C03GroupCard(
      children: <Widget>[
        // 每日一言总开关:关闭 → 不联网,摘要卡显示本地文案。
        MiuixSwitchPreference(
          key: const ValueKey('switch.quote'),
          title: '每日一言',
          summary: settings.quoteEnabled
              ? '联网获取,约每 45 分钟自动换新(点击可手动刷新)'
              : '已关闭:显示本地文案,不联网',
          value: settings.quoteEnabled,
          onChanged: controller.setQuoteEnabled,
          insideMargin: _itemMargin,
        ),
        // v1.28.0:动态行区(语言/风格行随 API 增减)包 AnimatedSize ——
        //   切换 UAPI 等来源时分组卡高度平滑过渡,不再瞬间跳变(割裂)。
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const C03IndentDivider(),
              // API 来源 → 悬浮选择窗(C-35)。
              _buildContentRow(
                context,
                rowKey: 'api',
                title: 'API 来源',
                valueLabel:
                    kQuoteApiLabels[settings.quoteApi] ?? settings.quoteApi,
                onTap: () => setState(() => _picker = 'api'),
              ),
              if (langRow) ...[
                const C03IndentDivider(),
                _buildContentRow(
                  context,
                  rowKey: 'lang',
                  title: '语言风格',
                  valueLabel:
                      kQuoteLangLabels[settings.quoteLang] ??
                      settings.quoteLang,
                  onTap: () => setState(() => _picker = 'lang'),
                ),
              ],
              if (styleRow) ...[
                const C03IndentDivider(),
                _buildContentRow(
                  context,
                  rowKey: 'style',
                  title: '每日一言风格',
                  valueLabel:
                      kQuoteStyleLabels[settings.quoteStyle] ??
                      settings.quoteStyle,
                  onTap: () => setState(() => _picker = 'style'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 选择行:标题 + 当前值 + 下拉箭头(点击弹悬浮窗,不再内联展开)。
  Widget _buildContentRow(
    BuildContext context, {
    required String rowKey,
    required String title,
    required String valueLabel,
    required VoidCallback onTap,
  }) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    return GestureDetector(
      key: ValueKey<String>('content.$rowKey'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: _itemMargin,
        child: Row(
          children: <Widget>[
            Expanded(
              child: MiuixText(
                title,
                style: textStyles.body1,
                color: colors.onSurface,
              ),
            ),
            Flexible(
              child: MiuixText(
                valueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyles.body1,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
            const SizedBox(width: 4),
            MiuixDropdownArrowEndAction(
              actionColor: colors.onSurfaceVariantSummary,
            ),
          ],
        ),
      ),
    );
  }

  /// 悬浮选择窗实例(常驻树,show 由 [_picker] 驱动;选项随上下文切换)。
  Widget _buildQuoteOptionSheet(
    BuildContext context,
    AppSettings settings,
    AppSettingsController controller,
  ) {
    final QuoteApi api = QuoteApi.fromKey(settings.quoteApi);
    final String? picker = _picker;
    String title = '';
    List<String> options = const <String>[];
    String Function(String) label = (String k) => k;
    String selected = '';
    ValueChanged<String>? apply;
    switch (picker) {
      case 'api':
        title = '选择 API 来源';
        options = kQuoteApiOptions;
        label = (String k) => kQuoteApiLabels[k] ?? k;
        selected = settings.quoteApi;
        apply = controller.setQuoteApi;
      case 'lang':
        title = '语言风格';
        options = kQuoteLangOptions;
        label = (String k) => kQuoteLangLabels[k] ?? k;
        selected = settings.quoteLang;
        apply = controller.setQuoteLang;
      case 'style':
        title = '内容风格';
        options = <String>[for (final QuoteStyle s in api.styles) s.key];
        label = (String k) => kQuoteStyleLabels[k] ?? k;
        selected = settings.quoteStyle;
        apply = controller.setQuoteStyle;
      default:
        break;
    }
    final bool show = picker != null && options.isNotEmpty;
    return QuoteOptionSheet(
      show: show,
      title: title,
      options: options,
      optionLabel: label,
      selected: selected,
      onSelect: (String k) {
        apply?.call(k);
        setState(() => _picker = null);
      },
      onDismissRequest: () => setState(() => _picker = null),
    );
  }

  // ── 其他组 ──────────────────────────────────────────────

  Widget _buildOtherGroup(BuildContext context) {
    // v1.34.0:Steam 查询密钥状态(加密存储;loading 视为未配置)。
    final bool steamKeySet =
        (steamApiKeyOrNull(ref.watch(steamApiKeyProvider)) ?? '').isNotEmpty;
    return C03GroupCard(
      children: [
        // v1.34.0(P-08):Steam 查询 UAPI 密钥(输入/清除,C-39 弹层)。
        MiuixArrowPreference(
          key: const ValueKey('steam.keyRow'),
          title: 'Steam 查询密钥',
          summary: steamKeySet ? '已配置(加密存储)' : '未配置(查询仍可用)',
          startAction: MiuixIcon(
            vector: appIcon('lock'),
            size: 22,
            tint: steamKeySet
                ? const Color(0xFF36D167)
                : MiuixTheme.of(context).colors.primary,
          ),
          insideMargin: _itemMargin,
          onClick: () => setState(() => _steamKeySheet = true),
        ),
        const C03IndentDivider(),
        MiuixArrowPreference(
          title: '色彩调色板',
          summary: '当前主题完整色板（P-02）',
          startAction: MiuixIcon(
            vector: appIcon('theme'),
            size: 22,
            tint: MiuixTheme.of(context).colors.primary,
          ),
          insideMargin: _itemMargin,
          onClick: () => context.push('/color-palette'),
        ),
        const C03IndentDivider(),
        MiuixArrowPreference(
          title: '权限管理',
          summary: '权限声明与状态（P-03）',
          startAction: MiuixIcon(
            vector: appIcon('lock'),
            size: 22,
            tint: MiuixTheme.of(context).colors.primary,
          ),
          insideMargin: _itemMargin,
          onClick: () => context.push('/permissions'),
        ),
        const C03IndentDivider(),
        MiuixArrowPreference(
          title: '关于',
          summary: '版本 · 许可 · 项目链接（P-01-03）',
          startAction: MiuixIcon(
            vector: appIcon('info'),
            size: 22,
            tint: MiuixTheme.of(context).colors.primary,
          ),
          insideMargin: _itemMargin,
          onClick: () => context.go('/about'),
        ),
      ],
    );
  }
}
