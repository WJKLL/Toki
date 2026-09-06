// lib/presentation/widgets/c48_flow_toolbar_v2.dart
// 编号:C-48 流程图悬浮收缩工具栏 · v2(v1.48 阶段3,vyuh 内核适配版)
// 说明:v1.45 C-48(旧内核)的能力集重构 —— 右下悬浮圆钮(与待办/首页
//   FAB 同视觉语言,毛玻璃按 U-03 政策),点击展开功能面板:
//   - 添加区:开始/步骤/判断/结束 2×2 + 泳道(全宽);
//   - 操作区:撤销/重做/删除选中/复制/粘贴(小胶囊流式);
//   - 视图区:适应视图/缩略图(开关态)/简化 LOD(开关态)/图例;
//   - 底部:播放(高亮)+ 导出 HTML 并排;
//   - 动作型点击后面板自动收起;toggle 型同步宿主状态;
//   - 面板与 docked(宽屏三栏常驻卡)共用 body(v1.48 阶段3 批3-3);
//   - collapse() 公开:点画布空白时经 GlobalKey 收起。
// v1.48(收尾 UI·MIUI 语言):FAB 改无底纯图标(删除毛玻璃圆底/阴影,
//   44 热区 19 图标,MIUI 无底化与 C-21 返回键同语言);面板/按钮组
//   背景与图标按 HyperOS 语义角色与圆角微调(节点按钮色点/操作图标化/
//   圆角 22)。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/widgets/app_icons.dart';
import '../../domain/entities/flow_doc.dart';

/// 工具栏使用方回调(页面注入)。
typedef C48V2AddNode = void Function(FlowNodeKind kind);

/// C-48 v2 悬浮收缩工具栏。
class C48FlowToolbarV2 extends StatefulWidget {
  const C48FlowToolbarV2({
    super.key,
    required this.onAddNode,
    required this.onAddLane,
    required this.onUndo,
    required this.onRedo,
    required this.onDeleteSelected,
    required this.onCopy,
    required this.onPaste,
    required this.onFit,
    required this.onLegend,
    required this.onPlay,
    required this.onExportHtml,
    this.onToggleMiniMap,
    this.onToggleLod,
    required this.canUndo,
    required this.canRedo,
    this.hasClip = false,
    this.miniMapOn = false,
    this.lodOn = false,
    this.playing = false,
    this.nodeCount = 0,
    this.visible = true,
    this.docked = false,
  });

  final C48V2AddNode onAddNode;
  final VoidCallback onAddLane;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onDeleteSelected;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onFit;
  final VoidCallback onLegend;
  final VoidCallback onPlay;
  final VoidCallback onExportHtml;
  final VoidCallback? onToggleMiniMap;
  final VoidCallback? onToggleLod;
  final bool canUndo;
  final bool canRedo;
  final bool hasClip;

  /// 视图开关状态(选中高亮;宿主页面持有)。
  final bool miniMapOn;
  final bool lodOn;

  /// 播放中(FAB 隐藏时页面直接不渲染,此参数保留给 docked 态显示)。
  final bool playing;

  /// 节点数(面板底行信息)。
  final int nodeCount;

  /// false = 整体隐藏(播放中/尺寸编辑模式)。
  final bool visible;

  /// 宽屏三段式常驻卡(阶段3 批3-3):无 FAB/无折叠,直接渲染面板卡。
  final bool docked;

  @override
  State<C48FlowToolbarV2> createState() => C48FlowToolbarV2State();
}

/// State 公开:使用方经 GlobalKey 在点画布空白时收起面板。
class C48FlowToolbarV2State extends State<C48FlowToolbarV2> {
  bool _open = false;

  /// 收起面板(幂等;点画布空白/外部操作时调用)。
  void collapse() {
    if (_open) setState(() => _open = false);
  }

  void _toggle() => setState(() => _open = !_open);

