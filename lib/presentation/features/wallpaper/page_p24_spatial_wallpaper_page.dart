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
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/depth/depth_guided_filter.dart';
import '../../../core/depth/depth_inference.dart';
import '../../../core/depth/depth_layer_splitter.dart';
import '../../../core/depth/depth_post_process.dart';
import '../../../core/depth/onnx_depth_inference.dart';
import '../../../core/depth/onnx_subject_segmentation.dart';
import '../../../core/depth/subject_edit_mask.dart';
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
  /// ★ 为什么需要它（关键诊断手段）
  ///   "深度图预览"走的是 ParallaxView（逐像素 shader），而实际渲染走的是
  ///   LayeredParallaxView（分层 + 整层平移）—— **两条完全不同的路径**。
  ///   前者正确并不能推出后者正确。
  ///   真正参与合成的是【层图】：里面含 alpha、含"猜"出来的填充内容，
  ///   而这些在深度图预览里一个都看不到。把层图原样铺出来（棋盘格衬底），
  ///   才能在"渲染出错"时一眼分清是素材的问题还是合成的问题。
  int _showLayer = 0;

  // ── 工具分页（参考系统相册编辑器）──────────────────────────
  /// 当前选中的工具页：0 = 无（画面最大），1 = 主体，2 = 空间，
  /// 3 = 焦点，4 = 组件，5 = 导出。
  ///
  /// ★ 为什么改成分页
  ///   之前十几个滑块与开关全部平铺在一列里 —— 画面被挤到只剩四成屏高，
  ///   而且调试开关和正式功能混在一起。分页后画面成为主角、参数按需出现。
  int _toolTab = 0;

  /// 调试面板展开态（顶部 ⋮）。
  ///
  /// 四个预览开关（深度图/遮罩/层素材）是开发工具，不该占主面板 ——
  /// 收进这里，需要时展开、平时收起。
  bool _debugOpen = false;

  /// 画面截图锚点（保存到相册用）。
  final GlobalKey _captureKey = GlobalKey();

  // ── U-14 手动修正（涂刷 / 擦除）────────────────────────────
  /// 手动修正层（分辨率与 AI mask 一致）。为空 = 还没进过涂刷模式。
  ///
  /// 与 AI 是【互补】关系：编辑层叠加在整条 AI 管线之后，用户只修 AI 做错的
  /// 那一两处，其余仍旧交给 AI 承担。
  SubjectEditMask? _editMask;

  /// 笔刷模式：0 = 关闭（画面手势归焦点/组件），1 = 画笔，2 = 橡皮。
  int _brushMode = 0;

  /// 笔刷半径（归一化，相对画面短边）。
  double _brushSize = 0.06;

  /// 本次涂抹的轨迹（归一化坐标），仅用于实时反馈；松手后才写入 [_editMask]。
  ///
  /// 之所以"先画轨迹、松手再落盘"：写入编辑层后要重建分层，而重建要跑完整的
  /// 闭运算 / 深度连通筛选 / 层图生成，每帧做会明显卡顿；用户需要的只是
  /// 【立刻看到笔迹】，所以轨迹先画出来，松手再统一提交。
  final List<Offset> _brushTrail = <Offset>[];

  /// 橡皮的笔刷半径（与画笔【分开记忆】）。
  ///
  /// 擦掉一小块残留用细笔、补一大片漏抠用粗笔 —— 两者需要的粗细完全不同，
  /// 共用一个数值会逼着用户来回拖滑块。
  double _eraseSize = 0.035;

  /// 涂刷时当前生效的笔刷半径。
  double get _activeBrushSize => _brushMode == 2 ? _eraseSize : _brushSize;

  /// 撤销栈：每次落笔【之前】压入一份编辑层快照。
  ///
  /// 存整份快照而不是"操作记录"：编辑层只有 mask 分辨率（典型 280×640，
  /// 每份约 0.7MB），12 步不到 9MB；换来的是撤销瞬间完成、逻辑零分支
  /// （重放式撤销要在每次撤销时重算全部笔迹，越撤越慢）。
  final List<Float32List> _undoStack = <Float32List>[];
  static const int _undoLimit = 12;

  /// 涂刷模式下的缩放/平移控制器。
  ///
  /// 双指缩放 + 平移，单指留给笔刷 —— 所以 InteractiveViewer 要 panEnabled:false。
  /// 笔刷坐标不用手动逆变换：GestureDetector 在变换后的 child 内部，
  /// localPosition 本来就是 child 自己的坐标系。
  final TransformationController _zoomCtrl = TransformationController();

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
  ///   取 3px 作平衡点 —— 空间感仍在，而背景瑕疵的露出量进一步收窄。
  ///   （演进：5px → 4px（"背景晃动稍微减小"）→ 3px（"背景瑕疵会出露"）。
  ///     2 层下背景位移由 8px 降到 6px。）
  ///
  ///   注意：实际层间差 = 总位移 ×(1 − subjectRatio)/(层数 − 1)，所以这里锁定
  ///   的是【层间差】而不是【总位移】—— 2/3/4 层下的观感才能一致（层数越多，
  ///   单层位移与总位移都按比例缩小）。
  static const double _layerDelta = 3.0;

  /// 最远层的位移上限（逻辑像素）。
  ///
  /// 取 6，与 2 层时的实际总位移持平 —— 否则层数一多，总位移会被这条上限顶到
  /// 比 2 层还大（原先取 10 / 14 时都有这个问题），换个层数背景反而晃得更凶。
  static const double _amountMax = 6.0;

  /// 主体（最近层）位移占最远层的比例。
  ///
  /// 0.5 = 主体**跟着动，但幅度只有背景的一半** —— 这就是"晃动时主体还有一点
  /// 立体感"（对齐苹果空间照片）。取 0 会退化成旧的"主体钉死"反向模型：层间差
  /// 被拉满、穿帮明显，而且主体完全没有立体感。
  static const double _subjectRatio = 0.5;

  /// 主体层的【立体起伏】幅度（逻辑像素）。
  ///
  /// ★ 这才是"立体感"的关键一层
  ///   主体若只做整层刚性平移，内部所有像素位移完全相同 —— 看上去是一块
  ///   硬邦邦的平板。真实物体鼻梁比耳朵近、肩膀比腰近，晃起来位移应当各不
  ///   相同。这里让主体层的位移随【深度】变化，于是内部产生起伏（浮雕感）。
  ///
  ///   为什么以前不敢：逐像素位移会产生遮挡空洞，这正是当初改成"整层平移"
  ///   的原因。现在主体层之下有背景层兜底、空洞会被填上，而起伏只有几个
  ///   像素、远小于主体自身尺寸，所以可以安全启用。
  ///
  /// ★ 取 1.5（本轮修复，原来是 6）
  ///   原来 ±3px 的逐像素起伏根本不成立 —— 它做出的是【液化揉搓】，不是立体：
  ///     · 物理上主体内部的视差差极小：鼻梁 1.5m 与耳朵 2.0m 换算成视差只差
  ///       0.167，而全画面的归一化视差范围约 0.6 —— 落到 3px 的总位移上只有
  ///       约 0.8px。取 6 相当于把真实值放大了 3~6 倍。
  ///     · 更要命的是这个位移场会随【晃动方向】整体翻转：晃动过程中主体内部
  ///       被来回拉扯，观感就是"揉"。实测反馈："主体在镜头晃动时那种扭曲感
  ///       做的很不自然"。
  ///   降到 1.5 → 主体内部起伏约 ±0.75px：保留了"不是一块平板"的体积暗示，
  ///   又小到看不出形变。
  ///
  ///   ⚠️ 别把"物理正确值"当目标 —— 那只有亚像素，观感上等于没有立体感。
  ///      这里取的是"略大于物理、但远低于可见形变阈值"的折中。
  static const double _relief = 1.5;

  /// 判"这张图有主体"的前景覆盖率下限；低于它按【风景/无主体】处理。
  ///
  /// ★★ 0.05 → 0.15（本轮修复）。0.05 是错的，实测证据三条：
  ///
  ///   1) modnet / isnet 是【人像抠图】模型，对风景也会"抠出点什么"。
  ///      实测 3 张纯风景：41.09% / 6.62% / 25.76% —— 全都 ≥ 5%，
  ///      于是【全部被判为"有主体"、全部走 mask 分支】。
  ///
  ///   2) mask 分支会**强制 2 层、并且完全按 mask 分层、根本不用深度**
  ///      （见 DepthLayerSplitter.split 里 mw != null 的说明）。
  ///      一张风景图只要被误判出一个小 mask，后果是：
  ///        · 剩下 90%+ 的画面变成【一整块刚体】、同一个速度 → 毫无视差；
  ///        · 那个小 mask 成了全图唯一"分出来"的东西，走 0.5 倍速度
  ///          → 它的边缘必然撕裂。
  ///      真机截图（富士山那张，modnet 6.62%）：主体层素材预览几乎全是
  ///      棋盘格，只有右下角一小块樱花 —— 正是这个 6.62%。
  ///      → 用户反馈的"风景图前后识别不行"与"渲染分割出错"同源于此。
  ///
  ///   3) 阈值必须显著抬高，让小 mask 不再劫持分层，风景图才能落到
  ///      【按深度分层】的路径上、真正吃到视差。
  ///
  /// ⚠️ 0.15 只是把最明显的误判挡掉；它不能可靠区分"人像"与"风景"——
  ///    实测 4 个判据全部不可分（覆盖率 / 连通域结构 / 深度双峰性 /
  ///    形状等周比，脚本见 mode\yolo_work\diagI~diagK）。真正的解法是
  ///    让"有 mask 时背景层仍按深度分层"，而不是让 mask 独占总位移。
  static const double _subjectCoverageMin = 0.15;

  /// 内容类型：**由用户显式指定**走哪条渲染路径。
  ///
  /// ★ 为什么必须有这个开关（不是偷懒，是实测结论）
  ///   自动区分"人像 / 风景"做不到。4 个判据全测过，**全部不可分**：
  ///     · mask 覆盖率        风景 0 ~ 41.09%   |  人像/二次元 24.08 ~ 49.93%
  ///     · 连通域(最大块/紧凑度) 41.07% / 1.00   |  35.27% / 0.99
  ///     · 深度双峰性 η        0.748 ~ 0.839    |  0.744 ~ 0.827
  ///     · 形状等周比 4πA/P²    0 ~ 0.589        |  0.178 ~ 0.392
  ///   （脚本 mode\yolo_work\diagI ~ diagK，数字都在，可复核。）
  ///   根因：modnet / isnet 是【人像抠图】模型 —— 给它一棵树，它也能抠出 41%
  ///   的"主体"（真机截图：主体层素材里装了一整棵树 + 岩石）。
  ///   机器判不出来，就把选择权交给用户 —— 这是唯一诚实的做法。
  ///
  ///   0 = 自动（按 mask 覆盖率兜底，保留原来的行为）
  ///   1 = 人物 → 分层：mask 定主体、深度定背景，主体整片刚体移动
  ///   2 = 风景 → 连续视差：不切层，位移随深度连续变化，不会撕裂
  int _subjectMode = 0;
  static const List<String> _subjectModeLabels = <String>['自动', '人物', '风景'];

  /// 是否走【分层】渲染；false = 走连续视差（逐像素）。
  ///
  /// 用户显式指定优先；「自动」时才用 mask 覆盖率兜底。
  bool _useLayerPath(SubjectMask? mask) {
    switch (_subjectMode) {
      case 1:
        // 人物：只要分割拿到了东西就分层（主体层由 mask 界定）
        return mask != null;
      case 2:
        // 风景：一律不切层 —— 连续视差对连续深度才是对的
        return false;
      default:
        return mask != null && mask.coverage >= _subjectCoverageMin;
    }
  }

  void _setSubjectMode(int m) {
    if (m == _subjectMode) return;
    setState(() => _subjectMode = m);
    // 已经算过 AI 深度 → 直接重建分层即可，不必重跑推理（省一次 DAV2）。
    if (_aiDepth) _refreshAiDepthImage();
  }
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
    _zoomCtrl.dispose();
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
      // ★ 不传 inputSize：DAV2 的输入边长是"面积对齐 518² + 取整到 14 的倍数"
      //   算出来的，由实现内部决定（旧 YOLO26 才需要外部指定 640）。
      final DepthResult? r = await engine.infer(bytes);
      sw.stop();
      if (!mounted) return;
      if (r == null) {
        setState(() => _aiInfo = '推理失败 —— 已保留预设模板');
        return;
      }
      final DepthResult smoothed = await _refineDepth(r);
      final ui.Image img = await smoothed.toImage();
      // ★ S-39：主体分割。不可用/失败 → null，分层自动退回纯深度阈值 ——
      //   分割只负责"让分层更准"，绝不允许它阻断整条链路。
      final SubjectMask? mask = await _runSegmentation(bytes);
      // ★ 切成图层 —— "分层 + 图层平移"渲染的数据基础
      final ui.Image? photoImg = _photo;
      // ★ 走哪条路：用户显式指定优先（仅"自动"时才用覆盖率兜底）。
      //   走连续视差时不切层 —— 连续深度被等深线切块会撕裂（见 _subjectMode）。
      final bool useLayers = _useLayerPath(mask);
      final DepthLayerSet? set = (photoImg == null || !useLayers)
          ? null
          : await DepthLayerSplitter.split(
              photo: photoImg,
              depth: smoothed,
              layerCount: _layerCount,
              subject: mask,
              // 膨胀量 = 层间位移差：背景层比主体层多走的距离，正好等于背景层
              // 里那片填充会滑出主体轮廓的距离。
              subjectDilate: _layerDelta,
              editMask: _editMask,
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
        // ★ 单位随模型变：DAV2 输出的是相对视差，没有米制含义 ——
        //   再在它后面标一个 "m" 就是误导（旧 YOLO26 是米制才该标）。
        final String rangeInfo = r.isMetric
            ? '${r.minMeters.toStringAsFixed(2)}~'
                '${r.maxMeters.toStringAsFixed(2)} m'
            : '视差 ${r.minMeters.toStringAsFixed(2)}~'
                '${r.maxMeters.toStringAsFixed(2)}';
        _aiInfo = 'AI 深度 · ${sw.elapsedMilliseconds} ms · '
            '$rangeInfo$layerInfo$segInfo';
      });
    } catch (e) {
      if (mounted) setState(() => _aiInfo = '异常：$e');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  /// 深度后处理链：保边平滑 → **引导滤波**（U-13）。
  /// 抽成一个方法是因为两条路径都需要它（首次推理 / 调「主体平滑」后重建）；
  /// 两条路径必须产出一致的深度图，否则调一次平滑就会看到另一种边缘。
  ///
  /// ★ 引导滤波为什么放在最后（本轮的根本结论）
  ///   前面所有针对边界的启发式（深度阈值、连通性）都是在拿【深度值】去猜
  ///   边界在哪，而物体边界本来就画在图像上（亮度/颜色在那里有明显跳变）。
  ///   引导滤波以原图为引导、让深度边缘对齐图像的真实边缘 —— 这才用对了信息。
  // ── U-14 手动修正（涂刷 / 擦除）────────────────────────────
  /// 进入 / 切换涂刷模式（再点一次同一个模式即退出）。
  void _setBrushMode(int mode) {
    final SubjectMask? m = _subjectMask;
    if (m == null) return;
    setState(() {
      _brushMode = _brushMode == mode ? 0 : mode;
      _brushTrail.clear();
      if (_brushMode > 0) {
        _editMask ??= SubjectEditMask(m.width, m.height);
      }
    });
  }

  /// 记录一个涂抹点（只画轨迹，不落盘）。
  void _brushMove(Offset local, Size size, {bool first = false}) {
    if (size.isEmpty || _brushMode == 0) return;
    final Offset uv = Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
    setState(() {
      if (first) _brushTrail.clear();
      _brushTrail.add(uv);
    });
  }

  /// 松手：把轨迹写进 [_editMask]，然后重建分层。
  void _commitBrush() {
    final SubjectEditMask? em = _editMask;
    if (em == null || _brushTrail.isEmpty) {
      if (_brushTrail.isNotEmpty) setState(_brushTrail.clear);
      return;
    }
    // ★ 落笔前先压一份快照 —— 撤销要回到"这一笔之前"的状态。
    _undoStack.add(Float32List.fromList(em.data));
    if (_undoStack.length > _undoLimit) _undoStack.removeAt(0);

    final bool erase = _brushMode == 2;
    final double size = _activeBrushSize;
    // 逐段插值，避免手指快划时留下断续的圆点
    Offset prev = _brushTrail.first;
    em.stamp(prev.dx, prev.dy, size, erase: erase);
    for (int i = 1; i < _brushTrail.length; i++) {
      final Offset cur = _brushTrail[i];
      em.stroke(prev.dx, prev.dy, cur.dx, cur.dy, size, erase: erase);
      prev = cur;
    }
    setState(_brushTrail.clear);
    // 笔迹变了 → 重走一遍分层（AI 管线 + 编辑层）
    _refreshAiDepthImage();
  }

  /// 撤销上一笔。
  void _undoBrush() {
    final SubjectEditMask? em = _editMask;
    if (em == null || _undoStack.isEmpty) return;
    final Float32List snap = _undoStack.removeLast();
    setState(() {
      em.data.setAll(0, snap);
      _brushTrail.clear();
    });
    _refreshAiDepthImage();
  }

  /// 复位涂刷视图（缩放/平移回到初始）。
  void _resetZoom() {
    if (_zoomCtrl.value.isIdentity()) return;
    setState(() => _zoomCtrl.value = Matrix4.identity());
  }

  /// 清除全部手动修改（回到纯 AI 的结果）。
  void _clearBrush() {
    final SubjectEditMask? em = _editMask;
    if (em == null) return;
    setState(() {
      em.clear();
      _brushTrail.clear();
    });
    _refreshAiDepthImage();
  }

  Future<DepthResult> _refineDepth(DepthResult raw) async {
    DepthResult d = DepthPostProcess.smooth(raw, _smooth);
    final ui.Image? guide = _photo;
    if (guide != null) {
      d = await DepthGuidedFilter.apply(depth: d, photo: guide);
    }
    return d;
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
      final DepthResult smoothed = await _refineDepth(r);
      final ui.Image img = await smoothed.toImage();
      final SubjectMask? sm = _subjectMask;
      // ★ 与 _runAiDepth 必须用同一条判据 —— 否则切换「内容类型」后看到的
      //   分层会和首次推理时不一致。
      final DepthLayerSet? set = !_useLayerPath(sm)
          ? null
          : await DepthLayerSplitter.split(
              photo: photo,
              depth: smoothed,
              layerCount: _layerCount,
              // 复用已算好的主体 mask —— 切「内容类型 / 主体平滑 / 分层数」
              // 都不必重跑分割。
              subject: sm,
              subjectDilate: _layerDelta,
              editMask: _editMask,
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
    // ★ 本页【强制深色】—— 参考系统相册编辑器的沉浸式编辑界面。
    //   浅色主题下画面周围的大片留白会把整体观感带偏（判断视差效果时尤其明显）。
    //   只包这一页，不影响 App 其它页面的主题。
    return MiuixThemeController(
      colorSchemeMode: MiuixColorSchemeMode.dark,
      child: Builder(
        builder: (BuildContext context) {
          final MiuixColors colors = MiuixTheme.of(context).colors;
          return MiuixScaffold(
            contentWindowInsets: EdgeInsets.zero,
            topBar: _buildTopBar(),
            content: (EdgeInsets padding) {
              // 参数区限高 30% 屏高并就地滚动；画面靠 Expanded 吃掉剩余空间 ——
              // 相册编辑器的比例：画面是主角，参数只是配角。
              final double maxPanel = MediaQuery.sizeOf(context).height * 0.30;
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
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _buildControls(colors),
                      ),
                    ),
                    _buildToolBar(colors),
                    SizedBox(height: padding.bottom),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// 顶部栏：返回 / 撤销 / 导入 / 保存 / 更多（对齐系统相册编辑器的动作集合）。
  Widget _buildTopBar() {
    return C25FrostedTopBar(
      title: '空间壁纸',
      largeTitle: '空间壁纸',
      navigationIcon: _backButton,
      actions: <Widget>[
        C21CapsuleIconButton(
          key: const ValueKey<String>('wallpaper.undo'),
          icon: appIcon('undo'),
          tooltip: '撤销',
          // 无可撤销笔迹时置灰（onTap 为 null）
          onTap: _undoStack.isEmpty ? null : _undoBrush,
        ),
        C21CapsuleIconButton(
          key: const ValueKey<String>('wallpaper.pickTop'),
          icon: appIcon('image'),
          tooltip: '导入图片',
          onTap: () => unawaited(_pickPhoto()),
        ),
        C21CapsuleIconButton(
          key: const ValueKey<String>('wallpaper.save'),
          icon: appIcon('download'),
          tooltip: '保存到相册',
          onTap: _photo == null || _busy
              ? null
              : () => unawaited(_saveToGallery()),
        ),
        const C26MoreMenu(),
      ],
      scrollBehavior: _collapse,
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
        // ★ 截图锚点：保存到相册时对这个边界做 toImage ——
        //   只框住画面本身，不含顶栏/参数区/工具行。
        child: RepaintBoundary(
          key: _captureKey,
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
                // ★ 涂刷模式下才允许缩放：双指缩放/移动画面，单指留给笔刷
                //   （panEnabled 恒为 false，否则单指一划就把画面拖走了）。
                //   笔刷坐标不需要手动逆变换 —— GestureDetector 在变换后的
                //   child 内部，localPosition 本来就是 child 自己的坐标系。
                child: InteractiveViewer(
                  transformationController: _zoomCtrl,
                  panEnabled: false,
                  scaleEnabled: _brushMode > 0,
                  minScale: 1,
                  maxScale: 5,
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // ★ 涂刷模式下画面手势整体让位给笔刷 —— 否则点一下就会顺手
                  //   把焦点挪走，用户涂到一半画面就变样了。
                  onTapUp: _brushMode > 0
                      ? null
                      : (TapUpDetails d) => _setFocusAt(d.localPosition, size),
                  onPanStart: _brushMode > 0
                      ? (DragStartDetails d) =>
                          _brushMove(d.localPosition, size, first: true)
                      : null,
                  onPanUpdate: _brushMode > 0
                      ? (DragUpdateDetails d) =>
                          _brushMove(d.localPosition, size)
                      : (DragUpdateDetails d) => _moveFocusBy(d.delta, size),
                  onPanEnd:
                      _brushMode > 0 ? (DragEndDetails _) => _commitBrush() : null,
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
                                  // 深度图给主体层做立体起伏（见 _relief 说明）
                                  depthImage: depth,
                                  shift: shift,
                                  amount: motionAmount,
                                  subjectRatio: _subjectRatio,
                                  relief: _relief,
                                )
                              : ParallaxView(
                                  image: photo,
                                  depth: depth,
                                  shift: shift,
                                  amount: motionAmount,
                                  // ★ 无主体（AI 深度且未切层）时把焦点钉在【最近处】：
                                  //   此时 rel = d − 1 ≤ 0，所有像素【同向】位移、
                                  //   近处小远处大 —— 即"同向递减"，与分层模式的
                                  //   观感一致。若沿用默认的 0.5，画面会一半向
                                  //   +shift、一半向 −shift，看起来像从中间被撕开。
                                  //   几何模板模式（_aiDepth=false）仍由用户控制焦点。
                                  focus: (_aiDepth && set == null) ? 1.0 : _focus,
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
                      // 涂刷轨迹的实时反馈 —— 只画轨迹，松手才写入编辑层并重建
                      // 分层（重建要跑完整的闭运算/深度筛选/层图生成，每帧做会卡）。
                      if (_brushTrail.isNotEmpty)
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _BrushTrailPainter(
                              trail: _brushTrail,
                              radius: _activeBrushSize,
                              erase: _brushMode == 2,
                            ),
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
                ),
              );
            },
          ),
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

  /// 参数区：按选中的工具页显示对应参数（参考系统相册编辑器的分页）。
  ///
  /// ★ 性能说明：这里只做"按条件构建 widget"，完全不碰渲染 —— 画面在
  ///   Expanded 里、由 LayeredParallaxView 自己管 shouldRepaint，
  ///   切换工具页不会触发它重建或重绘。
  Widget _buildControls(MiuixColors colors) {
    final bool hasImage = _photo != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ══════════ 1 主体 ══════════
          if (_toolTab == 1) ...<Widget>[
            // ── 深度来源：几何模板（B4 降级链的最后一级）──
            Row(
              children: <Widget>[
                for (int i = 0;
                    i < DepthTemplate.presets.length;
                    i++) ...<Widget>[
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
            const SizedBox(height: 6),
            // ── ★ 内容类型：由用户指定走哪条渲染路径 ──
            //   自动判据实测不可靠（见 _subjectMode 的说明：4 个判据全不可分），
            //   所以把选择权交出来：
            //     人物 → 分层（mask 定主体、深度定背景）
            //     风景 → 连续视差（不切层，位移随深度连续变化）
            Row(
              children: <Widget>[
                for (int i = 0;
                    i < _subjectModeLabels.length;
                    i++) ...<Widget>[
                  Expanded(
                    child: MiuixButton(
                      key: ValueKey<String>('wallpaper.subjectMode.$i'),
                      onPressed: hasImage ? () => _setSubjectMode(i) : null,
                      colors: _subjectMode == i
                          ? MiuixButtonDefaults.buttonColorsPrimary(context)
                          : null,
                      child: Text(_subjectModeLabels[i]),
                    ),
                  ),
                  if (i != _subjectModeLabels.length - 1)
                    const SizedBox(width: 8),
                ],
              ],
            ),
            if (_aiInfo.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              MiuixText(
                _aiInfo,
                style: MiuixTheme.of(context).textStyles.body2,
                color: colors.onSurfaceVariantSummary,
              ),
            ],
          ],
          const SizedBox(height: 4),
          // ★ 「视差强度」滑块已移除（v1.53）：穿帮带宽 = 相邻层位移差，位移越大
          //   主体轮廓外露出的错位内容越宽。交给用户调就一定会被调到穿帮的位置，
          //   故改为固定值 _amount，并由 _subjectRatio 保证"主体跟着动、幅度小"。
          if (_toolTab == 2)
            MiuixText(
              '晃动幅度已锁定：层间位移差 ${_layerDelta.round()} px · '
              '主体占背景的 ${(_subjectRatio * 100).round()}%',
              style: MiuixTheme.of(context).textStyles.body2,
              color: colors.onSurfaceVariantSummary,
            ),
          // ★ 分层数：2 层最稳（主体 / 背景两块），层数越多纵深层次越细，
          //   但层与层之间的"纸片感"也越明显。仅 AI 深度下有效。
          if (_toolTab == 2)
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
          if (_toolTab == 3)
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
          if (_toolTab == 2)
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
          // ══════════ 3 焦点（几何模板用）══════════
          if (_toolTab == 3) ...<Widget>[
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
          ], // ══════════ /3 焦点 ══════════

          // ══════════ 2 空间（续）══════════
          if (_toolTab == 2)
            MiuixSwitchPreference(
              title: '自动晃动',
            summary: '用正弦轨迹模拟陀螺仪输入',
            value: _autoWobble,
            onChanged: _toggleAutoWobble,
            insideMargin: _itemMargin,
          ),
          // ══════════ 调试（顶部 ⋮ 展开）══════════
          // 这四个是开发工具：深度图预览走的是另一条渲染路径，只有层素材预览
          // 才反映实际参与合成的东西。收进这里，不占主面板。
          if (_debugOpen) ...<Widget>[
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
          ], // ══════════ /调试 ══════════

          // ══ U-14 手动修正（涂刷 / 擦除）· 归入「主体」页 ══
          // 自动分割在边界模糊处永远有误差；"哪块像素是人"这件事，用户刷一笔
          // 比任何启发式都准。它与 AI 互补 —— 只修 AI 做错的那一两处。
          if (_toolTab == 1) ...<Widget>[
          const SizedBox(height: 10),
          MiuixText('手动修正', style: MiuixTheme.of(context).textStyles.body1),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: MiuixButton(
                  key: const ValueKey<String>('wallpaper.brush.paint'),
                  onPressed:
                      _subjectMask == null ? null : () => _setBrushMode(1),
                  colors: _brushMode == 1
                      ? MiuixButtonDefaults.buttonColorsPrimary(context)
                      : null,
                  child: const Text('画笔'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MiuixButton(
                  key: const ValueKey<String>('wallpaper.brush.erase'),
                  onPressed:
                      _subjectMask == null ? null : () => _setBrushMode(2),
                  colors: _brushMode == 2
                      ? MiuixButtonDefaults.buttonColorsPrimary(context)
                      : null,
                  child: const Text('橡皮'),
                ),
              ),
            ],
          ),
          if (_brushMode > 0) ...<Widget>[
            MiuixSliderPreference(
              title: _brushMode == 2 ? '橡皮大小' : '笔刷大小',
              summary: '${(_activeBrushSize * 100).round()}% 画面短边'
                  '（${_brushMode == 2 ? "擦除" : "涂抹"}中，松手生效）',
              value: _activeBrushSize,
              min: 0.02,
              max: 0.30,
              insideMargin: _itemMargin,
              onValueChange: (double v) => setState(() {
                // 画笔与橡皮各自记忆大小：擦细节和补大片需要的粗细差很多
                if (_brushMode == 2) {
                  _eraseSize = v;
                } else {
                  _brushSize = v;
                }
              }),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: MiuixButton(
                    key: const ValueKey<String>('wallpaper.brush.undo'),
                    onPressed: _undoStack.isEmpty ? null : _undoBrush,
                    child: Text('撤销（${_undoStack.length}）'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MiuixButton(
                    key: const ValueKey<String>('wallpaper.brush.reset'),
                    onPressed: _resetZoom,
                    child: const Text('复位视图'),
                  ),
                ),
              ],
            ),
            MiuixText(
              '双指缩放/移动画面，单指涂刷；最多可撤销 $_undoLimit 笔',
              style: MiuixTheme.of(context).textStyles.body2,
              color: colors.onSurfaceVariantSummary,
            ),
          ],
          if (_brushMode == 0 && _editMask != null && !_editMask!.isEmpty)
            MiuixButton(
              key: const ValueKey<String>('wallpaper.brush.clear'),
              onPressed: _clearBrush,
              child: const Text('清除手动修改'),
            ),
          ], // ══════════ /1 主体 ══════════

          // ══════════ 4 组件 ══════════
          // 组件叠在分层视差画面【之上】，与画面共用同一个晃动源。
          // 期 1：数字时钟 + Z/视差解耦 + 3D 平面透视 + 透明度。
          // 期 2 接入折射玻璃（LensRefraction）、期 6 接入深度遮挡。
          if (_toolTab == 4) ...<Widget>[
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
          ], // ══════════ /4 组件 ══════════

          // ══════════ 5 导出 ══════════
          if (_toolTab == 5) ...<Widget>[
          MiuixButton(
            key: const ValueKey<String>('wallpaper.save.panel'),
            onPressed: (hasImage && !_busy)
                ? () => unawaited(_saveToGallery())
                : null,
            colors: MiuixButtonDefaults.buttonColorsPrimary(context),
            child: const Text('保存到相册'),
          ),
          const SizedBox(height: 6),
          MiuixText(
            '保存当前画面（含组件与当前晃动姿态）。'
            '导出静态图以外的格式（GIF / 互动 HTML）在后续版本。',
            style: MiuixTheme.of(context).textStyles.body2,
            color: colors.onSurfaceVariantSummary,
          ),
          ], // ══════════ /5 导出 ══════════
        ],
      ),
    );
  }

  /// 工具行（对齐系统相册编辑器：图标+文字、选中态高亮、再点一次收起）。
  ///
  /// 收起的价值：画面能拿回那 30% 的高度（相册编辑器也允许工具行隐藏）。
  Widget _buildToolBar(MiuixColors colors) {
    const List<(int, String)> tools = <(int, String)>[
      (1, '主体'),
      (2, '空间'),
      (3, '焦点'),
      (4, '组件'),
      (5, '导出'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: <Widget>[
          for (final (int id, String label) in tools)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: MiuixButton(
                  key: ValueKey<String>('wallpaper.tab.$id'),
                  onPressed: () => setState(() {
                    _toolTab = _toolTab == id ? 0 : id;
                    // 离开「主体」页时顺手退出涂刷 —— 否则手势还留在笔刷上，
                    // 用户回去想点画面设焦点会发现点不动。
                    if (_toolTab != 1) _brushMode = 0;
                  }),
                  colors: _toolTab == id
                      ? MiuixButtonDefaults.buttonColorsPrimary(context)
                      : null,
                  child: Text(label),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: MiuixButton(
              key: const ValueKey<String>('wallpaper.tab.debug'),
              onPressed: () => setState(() => _debugOpen = !_debugOpen),
              colors: _debugOpen
                  ? MiuixButtonDefaults.buttonColorsPrimary(context)
                  : null,
              child: const Text('调试'),
            ),
          ),
        ],
      ),
    );
  }

  /// 保存当前画面到系统相册。
  ///
  /// 用画面自己的 RepaintBoundary 截图 —— 所见即所得（含组件、含当前晃动姿态）。
  /// 复用 PlatFileOps.saveImageToGallery：Android 走 MediaStore → Pictures/Toki，
  /// 鸿蒙侧由镜像实现接管，不引入任何新的平台依赖。
  Future<void> _saveToGallery() async {
    final RenderRepaintBoundary? boundary =
        _captureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    setState(() {
      _busy = true;
      _aiInfo = '正在保存…';
    });
    try {
      // pixelRatio 3：与多数手机屏幕密度相当，导出的图不会糊
      final ui.Image img = await boundary.toImage(pixelRatio: 3);
      final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (bd == null) return;
      final String name =
          'toki_spatial_${DateTime.now().millisecondsSinceEpoch}.png';
      final String? msg = await PlatFileOpsRegistry.instance
          .saveImageToGallery(
            bytes: bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes),
            fileName: name,
          );
      if (mounted) setState(() => _aiInfo = msg ?? '已保存到相册');
    } catch (e) {
      debugPrint('🔴 保存失败: $e');
      if (mounted) setState(() => _aiInfo = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

/// 涂刷轨迹的实时反馈：红色 = 画笔（加主体），蓝色 = 橡皮（去主体）。
///
/// 只画本次轨迹（归一化坐标 + 归一化半径），不做任何像素写入 ——
/// 真正的落盘在松手后统一进行。
class _BrushTrailPainter extends CustomPainter {
  const _BrushTrailPainter({
    required this.trail,
    required this.radius,
    required this.erase,
  });

  final List<Offset> trail;
  final double radius;
  final bool erase;

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty || size.isEmpty) return;
    final double r = radius * size.shortestSide;
    final Paint p = Paint()
      ..color = (erase
              ? const Color(0xFF3B82F6)
              : const Color(0xFFFF3B30))
          .withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    if (trail.length == 1) {
      canvas.drawCircle(
        Offset(trail.first.dx * size.width, trail.first.dy * size.height),
        r,
        p,
      );
      return;
    }
    for (int i = 1; i < trail.length; i++) {
      final Offset a =
          Offset(trail[i - 1].dx * size.width, trail[i - 1].dy * size.height);
      final Offset b =
          Offset(trail[i].dx * size.width, trail[i].dy * size.height);
      // 用圆头粗线把相邻点连起来 —— 与 stamp 的插值行为一致，不会出现断续
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = p.color
          ..strokeWidth = r * 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BrushTrailPainter old) =>
      old.trail.length != trail.length ||
      old.radius != radius ||
      old.erase != erase;
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
