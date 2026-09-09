# 调研:沉浸光感(HDS)参数对齐分析

> 2026-07 调研,仅输出分析,**未落地任何代码**。
> 背景:评估 Flutter 侧接入鸿蒙"沉浸光感"的可行性。调研对象为社区包
> `harmony_immersive_glow`(GitCode,纯 Dart 近似)与 `ohos_immersive_light`(原生插件范例)。
> 结论先行:**系统级光感无法接入;组件级 HDS 系统材质仅原生可用;Flutter 侧唯一现实路径 =
> 自绘近似,且本项目已有 80% 基础设施(快照/预模糊/折射/双峰高光),差距集中于"光池/扫光/交互光圈"与"能力门禁分级"。**

---

## 1. 事实核实(来源)

| 项 | 核实结果 |
|---|---|
| `harmony_immersive_glow` | ✅ 真实存在。GitCode `ZuoYueLiang/harmony_immersive_glow_tabbar`(MIT,纯 Dart,git 依赖,无 pub 发布)。作者自述"近似",**不是 ArkUI 系统材质 API 的绑定**;真实 HDS 由 `@kit.UIDesignKit` 提供 |
| `ohos_immersive_light` | ✅ 真实存在。Flutter-OH 插件开发范例(CSDN 2026-06-05 实战教程,Windows 踩坑:example 不可用需自建工程、必须 `path:` 本地依赖) |
| 原生能力真身 | `HdsTabsFloatingStyle.systemMaterialEffect` / 标题栏 `systemMaterialEffect`(HDS 组件级系统材质,API 23+)+ 门禁 `hdsMaterial.getSystemMaterialTypes()`(含 `MaterialType.IMMERSIVE` 才允许 GENTLE/EXQUISITE,否则回退 SMOOTH) |
| 三个限制 | ✅ 均属 API 23+、华为独有(OpenHarmony 不可用)、第三方不可调系统级光感折射(pointLight 是 System API) |
| Flutter 侧差异 | 原文档明确:Flutter `BackdropFilter` 与 ArkUI 系统材质**不在同一合成管线**,采样范围/边缘裁剪/能力门禁/设备策略均不一致 |

**参考仓库克隆位置**:`<research-tree>/harmony_immersive_glow/`
核心文件:`lib\harmony_immersive_glow.dart`(1359 行)、`docs\native_hds_compare.md`、`README.md`。

---

## 2. 参考实现拆解(参数全表)

### 2.1 等级 × 6 参数(源码 `_HarmonyGlowMaterialPainter` / level extension)

| 等级 | blurSigma | fillOpacity(白底) | glowOpacity(光池) | shadowOpacity | specularOpacity(扫光) | scatterOpacity(散射) |
|---|---|---|---|---|---|---|
| `smooth` | **8** | .58 | .05 | .08 | .12 | .08 |
| `gentle` | **22** | .30 | .28 | .16 | .38 | **.90** |
| `exquisite` | **34** | .13 | .34 | .24 | .48 | .48 |
| `adaptive` | 22(跟随 gentle) | — | — | — | — | — |

`adaptive` 特殊:系统"减弱动画"(disableAnimations)→ 自动解析为 `smooth`,否则 `gentle`。

### 2.2 能力门禁(Flutter 侧适配)

```dart
harmonyGlowLevelForCapability(supportsImmersiveMaterial, preferExquisite)
// 不支持 → smooth;支持 → exquisite(或 preferExquisite:false → gentle)
```

- 原生侧 `hdsMaterial.getSystemMaterialTypes()` 返回含 `MaterialType.IMMERSIVE` 才允许 GENTLE/EXQUISITE;
- **Flutter 侧不能直接查询该 ArkUI API**,参考包通过宿主注入(`harmonyGlowLevelForCapability` 入参)实现门禁——本项目 §9 `plat` 能力层已计划承担此职责;
- `HarmonyGlowEffectTuning` 含 7 个乘子(`blurScale/surfaceScale/glowScale/shadowScale/specularScale/elasticScale/scatterScale`),在等级基础上二次微调,不改变等级语义。

### 2.3 调色板(默认)

| token | 值 | 语义 |
|---|---|---|
| `surfaceTint` | `#FFFFFF` | 材质底色 |
| `edgeHighlight` | `#E6FFFFFF` | 上/外缘高光描边 |
| `edgeShadow` | `#24000000` | 下缘/投影 |
| `activeColor` | `#1476FF` | 选中图标/文字 |
| `inactiveColor` | `#15171A` | 未选中 |
| `glowColors` | `#72E3C0` / `#7C8DF7` / `#FFC178` | 三色光池(青绿/靛紫/琥珀) |

### 2.4 材质层渲染结构(每帧)

