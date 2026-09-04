// lib/presentation/widgets/c31_agreement_card.dart
// 编号:C-31 鸿蒙风格开屏用户协议卡片(v1.20.0,P-07 浮层)
// 说明:**deferred 懒加载库** —— 由 AgreementGate 首次需要时 loadLibrary(),
//   首帧不解析本库;卡片悬浮于主界面之上:
//   - 容器:毛玻璃(复用 C-27 预模糊,blurRadius 20 与 C-25 顶部一致;
//     backdrop 为空 → U-03 降级半透明纯色,Web/Android<13/开关关闭兼容);
//   - 样式:鸿蒙大圆角 24 + Miuix 主题 token 自适应深浅色
//     (容器 surfaceContainer / 标题 onSurface / 正文 onSurfaceVariantSummary,
//      规格色表 #1C1C1E/#3A3A3C 与 #FFFFFF/#AEAEB2 由 token 深浅色覆盖);
//   - 动画:进入 遮罩 200ms + 卡片 300ms easeOutCubic 底部滑入;
//     同意/退出 → 反向 300ms 收起后回调(Gate 再落状态/退出);
//   - 按钮:本工程 flutter_miuix 无 MiuixFilledButton/OutlinedButton 命名,
//     用等价的 MiuixButton(主色=buttonColorsPrimary)与 MiuixTextButton;
//   - 布局:竖屏 88%宽/贴底24、600-840 60%宽/贴底24、≥840 平板居中 55%宽
//     (折叠屏展开同理;折叠态=竖屏),上限高度 60%/70%/55% 屏高;
//   - 退出按钮:Web 浏览器无法自关标签页(标准限制) → Web 端隐藏退出,
//     仅保留「同意并继续」(Android 保留双按钮,SystemNavigator.pop 退出)。
// 功耗:静态卡片,动画结束后零 ticker(controller 停);同意后整树卸载。
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import 'c27_prefrosted_blur.dart';

/// ⚠️ 上线前替换为真实协议页地址(与 Web 版同源部署)。
const String _kAgreementUrl = 'https://example.com/agreement';
const String _kPrivacyUrl = 'https://example.com/privacy';

/// C-31 协议卡浮层(遮罩 + 卡片 + 进出场动画)。
/// [showExit] Web 端为 false 时仅显示「同意并继续」。
class C31AgreementCard extends StatefulWidget {
  const C31AgreementCard({
    super.key,
    required this.backdrop,
    required this.showExit,
    required this.onAgree,
    required this.onExit,
  });

  /// 主界面快照源(可为 null → 降级半透明;由 Gate 传入 shell 的 _backdrop)。
  final MiuixBackdrop? backdrop;
  final bool showExit;
  final VoidCallback onAgree;
  final VoidCallback onExit;

  @override
  State<C31AgreementCard> createState() => _C31AgreementCardState();
}

