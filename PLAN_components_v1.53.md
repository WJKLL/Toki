# 空间壁纸 · 组件 / 景深 / 导出 / 模板 完整方案

> 版本：v1.53 提案（待审核）
> 前置：`PLAN_wallpaper_v1.52.md`（P-24 分层视差已落地）
> 状态：**仅规划，未改代码**
> 编号说明：本文用描述性名称；具体 S-/C-/U- 编号在落地时按 `PROJECT_SPEC.md` 分配，避免与在编条目冲突。

---

## 0. 结论摘要（先看这段）

**这次要做的四件事，其中三件事的地基已经打好了。**

| 要做的 | 家底 | 判断 |
|:--|:--|:--|
| **组件玻璃质感** | `LensRefraction`（C-22 底栏那套液态玻璃，含折射 + 色散 + 内阴影） | ✅ **直接复用**，不新造 |
| **导出静态图** | `PlatFileOps.saveImageToGallery`（MediaStore → `Pictures/Toki`） | ✅ **直接复用** |
| **模板体系** | `DepthTemplate` 3 个几何模板 + `tools.json` 外部化配置模式 | 🟡 扩展成四层 |
| **导出动态视频** | **无**（全项目零视频基础设施） | 🔴 **唯一需要新造的部分** |

**唯一的技术硬骨头是"导出几秒视频"**，而它的难点不在渲染，在**编码**。本文第 6 节给出结论：**录轨迹 + 离屏重渲染 + 编码走平台注册制**。

---

## 1. 家底盘点（可复用资产，逐条已核）

| # | 资产 | 位置 | 本方案怎么用 |
|:--|:--|:--|:--|
| 1 | 分层视差渲染（GPU 合成） | `lib/presentation/widgets/kernel/layered_parallax_view.dart` + `shaders/layer_compose.frag` | 组件层的底板，**原样复用** |
| 2 | **液态玻璃折射组件** | `lib/presentation/widgets/kernel/lens.dart`（`LensRefraction`）+ `shaders/lens_refraction.frag` | **组件玻璃质感的核心** |
| 3 | 玻璃参数面 | `LensRefraction`：`midRefraction` / `edgeRefraction` / `edgeWidth` / `chromaticAberration` / `flowAmount` / `depthEffect` | 直接映射成用户可调项 |
| 4 | 背景快照机制 | `MiuixLayerBackdrop` + `MiuixLayerBackdropCapture` | 玻璃的背板来源 |
| 5 | 降采样快照 | `lib/presentation/widgets/c28_downsampled_capture.dart` | 玻璃背板降采样，控性能 |
| 6 | **保存图片到相册** | `lib/core/platform/contract/plat_file_ops.dart` → `saveImageToGallery` | **静态导出直接用** |
| 7 | 保存任意文件 | 同上 → `saveFile` | 导出 GIF / HTML / JSON 用 |
| 8 | 图片保存服务 | `lib/core/media/image_saver_service.dart` | 格式判定 / 文件名，复用 |
| 9 | **导出器模式范本** | `lib/core/export/flow_html_exporter.dart`（P-11 流程图导出 HTML） | HTML 互动包照抄这个模式 |
| 10 | 参数驱动 UI 模式 | `lib/presentation/widgets/c40_tool_dynamic_params.dart`（text/number/select/file） | **复用模式**，需扩展 `slider` |
| 11 | 几何深度模板 | `lib/domain/entities/depth_template.dart`（径向 / 线性 / 分带） | 并入新模板体系的"深度层" |
| 12 | 端侧深度推理 | `lib/core/depth/depth_inference.dart` + `DepthInferenceRegistry` | 已是注册制，模板体系直接对接 |
| 13 | 平台契约注册制 | `PlatFileOpsRegistry` / `DepthInferenceRegistry` | **视频编码器照这个模式做** |
| 14 | 确定性 muxix 图标 | `lib/core/widgets/app_icons.dart` | 新 UI 图标来源 |

**结论**：8 成地基已在。本方案的主要工作是**组装 + 扩展 + 补一个编码契约**，不是从零造。

---

## 2. 架构总览