```
[DecoratedBox: boxShadow(0,12) blur 12|24 × shadowScale]
└─ ClipRRect
   └─ Stack
      ├─ BackdropFilter(blur σ)                    → 主模糊(每帧实时)
      ├─ _HarmonyBackdropScatter(scatter>0 时)     → 3 层
      │   ├─ ImageFilter.matrix 中心放大 ×(1+.035c, 1+.012c) + 白 tint .028c
      │   ├─ blur(σx=σ(.65+.32c)≥2, σy=σ(.18+.08c)≥6) 平移 ±c + tint .018c
      │   ├─ blur(同 ·σ≥.78) 平移 ±c + tint .014c
      │   └─ _ScatterVeilPainter:4 白竖椭圆(screen, 相位漂移 ±4px)
      ├─ CustomPaint(_HarmonyGlowMaterialPainter)
      │   ├─ 白底 fill(σ fillOpacity×surfaceScale)
      │   ├─ 光池:3 色 RadialGradient(plus) 亮度 .38/.1, 半径 .55+.08i, 相位圆周漂移 9%宽/12%高
      │   ├─ 扫光:白 RadialGradient(screen) 横向扫动 68%宽/150%高
      │   └─ 边缘:1.1px LinearGradient(顶 .9→中 .2→底 .26) + 顶高光线(.7, 12px inset)
      └─ Material(transparency) + child
```

### 2.5 交互(悬浮底栏专属,按需)

按压→光池(3 色 caustic + 白 lens 高光)+ 弹簧 ticker(stiffness 68+24e / damping 14+4(1-e), 位置 clamp ±1.12,拖拽 pull clamp ±.24/.18)+ 整体 scale 拉伸(1+.34H+.035V / 1+.24V−.025H);图标按压 `.88 / 80ms`、回弹 `elasticOut / 360ms`;松手 `interactionFadeDuration 260ms reverse`。选中态切换**故意不再补白 flash**(对齐原生 HDS 只有按压中有白色光圈)。

### 2.6 性能成本(重要)

每帧含 **3 个 BackdropFilter**(1 个主 + 2 个散射 blur)+ 1 个 `ImageFilter.matrix` + 4 层 CustomPaint,无缓存——`exquisite`(σ34 + 高 scatter)≈ 每帧 3 次高斯离屏 pass,低端设备代价明显。README 自述:低端应回退 `smooth`;`BackdropFilter` 需后方真实内容(纯色背景效果弱)。

---

## 3. 项目现有能力盘点

双端一致(镜像与主项目 kernel/shaders **逐文件哈希 SAME**;镜像仅多 main.dart shader 预热):

| 能力 | 位置 | 现状 |
|---|---|---|
| 背景快照体系 | `MiuixLayerBackdrop`(flutter_miuix) | 快照 + globalOffset + **pixelRatio 可降采样**,驱动全部自研模糊/折射 |
| 预模糊缓存 | `kernel/blur.dart` `BackdropBlur`(+ `c27_prefrosted_blur.dart`) | **P0 缓存**:快照/采样区/半径不变时复用模糊纹理,每帧仅 `drawImageRect`——已在切页/按压中根治每帧高斯抖动;参考包无此优化 |
| 边缘折射 | `kernel/lens.dart` `LensRefraction` + `shaders/lens_refraction.frag` | 边缘折射(≈10dp)/彩虹/流动/深度,可 backdrop(页面+底栏玻璃);参数与 shader 均双端同源 |
| 双峰高光 | `kernel/dual_peak_highlight.dart` + `shaders/bloom_dual_peak.frag` | 方向双光(primary/secondary,180° 对峰),`LightSource` position/intensity/color + innerBlur + blendMode——与 HDS"点击光圈/高光"同构 |
| 毛玻璃组件 | `c22_mask_selection_bar` / `c23_push_collapsing_header` / `c24_frosted_fab` / `c25_frosted_top_bar`(官方毛玻璃) | U-03 策略统一管控 |
| 模糊策略 | `core/utils/u03_blur_policy.dart` | **sigma ≤ 20**、面积 ≤ 40% 视口、Android 13+ 开 / Web 关;**OH 无 androidSdkInt(判 null)→ 当前默认允许** |
| 阻尼拖拽 | `kernel/damped_drag.dart` | 已有(可作弹性 ticker 参考) |
| 主题 | `main.dart` `_shellTheme` seedColor = `theme.colors.primary`(MiuixThemeData 派生);Miuix 已铺 56 文件 | 主题 token 单一来源 = Miuix |
| shader 预热 | 仅镜像 `main.dart` `_warmupShaders`(lens_refraction + bloom_dual_peak) | 主项目懒加载(首次使用 `FragmentProgram.fromAsset`);Impeller/Vulkan 冷编译首次卡顿 |
| 卡片阴影 | `card_shell.dart` | 已有宽屏(≥600px)降级 tier(blur/offset 减半) |

---

## 4. 能力对照矩阵

