// === 文件: lib/presentation/features/tools/page_p09_tool_generic.dart ===
// 编号：P-09 通用工具页（v1.35.0 新增;路由 R-12 /tool/:toolId）
// 说明：UAPI 通用工具的统一二级页 —— 配置全来自 tools.json，新增工具
//   零代码（复用率目标 >90%）。整合:
//   - C-40 动态参数输入（有参工具空闲态等提交）;
//   - ToolApiService 统一调用（GET/POST、key 可选、并发/去重）;
//   - C-41 结果展示（displayType 分发:image 两态/text/keyValue/list/json）;
//   - 凭证行:UAPI key 可选(匿名可用),点击打开 C-39 密钥弹层(与 P-08 共用);
//   - 无参工具进页**自动请求一次**,成功后按钮变「刷新」;
//   - 四态机 idle/loading/success/error(与 P-08 同模式)。
// 转场/响应式:二级页转场由路由 _pageFor 提供;内容 maxWidth 560 居中
//   (与 P-08 一致,全局单列语言)。
import 'dart:async' show unawaited;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/tools/tool_api_service.dart';
import '../../../core/tools/tool_catalog_store.dart';
import '../../../core/utils/u03_blur_policy.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/c03_group_card.dart';
import '../../../core/widgets/mini_toast.dart';
import '../../../core/widgets/tool_brand_icon.dart';
import '../../../domain/entities/tool_config.dart';
import '../../providers/platform_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/steam_providers.dart';
import '../../providers/tool_items_provider.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c22_backdrop_heartbeat.dart';
import '../../widgets/c28_downsampled_capture.dart';
import '../../widgets/c22_content_through_floating_bottom_bar.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c39_steam_key_sheet.dart';
import '../../widgets/c40_tool_dynamic_params.dart';
import '../../widgets/c41_tool_result_display.dart';

/// 页面阶段。
enum _ToolPhase { idle, loading, success, error }

/// P-09 通用工具页（toolId 由 R-12 路由参数注入）。
class PageP09ToolGenericPage extends ConsumerStatefulWidget {
  const PageP09ToolGenericPage({super.key, required this.toolId});

  final String toolId;

  @override
  ConsumerState<PageP09ToolGenericPage> createState() =>
      _PageP09ToolGenericPageState();
}

