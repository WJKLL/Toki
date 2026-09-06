# Toki(xiangjugong)

Toki —— 基于 Flutter + [flutter_miuix](https://miuix.nekofun.top/)(小米 HyperOS / MIUI 设计语言)
的个人效率工具:待办时间轴、流程图编辑器、小工具集与资讯入口。

## ✨ 亮点

- **液态玻璃设计语言**:悬浮底栏 / 顶栏 / 悬浮按钮全链路 HyperOS 毛玻璃(Backdrop 实时采样,
  按平台与系统策略自动降级),超椭圆圆角 + Folme 弹性动效 + Monet 动态取色,深浅色实时跟随
- **上课常驻通知**:课程倒计时常驻通知 + 课程提醒(Android 前台服务,锁屏/后台常显)
- **流程图编辑器**:内嵌 vyuh_node_flow 内核 + 专有触摸体验补丁——泳道分区、逻辑播放(连线流光)、
  HTML 可播放导出,竖屏悬浮工具箱 / 宽屏三段式
- **零感知功耗**:静止零 ticker 设计(毛玻璃被动采样、无常驻动画),后台复位兜底

## 演示

<video src="docs/demo/VID_20260906_182410.mp4" controls width="100%"></video>

## 功能

- **待办(P-10)**:按日待办时间轴,完成即归档;回收站恢复/永久删除;任务可关联流程图
- **流程图编辑器(P-11)**:vyuh_node_flow 内核(third_party 内嵌 + 专有触摸/体验补丁),
  FlowDoc(v2)持久化,旧版数据自动迁移;泳道分区、锁定、连接校验、复制粘贴、
  逻辑播放(连线流光)、HTML 播放文件导出;竖屏悬浮工具箱 / 宽屏三段式;PC 键盘与 hover
- **首页**:问候与每日一言摘要、实时「待办」统计卡(点击直达待办)、组合卡、课程倒计时,
  网格支持拖拽排序与长按整理
- **工具集(P-08)**:目录化小工具(占位/服务/工具流),可加入首页快速启动
- 深浅色与 Monet 动态取色实时跟随;原生式开屏;后台复位兜底
- **课表与提醒**:课程倒计时常驻通知、上课/下课提醒(Android 前台服务 + 系统通知)

## 技术栈

- Flutter(Dart)+ flutter_miuix(组件)/ flutter_riverpod(状态)/ go_router(路由)
- 第三方内核:`third_party/vyuh_node_flow`(MIT,vendored 0.32.0,含本仓库专有补丁,
  补丁均以源码注释 `POC vendor 补丁(vX.Y …)` 为锚点标注)
- 持久化:shared_preferences(本地 JSON)

## 构建

```bash
flutter pub get
flutter run            # 调试运行(Android / Web)
flutter build apk --release
flutter build web --release
```

质量门:仓库提交要求 `flutter analyze` 0 issues 且全部测试通过:

```bash
flutter analyze
flutter test
```

## 目录速览

- `lib/domain|data|core|presentation` 分层;页面组件带功能编号(P-/C-/S-…),
  变更逐版本记录于 `CHANGELOG.md`
- `third_party/vyuh_node_flow` 流程图内核(vendored,含补丁,勿用 pub 版本替换)
- `PLAN_*.md` / `REPORT_*.md` 功能规划与流程总结(部分含内部编号,仅供参考)

## 许可证

见仓库 LICENSE(由作者维护;第三方依赖见各自声明)。