```
┌──────────────────────── 编辑 UI 层（可整体替换） ────────────────────────┐
│  P-24 空间壁纸页（现有）                                                  │
│    ├─ 画面舞台         ← 已有                                            │
│    ├─ 参数面板         ← 由 schema 生成（见 §7），UI 可重做               │
│    ├─ 组件面板         ← 新增                                            │
│    └─ 导出面板         ← 新增                                            │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ 只传纯数据
┌───────────────────────────────▼──────────────────────────────────────┐
│                       SpacialScene（纯数据场景图）                      │
│   分层来源 + 运动参数 + 组件列表 + 全局观感参数                            │
└───────┬───────────────────────────────────────────┬──────────────────┘
        │                                           │
┌───────▼────────────────┐              ┌───────────▼──────────────────┐
│   实时渲染内核          │              │   离屏渲染内核（导出用）        │
│  分层视差 + 组件层      │              │   同源逻辑，无 widget 依赖      │
│  （屏幕预览）           │              │   → 帧序列                    │
└────────────────────────┘              └───────────┬──────────────────┘
                                                    │
                                        ┌───────────▼──────────────────┐
                                        │  编码契约（平台注册制）         │
                                        │  GIF（纯 Dart 兜底）          │
                                        │  MP4（Android / OH 各自实现） │
                                        └──────────────────────────────┘
```

**三条架构红线**（为了"留好 UI 改造空间"）：

1. **UI 只读 schema、只写 `SpatialScene`** —— UI 怎么改都不影响内核。
2. **组件走注册表** —— 加组件类型不改渲染内核、不改面板代码。
3. **实时内核与离屏内核共用同一份合成逻辑** —— 预览所见即导出所得。

---

## 3. 组件系统（不止时钟）

### 3.1 组件类型清单（建议）

| 组别 | 组件 | 说明 |
|:--|:--|:--|
| **时间** | 数字时钟、模拟时钟、日期、星期、倒计时、秒表 | 时钟是首要 |
| **信息** | 天气、电量、步数、日期节日 | 需平台数据，可后期 |
| **装饰** | 文字（多种字体/排印）、Logo、图片贴纸、形状（圆/线/框） | |
| **氛围** | 光斑、颗粒、暗角、边缘光 | 可与 P-23 光感合并 |

**期 1 只做：数字时钟 + 文字**。其余按需增量，因为**注册制下加组件不改内核**。

### 3.2 组件数据模型（草案）

```dart
/// 组件类型标识（注册表 key）。
class SpatialComponentKind {
  static const String clock  = 'clock';
  static const String text   = 'text';
  static const String logo   = 'logo';
  // 新增只需在此登记 + 注册一个渲染器
}

/// 一个组件的完整状态（纯数据，可序列化）。
class SpatialComponent {
  final String id;
  final String kind;            // ← 注册表 key

  // ── 位置与形态 ──
  final double u, v;            // 归一化位置 0..1（跟随画面比例）
  final double scale;
  final double rotation;        // 平面内旋转

  // ── 空间（景深三要素）──
  final double depth;           // Z：0 最远 .. 1 最近  → 决定遮挡 + 景深虚化
  final double parallax;        // 位移系数 -1..1     → 默认 0（固定）
  final double tiltX, tiltY;    // 平面倾角
  final double perspective;     // 透视强度

  // ── 玻璃质感 ──
  final double opacity;         // 内容不透明度
  final double glass;           // 玻璃感总旋钮 0..1
  final double blur;            // 背景模糊
  final double tint;            // 底色浓度
  final double refraction;      // 折射（→ LensRefraction.edgeRefraction）
  final double chromatic;       // 色散 / 彩虹（→ chromaticAberration）
  final double rim;             // 边缘高光
  final double corner;          // 圆角

  // ── 类型专属参数（schema 驱动）──
  final Map<String, Object?> props;   // 例：clock 的 {24h:true, showDate:true}

  // ── 景深虚化 ──
  final double dofBlur;         // 自身虚化强度（"组件可景深"）
}
```

### 3.3 关键设计：**Z 与视差解耦**（沿用上轮结论）

| 维度 | 决定什么 | 时钟默认 |
|:--|:--|:--|
| **depth（Z）** | 遮挡关系 + 阴影 + 景深虚化量 | **1.0（最前）** |
| **parallax** | 动不动、动多少 | **0（完全固定）** |

> 这样"时钟固定"与"时钟在最上层"可以同时成立 —— 这是鸿蒙那个效果的唯一正确解。

