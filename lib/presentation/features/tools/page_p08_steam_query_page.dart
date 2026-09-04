// lib/presentation/features/tools/page_p08_steam_query_page.dart
// 编号：P-08 Steam 用户查询页（v1.34.0 新增;路由 R-11 /steam）
// 说明：UAPI Steam 公开摘要查询 —— 四态机(idle / loading / success / error):
//   - 输入卡:徽标(C-38)+ 输入框(MiuixTextField,悬浮标签)+ 全宽查询按钮
//     (MiuixButton 主色;空输入/加载中禁用)+ 凭证状态行(未配置提示 +
//     点击打开 C-39 密钥弹层)+ 识别格式帮助小字(4 格式);
//   - 成功卡:头像 48 圆(网络图,失败回退徽标)+ 昵称 + 状态胶囊
//     (0 灰/1 绿/2 红/3-4 橙/5-6 蓝,自绘圆点胶囊)+ 国家 + 详情行
//     (实名/资料可见性/SteamID64/ID3/注册日期/国家;行值点击复制 +
//     MiniToast)+ 打开资料页按钮(url_launcher 外开);
//   - 失败:错误文案 + 重试(输入保留);
//   - 凭证:key 可选(C-39 弹层配置,加密存储;查询自动携带)。
// 转场/响应式:二级页统一转场由路由 _pageFor 提供;内容 maxWidth 居中(宽屏)。
import 'dart:async' show unawaited;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/tools/steam_api_service.dart';
import '../../../core/utils/u03_blur_policy.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/c03_group_card.dart';
import '../../../core/widgets/mini_toast.dart';
import '../../../core/widgets/steam_logo_icon.dart';
import '../../../domain/entities/steam_user.dart';
import '../../providers/platform_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/steam_providers.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c22_backdrop_heartbeat.dart';
import '../../widgets/c28_downsampled_capture.dart';
import '../../widgets/c22_content_through_floating_bottom_bar.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c39_steam_key_sheet.dart';

/// 页面阶段。
enum _SteamPhase { idle, loading, success, error }

/// 状态胶囊配色(用户验收映射:0 灰/1 绿/2 红/3-4 橙/5-6 蓝)。
Color _stateColor(int state) {
  return switch (state) {
    1 => const Color(0xFF36D167), // 在线 · 绿
    2 => const Color(0xFFE5484D), // 忙碌 · 红
    3 || 4 => const Color(0xFFFFB21D), // 离开/打盹 · 橙
    5 || 6 => const Color(0xFF3482FF), // 想交易/想玩 · 蓝
    _ => const Color(0xFF8A8F99), // 离线/未知 · 灰
  };
}

class PageP08SteamQueryPage extends ConsumerStatefulWidget {
  const PageP08SteamQueryPage({super.key});

  @override
  ConsumerState<PageP08SteamQueryPage> createState() =>
      _PageP08SteamQueryPageState();
}

class _PageP08SteamQueryPageState extends ConsumerState<PageP08SteamQueryPage> {
  late final Widget _backButton = C21CapsuleIconButton(
    key: const ValueKey('steam.back'),
    icon: appIcon('chevronBackward'),
    tooltip: '返回',
    onTap: () => Navigator.of(context).maybePop(),
  );

  final TextEditingController _input = TextEditingController();
  _SteamPhase _phase = _SteamPhase.idle;
  SteamUser? _user;
  String? _errorText;
  bool _keySheet = false;

