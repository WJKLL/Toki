// POC 调试钩子(v0.1.4 临时):vendor 补丁埋点 —— 开源版静默(不向控制台
// 输出);`pocDebugLog` 全局回调接口保留(宿主可注入自检通道)。
library;

/// 全局日志回调(宿主注入;null = 丢弃)。
typedef PocDebugFn = void Function(String message);

PocDebugFn? pocDebugLog;

/// 埋点入口(开源版:仅转发宿主回调,控制台静默)。
void pocLog(String message) {
  pocDebugLog?.call(message);
}
