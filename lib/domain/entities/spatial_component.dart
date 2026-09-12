// lib/domain/entities/spatial_component.dart
// 编号：S-38 空间组件模型（P-24 空间壁纸 · 期 1）
//
// 背景（见 PLAN_components_v1.53.md §3）：
//   空间壁纸的「组件」= 叠在分层视差画面之上的可摆放元素（时钟 / 文字 / Logo…）。
//   本文件是**纯数据模型**：不含渲染、不依赖 flutter widget，
//   因此【实时预览】与【离屏导出】共用同一份数据（架构红线 3：预览即导出）。
//
// ★ 关键设计：Z（depth）与视差（parallax）解耦
//   若组件的位移跟随层序（越近移得越多），最前面的时钟会移动最多 ——
//   与"时钟固定、背景和主体在动"的诉求完全相反。
//   故拆成两个独立维度：
//     depth    → 遮挡关系 / 投影强度 / 景深虚化（期 2、期 6 生效）
//     parallax → 动不动、动多少（默认 0 = 完全固定）
//   于是"时钟盖在最上层"与"时钟一动不动"可以同时成立。
//
// ★ 组件的"动"是【倾斜】而非位移
//   倾角随晃动轻微变化 → 产生"贴在空间里"的侧向透视感（参考鸿蒙 7 空间壁纸），
//   而位置保持不变，同时满足"时钟没动"与"像贴上去"。

import 'dart:typed_data';

import 'spatial_style.dart';

/// 空间组件类型。
///
/// 扩展点：新增类型时在此加值，并在渲染侧补上对应 builder
/// （期 7 起改为注册表，见 PLAN_components_v1.53.md §8.2）。
enum SpatialComponentKind {
  /// 数字时钟。
  clock,

  /// ★ 艺术字：自由文本 + 完整样式（S-42）。内容在 props['text']。
  text,

  /// ★ 图案：Logo / 贴纸 / 表情 / 图标。
  /// 图片字节在 props['bytes']（Uint8List），列表展示用 props['imgName']。
  image,
}

/// 一个空间组件（不可变）。
///
/// 位置用**归一化坐标** [u]/[v]（0..1，相对画面），因此换图/换屏幕尺寸时
/// 组件保持在画面的同一相对位置。
class SpatialComponent {
  const SpatialComponent({
    required this.id,
    required this.kind,
    this.label = '',
    this.visible = true,
    this.u = 0.5,
    this.v = 0.14,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.depth = 1.0,
    this.parallax = 0.0,
    this.tiltX = 0.0,
    this.tiltY = 0.0,
    this.perspective = 0.0012,
    this.opacity = 0.92,
    this.corner = 26.0,
    this.glass = 0.55,
    this.tiltFollow = 1.0,
    this.style = SpatialStylePresets.minimal,
    this.props = const <String, Object?>{},
  });

  /// 稳定标识（列表 key / 选中态）。
  final String id;

  /// 组件类型。
  final SpatialComponentKind kind;

  /// 用户可见的名字（列表展示）。
  final String label;

  /// 是否显示。
  final bool visible;

  /// 归一化水平位置 0..1（组件中心）。
  final double u;

  /// 归一化垂直位置 0..1（组件中心）。
  final double v;

  /// 缩放。
  final double scale;

  /// 平面内旋转（弧度）。
  final double rotation;

  /// 深度 Z：0 = 最远，1 = 最近。
  ///
  /// 决定【前后关系】（遮挡 / 投影 / 景深虚化），**不决定位移**。
  final double depth;

  /// 视差系数：单位方向上的位移倍率。
  ///
  /// **默认 0 = 完全固定不随晃动平移** —— 这是"时钟不动"的实现方式。
  /// 取负值可与背景反向运动。
  final double parallax;

  /// 平面倾角 X（弧度，绕水平轴；正 = 上沿远离观察者）。
  final double tiltX;

  /// 平面倾角 Y（弧度，绕垂直轴；正 = 右沿远离观察者）。
  final double tiltY;

  /// 3D 透视强度（Matrix4 的 (3,2) 项）。
  ///
  /// 越大"侧视感"越强。0.0012 约等于 830px 视距，是 375dp 宽屏上的适中值。
  final double perspective;

  /// 内容不透明度 0..1（玻璃底与内容一起生效）。
  final double opacity;

  /// 圆角半径（逻辑像素）。
  final double corner;

  /// 玻璃感总旋钮 0..1（期 2 生效：模糊 / 底色 / 折射 / 色散联动）。
  final double glass;

  /// 自身倾斜跟随晃动方向的倍率（0 = 不跟随，完全静态平面）。
  final double tiltFollow;

  /// ★ 样式（S-42）：**所有组件共用**的一套外观参数。
  ///
  /// 文字类用它（字体 / 描边 / 渐变 / 发光 / 胶囊底）；
  /// 图案类用它的阴影与不透明度（着色、裁切在 props 里）。
  /// 把它放在组件上而不是各 kind 自己一套，是"样式层"的全部意义 ——
  /// 加一个样式维度，所有组件自动获得。
  final SpatialStyle style;

  /// 类型专属参数（schema 驱动，见 PLAN_components_v1.53.md §8.1）。
  ///
  /// clock 用：`h24`(bool) / `showDate`(bool) / `showSeconds`(bool)。
  final Map<String, Object?> props;

  /// 读 props 中的 bool（缺省回退 [or]）。
  bool boolProp(String key, {bool or = false}) {
    final Object? v = props[key];
    return v is bool ? v : or;
  }

