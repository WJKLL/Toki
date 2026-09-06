// lib/core/flow/flow_connect_rules.dart
// 编号:P-11 连线校验规则(v1.47 阶段2,接入 vyuh onBeforeStart/onBeforeComplete)
// 规则(返回 null=允许;否则为禁止提示文案):
//   1. 端点锁定:起点/终点任一锁定 → 禁止拉线(锁定 = 不可编辑);
//   2. 防自环:同一节点输入连自身输出 → 禁止;
//   3. 防重复:同 (src → dst) 已存在连线 → 禁止(任何源);
//   4. 判断出口唯一:判断源的目标已有分支连线 → 禁止(播放分支不可分辨)。
// 纯函数,不依赖 Flutter/vyuh,可单测。
library;

/// 连线完成(落点)校验。
/// [sourceIsDecision]:源节点语义类型是否为判断(差异化提示)。
String? denyConnect({
  required bool sourceLocked,
  required bool targetLocked,
  required bool isSelf,
  required bool samePairExists,
  required bool sourceIsDecision,
}) {
  if (sourceLocked || targetLocked) return '节点已锁定,无法连线';
  if (isSelf) return '不能连接到节点自身';
  if (samePairExists && sourceIsDecision) {
    return '该判断已有到此节点的分支连线';
  }
  if (samePairExists) return '两节点之间已有连线';
  return null;
}

/// 连线起点(拉线)校验:锁定节点不可作为拉线起点。
String? denyConnectStart({required bool sourceLocked}) =>
    sourceLocked ? '节点已锁定,无法拉线' : null;