  /// 动作执行后收起。
  void _act(VoidCallback cb) {
    cb();
    collapse();
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    if (!widget.visible) return const SizedBox.shrink();
    // docked(宽屏三段式左栏):常驻卡,无 FAB/无折叠。
    if (widget.docked) {
      return Container(
        key: const ValueKey('flow.toolbar.docked'),
        width: 232,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: colors.outline.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: SingleChildScrollView(
            child: _panelBody(colors),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _open
              ? Container(
                  key: const ValueKey('flow.toolbar.panel'),
                  width: 240,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh.withValues(alpha: 0.97),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: colors.outline.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 430),
                    child: SingleChildScrollView(
                      child: _panelBody(colors),
                    ),
                  ),
                )
              : const SizedBox.shrink(
                  key: ValueKey<String>('flow.toolbar.hidden'),
                ),
        ),
        _buildFabButton(context, colors),
      ],
    );
  }

  // ── 悬浮无底圆钮(MIUI 无底化:纯图标 + 圆形按压遮罩;展开态转 ✕)──

  /// 热区边长 / 视觉图标尺寸。
  static const double _kFabSize = 44;
  static const double _kFabIcon = 19;

  Widget _buildFabButton(BuildContext context, MiuixColors colors) {
    return MiuixPressable(
      key: const ValueKey('flow.toolbar.fab'),
      onPressed: _toggle,
      semanticLabel: '编辑工具',
      borderRadius: BorderRadius.circular(_kFabSize / 2),
      child: SizedBox(
        width: _kFabSize,
        height: _kFabSize,
        child: AnimatedRotation(
          turns: _open ? 0.125 : 0, // 45° 旋转:展开=✕。
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: Center(
            child: MiuixIcon(
              vector: _open ? MiuixIcons.basic.close : appIcon('edit'),
              size: _kFabIcon,
              tint: colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  // ── 面板主体(悬浮展开态;docked 常驻卡共用)─────────────────────

  Widget _panelBody(MiuixColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 节点类型 2×2。
        Row(
          children: <Widget>[
            _nodeBtn(colors, FlowNodeKind.start, '开始'),
            const SizedBox(width: 8),
            _nodeBtn(colors, FlowNodeKind.step, '步骤'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            _nodeBtn(colors, FlowNodeKind.decision, '判断'),
            const SizedBox(width: 8),
            _nodeBtn(colors, FlowNodeKind.end, '结束'),
          ],
        ),
        const SizedBox(height: 8),
        _laneBtn(colors),
        const SizedBox(height: 10),
        _divider(colors),
        const SizedBox(height: 8),
        // 操作区(撤销/重做/删除选中/复制/粘贴,图标化)。
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _pill(
              colors,
              appIcon('undo'),
              '撤销',
              widget.canUndo,
              () => _act(widget.onUndo),
            ),
            _pill(
              colors,
              appIcon('redo'),
              '重做',
              widget.canRedo,
              () => _act(widget.onRedo),
            ),
            _pill(
              colors,
              appIcon('delete'),
              '删除选中',
              true,
              () => _act(widget.onDeleteSelected),
            ),
            _pill(
              colors,
              appIcon('copy'),
              '复制',
              true,
              () => _act(widget.onCopy),
            ),
            _pill(
              colors,
              appIcon('paste'),
              '粘贴${widget.hasClip ? '●' : ''}',
              true,
              () => _act(widget.onPaste),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _divider(colors),
        const SizedBox(height: 8),
        // 视图区。
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _viewPill(colors, '适应', IconsView.fit, false, () {
              _act(widget.onFit);
            }),
            _viewPill(
              colors,
              '缩略图',
              IconsView.grid,
              widget.miniMapOn,
              () => _act(widget.onToggleMiniMap ?? () {}),
            ),
            _viewPill(
              colors,
              '简化',
              IconsView.lod,
              widget.lodOn,
              () => _act(widget.onToggleLod ?? () {}),
            ),
            _viewPill(colors, '图例', IconsView.legend, false, () {
              _act(widget.onLegend);
            }),
          ],
        ),
        const SizedBox(height: 10),
        _divider(colors),
        const SizedBox(height: 8),
        // 播放 + 导出(图标化)。
        Row(
          children: <Widget>[
            Expanded(
              child: _bigBtn(
                colors,
                icon: appIcon('play'),
                label: '播放',
                primary: true,
                onTap: () => _act(widget.onPlay),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _bigBtn(
                colors,
                icon: appIcon('share'),
                label: '导出',
                primary: false,
                onTap: () => _act(widget.onExportHtml),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        MiuixText(
          '${widget.nodeCount} 节点 · 添加后画布可拖动/连线',
          fontSize: 10,
          color: colors.onSurfaceVariantSummary,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _divider(MiuixColors colors) => Container(
        height: 0.5,
        color: colors.outline.withValues(alpha: 0.3),
      );

  /// 节点语义色(与 vyuh_flow_theme.kindAccent 同规则;widgets 层内联,
  /// 避免跨层依赖)。
  Color _kindColor(MiuixColors colors, FlowNodeKind kind) =>
      switch (kind) {
        FlowNodeKind.start => colors.primary,
        FlowNodeKind.decision => colors.secondary,
        FlowNodeKind.end => colors.error,
        FlowNodeKind.step || FlowNodeKind.lane => colors.onSurfaceVariantSummary,
      };

  /// 节点添加按钮(2×2 网格项;色点 + 文字,MIUI 工具块语言)。
  Widget _nodeBtn(MiuixColors colors, FlowNodeKind kind, String label) {
    final Color dot = _kindColor(colors, kind);
    return Expanded(
      child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.94,
        borderRadius: BorderRadius.circular(12),
        onPressed: () => _act(() => widget.onAddNode(kind)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              MiuixText(
                label,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colors.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _laneBtn(MiuixColors colors) {
    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.94,
      borderRadius: BorderRadius.circular(12),
      onPressed: () => _act(widget.onAddLane),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            MiuixIcon(
              vector: appIcon('gridView'),
              size: 13,
              tint: colors.primary,
            ),
            const SizedBox(width: 6),
            MiuixText(
              '泳道分区',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colors.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  /// 小胶囊(操作区;图标 + 文字;disabled 灰)。
  Widget _pill(
    MiuixColors colors,
    MiuixVectorIcon icon,
    String label,
    bool enabled,
    VoidCallback onTap,
  ) {
    final Color fg = enabled ? colors.onSurface : colors.disabledOnSurface;
    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.9,
      borderRadius: BorderRadius.circular(999),
      onPressed: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: enabled
              ? colors.surfaceContainerHighest
              : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            MiuixIcon(vector: icon, size: 12, tint: fg),
            const SizedBox(width: 4),
            MiuixText(
              label,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ],
        ),
      ),
    );
  }

  /// 视图胶囊(选中态高亮)。
  Widget _viewPill(
    MiuixColors colors,
    String label,
    IconsView icon,
    bool on,
    VoidCallback onTap,
  ) {
    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.9,
      borderRadius: BorderRadius.circular(999),
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: on
              ? colors.primary.withValues(alpha: 0.14)
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: on ? Border.all(color: colors.primary, width: 1.2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != IconsView.none) ...<Widget>[
              MiuixIcon(
                vector: switch (icon) {
                  IconsView.grid => appIcon('gridView'),
                  IconsView.lod => appIcon('layers'),
                  IconsView.legend => appIcon('info'),
                  _ => appIcon('info'),
                },
                size: 12,
                tint: on ? colors.primary : colors.onSurfaceVariantActions,
              ),
              const SizedBox(width: 5),
            ],
            MiuixText(
              label,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: on ? colors.primary : colors.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigBtn(
    MiuixColors colors, {
    required MiuixVectorIcon icon,
    required String label,
    required bool primary,
    required VoidCallback onTap,
  }) {
    final Color fg =
        primary ? colors.onPrimary : colors.onSecondaryContainer;
    final Color bg = primary ? colors.primary : colors.secondaryContainer;
    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.94,
      borderRadius: BorderRadius.circular(12),
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            MiuixIcon(vector: icon, size: 13, tint: fg),
            const SizedBox(width: 5),
            MiuixText(
              label,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ],
        ),
      ),
    );
  }
}

/// 视图胶囊图标类型。
enum IconsView { none, fit, grid, lod, legend }