  SpatialComponent copyWith({
    String? id,
    SpatialComponentKind? kind,
    String? label,
    bool? visible,
    double? u,
    double? v,
    double? scale,
    double? rotation,
    double? depth,
    double? parallax,
    double? tiltX,
    double? tiltY,
    double? perspective,
    double? opacity,
    double? corner,
    double? glass,
    double? tiltFollow,
    SpatialStyle? style,
    Map<String, Object?>? props,
  }) {
    return SpatialComponent(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      label: label ?? this.label,
      visible: visible ?? this.visible,
      u: u ?? this.u,
      v: v ?? this.v,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      depth: depth ?? this.depth,
      parallax: parallax ?? this.parallax,
      tiltX: tiltX ?? this.tiltX,
      tiltY: tiltY ?? this.tiltY,
      perspective: perspective ?? this.perspective,
      opacity: opacity ?? this.opacity,
      corner: corner ?? this.corner,
      glass: glass ?? this.glass,
      tiltFollow: tiltFollow ?? this.tiltFollow,
      style: style ?? this.style,
      props: props ?? this.props,
    );
  }

  /// 序列化（模板体系期 4 使用；现在就写好，避免后面改动模型）。
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.name,
    'label': label,
    'visible': visible,
    'u': u,
    'v': v,
    'scale': scale,
    'rotation': rotation,
    'depth': depth,
    'parallax': parallax,
    'tiltX': tiltX,
    'tiltY': tiltY,
    'perspective': perspective,
    'opacity': opacity,
    'corner': corner,
    'glass': glass,
    'tiltFollow': tiltFollow,
    'props': props,
  };

  /// 反序列化。未知字段/类型一律回退默认值，**绝不抛异常**。
  factory SpatialComponent.fromJson(Map<String, Object?> j) {
    double d(String k, double or) {
      final Object? v = j[k];
      if (v is num) return v.toDouble();
      return or;
    }

    Object? kindRaw = j['kind'];
    SpatialComponentKind kind = SpatialComponentKind.clock;
    for (final SpatialComponentKind k in SpatialComponentKind.values) {
      if (k.name == kindRaw) {
        kind = k;
        break;
      }
    }

    final Object? rawProps = j['props'];
    return SpatialComponent(
      id: j['id'] is String ? j['id']! as String : _newId(),
      kind: kind,
      label: j['label'] is String ? j['label']! as String : '',
      visible: j['visible'] is bool ? j['visible']! as bool : true,
      u: d('u', 0.5),
      v: d('v', 0.14),
      scale: d('scale', 1.0),
      rotation: d('rotation', 0.0),
      depth: d('depth', 1.0),
      parallax: d('parallax', 0.0),
      tiltX: d('tiltX', 0.0),
      tiltY: d('tiltY', 0.0),
      perspective: d('perspective', 0.0012),
      opacity: d('opacity', 0.92),
      corner: d('corner', 26.0),
      glass: d('glass', 0.55),
      tiltFollow: d('tiltFollow', 1.0),
      props: rawProps is Map
          ? rawProps.map(
              (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
            )
          : const <String, Object?>{},
    );
  }

  /// 生成新 id（微秒时间戳足够——同一毫秒内不会连点两次添加）。
  static String _newId() =>
      'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  /// 新建一个数字时钟组件（默认 24 小时制 + 显示日期）。
  static SpatialComponent clock({
    double u = 0.5,
    double v = 0.14,
    double scale = 1.0,
    String label = '时钟',
  }) {
    return SpatialComponent(
      id: _newId(),
      kind: SpatialComponentKind.clock,
      label: label,
      u: u,
      v: v,
      scale: scale,
      props: const <String, Object?>{
        'h24': true,
        'showDate': true,
        'showSeconds': false,
      },
    );
  }

  /// 新建一个**艺术字**组件。
  ///
  /// 内容放 props['text']（沿用既有 schema，不必再开字段）；
  /// 外观全部交给 [style]，于是"样式层加一个维度、所有文字类组件自动获得"。
  static SpatialComponent text({
    String content = '你好',
    double u = 0.5,
    double v = 0.5,
    double scale = 1.0,
    SpatialStyle style = SpatialStylePresets.minimal,
  }) {
    return SpatialComponent(
      id: _newId(),
      kind: SpatialComponentKind.text,
      // 列表里显示一小段即可，别把整段文字塞进 label。
      // 直接从码点截断，不引 characters 包。
      label: content.runes.length > 6
          ? '${String.fromCharCodes(content.runes.take(6))}…'
          : content,
      u: u,
      v: v,
      scale: scale,
      style: style,
      // ★ 默认【不要外壳】：文字的美感在字本身，给它垫一个玻璃方框就俗了。
      //   想要外壳（手账/标签那类）在样式里调 glass 即可。
      glass: 0,
      props: <String, Object?>{'text': content},
    );
  }

  /// 新建一个**图案**组件（Logo / 贴纸 / 表情）。
  ///
  /// [shape]：0 = 原样，1 = 圆形，2 = 圆角（配合 props['rounded']）。
  static SpatialComponent sticker({
    required Uint8List bytes,
    required String name,
    double u = 0.5,
    double v = 0.5,
    double scale = 1.0,
    SpatialStyle style = SpatialStylePresets.minimal,
    double size = 120,
    int shape = 0,
  }) {
    return SpatialComponent(
      id: _newId(),
      kind: SpatialComponentKind.image,
      label: name,
      u: u,
      v: v,
      scale: scale,
      style: style,
      // ★ 默认不要外壳：Logo / 贴纸本身就带形状，垫方框会露出四个角。
      glass: 0,
      props: <String, Object?>{
        'bytes': bytes,
        'imgName': name,
        'size': size,
        'shape': shape,
        'rounded': 16.0,
      },
    );
  }
}
