// lib/presentation/widgets/c39_steam_key_sheet.dart
// 编号：C-39 UAPI 密钥弹层（v1.34.0 新增,P-08 配套）
// 说明：Steam 查询凭证(UAPI key)输入/清除浮层 —— MiuixOverlayDialog
//   自适应(窄屏底部 / 宽屏居中,与 C-35/C-36 同体系,show 布尔驱动):
//   - 内容:obscure 输入框(明文/密文可切换 lock↔unlock)+ 取消/保存;
//   - 已配置时额外提供「清除已保存密钥」操作(error 色文字);
//   - 明文不回显(输入框留空,避免窥屏);保存空串 = 清除;
//   - 保存/清除经 steam_providers(加密存储,见 S-07/P-08 决策记录)。
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_icons.dart';
import '../../core/widgets/mini_toast.dart';
import '../providers/steam_providers.dart';

/// C-39 密钥输入弹层(常驻树,show=false 零开销)。
class SteamKeySheet extends ConsumerStatefulWidget {
  const SteamKeySheet({
    super.key,
    required this.show,
    required this.onDismissRequest,
  });

  final bool show;
  final VoidCallback onDismissRequest;

  @override
  ConsumerState<SteamKeySheet> createState() => _SteamKeySheetState();
}

class _SteamKeySheetState extends ConsumerState<SteamKeySheet> {
  final TextEditingController _input = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final String key = _input.text.trim();
    await saveSteamApiKey(ref, key);
    if (!mounted) return;
    setState(() => _saving = false);
    showMiniToast(context, key.isEmpty ? '已清除 UAPI 密钥' : 'UAPI 密钥已保存');
    widget.onDismissRequest();
  }

  Future<void> _clear() async {
    if (_saving) return;
    setState(() => _saving = true);
    await clearSteamApiKey(ref);
    if (!mounted) return;
    setState(() => _saving = false);
    showMiniToast(context, '已清除 UAPI 密钥');
    widget.onDismissRequest();
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    // 凭证状态(loading 视为未配置)。
    final bool hasKey =
        (steamApiKeyOrNull(ref.watch(steamApiKeyProvider)) ?? '').isNotEmpty;

    return MiuixOverlayDialog(
      show: widget.show,
      title: 'UAPI 密钥',
      summary: 'UAPI 凭证(选填,以 Authorization: Bearer 头发送)。'
          '不填则以访客额度匿名调用,多数工具可用;'
          '部分请求计入积分,可在 uapis.cn 控制台获取密钥。'
          '密钥仅加密保存在本机,不明文回显。',
      onDismissRequest: widget.onDismissRequest,
      content: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (hasKey) ...[
              // 已配置提示 + 清除操作。
              Row(
                children: <Widget>[
                  Expanded(
                    child: MiuixText(
                      '已配置(点击下方按钮可清除)',
                      fontSize: 12,
                      color: colors.onSurfaceVariantSummary,
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('steamKey.clear'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _saving ? null : _clear,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: MiuixText(
                        '清除',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            MiuixTextField(
              key: const ValueKey('steamKey.input'),
              controller: _input,
              label: '输入 UAPI 密钥',
              useLabelAsPlaceholder: true,
              singleLine: true,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              trailingIcon: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _obscure = !_obscure),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: MiuixIcon(
                    vector: appIcon(_obscure ? 'lock' : 'unlock'),
                    size: 18,
                    tint: colors.onSurfaceVariantSummary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // 操作行:取消(次按钮)+ 保存(主按钮)。
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                MiuixTextButton(
                  '取消',
                  onPressed: widget.onDismissRequest,
                ),
                const SizedBox(width: 8),
                MiuixButton(
                  key: const ValueKey('steamKey.save'),
                  onPressed: _saving ? null : _save,
                  colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                  child: MiuixText(_saving ? '保存中…' : '保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