class _C31AgreementCardState extends State<C31AgreementCard>
    with SingleTickerProviderStateMixin {
  /// 遮罩渐入(0→0.5,200ms)与卡片滑入(300ms)分控,退出同步反向。
  late final AnimationController _mask = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final AnimationController _card = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _maskOpacity = Tween<double>(
    begin: 0,
    end: 0.5,
  ).animate(CurvedAnimation(parent: _mask, curve: Curves.easeOut));
  late final Animation<Offset> _cardOffset = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _card, curve: Curves.easeOutCubic));

  bool _leaving = false;
  TapGestureRecognizer? _agreementLink;
  TapGestureRecognizer? _privacyLink;

  @override
  void initState() {
    super.initState();
    _agreementLink = TapGestureRecognizer()
      ..onTap = () => _openUrl(_kAgreementUrl);
    _privacyLink = TapGestureRecognizer()..onTap = () => _openUrl(_kPrivacyUrl);
    _mask.forward();
    _card.forward();
  }

  @override
  void dispose() {
    _agreementLink?.dispose();
    _privacyLink?.dispose();
    _mask.dispose();
    _card.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final Uri uri = Uri.parse(url);
    // 外部应用打开(浏览器),失败静默(开发期占位地址可能不可达)。
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 收起动画完成后回调(同意/退出共用,300ms 反向)。
  Future<void> _dismissThen(VoidCallback action) async {
    if (_leaving) return;
    _leaving = true;
    await Future.wait<void>(<Future<void>>[_card.reverse(), _mask.reverse()]);
    if (!mounted) return;
    action();
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Stack(
      children: <Widget>[
        // 全屏遮罩:黑 50%(0x80 = 0.5,深浅色不变);barrierDismissible=false ——
        // 遮罩不响应点击,下层主界面由 Gate 的 IgnorePointer 屏蔽。
        Positioned.fill(
          child: FadeTransition(
            opacity: _maskOpacity,
            child: const ColoredBox(color: Color(0x80000000)),
          ),
        ),
        // 卡片:位置与宽度按规格自适应(手机贴底 / 平板居中)。
        Positioned.fill(child: _buildCard(colors)),
      ],
    );
  }

  Widget _buildCard(MiuixColors colors) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double screenW = mq.size.width;
    final double screenH = mq.size.height;
    // 断点:600 / 840(与 F-01 响应式一致;折叠屏展开 >840 走居中档)。
    final bool centered = screenW >= 840;
    final bool mid = screenW >= 600 && !centered;
    final double cardW = centered
        ? screenW * 0.55
        : (mid ? screenW * 0.60 : screenW * 0.88);
    final double maxH = centered
        ? screenH * 0.55
        : (mid ? screenH * 0.70 : screenH * 0.60);
    // 底部安全区(系统导航条),顶部由 maxH 上限天然避开状态栏。
    final double bottomPad = 24 + mq.padding.bottom;

    final Widget card = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        width: cardW,
        decoration: BoxDecoration(
          // 细描边(鸿蒙卡片质感;降级分支同样生效)。
          border: Border.all(color: colors.dividerLine.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(24),
        ),
        // 整卡可滚(p05 编辑窗同款):正文短 → 自然高度紧凑;
        // 正文超上限 → 卡内滚动,按钮仍可达。
        child: _buildShell(colors),
      ),
    );

    return Align(
      alignment: centered ? Alignment.center : Alignment.bottomCenter,
      child: Padding(
        padding: centered
            ? EdgeInsets.zero
            : EdgeInsets.only(bottom: bottomPad, left: 8, right: 8),
        child: FadeTransition(
          opacity: Tween<double>(
            begin: 0,
            end: 1,
          ).animate(CurvedAnimation(parent: _card, curve: Curves.easeOut)),
          child: SlideTransition(position: _cardOffset, child: card),
        ),
      ),
    );
  }

  /// 容器:毛玻璃(C-27,backdrop 非空)或半透明纯色(降级)。
  Widget _buildShell(MiuixColors colors) {
    final MiuixBackdrop? backdrop = widget.backdrop;
    // 整卡滚动:高度 = min(内容自然高, 上限 maxH),超出可滚到按钮。
    final Widget scroll = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(colors),
          _buildBody(colors),
          _buildFooter(colors),
        ],
      ),
    );
    // 降级:无快照(Web / 毛玻璃开关关 / Android<13)→ 半透明纯色。
    if (backdrop == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ColoredBox(
          color: colors.surfaceContainer.withValues(alpha: 0.92),
          child: scroll,
        ),
      );
    }
    return C27PrefrostedBlur(
      backdrop: backdrop,
      blurRadius: 20, // 与 C-25 顶部毛玻璃一致(20dp)。
      shape: const MiuixSquircleBorder(cornerRadius: 24),
      colors: MiuixBlurDefaults.blurColors(
        blendColors: <BlendColorEntry>[
          BlendColorEntry(colors.surfaceContainer.withValues(alpha: 0.7)),
        ],
      ),
      child: scroll,
    );
  }

  Widget _buildHeader(MiuixColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MiuixText(
            '欢迎使用${AppConstants.appName}',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
          const SizedBox(height: 4),
          MiuixText(
            '请先阅读并同意以下条款,再开始使用',
            fontSize: 12,
            color: colors.onSurfaceVariantSummary,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(MiuixColors colors) {
    final TextStyle base = TextStyle(
      fontSize: 14,
      height: 1.7,
      color: colors.onSurfaceVariantSummary,
    );
    final TextStyle linkStyle = TextStyle(
      fontSize: 14,
      height: 1.7,
      color: colors.primary,
      decoration: TextDecoration.underline,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MiuixText(
            '1. 本应用为本地工具类应用:课程表、每日活动时间等数据仅保存在您的设备上,不会上传至任何服务器。',
            style: base,
          ),
          const SizedBox(height: 8),
          MiuixText(
            '2. 您可在「设置」中随时调整外观与功能开关;卸载应用会同时清除本机数据,请自行留意重要内容。',
            style: base,
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: base,
              children: <InlineSpan>[
                const TextSpan(text: '3. 继续使用即表示您已阅读并同意'),
                TextSpan(
                  text: '《用户协议》',
                  style: linkStyle,
                  recognizer: _agreementLink,
                ),
                const TextSpan(text: '与'),
                TextSpan(
                  text: '《隐私政策》',
                  style: linkStyle,
                  recognizer: _privacyLink,
                ),
                const TextSpan(text: '的全部内容。'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(MiuixColors colors) {
    final List<Widget> buttons = <Widget>[
      if (widget.showExit)
        MiuixTextButton('退出', onPressed: () => _dismissThen(widget.onExit)),
      if (widget.showExit) const SizedBox(width: 12),
      MiuixButton(
        onPressed: () => _dismissThen(widget.onAgree),
        colors: MiuixButtonDefaults.buttonColorsPrimary(context),
        child: const MiuixText('同意并继续'),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: buttons,
      ),
    );
  }
}