### 3.4 组件的"动"是**倾斜**，不是位移

```
位置 = 固定（不随 shift 平移）
倾角 = f(shift)      ← 晃动时轻微反向倾斜 → "像贴上去"
```

同时满足："时钟没动" + "有侧向透视感"。

---

## 4. 景深（组件可景深）

"组件可景深"落成**三个独立机制**，按需开关：

| # | 机制 | 用户可调 | 实现 |
|:--|:--|:--|:--|
| **1** | **遮挡**（前/后关系） | Z 滑块 + "置于主体前/后" | 层 alpha 做遮罩（见 §4.1） |
| **2** | **视差跟随** | 视差系数滑块（0 = 固定） | 组件自身 translate |
| **3** | **景深虚化**（真正的 DOF） | 虚化强度滑块 | `ImageFilter.blur` 或进 shader |

**⭐ 机制 3 是"组件可景深"最直观的解释**：组件按自己的 Z 获得不同程度的虚化 —— 放在主体之后 → 轻微虚化（像真的远了一截）；放最前 → 完全清晰。这比单纯遮挡更有"立体"说服力。

### 4.1 遮挡：用层 alpha 做遮罩，**不需要逐像素深度测试**

`depth_layer_splitter.dart` 产出的**每层自带 alpha 通道**，它天然就是"这层覆盖了哪些像素"：

```
主体层 alpha = 255 的区域  →  组件被裁掉
主体层 alpha = 0   的区域  →  组件正常显示
```

**实现**：把主体层 alpha 作为 `ui.Image`，用 `ImageShader` + `BlendMode.dstOut` 擦除组件；遮罩随视差**同步平移**，天然对齐；边缘可羽化。

**难度从"高"降到"中"**，因为不用做深度测试。

---

## 5. 玻璃质感（复用 `LensRefraction`）

### 5.1 为什么复用而不是用 `BackdropFilter`

项目里 **C-22 底栏的液态玻璃已经跑通**（`lens_refraction.frag`），它比 `BackdropFilter` 强得多：

| | `BackdropFilter` | **`LensRefraction`（已有）** |
|:--|:--|:--|
| 模糊 | ✅ | ✅ |
| **边缘折射** | ❌ | ✅ `edgeRefraction` |
| **彩虹色散** | ❌ | ✅ `chromaticAberration` |
| **内阴影/立体感** | ❌ | ✅ `depthEffect` |
| 形变支持 | ❌ | ✅ `scaleX/scaleY` |

> 截图里那种"玻璃有厚度、边缘发亮"的观感，正是**折射 + 色散**带来的，`BackdropFilter` 做不出来。

### 5.2 用户侧暴露的参数（映射到 `LensRefraction`）

| 用户看到的滑块 | 映射到 | 默认 |
|:--|:--|:--|
| 透明度 | `opacity`（内容） | 0.92 |
| **玻璃感**（总旋钮） | 联动下面 4 项 | 0.55 |
| 背景模糊 | `blur` | 14 |
| 底色浓度 | `tint` | 0.16 |
| **折射强度** | `edgeRefraction` / `edgeWidth` | 6 |
| **彩虹边缘** | `chromaticAberration` | 0 |
| 边缘高光 | `rim` | 0.55 |
| **玻璃厚度感** | `depthEffect` | on |

**"玻璃感"总旋钮 → 简单模式；展开 7 项 → 高级模式**。两档并存，符合"可调参数到自己想要的效果"。

### 5.3 性能约束（必须遵守）

- 玻璃背板走 **`C-28` 降采样捕获**，不每帧全分辨率快照
- 组件数上限 **5**；超出时远端组件降级为纯色（不折射）
- 模糊/折射参数**不进每帧重建路径**（静态参数只改 shader uniform）

---

## 6. 导出系统

### 6.1 三种导出物

| 导出物 | 用途 | 形态 |
|:--|:--|:--|
| **静态图** | 做壁纸、发图 | PNG / JPEG，1×/2×/3× |
| **动态视频** | 发朋友圈/小红书，展示晃动效果 | MP4（首选）/ GIF（兜底） |
| **互动 HTML 包** | 分享给别人"亲手晃一晃" | 单文件 HTML |

### 6.2 静态图（✅ 最简单，期 1 就能做）