class _PageP09ToolGenericPageState
    extends ConsumerState<PageP09ToolGenericPage> {
  late final Widget _backButton = C21CapsuleIconButton(
    key: const ValueKey('tool.back'),
    icon: appIcon('chevronBackward'),
    tooltip: '返回',
    onTap: () => Navigator.of(context).maybePop(),
  );

  ToolConfig? _tool;
  _ToolPhase _phase = _ToolPhase.idle;
  Map<String, String> _values = <String, String>{};
  ToolApiResult? _result;
  String? _errorText;
  bool _keySheet = false;

  // ── C-25:顶部毛玻璃快照源 + 折叠滚动行为 ──
  MiuixLayerBackdrop? _topBackdrop;
  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

  @override
  void initState() {
    super.initState();
    _tool = ToolCatalogStore.instance.byIdSync(widget.toolId);
    // v1.38.1:不再预填 defaultValue(输入框空、提交时兜底,见 _submit);
    // select 默认选中在 C-40 内部维护,提交兜底同覆盖。
    // 无参工具:进页自动请求一次(首帧后,目录已预加载)。
    if ((_tool?.params.isEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _phase == _ToolPhase.idle) {
          unawaited(_submit(auto: true));
        }
      });
    }
  }

  @override
  void dispose() {
    _topBackdrop?.dispose();
    super.dispose();
  }

  bool get _busy => _phase == _ToolPhase.loading;
  bool get _hasResult => _result != null && _phase == _ToolPhase.success;

  void _syncTopBackdrop(bool enabled) {
    if (enabled && _topBackdrop == null) {
      _topBackdrop = MiuixLayerBackdrop();
    } else if (!enabled && _topBackdrop != null) {
      _topBackdrop!.dispose();
      _topBackdrop = null;
    }
  }

  /// 提交请求（values 空值过滤交给 Service）。
  Future<void> _submit({bool auto = false}) async {
    if (_busy) return;
    final ToolConfig tool = _tool!;
    setState(() {
      _phase = _ToolPhase.loading;
      _errorText = null;
    });
    try {
      // 实时读 UAPI key（加密存储,与 P-08 同款;匿名可用）。
      final String? key = await ref.read(steamAuthServiceProvider).readApiKey();
      // v1.38.1:空值参数兜底 defaultValue(text 框不再预填,留空即用默认)。
      final Map<String, String> send = Map<String, String>.of(_values);
      for (final ToolParam p in tool.params) {
        final String v = send[p.name] ?? '';
        if (v.trim().isEmpty && p.defaultValue != null) {
          send[p.name] = p.defaultValue!;
        }
      }
      final ToolApiResult result = await ref
          .read(toolApiServiceProvider)
          .call(tool: tool, values: send, apiKey: key);
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _ToolPhase.success;
      });
    } on ToolApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.message;
        _phase = _ToolPhase.error;
      });
      if (e.error == ToolApiError.needsKey) {
        showMiniToast(context, '该工具需要 UAPI 密钥，请先配置');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = '请求失败，请稍后重试';
        _phase = _ToolPhase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ToolConfig? tool = _tool;
    final PlatformInfo platform = ref.watch(platformInfoProvider);
    final bool topBlurAllowed = U03BlurPolicy.allowBlur(
      userEnabled: ref.watch(appSettingsProvider.select((s) => s.blurEnabled)),
      isWeb: platform.isWeb,
      androidSdkInt: platform.androidSdkInt,
    );
    _syncTopBackdrop(topBlurAllowed);
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final double throughInset =
        ref.watch(appSettingsProvider).floatingBarEnabled
        ? C22ContentThroughFloatingBottomBar.contentBottomInset(context)
        : 0.0;

    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      topBar: C25FrostedTopBar(
        title: tool?.name ?? '工具',
        largeTitle: tool?.name ?? '工具',
        navigationIcon: _backButton,
        scrollBehavior: _collapse,
        backdrop: _topBackdrop,
      ),
      content: (padding) {
        final Widget page = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              dragStartBehavior: DragStartBehavior.down,
              padding: EdgeInsets.only(
                top: 12 + padding.top,
                bottom: 24 + throughInset,
              ),
              addAutomaticKeepAlives: false,
              children: <Widget>[
                if (tool == null)
                  _buildMissing(context)
                else ...[
                  _buildInfoCard(context, tool),
                  const SizedBox(height: 12),
                  if (tool.params.isNotEmpty) ...[
                    _buildInputCard(context, tool),
                    const SizedBox(height: 16),
                  ],
                  ..._buildStateArea(context, tool),
                ],
              ],
            ),
          ),
        );
        final Widget listWithBg = ColoredBox(color: colors.surface, child: page);
        final Widget captured = _topBackdrop != null
            ? C28DownsampledCapture(
                backdrop: _topBackdrop!,
                child: CaptureHeartbeat(everyNFrames: 4, child: listWithBg),
              )
            : listWithBg;
        return Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: MiuixScrollBehaviorListener(
                  behavior: _collapse,
                  child: captured,
                ),
              ),
              // UAPI 密钥弹层(C-39 复用;show 布尔驱动)。
              SteamKeySheet(
                show: _keySheet,
                onDismissRequest: () => setState(() => _keySheet = false),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMissing(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 60),
      child: Center(
        child: MiuixText(
          '工具不存在或已下架',
          style: MiuixTheme.of(context).textStyles.body2,
          color: colors.onSurfaceVariantSummary,
        ),
      ),
    );
  }

  // ── 输入卡:徽标 + 名称 + 说明 + C-40 + 按钮 + 凭证行 ──────────

  Widget _buildInfoCard(BuildContext context, ToolConfig tool) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final bool idle = _phase == _ToolPhase.idle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: C03GroupCard(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (idle || tool.params.isNotEmpty) ...[
                  Row(
                    children: <Widget>[
                      ToolBrandIcon(
                        tool: tool,
                        size: 40,
                        tint: colors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            MiuixText(
                              tool.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ts.title4.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            MiuixText(
                              tool.summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ts.body2,
                              color: colors.onSurfaceVariantSummary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                // C-40 动态参数(有参工具)。
                if (tool.params.isNotEmpty)
                  C40ToolDynamicParams(
                    params: tool.params,
                    onChanged: (Map<String, String> v) => _values = v,
                  ),
                const SizedBox(height: 14),
                // 全宽主按钮(文字色由按钮内容色注入:禁用自动切换)。
                MiuixButton(
                  key: const ValueKey('tool.submit'),
                  onPressed: _busy ? null : () => _submit(),
                  colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                  child: MiuixText(
                    _buttonLabel(tool),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 6),
                // 凭证状态行(点击配置;整行热区)。
                _buildKeyRow(context),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _buttonLabel(ToolConfig tool) {
    if (_busy) return '请求中…';
    if (_hasResult) return '🔄 刷新 · 消耗 ${tool.costCredits} 积分';
    return tool.params.isEmpty
        ? '获取 · 消耗 ${tool.costCredits} 积分'
        : '查询 · 消耗 ${tool.costCredits} 积分';
  }

  Widget _buildInputCard(BuildContext context, ToolConfig tool) {
    // 与 Steam P-08 的输入卡同体系：参数输入已并入 _buildInfoCard，
    // 此处为未来扩展预留（区分「说明区」与「提交区」视觉层次）。
    return const SizedBox.shrink();
  }

  Widget _buildKeyRow(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles ts = MiuixTheme.of(context).textStyles;
    final bool hasKey =
        (steamApiKeyOrNull(ref.watch(steamApiKeyProvider)) ?? '').isNotEmpty;
    return GestureDetector(
      key: const ValueKey('tool.keyRow'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _keySheet = true),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            MiuixIcon(
              vector: hasKey ? MiuixIcons.basic.check : appIcon('lock'),
              size: 13,
              tint: hasKey
                  ? const Color(0xFF36D167)
                  : colors.onSurfaceVariantSummary,
            ),
            const SizedBox(width: 6),
            MiuixText(
              hasKey ? 'UAPI 密钥已配置(加密存储)' : '未配置 UAPI 密钥 · 点击配置',
              style: ts.footnote1,
              color: hasKey
                  ? const Color(0xFF36D167)
                  : colors.onSurfaceVariantSummary,
            ),
          ],
        ),
      ),
    );
  }

  // ── 状态区(loading / error / success)─────────────────────────

  List<Widget> _buildStateArea(BuildContext context, ToolConfig tool) {
    return switch (_phase) {
      _ToolPhase.idle => const <Widget>[],
      _ToolPhase.loading => <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: <Widget>[
              MiuixInfiniteProgressIndicator(
                color: MiuixTheme.of(context).colors.primary,
                size: 30,
              ),
              const SizedBox(height: 14),
              MiuixText(
                '请求中…',
                style: MiuixTheme.of(context).textStyles.body2,
                color:
                    MiuixTheme.of(context).colors.onSurfaceVariantSummary,
              ),
            ],
          ),
        ),
      ],
      _ToolPhase.error => <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: C03GroupCard(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
                child: Column(
                  children: <Widget>[
                    MiuixIcon(
                      vector: appIcon('info'),
                      size: 30,
                      tint: MiuixTheme.of(context).colors.error,
                    ),
                    const SizedBox(height: 10),
                    MiuixText(
                      '请求失败',
                      style: MiuixTheme.of(context).textStyles.title4,
                      color: MiuixTheme.of(context).colors.onSurface,
                    ),
                    const SizedBox(height: 6),
                    MiuixText(
                      _errorText ?? '请稍后重试',
                      textAlign: TextAlign.center,
                      style: MiuixTheme.of(context).textStyles.body2,
                      color:
                          MiuixTheme.of(context).colors.onSurfaceVariantSummary,
                    ),
                    const SizedBox(height: 14),
                    MiuixButton(
                      key: const ValueKey('tool.retry'),
                      onPressed: _busy ? null : () => _submit(),
                      colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                      child: const MiuixText('重试'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      _ToolPhase.success => <Widget>[
        if (_result != null) C41ToolResultDisplay(tool: tool, result: _result!),
        const SizedBox(height: 4),
        MiuixText(
          '数据来源:UAPI · ${AppConstants.appName}',
          textAlign: TextAlign.center,
          fontSize: 11,
          color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
        ),
      ],
    };
  }
}
