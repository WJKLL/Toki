// lib/presentation/features/wallpaper/page_p24_spatial_wallpaper_page.dart
// 编号：P-24 空间壁纸编辑器（R-20 /spatial-wallpaper）
//
// 阶段 1 雏形（2026-09-11）：打通【图片 + 深度图 → 视差渲染 → 焦点设定】链路。
// 深度来源暂用 U-12 预设景深模板（决策 B4），AI 深度推理（S-31）尚未接入 ——
// 这样渲染链路可以独立验证，不必等推理运行时选型。
//
// 交互（对齐规格书 §3.3.1）：
//   单击画面 → 该点成为焦点（该层像素"钉住"不动）
//   拖拽画面 → 焦点连续跟随手指移动
//   "自动晃动"开关 → 用正弦轨迹模拟陀螺仪输入（U-08 的 RecordingInputSource 雏形），
//                    让视差效果无需真实传感器即可看到
import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/depth/depth_inference.dart';
import '../../../core/depth/depth_layer_splitter.dart';
import '../../../core/depth/depth_post_process.dart';
import '../../../core/depth/onnx_depth_inference.dart';
import '../../../core/platform/contract/plat_file_ops.dart';
import '../../../core/wallpaper/depth_template_renderer.dart';
import '../../../domain/entities/depth_template.dart';
import '../../../core/widgets/app_icons.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c26_more_menu.dart';
import '../../widgets/kernel/layered_parallax_view.dart';
import '../../widgets/kernel/parallax_view.dart';

class PageP24SpatialWallpaperPage extends ConsumerStatefulWidget {
  const PageP24SpatialWallpaperPage({super.key});

  @override
  ConsumerState<PageP24SpatialWallpaperPage> createState() =>
      _PageP24SpatialWallpaperPageState();
}