```
离屏渲染一帧 → ui.Image → PNG/JPEG 字节
  → PlatFileOps.saveImageToGallery()   ← 已有，落 Pictures/Toki
```

分辨率选项：`1080×1920` / `1440×2560` / 原始比例。

### 6.3 ⭐ 动态视频：**录轨迹 + 离屏重渲染**

**核心判断：不要录屏，要录轨迹。**

用户说"录制用户操作（陀螺仪等等的变动，导出几秒效果视频）"。两种做法：

| | 录屏（MediaProjection） | **录轨迹 + 离屏重渲染** ✅ |
|:--|:--|:--|
| 权限 | 需要系统授权弹窗 | **零权限** |
| 画质 | 跟着屏幕走，有码率损失 | **任意分辨率，无损合成** |
| 包含 UI | 会录到按钮/面板 ❌ | **只有纯净画面** ✅ |
| 可编辑 | ❌ | **可裁剪、平滑、变速** ✅ |
| 跨端 | 鸿蒙要重写 | 轨迹数据跨端 |

**做法**：
1. 录制时只存 `[(t, shiftX, shiftY), ...]` 时间序列（几十 KB）
2. 导出时**离屏**按这条轨迹逐帧跑合成
3. 帧序列 → 编码器 → 视频

**录制源可以有两种**（都走同一条轨迹格式）：
- **真机陀螺仪/晃动**（真实感）
- **预设运动曲线**（稳定、免设备）

> 关键前提已具备：渲染逻辑完全在 `layer_compose.frag` + 层图像里，**不依赖 widget 树** → 离屏逐帧渲染可行且快。

### 6.4 🔴 编码：这是唯一的硬骨头

| 方案 | 真 MP4 | Android | 鸿蒙 | Web | 体积代价 |
|:--|:--:|:--:|:--:|:--:|:--|
| **GIF（纯 Dart）** | ❌ 动图 | ✅ | ✅ | ✅ | +0（自带编码） |
| **平台 MediaCodec（原生）** | ✅ | ✅ | ❌ 需用 OH AVCodec 重写 | ❌ | 小 |
| `ffmpeg_kit_flutter` | ✅ | ✅ | ❌ `.so` 不跨端 | ❌ | **+30~40MB** |
| 第三方录屏插件 | ✅ | ✅ | ❌ | ❌ | 中 |

**结论：编码必须走平台注册制**，完全对齐项目已有的 `PlatFileOpsRegistry` / `DepthInferenceRegistry` 模式：

```
抽象：abstract interface class VideoEncoder {
         Future<EncodedVideo?> encode(List<ui.Image> frames, {int fps});
       }
注册：VideoEncoderRegistry.register(...)
默认实现：GifEncoder      ← 纯 Dart，全平台兜底，零依赖 ✅
Android 增强：Mp4Encoder   ← MediaCodec + MediaMuxer（原生 Kotlin）
鸿蒙实现：   Mp4Encoder    ← OH AVCodec / AVMuxer（镜像仓另写）
Web 实现：   WebmEncoder   ← canvas + MediaRecorder
```

**内核只调注册表，不知道具体格式** → 后续想换编码器不改业务代码 ✅

**建议路径**：
- **期 2**：先做 **GIF**（纯 Dart，立刻可用、全平台、含鸿蒙）
  - 参数建议：`540×960`、`15fps`、`2.5s` → 约 2~4 MB（可直接发微信）
- **期 3**：补 **Android MP4**（原生 MediaCodec），鸿蒙侧留接口
- ❌ **不推荐 ffmpeg**：+30~40MB 换来一个鸿蒙用不了的能力

### 6.5 ⭐ 互动 HTML 包（低成本高价值）

项目已有 `flow_html_exporter.dart`（P-11 导出 HTML 播放文件）**现成范本**。

- 把分层图 base64 内联 + 组件 + 运动参数 → **单文件 HTML**
- 打开即可用鼠标/陀螺仪看视差效果 —— **就是本轮那个仿真 HTML 的自动化版**
- 还能内嵌 `canvas.captureStream()` + `MediaRecorder` → **在浏览器里一键导 WebM**
- 跨平台、零原生依赖 ✅

**这个方案能顺手解决"分享"需求**：别人不用装 App 就能看到你的空间壁纸效果。

---

## 7. 模板体系（"整理我的模板"）

### 7.1 现状：模板只有一层

