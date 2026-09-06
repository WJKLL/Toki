// lib/presentation/widgets/cards/card_shell.dart
// 编号:P-01-01 内部件(首页卡片统一边缘阴影,自 home_card_layout 迁出,
//   v1.22.0;v1.25.0 双层悬浮阴影 + 深浅色自适应 + 拖拽浮起档;
//   v1.44.x 暗色高光内建)
// 说明:以 DecoratedBox 双层阴影包裹子卡;child 自带背景与圆角。
//   - 常态:定向近影(下缘贴地感)+ 环境远影(大扩散柔和浮起氛围);
//   - elevated=true(拖拽浮起/飞行期):两影同步加深加大 → 「离桌」反馈;
//   - 深浅色自适应:阴影为黑系,深色模式 alpha 提倍(浅阴影在深底不可见);
//   - v1.44.x:内建暗色高光(darkGlow=true 默认)—— 深色下在阴影外侧叠
//     1px 白描边 + 微光晕(CardDarkGlow),与黑系阴影分层(外投影 + 内描边),
//     浅色模式 CardDarkGlow 直接透传 → **零开销**;所有经本壳的内容卡
//     自动获得全 App 统一卡片语言,无需逐个嵌套;
//   - 阴影静态预构建 4 组(浅/深 × 常态/浮起),build 零分配、零 ticker。
//   摘要区、C-34 网格卡与其它页内容卡共用,保证全 App 阴影语言一致。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../../core/widgets/card_dark_glow.dart';

/// 首页卡片统一阴影壳(双层悬浮阴影 + 暗色高光)。
/// [radius] 阴影形状圆角 —— 与内卡圆角对齐,避免阴影露出直角/缺角;
/// [elevated] 浮起档 —— 拖拽激活/飞行中置 true;
/// [darkGlow] 暗色描边光晕开关(默认开;深色才产生绘制,浅色透传零成本)。
class CardShadow extends StatelessWidget {
  const CardShadow({
    super.key,
    required this.child,
    this.radius = 18,
    this.elevated = false,
    this.darkGlow = true,
  });

  final Widget child;

  /// 阴影形状圆角。
  final double radius;

  /// 浮起档:true → 阴影加深加大(离桌反馈)。
  final bool elevated;

  /// v1.44.x:暗色高光(1px 白描边 + 微光晕);false = 仅阴影。
  final bool darkGlow;

  // ── 黑系阴影参数(静态预构建;浅色常态/浮起,深色常态/浮起)──
  // 浅色:常态 定向 14% + 环境 6%;浮起 20% + 10%
  // 深色:常态 定向 28% + 环境 12%;浮起 36% + 20%(深底提倍保证可见)
  static const List<BoxShadow> _restLight = <BoxShadow>[
    BoxShadow(color: Color(0x24000000), blurRadius: 12, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 22, offset: Offset(0, 7)),
  ];
  static const List<BoxShadow> _restDark = <BoxShadow>[
    BoxShadow(color: Color(0x47000000), blurRadius: 12, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x1F000000), blurRadius: 22, offset: Offset(0, 7)),
  ];
  static const List<BoxShadow> _liftLight = <BoxShadow>[
    BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x1A000000), blurRadius: 34, offset: Offset(0, 14)),
  ];
  static const List<BoxShadow> _liftDark = <BoxShadow>[
    BoxShadow(color: Color(0x5C000000), blurRadius: 20, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x33000000), blurRadius: 34, offset: Offset(0, 14)),
  ];

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    // 深色判定跟随 Miuix 实际取色(Monet 深浅自适应)。
    final bool dark = colors.surface.computeLuminance() < 0.5;
    final List<BoxShadow> shadows = elevated
        ? (dark ? _liftDark : _liftLight)
        : (dark ? _restDark : _restLight);
    final Widget shadowed = DecoratedBox(
      decoration: BoxDecoration(
        // 透明底 + 阴影:阴影形状按卡片外接矩形,模糊后圆角观感自然。
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadows,
      ),
      child: child,
    );
    // v1.44.x:暗色高光内建 —— CardDarkGlow 浅色透传(零开销),深色在
    // 阴影 DecoratedBox 外侧叠 1px 白描边 + 微光晕(外投影 + 内描边分层)。
    if (!darkGlow) return shadowed;
    return CardDarkGlow(radius: radius, child: shadowed);
  }
}
