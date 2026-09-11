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
import 'dart:async';
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
import '../../../core/depth/onnx_subject_segmentation.dart';
import '../../../core/depth/subject_segmentation.dart';
import '../../../core/platform/contract/plat_file_ops.dart';
import '../../../core/wallpaper/depth_template_renderer.dart';
import '../../../domain/entities/depth_template.dart';
import '../../../domain/entities/spatial_component.dart';
import '../../../core/widgets/app_icons.dart';
import '../../widgets/c21_collapsing_title_bar.dart';
import '../../widgets/c25_frosted_top_bar.dart';
import '../../widgets/c26_more_menu.dart';
import '../../widgets/kernel/layered_parallax_view.dart';
import '../../widgets/kernel/parallax_view.dart';
import '../../widgets/kernel/spatial_component_layer.dart';

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

  // ── S-39 主体分割 ────────────────────────────────────────
  /// 主体 mask（随「用 AI 估计深度」一起产出）。为 null → 分层退回纯深度阈值。
  SubjectMask? _subjectMask;

  /// 主体遮罩预览（调试）：把 mask 判定的主体区域染成半透明红叠在画面上。
  /// 有它才能直接确认"分割到底覆盖了哪里"，不必再靠推理猜。
  bool _showMask = false;
  ui.Image? _maskImage;

  /// 层素材预览：0 = 关，1 = 背景层，2 = 主体层。
  ///
  /// ★ 为什么需要它（关键诊断手段）
  ///   "深度图预览"走的是 ParallaxView（逐像素 shader），而实际渲染走的是
  ///   LayeredParallaxView（分层 + 整层平移）—— **两条完全不同的路径**。
  ///   前者正确并不能推出后者正确。
  ///   真正参与合成的是【层图】：里面含 alpha、含"猜"出来的填充内容，
  ///   而这些在深度图预览里一个都看不到。把层图原样铺出来（棋盘格衬底），
  ///   才能在"渲染出错"时一眼分清是素材的问题还是合成的问题。
  int _showLayer = 0;

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
  /// 相邻层的位移差（逻辑像素）—— **这才是真正被控制的量**。
  ///
  ///   "看得出来"和"露瑕疵"是同一个量的两面，但敏感度不同：
  ///     · 看得出来：主要靠【背景的绝对位移】—— 背景整片在动，人就感知到了；
  ///     · 露瑕疵：只取决于【层间差】—— 错位带有多宽。
  ///   所以策略是"保住背景位移、压低层间差"：主体多跟一点即可。
  ///
  ///     · 层间差 < 3px：分层看不出，空间感出不来；
  ///     · 层间差 > 8px：主体轮廓外错位的那一条开始显眼。
  ///   取 4px 作平衡点 —— 空间感清楚；再配合背景色扩散填充（错位带里露出的
  ///   本来就是背景的延续），边界几乎看不出。
  ///   （初版取 5px，实测反馈"背景晃动稍微减小"，故收到 4px：2 层下背景位移
  ///     由 10px 降到 8px。）
  ///
  ///   注意：实际层间差 = 总位移 ×(1 − subjectRatio)/(层数 − 1)，所以这里锁定
  ///   的是【层间差】而不是【总位移】—— 2/3/4 层下的观感才能一致（层数越多，
  ///   单层位移与总位移都按比例缩小）。
  static const double _layerDelta = 4.0;

  /// 最远层的位移上限（逻辑像素）。
  ///
  /// 取 10，与 2 层时的实际总位移持平 —— 否则层数一多，总位移会被这条上限顶到
  /// 比 2 层还大（原先取 14 时正是如此），换个层数背景反而晃得更凶。
  static const double _amountMax = 10.0;

  /// 主体（最近层）位移占最远层的比例。
  ///
  /// 0.5 = 主体**跟着动，但幅度只有背景的一半** —— 这就是"晃动时主体还有一点
  /// 立体感"（对齐苹果空间照片）。取 0 会退化成旧的"主体钉死"反向模型：层间差
  /// 被拉满、穿帮明显，而且主体完全没有立体感。
  static const double _subjectRatio = 0.5;
  double _gamma = 1.0; // 深度曲线
  double _layers = 4; // 深度分层数（<=1 = 关闭）—— 仅几何模板需要
  double _focusBand = 0.12; // 焦点带宽度：主体整片钉住，向外平滑过渡
  bool _showDepth = false;
  bool _autoWobble = true;
  bool _busy = false;

  // ── 组件（S-38 / C-67 · PLAN_components_v1.53.md 期 1）──────────
  /// 叠在分层视差画面之上的组件列表。
  ///
  /// 默认放一个数字时钟：打开页面就有东西可调，而"时钟不动、背景和主体在动"
  /// 正是这个功能的核心验收点。
  List<SpatialComponent> _components = <SpatialComponent>[
    SpatialComponent.clock(),
  ];

  /// 当前选中的组件 id（null = 未选中）。
  String? _selectedId;

  /// 全局倾斜跟随强度 0..1：晃动时组件平面轻微反向倾斜 → "贴在空间里"的
  /// 侧向透视感。位置不动，所以仍然满足"时钟没动"。
  double _tiltFollow = 0.4;

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
    // S-39：注册主体分割实现。鸿蒙不注册 → Registry.instance 为 null →
    // DepthLayerSplitter 自动退回纯深度分层，页面不抛异常。
    SubjectSegmentationRegistry.register(OnnxSubjectSegmentation.instance);
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    if (_autoWobble) _ticker.repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _maskImage?.dispose();
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
        // 换图 → 上一张的主体 mask 立即失效，避免套用到新图的人身上。
        _subjectMask = null;
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
      _aiInfo = 'AI 推理中（深度 + 主体分割）…';
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
      // ★ S-39：主体分割。不可用/失败 → null，分层自动退回纯深度阈值 ——
      //   分割只负责"让分层更准"，绝不允许它阻断整条链路。
      final SubjectMask? mask = await _runSegmentation(bytes);
      // ★ 切成图层 —— "分层 + 图层平移"渲染的数据基础
      final ui.Image? photoImg = _photo;
      final DepthLayerSet? set = photoImg == null
          ? null
          : await DepthLayerSplitter.split(
              photo: photoImg,
              depth: smoothed,
              layerCount: _layerCount,
              subject: mask,
              // 膨胀量 = 层间位移差：背景层比主体层多走的距离，正好等于背景层
              // 里那片填充会滑出主体轮廓的距离。
              subjectDilate: _layerDelta,
            );
      // ★ 预览用【最终生效的那份 mask】，而不是模型原始输出 ——
      //   闭运算、深度一致性过滤、膨胀都会改变它；显示原始值会与实渲染不一致，
      //   继续误导判断（前面已经因为"预览 ≠ 实际"吃过几轮亏）。
      final SubjectMask? effective = set?.subjectMask ?? mask;
      final ui.Image? maskImg =
          effective == null ? null : await _maskToImage(effective);
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
        _subjectMask = mask;
        _maskImage?.dispose();
        _maskImage = maskImg;
        final String layerInfo = set == null ? '' : ' · ${set.layers.length} 层';
        final String segInfo = mask == null
            ? ' · 无主体分割'
            : ' · 主体 ${(mask.coverage * 100).round()}%';
        _aiInfo = 'AI 深度 · ${sw.elapsedMilliseconds} ms · '
            '${r.minMeters.toStringAsFixed(2)}~'
            '${r.maxMeters.toStringAsFixed(2)} m$layerInfo$segInfo';
      });
    } catch (e) {
      if (mounted) setState(() => _aiInfo = '异常：$e');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  /// S-39：跑一次主体分割。
  ///
  /// 未注册（鸿蒙未注入实现）或任何异常 → 返回 null，调用方降级为纯深度分层。
  /// 不做结果缓存：同一张图重复点「用 AI 估计深度」本就要重算深度，分割顺带
  /// 重跑的代价（真人只需 1 次推理）可以接受，换来的是实现简单、状态更少。
  Future<SubjectMask?> _runSegmentation(Uint8List bytes) async {
    final SubjectSegmentation? seg = SubjectSegmentationRegistry.instance;
    if (seg == null) return null;
    try {
      return await seg.segment(bytes);
    } catch (e) {
      debugPrint('🔴 S-39 分割异常（降级为纯深度分层）: $e');
      return null;
    }
  }

  /// soft mask → 半透明红色叠加图（供「主体遮罩预览」）。
  ///
  /// 用红色而非灰度：叠在原图上时，一眼就能看出"腿在不在里面、背景有没有被
  /// 收进来" —— 这是调分割参数时唯一可靠的依据。
  static Future<ui.Image> _maskToImage(SubjectMask m) {
    final Uint8List rgba = Uint8List(m.length * 4);
    for (int i = 0; i < m.length; i++) {
      // 显示【陡化后】的值 —— 与实际参与渲染的 alpha 保持一致
      // （DepthLayerSplitter 里用的是 smoothstep(0.45, 0.75)）。
      // 若直接画原始 soft 概率，背景那 0.3~0.5 的底色会让整幅画面泛红，
      // 看起来像"主体覆盖了全图"，从而误判。
      final double v = m.data[i].clamp(0.0, 1.0);
      final double t = ((v - 0.45) / 0.30).clamp(0.0, 1.0);
      final int a = (t * t * (3.0 - 2.0 * t) * 150).round();
      final int o = i * 4;
      rgba[o] = 255;
      rgba[o + 1] = 40;
      rgba[o + 2] = 40;
      rgba[o + 3] = a;
    }
    final Completer<ui.Image> done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      m.width,
      m.height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
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
        // 复用导入时算好的主体 mask —— 调「主体平滑/分层数」不必重跑分割。
        subject: _subjectMask,
        subjectDilate: _layerDelta,
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

  // ── 组件（S-38）─────────────────────────────────────────
  /// 当前选中的组件（未选中 / 已被删除 → null）。
  SpatialComponent? get _selected {
    final String? id = _selectedId;
    if (id == null) return null;
    for (final SpatialComponent c in _components) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 就地替换选中组件（整表换新实例 —— S-38 是不可变模型）。
  void _updateSelected(SpatialComponent Function(SpatialComponent) f) {
    final String? id = _selectedId;
    if (id == null) return;
    setState(() {
      _components = <SpatialComponent>[
        for (final SpatialComponent c in _components)
          if (c.id == id) f(c) else c,
      ];
    });
  }

  void _addClock() {
    // 依次错开纵向位置：连点两次不会完全重叠，省去"看不见新增组件"的困惑。
    final SpatialComponent c = SpatialComponent.clock(
      v: 0.16 + 0.13 * (_components.length % 5),
    );
    setState(() {
      _components = <SpatialComponent>[..._components, c];
      _selectedId = c.id;
    });
  }

  void _removeSelected() {
    final String? id = _selectedId;
    if (id == null) return;
    setState(() {
      _components = <SpatialComponent>[
        for (final SpatialComponent c in _components)
          if (c.id != id) c,
      ];
      _selectedId = null;
    });
  }

  /// 拖动组件：按归一化增量改位置，并夹在画面内（留边距，防拖出可视区）。
  void _moveComponent(String id, Offset deltaUv) {
    setState(() {
      _components = <SpatialComponent>[
        for (final SpatialComponent c in _components)
          if (c.id == id)
            c.copyWith(
              u: (c.u + deltaUv.dx).clamp(0.06, 0.94),
              v: (c.v + deltaUv.dy).clamp(0.04, 0.96),
            )
          else
            c,
      ];
    });
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
              // ★ 由【目标层间差】反推总位移：层间差 = 总位移×(1−ratio)/(层数−1)。
              //   锁定层间差而不是总位移，2/3/4 层下的观感才一致；_amountMax 兜住
              //   层数多时总幅度失控的情况。
              final int layerN = math.max(2, _layerSet?.layers.length ?? 2);
              final double motionAmount = math.min(
                _layerDelta * (layerN - 1) / (1.0 - _subjectRatio),
                _amountMax,
              );
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
                          final Widget picture = (set != null && !_showDepth)
                              ? LayeredParallaxView(
                                  layerSet: set,
                                  shift: shift,
                                  amount: motionAmount,
                                  subjectRatio: _subjectRatio,
                                )
                              : ParallaxView(
                                  image: photo,
                                  depth: depth,
                                  shift: shift,
                                  amount: motionAmount,
                                  focus: _focus,
                                  showDepth: _showDepth,
                                  depthGamma: _gamma,
                                  layers: _layers,
                                  focusBand: _focusBand,
                                );
                          // ★ 组件层与画面【共用同一个 shift】→ 完全同步。
                          //   组件的位移由各自 parallax 决定（默认 0 = 固定），
                          //   故默认观感就是"背景和主体在动、时钟不动"。
                          return Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              picture,
                              SpatialComponentLayer(
                                components: _components,
                                size: size,
                                shift: shift,
                                amount: motionAmount,
                                tiltFollow: _tiltFollow,
                                selectedId: _selectedId,
                                onSelect: (String id) =>
                                    setState(() => _selectedId = id),
                                onMove: _moveComponent,
                              ),
                            ],
                          );
                        },
                      ),
                      // 主体遮罩预览（调试）：红色半透明 = 被判为主体的区域。
                      // 放在 AnimatedBuilder 之外 —— 它不随晃动重绘。
                      if (_showMask && _maskImage != null)
                        IgnorePointer(
                          child: RawImage(
                            image: _maskImage,
                            fit: BoxFit.fill,
                          ),
                        ),
                      // 层素材预览：把实际参与合成的图层原样铺出来（含填充、
                      // 含 alpha）。棋盘格衬底让透明区域一目了然。
                      // 放在最后 = 盖在其它预览之上。
                      if (_showLayer > 0 && _layerSet != null)
                        IgnorePointer(
                          child: _LayerMaterialView(
                            layerSet: _layerSet!,
                            index: _showLayer - 1,
                          ),
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
          // ★ 「视差强度」滑块已移除（v1.53）：穿帮带宽 = 相邻层位移差，位移越大
          //   主体轮廓外露出的错位内容越宽。交给用户调就一定会被调到穿帮的位置，
          //   故改为固定值 _amount，并由 _subjectRatio 保证"主体跟着动、幅度小"。
          MiuixText(
            '晃动幅度已锁定：层间位移差 ${_layerDelta.round()} px · '
            '主体占背景的 ${(_subjectRatio * 100).round()}%',
            style: MiuixTheme.of(context).textStyles.body2,
            color: colors.onSurfaceVariantSummary,
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
          MiuixSwitchPreference(
            title: '主体遮罩预览',
            summary: _subjectMask == null
                ? '（需先点「用 AI 估计深度」）'
                : '红色 = 被判为主体的区域（调试）',
            value: _showMask,
            onChanged: (bool v) => setState(() => _showMask = v),
            insideMargin: _itemMargin,
          ),
          // ★ 层素材预览：这两个才反映【实际参与渲染的东西】。
          //   深度图预览走的是另一条路径，它对了不代表渲染就对。
          MiuixSwitchPreference(
            title: '背景层素材',
            summary: _layerSet == null
                ? '（需先点「用 AI 估计深度」）'
                : '看背景层里实际是什么（棋盘格 = 透明）',
            value: _showLayer == 1,
            onChanged: (bool v) => setState(() => _showLayer = v ? 1 : 0),
            insideMargin: _itemMargin,
          ),
          MiuixSwitchPreference(
            title: '主体层素材',
            summary: _layerSet == null
                ? '（需先点「用 AI 估计深度」）'
                : '看主体层里实际是什么（棋盘格 = 透明）',
            value: _showLayer == 2,
            onChanged: (bool v) => setState(() => _showLayer = v ? 2 : 0),
            insideMargin: _itemMargin,
          ),

          // ══ 组件（S-38 / C-67 · 期 1）══════════════════════════════
          // 组件叠在分层视差画面【之上】，与画面共用同一个晃动源。
          // 期 1：数字时钟 + Z/视差解耦 + 3D 平面透视 + 透明度。
          // 期 2 接入折射玻璃（LensRefraction）、期 6 接入深度遮挡。
          const SizedBox(height: 10),
          MiuixText('组件', style: MiuixTheme.of(context).textStyles.body1),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: MiuixButton(
                  key: const ValueKey<String>('wallpaper.comp.add'),
                  onPressed: hasImage ? _addClock : null,
                  child: const Text('添加时钟'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MiuixButton(
                  key: const ValueKey<String>('wallpaper.comp.del'),
                  onPressed: hasImage && _selected != null
                      ? _removeSelected
                      : null,
                  child: const Text('删除选中'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ..._buildComponentControls(colors, hasImage),
        ],
      ),
    );
  }

  /// 选中组件的参数（S-38）。未选中时给出操作提示。
  List<Widget> _buildComponentControls(MiuixColors colors, bool hasImage) {
    if (!hasImage) return const <Widget>[];
    final SpatialComponent? c = _selected;
    if (c == null) {
      return <Widget>[
        MiuixText(
          _components.isEmpty
              ? '还没有组件 —— 点「添加时钟」开始'
              : '点画面上的组件即可选中，拖动可改位置',
          style: MiuixTheme.of(context).textStyles.body2,
          color: colors.onSurfaceVariantSummary,
        ),
      ];
    }
    return <Widget>[
      MiuixText(
        '$c.label · 位置 ${(c.u * 100).round()}% / ${(c.v * 100).round()}%'
        '（直接拖动组件可改位置）',
        style: MiuixTheme.of(context).textStyles.body2,
        color: colors.onSurfaceVariantSummary,
      ),
      // ★ Z 与视差【解耦】：Z 决定前后关系（期 6 起同时决定遮挡），
      //   视差系数决定动不动。默认 Z 最前 + 视差 0 = 盖在最上层但完全固定。
      MiuixSliderPreference(
        title: '组件深度 Z',
        summary: '${(c.depth * 100).round()}%（1 = 最前，决定前后关系与投影）',
        value: c.depth,
        min: 0,
        max: 1,
        insideMargin: _itemMargin,
        onValueChange: (double v) =>
            _updateSelected((SpatialComponent x) => x.copyWith(depth: v)),
      ),
      MiuixSliderPreference(
        title: '视差系数',
        summary: c.parallax.abs() < 0.005
            ? '0 —— 完全固定（时钟不随晃动移动）'
            : '${c.parallax.toStringAsFixed(2)} × 画面晃动幅度',
        value: c.parallax,
        min: -1,
        max: 1,
        insideMargin: _itemMargin,
        onValueChange: (double v) =>
            _updateSelected((SpatialComponent x) => x.copyWith(parallax: v)),
      ),
      // 倾角 + 透视：这两个才是"像贴上去"的来源（位置不动，只改朝向）。
      MiuixSliderPreference(
        title: '平面倾斜',
        summary: '${(c.tiltY * 180 / math.pi).toStringAsFixed(0)}°（侧向视角）',
        value: c.tiltY,
        min: -0.6,
        max: 0.6,
        insideMargin: _itemMargin,
        onValueChange: (double v) =>
            _updateSelected((SpatialComponent x) => x.copyWith(tiltY: v)),
      ),
      MiuixSliderPreference(
        title: '俯仰倾斜',
        summary: '${(c.tiltX * 180 / math.pi).toStringAsFixed(0)}°',
        value: c.tiltX,
        min: -0.4,
        max: 0.4,
        insideMargin: _itemMargin,
        onValueChange: (double v) =>
            _updateSelected((SpatialComponent x) => x.copyWith(tiltX: v)),
      ),
      MiuixSliderPreference(
        title: '透视强度',
        summary: c.perspective < 0.0001
            ? '关闭（平行投影）'
            : '${(1 / c.perspective).round()}px 视距',
        value: c.perspective,
        min: 0,
        max: 0.004,
        insideMargin: _itemMargin,
        onValueChange: (double v) =>
            _updateSelected((SpatialComponent x) => x.copyWith(perspective: v)),
      ),
      MiuixSliderPreference(
        title: '倾斜跟随',
        summary: _tiltFollow < 0.01
            ? '关闭（组件平面完全静止）'
            : '${(_tiltFollow * 100).round()}%（晃动时组件轻微反向倾斜）',
        value: _tiltFollow,
        min: 0,
        max: 1,
        insideMargin: _itemMargin,
        onValueChange: (double v) => setState(() => _tiltFollow = v),
      ),
      MiuixSliderPreference(
        title: '组件缩放',
        summary: '${(c.scale * 100).round()}%',
        value: c.scale,
        min: 0.5,
        max: 2,
        insideMargin: _itemMargin,
        onValueChange: (double v) =>
            _updateSelected((SpatialComponent x) => x.copyWith(scale: v)),
      ),
      MiuixSliderPreference(
        title: '组件透明度',
        summary: '${(c.opacity * 100).round()}%',
        value: c.opacity,
        min: 0.15,
        max: 1,
        insideMargin: _itemMargin,
        onValueChange: (double v) =>
            _updateSelected((SpatialComponent x) => x.copyWith(opacity: v)),
      ),
      MiuixSliderPreference(
        title: '玻璃感',
        summary: c.glass < 0.02
            ? '关闭（无玻璃底）'
            : '${(c.glass * 100).round()}%（期 2 起接入折射玻璃）',
        value: c.glass,
        min: 0,
        max: 1,
        insideMargin: _itemMargin,
        onValueChange: (double v) =>
            _updateSelected((SpatialComponent x) => x.copyWith(glass: v)),
      ),
      MiuixSliderPreference(
        title: '圆角',
        summary: '${c.corner.round()} px',
        value: c.corner,
        min: 0,
        max: 48,
        insideMargin: _itemMargin,
        onValueChange: (double v) =>
            _updateSelected((SpatialComponent x) => x.copyWith(corner: v)),
      ),
    ];
  }
}

/// 层素材预览：棋盘格衬底 + 指定图层的原始像素。
///
/// 为什么要看这个：深度图预览走的是另一条渲染路径（逐像素 shader），它正确
/// 并不能推出分层渲染正确。真正参与合成的是【层图】—— 里面含 alpha、含"猜"
/// 出来的填充内容，而这一切在深度图预览里完全看不到。
class _LayerMaterialView extends StatelessWidget {
  const _LayerMaterialView({required this.layerSet, required this.index});

  final DepthLayerSet layerSet;
  final int index;

  @override
  Widget build(BuildContext context) {
    final List<DepthLayer> ls = layerSet.layers;
    if (ls.isEmpty) return const SizedBox.shrink();
    final DepthLayer l = ls[index.clamp(0, ls.length - 1)];
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 棋盘格在下：层的 alpha 为 0 处会透出它，一眼可辨。
        const CustomPaint(painter: _CheckerPainter()),
        RawImage(image: l.image, fit: BoxFit.fill),
      ],
    );
  }
}

/// 棋盘格衬底（让 alpha=0 的区域一眼可辨）。
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const double cell = 14;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF43434E),
    );
    final Paint dark = Paint()..color = const Color(0xFF2C2C34);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final int ix = (x / cell).floor();
        final int iy = (y / cell).floor();
        if ((ix + iy).isEven) continue;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