现在只有 **`DepthTemplate`（3 个几何深度模板）**：中心凸起 / 斜向纵深 / 前中后景。
它是 **B4 决策的降级链产物**（AI 失败时兜底），**不是面向用户的效果模板**。

### 7.2 建议：整理成四层

```
┌ 场景模板（ScenePreset）— 一键套用的完整效果           ← 面向用户
│   ├─ 深度层（DepthSource）
│   │     ├─ AI 推理（YOLO26-n ONNX）        ← 已有
│   │     └─ 几何模板（现有 3 个）            ← 已有，建议扩到 5~6 个
│   ├─ 运动层（MotionPreset）
│   │     视差强度 / 分层数 / 主体平滑 / 焦点带 / 深度曲线 / 运动曲线
│   ├─ 组件层（List<SpatialComponent>）
│   │     时钟 / 文字 / Logo 各自的完整状态
│   └─ 导出层（ExportPreset）
│         尺寸 / 帧率 / 时长 / 格式
└ 用户模板（UserPreset）— 用户自己存的效果，可命名、可分享
```

### 7.3 序列化

- **格式**：JSON（与 `tools.json`、`FlowDoc` 一致的思路）
- **存储**：`shared_preferences`（小）/ 文件（含缩略图时）
- **分享**：一段 JSON 字符串即可（可编码进二维码/链接）

```json
{
  "v": 1,
  "name": "黄昏窗景 · 玻璃时钟",
  "depth": { "source": "ai", "model": "yolo26n-depth_fp16" },
  "motion": { "amount": 16, "layers": 3, "smooth": 0.45, "focusBand": 0.12,
              "curve": "sway", "subjectRatio": 0.25 },
  "components": [
    { "kind": "clock", "u": 0.5, "v": 0.14, "depth": 1.0, "parallax": 0.0,
      "glass": 0.55, "blur": 14, "refraction": 6, "opacity": 0.92,
      "props": { "h24": true, "showDate": true } }
  ],
  "export": { "size": "1080x1920", "fps": 15, "seconds": 2.5, "format": "gif" }
}
```

### 7.4 内置模板建议（首批 6 个）

| 模板 | 深度来源 | 运动 | 组件 |
|:--|:--|:--|:--|
| 人像 · 玻璃时钟 | AI | 主体 0.25，背景大 | 时钟（玻璃） |
| 风景 · 纵深 | AI | 同向递减 | 无 / 小日期 |
| 建筑 · 反向立体 | AI | 主体反向 | 时钟 + Logo |
| 二次元 · 轻晃动 | AI | 小幅度 | 时钟 |
| 中心凸起（几何） | 几何径向 | 中等 | 时钟 |
| 前中后景（几何） | 几何分带 | 中等 | 文字 |

---

## 8. 为交互 UI 改造预留的空间（重点要求）

用户明确要求"留好交互 UI 改造的空间"。四条措施：

### 8.1 参数 **schema 驱动**，UI 自动生成

复用项目已有的 `C-40` 模式（`tools.json` → 自动生成控件，**新增工具不改代码**）。

**现状缺口**：`C-40` 只支持 `text / number / select / file`，**没有 `slider`**。

**做法**：扩展 `ToolParamType`（或新建空间壁纸专用 schema），增加 `slider`（范围 + 步长 + 单位）。
→ 之后**所有参数面板都由 schema 生成**，改 UI = 改布局，不改内核。✅

### 8.2 组件走**注册表**，加组件不改面板

```dart
SpatialComponentRegistry.register(
  kind: 'clock',
  schema: [...],          // 参数 schema → 面板自动出现
  builder: (props) => ..., // 渲染器
  icon: ...,
);
```
新增"天气""倒计时"→ **只加一个注册项**，面板和渲染自动跟进。

### 8.3 渲染内核只吃**纯数据**

内核签名固定为 `render(SpatialScene, shift) → ui.Image`。
UI 层怎么重构，内核零改动。

### 8.4 导出内核**不依赖 widget 树**

离屏渲染独立成管线，与编辑界面完全解耦 → 将来做"批量导出""后台导出"不用动 UI。

---

## 9. 分期路线

