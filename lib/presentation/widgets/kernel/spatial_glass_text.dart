// lib/presentation/widgets/kernel/spatial_glass_text.dart
// 编号：C-70 玻璃文字渲染器（「内容玻璃」）
//
// ★ 用户原话："我需要的玻璃是字体本身变成玻璃而不是加个框"。
//   请注意这和 C-67 的「组件外壳」是**两条不同的路**：
//     · 组件外壳（SpatialComponent.glass）= 给组件垫一块玻璃底 → 卡片感
//     · 本文件（SpatialStyle.contentGlass）= **让笔画自己成为玻璃**
//   背后的画面透过字发生模糊，像真的玻璃字。
//   UI 上必须分开命名，否则用户会以为是同一个东西（PLAN §8.3 第 3 条）。
//
// 实现三步（PLAN_components_v2.0.md §8.5）：
//   ① TextPainter 把文字画进一张 ui.Image（只用它的 alpha）→ 形状图
//   ② ShaderMask(blendMode: dstIn) + ImageShader(形状图) → 只保留笔画
//   ③ 遮罩里放 BackdropFilter —— 它采样的是【已经画在它下面的画面】
//   ⇒ "透过笔画看见被模糊的背景"自然成立，**不需要改渲染管线**。
//
// ★ 为什么是 dstIn 而不是 srcIn：ShaderMask 把 shader 当 src、把 child 当 dst。
//   我们要的是"只显示 child 中 shader 不透明的部分"，语义正是 dstIn；
//   srcIn 相反（显示 shader 中 child 不透明的部分），会得到反过来的结果。
//
// ★ 两个必须处理的细节（§8.5）：
//   1. 形状图是异步生成的。首帧取不到时返回**等尺寸空盒** ——
//      一帧，肉眼不可见，但组件不会因此跳一下。
//   2. 形状图必须缓存：每次 build 重画文字再 toImage 会走一次 GPU 回读，
//      纯属浪费。只在文字 / 字号 / 字重 / 字距 / 行高 / 竖排 / dpr 变化时重渲。
//
// ★ 性能（§8.3 第 1 条）：BackdropFilter 会强制图层分离并读回后台缓冲，
//   所以它**只在真的开了玻璃时才挂**（intensity > 0），
//   而且只覆盖组件自身那块区域，不是全屏。
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../domain/entities/spatial_style.dart';

/// 把一段文字渲染成「玻璃笔画」：透过字看见被模糊的背景。
///
/// 只负责**玻璃那一层**（形状图 + 裁切 + 模糊）。描边、发光、胶囊底、竖排
/// 排版等仍由 C-68 `SpatialStyledText` 负责 —— 它会把本组件当作一个图层插进去。
/// 这样职责单一：C-70 管"材质"，C-68 管"排版与装饰"。
class SpatialGlassText extends StatefulWidget {
  const SpatialGlassText({
    super.key,
    required this.text,
    required this.style,
    this.scale = 1,
    this.textAlign = TextAlign.center,
    this.vertical = false,
    this.wrapWidth = 0,
    this.intensity = 1,
  });

  final String text;
  final SpatialStyle style;

  /// 组件在画面上的缩放（与 C-68 同一套语义，保证两层尺寸完全对齐）。
  final double scale;

  final TextAlign textAlign;

  /// 竖排（逐字换行）—— 与 C-68 一致，见那里的说明。
  final bool vertical;

  /// 自动换行宽度（逻辑像素）；0 = 不限制。
  final double wrapWidth;

  /// 玻璃强度 0..1（通常直接传 `style.contentGlass`）。
  /// 0 = 完全不画玻璃层；越大模糊越强、那层淡色也越明显。
  final double intensity;

  @override
  State<SpatialGlassText> createState() => _SpatialGlassTextState();
}