  // ── C-25:顶部毛玻璃快照源 + 折叠滚动行为 ──
  MiuixLayerBackdrop? _topBackdrop;
  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

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
    _input.dispose();
    _topBackdrop?.dispose();
    super.dispose();
  }

  bool get _busy => _phase == _SteamPhase.loading;

  Future<void> _submit() async {
    if (_busy) return;
    final String input = _input.text;
    if (input.trim().isEmpty) return;
    setState(() {
      _phase = _SteamPhase.loading;
      _errorText = null;
    });
    try {
      // 实时读凭证(加密存储),未配置 → null(匿名可用)。
      final String? key = await ref.read(steamAuthServiceProvider).readApiKey();
      final SteamUser user = await ref
          .read(steamApiServiceProvider)
          .fetchSummary(input: input, apiKey: key);
      if (!mounted) return;
      setState(() {
        _user = user;
        _phase = _SteamPhase.success;
      });
    } on SteamFetchException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e.error.message;
        _phase = _SteamPhase.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = '查询失败,请稍后重试';
        _phase = _SteamPhase.error;
      });
    }
  }

  void _copy(BuildContext context, String text) {
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    showMiniToast(context, '已复制');
  }

  Future<void> _openProfile(SteamUser user) async {
    final Uri? uri = Uri.tryParse(user.profileurl);
    if (uri == null) return;
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showMiniToast(context, '无法打开浏览器');
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final PlatformInfo platform = ref.watch(platformInfoProvider);
    final bool topBlurAllowed = U03BlurPolicy.allowBlur(
      userEnabled: ref.watch(appSettingsProvider.select((s) => s.blurEnabled)),
      isWeb: platform.isWeb,
      androidSdkInt: platform.androidSdkInt,
    );
    _syncTopBackdrop(topBlurAllowed);
    final double throughInset =
        ref.watch(appSettingsProvider).floatingBarEnabled
        ? C22ContentThroughFloatingBottomBar.contentBottomInset(context)
        : 0.0;

    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      topBar: C25FrostedTopBar(
        title: 'Steam 用户',
        largeTitle: 'Steam 用户',
        navigationIcon: _backButton,
        scrollBehavior: _collapse,
        backdrop: _topBackdrop,
      ),
      content: (padding) {
        // 宽屏内容居中(maxWidth 约束,与全 App 响应式语言一致)。
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
                _buildInputCard(context),
                const SizedBox(height: 16),
                ..._buildStateArea(context),
              ],
            ),
          ),
        );
        final Widget listWithBg = ColoredBox(
          color: colors.surface,
          child: page,
        );
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
              // 凭证弹层(C-39;show 布尔驱动,false 零开销)。
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

  // ── 输入卡(idle/loading/error 常驻,供输入与重试)──────────────────

  Widget _buildInputCard(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final bool hasKey =
        (steamApiKeyOrNull(ref.watch(steamApiKeyProvider)) ?? '').isNotEmpty;
    final bool idle = _phase == _SteamPhase.idle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: C03GroupCard(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 徽标 + 标题区(idle 大号,水平居中)。
                if (idle) ...[
                  Center(
                    child: SteamLogoIcon(size: 48, tint: colors.primary),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: MiuixText(
                      '查询 Steam 用户公开资料',
                      style: textStyles.title4.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: MiuixText(
                      '粘贴 SteamID / ID3 / 资料页链接 / 自定义 URL',
                      style: textStyles.body2,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                MiuixTextField(
                  key: const ValueKey('steam.input'),
                  controller: _input,
                  label: '输入 Steam 标识或链接',
                  useLabelAsPlaceholder: true,
                  singleLine: true,
                  enabled: !_busy,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                // 全宽主按钮(文字色由按钮内容色注入:禁用自动切换)。
                MiuixButton(
                  key: const ValueKey('steam.submit'),
                  onPressed: _busy || _input.text.trim().isEmpty
                      ? null
                      : _submit,
                  colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                  child: MiuixText(
                    _busy ? '查询中…' : '查询 · 消耗 2 积分',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 6),
                // 凭证状态行(点击配置;整行热区)。
                GestureDetector(
                  key: const ValueKey('steam.keyRow'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _keySheet = true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        MiuixIcon(
                          vector: hasKey
                              ? MiuixIcons.basic.check
                              : appIcon('lock'),
                          size: 13,
                          tint: hasKey
                              ? const Color(0xFF36D167)
                              : colors.onSurfaceVariantSummary,
                        ),
                        const SizedBox(width: 6),
                        MiuixText(
                          hasKey ? '密钥已配置(加密存储)' : '未配置 UAPI 密钥 · 点击配置',
                          style: textStyles.footnote1,
                          color: hasKey
                              ? const Color(0xFF36D167)
                              : colors.onSurfaceVariantSummary,
                        ),
                      ],
                    ),
                  ),
                ),
                // 识别格式帮助小字。
                if (idle)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SizedBox(height: 4),
                        _helpLine(context, '17 位纯数字 → SteamID64'),
                        _helpLine(context, 'STEAM_x:y:z → ID3'),
                        _helpLine(context, 'steamcommunity.com 链接 → 直接粘贴'),
                        _helpLine(context, '其它 → 自定义 URL / 好友代码'),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _helpLine(BuildContext context, String text) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 3,
            margin: const EdgeInsets.only(right: 8, left: 2),
            decoration: BoxDecoration(
              color: colors.onSurfaceVariantSummary,
              shape: BoxShape.circle,
            ),
          ),
          MiuixText(
            text,
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
          ),
        ],
      ),
    );
  }

  // ── 状态区(loading / success / error)─────────────────────────

  List<Widget> _buildStateArea(BuildContext context) {
    return switch (_phase) {
      _SteamPhase.idle => const <Widget>[],
      _SteamPhase.loading => <Widget>[
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
                '查询中…',
                style: MiuixTheme.of(context).textStyles.body2,
                color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
              ),
            ],
          ),
        ),
      ],
      _SteamPhase.error => <Widget>[
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
                      '查询失败',
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
                      key: const ValueKey('steam.retry'),
                      onPressed: _submit,
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
      _SteamPhase.success => <Widget>[_buildResultCard(context)],
    };
  }

  // ── 成功卡 ─────────────────────────────────────────────────

  Widget _buildResultCard(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MiuixTextStyles textStyles = MiuixTheme.of(context).textStyles;
    final SteamUser user = _user!;
    final SteamUserState state = SteamUserState.of(user.personaState);
    final Color stateColor = _stateColor(user.personaState);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 头部:头像 + 昵称 + 状态。
          C03GroupCard(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: <Widget>[
                    ClipOval(
                      child: Image.network(
                        user.avatarMedium.isEmpty
                            ? user.avatarFull
                            : user.avatarMedium,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, _, _) => Container(
                              width: 48,
                              height: 48,
                              color: colors.surfaceContainerHigh,
                              child: SteamLogoIcon(
                                size: 26,
                                tint: colors.onSurfaceVariantActions,
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          MiuixText(
                            user.personaname.isEmpty
                                ? '未设置昵称'
                                : user.personaname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyles.title4.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              _stateChip(context, state, stateColor),
                              if (user.countryCode != null) ...[
                                const SizedBox(width: 8),
                                MiuixText(
                                  user.countryCode!,
                                  fontSize: 12,
                                  color: colors.onSurfaceVariantSummary,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 详情行组。
          C03GroupCard(
            children: <Widget>[
              if (user.realNameOrNull != null)
                _detailRow(
                  context,
                  label: '实名',
                  value: user.realNameOrNull!,
                ),
              _detailRow(
                context,
                label: '资料可见',
                value: user.isPublic ? '公开' : '私密',
              ),
              _detailRow(
                context,
                label: 'SteamID64',
                value: user.steamid,
                copyable: true,
              ),
              if (user.steamid3.isNotEmpty)
                _detailRow(
                  context,
                  label: 'ID3',
                  value: user.steamid3,
                  copyable: true,
                ),
              if (user.createdDate.isNotEmpty)
                _detailRow(context, label: '注册时间', value: user.createdDate),
            ],
          ),
          const SizedBox(height: 12),
          // 打开资料页。
          C03GroupCard(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: MiuixButton(
                  key: const ValueKey('steam.openProfile'),
                  onPressed: () => _openProfile(user),
                  colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      MiuixIcon(vector: appIcon('link'), size: 16),
                      const SizedBox(width: 8),
                      const MiuixText('打开 Steam 资料页'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          MiuixText(
            '数据来源:UAPI · ${AppConstants.appName}',
            textAlign: TextAlign.center,
            fontSize: 11,
            color: colors.onSurfaceVariantSummary,
          ),
        ],
      ),
    );
  }

  Widget _stateChip(
    BuildContext context,
    SteamUserState state,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          MiuixText(
            state.label,
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    BuildContext context, {
    required String label,
    required String value,
    bool copyable = false,
  }) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: copyable ? () => _copy(context, value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 72,
              child: MiuixText(
                label,
                fontSize: 12,
                color: colors.onSurfaceVariantSummary,
              ),
            ),
            Expanded(
              child: MiuixText(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MiuixTheme.of(context).textStyles.body2.copyWith(
                  color: colors.onSurface,
                ),
              ),
            ),
            if (copyable) ...<Widget>[
              const SizedBox(width: 4),
              MiuixIcon(
                vector: appIcon('copy'),
                size: 15,
                tint: colors.onSurfaceVariantActions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
