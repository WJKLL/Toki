// 指示框边缘折射着色器（液态玻璃：中间极轻放大 + 边缘折射/彩虹/沿边缘流动）。
//
// 坐标约定（关键，与 dual_peak_highlight 一致）：
//   paint 已 translate(offset) + scale(1/dpr)，因此 FlutterFragCoord() 直接返回
//   组件本地【物理像素】[0,uSize.x]×[0,uSize.y]（uSize = 布局尺寸 × 组件dpr）。
//   SDF/边缘带在【基础空间】计算：p = (local-center)/uScale（逆缩放回未放大
//   的 stadium，半径 uCornerRadius），支持 sx≠sy 非均匀形变；
//   折射采样在【本地物理】local 上做 → 放大溢出区域自然折射，映射正确。
//   法线：n_screen = normalize(n_base / uScale)。
//
// combined（参考项目 combinedBackdrop）：页面 uTexture + overlay uOverlay(底栏
// accent 标签层 tabsBackdrop)。注意：两个 sampler【恒绑定】（无 overlay 时
// uOverlay 也绑页面占位），否则 Impeller 报 missing sampler 使整个 shader 失效。
#version 460 core
#include <flutter/runtime_effect.glsl>
precision mediump float;

uniform vec2  uSize;               // 组件物理像素尺寸（布局 W'×H' × 组件dpr）
uniform float uCornerRadius;       // 基础圆角半径（未放大 stadium，28dp×dpr）
uniform vec2  uScale;              // 形变系数 (sx, sy)，非均匀缩放支持
uniform float uMidRefraction;      // 中间极轻折射量（px，负=向内→轻微放大）
uniform float uEdgeRefraction;     // 边缘带额外折射量（px，负=向内）
uniform float uEdgeWidth;          // 边缘带宽（px，基础空间）
uniform float uChromaticAberration;// 彩虹强度（0=关闭；按比例 → px 偏移）
uniform float uFlowAmount;         // 沿边缘流动幅度（px）
uniform float uFlowDir;            // 流动方向：右移+1(逆时针) / 左移-1(顺时针)
uniform float uDepthEffect;        // 深度效果（0/1）
uniform vec2  uSampleOffset;       // 页面快照相对偏移 = (组件全局-页面快照全局) × 页面快照dpr
uniform vec2  uImageSize;          // 页面快照像素尺寸
uniform float uDprScale;           // 页面快照dpr / 组件dpr
uniform vec2  uOverlayOffset;      // overlay(底栏标签)快照相对偏移（overlay dpr）
uniform vec2  uOverlayImageSize;   // overlay 快照像素尺寸
uniform float uOverlayDprScale;    // overlay dpr / 组件dpr
uniform float uHasOverlay;         // 是否有 overlay（1/0）
uniform sampler2D uTexture;        // 页面
uniform sampler2D uOverlay;        // 底栏标签玻璃层（tabsBackdrop）

out vec4 fragColor;

float sdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    float outside = length(max(cornerCoord, 0.0)) - radius;
    float inside = min(max(cornerCoord.x, cornerCoord.y), 0.0);
    return outside + inside;
}

vec2 gradSdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    if (cornerCoord.x >= 0.0 || cornerCoord.y >= 0.0) {
        return sign(coord) * normalize(max(cornerCoord, 0.0));
    } else {
        float gradX = step(cornerCoord.y, cornerCoord.x);
        return sign(coord) * vec2(gradX, 1.0 - gradX);
    }
}

vec4 sampleTex(vec2 localPx) {
    vec2 snapPx = localPx * uDprScale + uSampleOffset;
    // 越界（折射/色散把采样坐标推到快照外）：返回透明而非 clamp 拉伸，
    // 避免"边缘拉伸色条/发丝横线"（页面快照一般覆盖全屏，极少越界）。
    if (snapPx.x < 0.0 || snapPx.y < 0.0 ||
        snapPx.x > uImageSize.x || snapPx.y > uImageSize.y) {
        return vec4(0.0);
    }
    return texture(uTexture, snapPx / uImageSize);
}

vec4 sampleOverlay(vec2 localPx) {
    vec2 snapPx = localPx * uOverlayDprScale + uOverlayOffset;
    // 越界（指示框到最左/最右、放大溢出、折射偏移超出底栏本体快照）：
    // 返回透明 → combined 里 mix 落回页面层，而非 clamp 拉伸底栏边缘像素
    // 产生延伸到玻璃外的彩色横线。
    if (snapPx.x < 0.0 || snapPx.y < 0.0 ||
        snapPx.x > uOverlayImageSize.x || snapPx.y > uOverlayImageSize.y) {
        return vec4(0.0);
    }
    return texture(uOverlay, snapPx / uOverlayImageSize);
}