class _PageP24SpatialWallpaperPageState
    extends ConsumerState<PageP24SpatialWallpaperPage>
    with SingleTickerProviderStateMixin {
  /// 组内项统一紧凑内边距（static const，§11.2 静态配置）。
  static const EdgeInsets _itemMargin = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 12,
  );

  // ── 资源 ────────────────────────────────────────────────
  ui.Image? _photo;
  ui.Image? _depth;

  /// 原图字节：AI 深度推理需要原始字节重新做 letterbox 预处理。
  Uint8List? _photoBytes;

  /// S-31 状态：当前深度是否来自 AI（false = 预设模板）。
  bool _aiDepth = false;
  bool _aiBusy = false;
  String _aiInfo = '';

  /// AI 原始推理结果（保留一份：调「主体平滑」时无需重新推理）。
  DepthResult? _aiResult;

  /// 分层结果。**非空 = 走「分层 + 图层平移」渲染**（无拖影）；
  /// 空 = 回退到 shader 逐像素位移（几何模板，或分层失败）。
  DepthLayerSet? _layerSet;

  /// 分层数 2~6。默认 2：主体 / 背景两块 —— 边界只有一条，最不容易出现
  /// "多层叠加发白"与"画面被切成几条"的问题；要更细的纵深再往上调。
  int _layerCount = 2;

  /// 主体平滑强度 0..1（U-12 保边平滑）。
  double _smooth = 0.45;

  // ── 参数 ────────────────────────────────────────────────
  DepthTemplate _template = DepthTemplate.presets.first;
  Offset _focusUv = const Offset(0.5, 0.5);
  double _focus = 0.5; // 焦点深度（0 = 最远，1 = 最近）
  /// 视差强度（逻辑像素）：**直接就是最大位移量**。
  ///
  /// ⚠️ 历史上这里与「晃动幅度」双重缩放（14 × 0.55 ≈ 7.7 px），使主体与背景的
  ///    实际位移差只有 2~4 px —— 观感上就是"主体区分不清"。现已合并为单一像素值。
  /// 默认 12：市面成熟空间壁纸的视差是"轻微"的；26px 在 380dp 宽的屏上已达
  ///    屏宽 6.8%，分层错位会非常刺眼。
  double _amount = 12;
  double _gamma = 1.0; // 深度曲线
  double _layers = 4; // 深度分层数（<=1 = 关闭）—— 仅几何模板需要
  double _focusBand = 0.12; // 焦点带宽度：主体整片钉住，向外平滑过渡
  bool _showDepth = false;
  bool _autoWobble = true;
  bool _busy = false;

  late final AnimationController _ticker;

  final MiuixExitUntilCollapsedScrollBehavior _collapse =
      MiuixExitUntilCollapsedScrollBehavior();

  late final Widget _backButton = C21CapsuleIconButton(
    key: const ValueKey<String>('wallpaper.back'),
    icon: appIcon('chevronBackward'),
    tooltip: '返回',
    onTap: () => Navigator.of(context).maybePop(),
  );

  @override
  void initState() {
    super.initState();
    // S-31：注册 ONNX 实现。鸿蒙不注册 → isAvailable() 为 false →
    // 页面自动停留在预设景深模板，不会抛异常。
    DepthInferenceRegistry.register(OnnxDepthInference.instance);
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    if (_autoWobble) _ticker.repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _layerSet?.dispose();
    _depth?.dispose();
    _photo?.dispose();
    super.dispose();
  }

  // ── 晃动轨迹（U-08 RecordingInputSource 雏形）──────────────
  // 双轴异频正弦：避免两轴同步导致"直线往复"的呆板感。
  Offset _shiftAt(double t) {
    final double a = t * 2 * math.pi;
    // 只返回【单位方向】—— 幅度由 uAmount（像素）承担，避免双重缩放。
    return Offset(math.sin(a), math.cos(a * 0.72) * 0.62);
  }

  // ── 导入图片 ────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final PlatPickedFile? f =
          await PlatFileOpsRegistry.instance.pickImage();
      if (f == null) return;
      final ui.Image img = await decodeImageFromList(f.bytes);
      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() {
        _photo?.dispose();
        _photo = img;
        _photoBytes = f.bytes;
        _aiDepth = false;
        _aiInfo = '';
        _layerSet?.dispose();
        _layerSet = null;
      });
      await _rebuildDepth();
    } catch (e) {
      debugPrint('🔴 空间壁纸: 导入图片失败 $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 按【图片宽高比】生成深度图 —— 否则径向模板在非方形画面上会被拉成椭圆。
  Future<void> _rebuildDepth() async {
    final ui.Image? photo = _photo;
    if (photo == null) return;
    const int base = 256;
    final int w;
    final int h;
    if (photo.width >= photo.height) {
      w = base;
      h = math.max(24, (base * photo.height / photo.width).round());
    } else {
      h = base;
      w = math.max(24, (base * photo.width / photo.height).round());
    }
    final ui.Image d =
        await DepthTemplateRenderer.renderImage(_template, width: w, height: h);
    if (!mounted) {
      d.dispose();
      return;
    }
    setState(() {
      _depth?.dispose();
      _depth = d;
    });
  }

  /// S-31：跑一次端侧 AI 深度估计，成功后用真实深度图替换模板深度。
  ///
  /// 失败（未注册 / 加载失败 / 推理异常）一律**降级保留预设模板**，不阻断页面。
  Future<void> _runAiDepth() async {
    final Uint8List? bytes = _photoBytes;
    if (bytes == null || _aiBusy) return;
    setState(() {
      _aiBusy = true;
      _aiInfo = 'AI 推理中…';
    });
    final Stopwatch sw = Stopwatch()..start();
    try {
      final DepthInference? engine = DepthInferenceRegistry.instance;
      if (engine == null) {
        setState(() => _aiInfo = '当前平台未注册深度推理实现');
        return;
      }
      final DepthResult? r = await engine.infer(bytes, inputSize: 640);
      sw.stop();
      if (!mounted) return;
      if (r == null) {
        setState(() => _aiInfo = '推理失败 —— 已保留预设模板');
        return;
      }
      final DepthResult smoothed = DepthPostProcess.smooth(r, _smooth);
      final ui.Image img = await smoothed.toImage();
      // ★ 切成图层 —— "分层 + 图层平移"渲染的数据基础
      final ui.Image? photoImg = _photo;
      final DepthLayerSet? set = photoImg == null
          ? null
          : await DepthLayerSplitter.split(
              photo: photoImg,
              depth: smoothed,
              layerCount: _layerCount,
            );
      if (!mounted) {
        img.dispose();
        set?.dispose();
        return;
      }
      setState(() {
        _depth?.dispose();
        _depth = img;
        _layerSet?.dispose();
        _layerSet = set;
        _aiDepth = true;
        _aiResult = r;
        // shader 侧的「深度分层」对 AI 深度图有害（会按等深线切出可见边界）。
        // 现在分层由上面的图层切分承担，故置 1 关闭 shader 侧的分层。
        _layers = 1;
        final String layerInfo = set == null ? '' : ' · ${set.layers.length} 层';
        _aiInfo = 'AI 深度 · ${sw.elapsedMilliseconds} ms · '
            '${r.minMeters.toStringAsFixed(2)}~'
            '${r.maxMeters.toStringAsFixed(2)} m$layerInfo';
      });
    } catch (e) {
      if (mounted) setState(() => _aiInfo = '异常：$e');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  /// 重新应用主体平滑并**重建分层**（无需重新推理）。
  /// 「主体平滑」与「分层数」变化时调用。
  void _refreshAiDepthImage() {
    final DepthResult? r = _aiResult;
    final ui.Image? photo = _photo;
    if (r == null || photo == null) return;
    unawaited(() async {
      final DepthResult smoothed = DepthPostProcess.smooth(r, _smooth);
      final ui.Image img = await smoothed.toImage();
      final DepthLayerSet? set = await DepthLayerSplitter.split(
        photo: photo,
        depth: smoothed,
        layerCount: _layerCount,
      );
      if (!mounted) {
        img.dispose();
        set?.dispose();
        return;
      }
      setState(() {
        _depth?.dispose();
        _depth = img;
        _layerSet?.dispose();
        _layerSet = set;
      });
    }());
  }

  // ── 焦点 ────────────────────────────────────────────────
  void _setFocusAt(Offset local, Size size) {
    if (size.isEmpty) return;
    final double u = (local.dx / size.width).clamp(0.0, 1.0);
    final double v = (local.dy / size.height).clamp(0.0, 1.0);
    setState(() {
      _focusUv = Offset(u, v);
      _focus = DepthTemplateRenderer.depthAt(_template, u, v);
    });
  }

  void _moveFocusBy(Offset delta, Size size) {
    if (size.isEmpty) return;
    final double u =
        (_focusUv.dx + delta.dx / size.width).clamp(0.0, 1.0);
    final double v =
        (_focusUv.dy + delta.dy / size.height).clamp(0.0, 1.0);
    setState(() {
      _focusUv = Offset(u, v);
      _focus = DepthTemplateRenderer.depthAt(_template, u, v);
    });
  }

  void _applyTemplate(DepthTemplate t) {
    setState(() {
      _template = t;
      // 保持"点击处钉住"的语义：换模板后按同一位置重算焦点深度。
      _focus = DepthTemplateRenderer.depthAt(t, _focusUv.dx, _focusUv.dy);
    });
    unawaited(_rebuildDepth());
  }

  void _toggleAutoWobble(bool v) {
    setState(() => _autoWobble = v);
    if (v) {
      _ticker.repeat();
    } else {
      _ticker.stop();
    }
  }

  // ── 视图 ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      contentWindowInsets: EdgeInsets.zero,
      topBar: C25FrostedTopBar(
        title: '空间壁纸',
        largeTitle: '空间壁纸',
        navigationIcon: _backButton,
        actions: <Widget>[
          C21CapsuleIconButton(
            key: const ValueKey<String>('wallpaper.pickTop'),
            icon: appIcon('image'),
            tooltip: '导入图片',
            onTap: () => unawaited(_pickPhoto()),
          ),
          const C26MoreMenu(),
        ],
        scrollBehavior: _collapse,
      ),
      content: (EdgeInsets padding) {
        // 控制面板限高（≤42% 屏高）+ 可滚动 —— 关键：4 个滑块 + 2 个开关 +
        // 按钮行的固有高度约 540dp，若直接放进 Column，Expanded 会被挤到 0，
        // 表现为"预览画面被操控面板挡住 / 完全看不到"。
        final double maxPanel = MediaQuery.sizeOf(context).height * 0.42;
        return Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(height: padding.top),
              Expanded(child: _buildStage(colors)),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxPanel),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _buildControls(colors),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStage(MiuixColors colors) {
    final ui.Image? photo = _photo;
    final ui.Image? depth = _depth;
    if (photo == null || depth == null) {
      return _buildEmptyState(colors);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Center(
        child: AspectRatio(
          aspectRatio: photo.width / photo.height,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final Size size = c.biggest;
              return ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (TapUpDetails d) =>
                      _setFocusAt(d.localPosition, size),
                  onPanUpdate: (DragUpdateDetails d) =>
                      _moveFocusBy(d.delta, size),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      AnimatedBuilder(
                        animation: _ticker,
                        builder: (BuildContext context, Widget? _) {
                          final Offset shift = _autoWobble
                              ? _shiftAt(_ticker.value)
                              : Offset.zero;
                          // 有分层结果 → 「分层 + 图层平移」：层内刚体平移、
                          // 近层移开由下层内容填补 → **没有遮挡空洞/拖影**。
                          // 深度图预览时仍走 shader（要看深度本身）。
                          final DepthLayerSet? set = _layerSet;
                          if (set != null && !_showDepth) {
                            return LayeredParallaxView(
                              layerSet: set,
                              shift: shift,
                              amount: _amount,
                              focus: _focus,
                            );
                          }
                          return ParallaxView(
                            image: photo,
                            depth: depth,
                            shift: shift,
                            amount: _amount,
                            focus: _focus,
                            showDepth: _showDepth,
                            depthGamma: _gamma,
                            layers: _layers,
                            focusBand: _focusBand,
                          );
                        },
                      ),
                      // 焦点指示器（不拦截手势）
                      IgnorePointer(
                        child: Stack(
                          children: <Widget>[
                            Positioned(
                              left: _focusUv.dx * size.width - 14,
                              top: _focusUv.dy * size.height - 14,
                              child: _FocusMarker(
                                color: colors.primary,
                                outline: colors.onPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(MiuixColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MiuixIcon(
            vector: appIcon('image'),
            size: 44,
            tint: colors.onSurfaceVariantSummary,
          ),
          const SizedBox(height: 12),
          MiuixText(
            _busy ? '正在读取图片…' : '导入一张照片开始',
            style: MiuixTheme.of(context).textStyles.body1,
            color: colors.onSurfaceVariantSummary,
          ),
          const SizedBox(height: 16),
          MiuixButton(
            key: const ValueKey<String>('wallpaper.pick'),
            onPressed: _busy ? null : _pickPhoto,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            child: const Text('导入图片'),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(MiuixColors colors) {
    final bool hasImage = _photo != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── 预设景深模板（B4：2~3 套 + 后续可手动修正）──
          Row(
            children: <Widget>[
              for (int i = 0; i < DepthTemplate.presets.length; i++) ...<Widget>[
                Expanded(
                  child: MiuixButton(
                    key: ValueKey<String>(
                      'wallpaper.tpl.${DepthTemplate.presets[i].kind.name}',
                    ),
                    onPressed: hasImage
                        ? () => _applyTemplate(DepthTemplate.presets[i])
                        : null,
                    colors: DepthTemplate.presets[i].kind == _template.kind
                        ? MiuixButtonDefaults.buttonColorsPrimary(context)
                        : null,
                    child: Text(DepthTemplate.presets[i].label),
                  ),
                ),
                if (i != DepthTemplate.presets.length - 1)
                  const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // ── S-31：端侧 AI 深度估计（真实场景层次）──
          MiuixButton(
            key: const ValueKey<String>('wallpaper.ai'),
            onPressed: (!hasImage || _aiBusy) ? null : _runAiDepth,
            colors: _aiDepth
                ? MiuixButtonDefaults.buttonColorsPrimary(context)
                : null,
            child: Text(
              _aiBusy
                  ? 'AI 推理中…'
                  : (_aiDepth ? 'AI 深度（已启用）' : '用 AI 估计深度'),
            ),
          ),
          if (_aiInfo.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            MiuixText(
              _aiInfo,
              style: MiuixTheme.of(context).textStyles.body2,
              color: colors.onSurfaceVariantSummary,
            ),
          ],
          const SizedBox(height: 4),
          MiuixSliderPreference(
            title: '视差强度',
            summary: '${_amount.round()} px（主体与背景的位移差上限）',
            value: _amount,
            min: 0,
            max: 48,
            insideMargin: _itemMargin,
            onValueChange: (double v) => setState(() => _amount = v),
          ),
          // ★ 分层数：2 层最稳（主体 / 背景两块），层数越多纵深层次越细，
          //   但层与层之间的"纸片感"也越明显。仅 AI 深度下有效。
          MiuixSliderPreference(
            title: '分层数',
            summary: !_aiDepth
                ? '（需先运行 AI 深度）'
                : '$_layerCount 层 · 生效 ${_layerSet?.layers.length ?? 0} 层',
            value: _layerCount.toDouble(),
            min: 2,
            max: 6,
            enabled: _aiDepth,
            insideMargin: _itemMargin,
            onValueChange: (double v) {
              final int n = v.round();
              if (n == _layerCount) return;
              setState(() => _layerCount = n);
              _refreshAiDepthImage();
            },
          ),
          MiuixSliderPreference(
            title: '焦点深度',
            summary: '${(_focus * 100).round()}%（点击画面可设定）',
            value: _focus,
            min: 0,
            max: 1,
            insideMargin: _itemMargin,
            onValueChange: (double v) => setState(() => _focus = v),
          ),
          // 「晃动幅度」滑块已移除 —— 它与「视差强度」双重缩放同一件事，是早期
          // 设计失误（14 × 0.55 ≈ 7.7 px，主体与背景位移差仅 2~4 px）。
          // 详见 _amount 字段注释。
          // ★ 主体平滑（U-12 保边平滑）：把物体内部深度抹平，同时保住物体
          //   边界的跳变。抹平后**小带宽即可整片钉住主体**，不必把焦点带开大
          //   而牵连到背景。仅在 AI 深度下有意义。
          MiuixSliderPreference(
            title: '主体平滑',
            summary: !_aiDepth
                ? '（仅 AI 深度生效）'
                : (_smooth <= 0.01
                      ? '关闭'
                      : '${(_smooth * 100).round()}%'),
            value: _smooth,
            min: 0,
            max: 1,
            enabled: _aiDepth,
            insideMargin: _itemMargin,
            onValueChange: (double v) {
              setState(() => _smooth = v);
              _refreshAiDepthImage();
            },
          ),
          // ★ 焦点带：让"主体整片钉住"的关键。只有焦点那一条等深线不动是
          //   不够的（真实深度图上人物内部深度并不均匀）；焦点带把 |深度−焦点|
          //   小于带宽的整片区域压成不动，再向外 smoothstep 平滑过渡 ——
          //   既得到"主体不动、背景滑动"的观感，又不会切出硬分割线。
          MiuixSliderPreference(
            title: '焦点带',
            summary: _focusBand < 0.005
                ? '关闭（只有焦点那条等深线钉住）'
                : '±${(_focusBand * 100).round()}%（主体整片钉住）',
            value: _focusBand,
            min: 0,
            max: 0.4,
            insideMargin: _itemMargin,
            onValueChange: (double v) => setState(() => _focusBand = v),
          ),
          MiuixSliderPreference(
            title: '深度分层',
            summary: _aiDepth
                ? 'AI 深度下已锁定关闭（分层只适合几何模板）'
                : (_layers <= 1.5 ? '关闭' : '${_layers.round()} 层'),
            value: _layers,
            min: 1,
            max: 10,
            // ⚠️ AI 深度图下禁用：全局按深度值切层会在人物身上切出可见的
            //    等深线边界（实测反馈："切割出一片区域 / 参数拉大有好几条线"）。
            enabled: !_aiDepth,
            insideMargin: _itemMargin,
            onValueChange: (double v) => setState(() => _layers = v),
          ),
          MiuixSliderPreference(
            title: '深度曲线',
            summary: _gamma.toStringAsFixed(2),
            value: _gamma,
            min: 0.5,
            max: 2.5,
            insideMargin: _itemMargin,
            onValueChange: (double v) => setState(() => _gamma = v),
          ),
          MiuixSwitchPreference(
            title: '自动晃动',
            summary: '用正弦轨迹模拟陀螺仪输入',
            value: _autoWobble,
            onChanged: _toggleAutoWobble,
            insideMargin: _itemMargin,
          ),
          MiuixSwitchPreference(
            title: '深度图预览',
            summary: '显示深度图而非成片（调试）',
            value: _showDepth,
            onChanged: (bool v) => setState(() => _showDepth = v),
            insideMargin: _itemMargin,
          ),
        ],
      ),
    );
  }
}

/// 焦点标记：小圆点 + 描边，指示当前"钉住"的层。
class _FocusMarker extends StatelessWidget {
  const _FocusMarker({required this.color, required this.outline});

  final Color color;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: outline.withValues(alpha: 0.9), width: 2),
        ),
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}