| # | HDS 光感要素 | 参考包实现 | 本项目已有 | 结论 |
|---|---|---|---|---|
| 1 | 背景模糊(主材质) | BackdropFilter σ8–34 | `BackdropBlur` + P0 缓存 | ✅ **已有且更优**(缓存;σ 上限待 U-03 裁决) |
| 2 | 散射/放大感 | matrix 放大 1.035 + 2 路 blur 平移 + 白 veil | `LensRefraction`(边缘折射,非整面放大) | ⚠️ 部分:整面微放大需新 scatter 能力(可扩 lens shader 或新增小 shader) |
| 3 | 彩色光池 | 3 色 radial(plus)相位漂移 | `DualPeakHighlight`(方向光,非光池) | ⚠️ 需新 painter(简单 radial 循环,低成本) |
| 4 | 扫光/高光 sweep | 白 radial 横扫(screen) | 静态双峰高光 | ⚠️ 需 animationValue 驱动(现有 shader 可复用,接动画即可) |
| 5 | 边缘描边 + 顶光线 | 1.1px 渐变 + 顶线 .7 | `inner_shadow`(暗边) | ⚠️ 新增高光边(小 painter/重绘) |
| 6 | 按压光圈(白 lens) | 白 radial + 弹簧 ticker | 无(Miuix 按压高亮能力有限) | ❌ 需新增(交互) |
| 7 | 拖拽二维弹性形变 | spring ticker + scale 拉伸 | `damped_drag.dart` | ⚠️ 有基础件,需接入材质层 |
| 8 | 图标点击弹性 | .88 / 80ms, elasticOut 360ms | Miuix 组件自带 | ✅ 无需开发 |
| 9 | 能力门禁分级 | getSystemMaterialTypes + levelForCapability + disableAnimations | 无(§9 plat capability 计划中) | ❌ 属 §9 `plat_visual_tokens` 范畴 |

**自绘骨架(1/3/4/5)总代码量预估 ≈ 300–500 行**(painter + 组装),交互(6/7)另需 200–300 行 + 真机联调。

---

## 5. 关键冲突与风险

1. **σ 上限冲突**:HDS `exquisite` σ34 > U-03 `maxBlurSigma` 20。⚠️ 需裁决:OH 支持设备放宽(36)还是按 U-03 降级到 `gentle`(σ22 亦超 20,20 以内 ≈ 介于 smooth/gentle)。
2. **合成管线差异**(无法消除):`BackdropFilter`/快照均非 ArkUI 系统材质管线,采样范围、边缘裁剪、材质等级行为与真品不一致——参考包原生对比页用于人工校准(项目若做,需要一名对比基准;建议低优先级)。
3. **性能**:参考包每帧 3 次模糊无缓存;项目用预模糊缓存可压到 1 次。**若做光感必须走缓存路径**,否则违背 C-27 既有结论。
4. **门禁不可读取**:Flutter 侧无法查 `getSystemMaterialTypes()`,只能宿主注入;设备(API 23 真机)是否支持 IMMERSIVE 需原生侧探测(可复用 W3/W4 的 Plat* 通道模式)。
5. **无升级冲突**但 **无系统联动**:系统设置"沉浸光感 关/均衡/开"不可感知、不可联动——仅视觉近似,与小米 Miuix 液态玻璃定位一致,双端均可跑,Web 端按 U-03 禁用。

---

## 6. 建议(归 §9,不在本轮落地)

- §9 UI tokens(`plat_visual_tokens`)中新增**光感档位 token 组**:`{level, blurSigma, fillOpacity, glowOpacity, shadowOpacity, specularOpacity, scatterOpacity}` + 三色光池,默认 `adaptive`(=gentle,disableAnimations→smooth),能力注入走 plat capability(与 HUKS/picker 同一通道模式)。
- **复用优先**:主模糊→`BackdropBlur`(缓存);高光/光圈→`DualPeakHighlight`(shader 已就绪);散射→评估扩 `lens_refraction.frag`(midRefraction 微放大)或新增轻量 scatter shader;光池/边缘→新增 `GlowMaterialPainter`(纯 Canvas,无 shader 依赖,可先上)。
- **交互先不做**(按压光圈/拖拽弹性):高成本、真机基准缺失;首版只做静态材质(1–5),交互列为二期。
- **性能红线**:设备未知支持时强制 `smooth`(σ8);`exquisite` 仅真机验证后放开;任何档位都不得再用每帧多次 BackdropFilter。

---

## 7. 复核补充(2026-09,重写时追加)

1. **目标设备结论**:实际验收设备为 **OpenHarmony 6.1.1.120 / API 24 / arm64**(非华为 HarmonyOS)。HDS 系统材质(`systemMaterialEffect`、`getSystemMaterialTypes()`)在该设备上**不存在**,因此能力门禁必然解析为"不支持",自绘 `smooth`/`gentle` 档位是唯一可交付形态;`exquisite` 仅作后续在华为真机上验证后放开。
2. **σ 上限裁决建议**:既然系统材质不可用、光感完全自绘,σ 上限不必对齐 HDS 的 34;建议**维持 U-03 的 20 上限**,用 `gentle`(σ 收敛到 20)作为 OH 端默认,避免为了"参数对齐"而牺牲切页/滚动的帧率。
3. **文档编码事故记录**:本文件 2026-07 初版以 UTF-8 **带 BOM + GBK 双重编码**保存(PowerShell 写中文文件所致),2026-09 检测时正文已乱码、约 466 处字符在编码往返中永久丢失;本次按还原稿重写为 **UTF-8 无 BOM**。相关红线见 `D:\Projects\SYNC_RULES.md` 第 2 节。