// 页面 + overlay（底栏标签）合成：标签非透明处覆盖页面（替换而非叠加，
// 避免双层图标 —— 底栏可见行被玻璃盖住，玻璃内只显示 accent 标签）。
vec4 sampleCombined(vec2 localPx) {
    vec4 base = sampleTex(localPx);
    if (uHasOverlay <= 0.5) return base;
    vec4 ov = sampleOverlay(localPx);
    return vec4(mix(base.rgb, ov.rgb, ov.a), max(base.a, ov.a));
}

void main() {
    vec2 local = FlutterFragCoord().xy;      // 组件本地物理像素 [0,uSize]
    vec2 halfSize = uSize * 0.5;

    // ── 基础空间 SDF：把放大后矩形逆缩放回未放大 stadium ──
    vec2 baseHalf = halfSize / uScale;
    vec2 p = (local - halfSize) / uScale;                 // 以基础中心为原点
    float radius = min(uCornerRadius, min(baseHalf.x, baseHalf.y));
    float sd = sdRoundedRect(p, baseHalf, radius);

    // 到边界的距离（内部为正；边界 sd=0，外部为负）。
    float dEdge = -sd;

    // 边缘带权重：贴边=1，深入 uEdgeWidth 后=0；外部(sd>0)按 1（溢出边缘）。
    float wEdge = 1.0 - smoothstep(0.0, max(uEdgeWidth, 0.001), max(dEdge, 0.0));
    if (sd > 0.0) wEdge = 1.0;
    // 中间权重：1 = 完全中心（仅极轻折射），0 = 贴边。
    float wMid = 1.0 - wEdge;

    // 中心无折射：若 midRefraction 为 0 且在边缘带内（wEdge 极小），
    // 直接原样采样（避免中心法线归一化的方向跳变产生放射分割线）。
    if (abs(uMidRefraction) < 0.001 && wEdge < 0.01) {
        fragColor = sampleCombined(local);
        return;
    }

    // ── 基础空间法线 → 屏幕空间法线（逆缩放）与逆时针切线 ──
    float gradRadius = min(radius * 1.5, min(baseHalf.x, baseHalf.y));
    vec2 pSafe = p + vec2(1e-4);
    vec2 nBase = normalize(gradSdRoundedRect(p, baseHalf, gradRadius)
                           + uDepthEffect * normalize(pSafe));
    vec2 n = normalize(nBase / max(uScale, vec2(1e-4)));
    // 逆时针切线：矩形顶边向右、右边向下。右移(+1)取逆时针 → uFlowDir 乘它。
    vec2 t = vec2(-n.y, n.x);

    // ── 折射偏移（本地物理采样）──
    // 中间：极轻向内折射（轻微放大，保留清透观感）。
    vec2 midOffset = n * (uMidRefraction * wMid);
    // 边缘：强折射（向内）+ 沿边缘流动（方向 uFlowDir）。
    // 柔和过渡：位移 ∝ wEdge²（而非 wEdge）→ 折射从边缘内缘渐进增强，
    // 中间几乎无折射、向边缘平滑变强，无生硬跳变（玻璃光滑表面）。
    float wSoft = wEdge * wEdge;
    vec2 edgeOffset = n * (uEdgeRefraction * wSoft)
                    + t * (uFlowDir * uFlowAmount * wSoft);
    // 偏移幅度上限（px）：只防极端（理论上限 > 折射+流动，不截断 smoothstep
    // 的平滑过渡 → 中间→边缘折射柔和丝滑；越界由 sample 归零兜底）。
    float maxOffset = max(uEdgeWidth, 0.001) * 1.6;
    vec2 total = midOffset + edgeOffset;
    if (length(total) > maxOffset) {
        total = normalize(total) * maxOffset;
    }
    vec2 refracted = local + total;

    // ── 彩虹（色散）：仅在【更窄的边缘带】出现（uEdgeWidth×0.5），
    // 使彩虹纹收窄、贴边，不与整个折射带同宽；3 通道采样。
    float caBand = uEdgeWidth * 0.5;
    float wCa = 1.0 - smoothstep(0.0, max(caBand, 0.001), max(dEdge, 0.0));
    if (sd > 0.0) wCa = 1.0;
    float ca = min(uChromaticAberration * abs(uEdgeRefraction) * wCa,
                   max(caBand * 0.33, 0.001));
    if (ca <= 0.0) {
        fragColor = sampleCombined(refracted);
        return;
    }
    vec2 caDir = n * ca;
    vec4 cR = sampleCombined(refracted + caDir);
    vec4 cG = sampleCombined(refracted);
    vec4 cB = sampleCombined(refracted - caDir);
    fragColor = vec4(cR.r, cG.g, cB.b, cG.a);
}