| 期 | 内容 | 交付判据 | 复用/新建 |
|:--|:--|:--|:--|
| **1** | 组件模型 + **数字时钟** + Z/视差解耦 + **3D 透视** + 透明度；参数 schema 机制 | 时钟固定、有侧向透视感 | 模型新建，schema 扩展 C-40 |
| **2** | **玻璃质感**（复用 `LensRefraction`）+ 简单/高级两档 + 景深虚化（DOF） | 时钟呈玻璃质感，能透出**正在移动**的画面 | ✅ 复用 C-22 玻璃 |
| **3** | **静态图导出**（PNG/JPEG @ 可选尺寸） | 存进相册 `Pictures/Toki` | ✅ 复用 `saveImageToGallery` |
| **4** | **模板体系**：四层模型 + 内置 6 模板 + 用户保存/加载 | 一键套用、可命名、可分享 JSON | 模型新建，pattern 复用 |
| **5** | **运动轨迹录制** + **离屏渲染管线** + **GIF 导出** | 录一段晃动 → 导出 2.5s 动图 | 管线新建，编码纯 Dart |
| **6** | **深度遮挡**（层 alpha 遮罩 + 羽化） | 组件置于主体后被挡住 | 扩展 splitter |
| **7** | 文字 / Logo / 图片贴纸 | 多组件共存 | 注册表增量 |
| **8** | 编辑手势（拖拽/缩放/旋转/Z/删除/层级） | 自由摆放 | 新建 |
| **9** | Android **MP4** 编码 + 鸿蒙 AVCodec 接口 | 导出真视频 | 注册制，原生 |
| **10** | 互动 HTML 包导出 | 分享即可看 | ✅ 照抄 `flow_html_exporter` |
| **11** | 真机陀螺仪实时驱动 | 实时响应 | `sensors_plus` |

**建议先做到期 5** —— 到那一步，"调参 → 看效果 → 导出图/动图"整条用户链路就闭环了。

---

## 10. 决策结果（用户已审核）

| # | 决策 | **结论** |
|:--|:--|:--|
| **A** | 视频格式优先级 | ✅ **先 GIF**（纯 Dart，全平台含鸿蒙）；MP4 放到期 9 |
| **B** | 是否接受 ffmpeg | ✅ **不使用**（+30~40MB 且鸿蒙用不了） |
| **C** | 玻璃实现 | ✅ **复用 `LensRefraction`**（折射 + 色散 + 厚度感）；`BackdropFilter` 方案作废 |
| **D** | 组件默认视差系数 | ✅ **0（完全固定）** |
| **E** | 主体运动方向 | ✅ **同向递减为默认**（远 1.0 / 中 0.55 / 主体 0.25）；"反向"做成可选滑块 |
| **F** | 内置模板数量 | ✅ **6 个** |
| **G** | 互动 HTML 包 | 🟡 **待确认**（见 §6.5；用户询问其含义） |
| **H** | 起点 | ✅ **期 1 起，按序落地** |

> **C 的影响（重要）**：§5 的玻璃质感全部基于 `LensRefraction` 实现；上轮"用 `BackdropFilter` 做玻璃"的初步方案作废，避免两条玻璃路径并存。

---

## 11. 风险

| 风险 | 影响 | 对策 |
|:--|:--|:--|
| `LensRefraction` 需 `MiuixLayerBackdrop` 快照 | 每帧快照有成本 | 走 `C-28` 降采样；参数不变时不重捕获 |
| 组件玻璃 + 分层 shader 共存 | 可能出现合成异常 | 期 2 先真机验证；失败退化为"底色 + 高光"假玻璃 |
| GIF 体积 | 太大不便分享 | 限 `540×960 / 15fps / 2.5s`；提供时长/尺寸档位 |
| 遮挡遮罩精度 | 主体边缘穿帮 | 羽化 + 遮罩随视差同步平移 |
| 离屏渲染与实时预览不一致 | 导出非所见 | 共用同一份合成逻辑（架构红线 3） |
| 组件过多掉帧 | 低端机卡顿 | 上限 5 个；超限降级 |
| 鸿蒙侧编码缺失 | 导不出真 MP4 | GIF 全平台兜底；MP4 走注册制留给镜像仓 |

---

## 12. 下一步

**本文档只做规划，未改任何代码。**

请审核第 10 节的 8 个决策点。确认后我按选定顺序落地，并把本方案并入 `PLAN_wallpaper_v1.52.md` 的姊妹文档体系。