class _SpatialGlassTextState extends State<SpatialGlassText> {
  ui.Image? _shape;
  double _dpr = 1;
  bool _rendering = false;
  bool _dirty = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    if (_shape == null || dpr != _dpr) {
      _dpr = dpr <= 0 ? 1 : dpr;
      _schedule();
    }
  }

  @override
  void didUpdateWidget(SpatialGlassText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text ||
        old.scale != widget.scale ||
        old.vertical != widget.vertical ||
        old.wrapWidth != widget.wrapWidth ||
        old.textAlign != widget.textAlign ||
        !_sameFont(old.style, widget.style)) {
      _schedule();
    }
  }

  @override
  void dispose() {
    _shape?.dispose();
    _shape = null;
    super.dispose();
  }

  /// 形状图只关心"字形长什么样"，所以只比较排版相关字段；
  /// 颜色 / 描边 / 发光 / 玻璃强度变了都不需要重渲。
  static bool _sameFont(SpatialStyle a, SpatialStyle b) =>
      a.fontFamily == b.fontFamily &&
      a.fontSize == b.fontSize &&
      a.fontWeight == b.fontWeight &&
      a.letterSpacing == b.letterSpacing &&
      a.lineHeight == b.lineHeight;

  String get _shown =>
      widget.vertical ? widget.text.split('').join('\n') : widget.text;

  /// 形状图用的文字样式：**强制不透明白色**。
  /// 遮罩只读 alpha，带 alpha 的颜色会让笔画出现"半透明的洞"；
  /// "玻璃上那层淡淡的字色"由 build 里第二个图层单独负责。
  TextStyle _paintStyle() {
    // FontWeight.w100..w900 就是 values[0..8]
    final int wi = ((widget.style.fontWeight / 100).round() - 1).clamp(0, 8);
    return TextStyle(
      fontFamily: widget.style.fontFamily,
      fontSize: widget.style.fontSize * widget.scale,
      fontWeight: FontWeight.values[wi],
      letterSpacing: widget.style.letterSpacing * widget.scale,
      height: widget.style.lineHeight,
      color: const Color(0xFFFFFFFF),
    );
  }

  TextPainter _layout() {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: _shown, style: _paintStyle()),
      textAlign: widget.textAlign,
      textDirection: TextDirection.ltr,
    )..layout(
      maxWidth: widget.wrapWidth > 0 ? widget.wrapWidth : double.infinity,
    );
    return tp;
  }

  void _schedule() {
    // 正在渲染时不能并发再起一次（toImage 会排队），但也**不能丢掉这次变更**
    // —— 拖字号滑条会连续改尺寸，丢掉就会让形状图停在中间某个字号上。
    if (_rendering) {
      _dirty = true;
      return;
    }
    _rendering = true;
    unawaited(_buildShape());
  }

  Future<void> _buildShape() async {
    try {
      final TextPainter tp = _layout();
      final Size size = tp.size;
      final double dpr = _dpr <= 0 ? 1 : _dpr;
      if (size.width <= 0 || size.height <= 0) return;

      final ui.PictureRecorder rec = ui.PictureRecorder();
      final Canvas canvas = Canvas(rec);
      canvas.scale(dpr);
      tp.paint(canvas, Offset.zero);
      final ui.Picture pic = rec.endRecording();
      final ui.Image img = await pic.toImage(
        (size.width * dpr).ceil().clamp(1, 8192),
        (size.height * dpr).ceil().clamp(1, 8192),
      );
      pic.dispose();

      if (!mounted) {
        img.dispose();
        return;
      }
      final ui.Image? old = _shape;
      setState(() => _shape = img);
      old?.dispose();
    } catch (_) {
      // 形状图失败不该让整个编辑器垮掉：这一层退化为"没有玻璃"，
      // C-68 的描边与填充仍在，用户至少还能正常编辑。
    } finally {
      _rendering = false;
      if (_dirty && mounted) {
        _dirty = false;
        _schedule();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double g = widget.intensity.clamp(0.0, 1.0);
    final TextPainter tp = _layout();
    final Size size = tp.size;
    if (size.width <= 0 || size.height <= 0) return const SizedBox.shrink();

    final ui.Image? shape = _shape;
    // ① 首帧形状图还没好，或 ② 强度为 0 —— 都只占位，不画任何东西。
    if (g <= 0 || shape == null) {
      return SizedBox(width: size.width, height: size.height);
    }

    // 模糊半径随强度走：刚开一点是"磨砂"，拉满是"毛玻璃"。
    final double blur = 2.0 + 12.0 * g;

    // 形状图是按 dpr 倍画出来的位图像素，shader 的本地坐标系却是逻辑像素
    // （0..size.width），所以要缩回 1/dpr 才能与 C-68 的字形严丝合缝。
    // ImageShader 要的是 4×4 列主序 Float64List，Matrix4.storage 正是它。
    final Float64List m = Matrix4.diagonal3Values(1 / _dpr, 1 / _dpr, 1).storage;

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // ① 玻璃本体。BackdropFilter 采样【已经画在它下面的画面】，
          //    再用字形把它裁成笔画 —— "透过笔画看见模糊的背景"。
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (Rect bounds) => ui.ImageShader(
                shape,
                TileMode.decal,
                TileMode.decal,
                m,
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // ② 极淡的一层字色：给玻璃一点"材质厚度"。
          //    完全不加会像在背景上挖了个洞，加了才像"一块玻璃"。
          Positioned.fill(
            child: Opacity(
              opacity: 0.12 * g,
              child: RawImage(image: shape, fit: BoxFit.fill),
            ),
          ),
        ],
      ),
    );
  }
}
