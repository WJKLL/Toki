// 分层视差合成着色器（P-24 / 分层版）
//
// 为什么用 shader 而不是 Canvas 的多次 drawImage：
//   Canvas 路径在真机上出现"背景大范围泛白"，连续调整 FilterQuality / margin /
//   srcRect / 工作尺寸全部无效。shader 路径已被本项目验证可靠（几何模板
//   spatial_parallax.frag 从未出问题），且缩放由 GPU 双线性完成。
//
// 合成公式即标准 source-over，从【最远层】开始：
//     acc = mix(acc, layerColor, layerAlpha)
//
// uniform 槽位（Flutter setFloat 按 float 分量顺序编号，sampler 不占位）：
//   0,1    uSize     视口物理像素
//   2,3    uShift    单位位移方向（-1..1）
//   4      uAmount   最大位移（物理像素）
//   5..8   uCoefs    各层【位移系数】（远 → 近；最近层 = subjectRatio）
//   9      uCount    实际层数
//   10     uZoom     视野放大倍率（≥1；见下）
//   11..14 uReliefs  各层的【立体起伏系数】（只有最近层非 0）
//
// ★ 位移系数按【层序距离焦点层】给，而不是按"层中心深度 − 焦点"：
//   后者在 2 层下只能做出 ~6px 的层间差，要看出空间感就得把总位移拉到 20px+，
//   而总位移一大，采样越界的边缘拉伸就明显。
//
// ★★ uReliefs：主体层的【立体起伏】
//   主体若只做整层刚性平移，内部所有像素位移完全相同 —— 看上去就是一块
//   硬邦邦的平板。真实物体鼻梁比耳朵近、肩膀比腰近，晃起来位移应当各不相同。
//   这里让最近层的位移在常量系数之上再叠加一项，随【深度】变化：
//       off = uShift * (coef + relief * (depth − 0.5)) * uAmount / uSize
//   于是主体内部产生"深度差 → 位移差"的起伏（浮雕感），主体就有了体积。
//
//   为什么以前不敢这么做：逐像素位移会产生遮挡空洞。现在主体层之下有背景层
//   兜底，空洞会被背景内容填上 —— 所以【背景层继续整层平移（避免空洞）、
//   主体层改回逐像素（产生起伏）】，两者各取所需。
//   起伏幅度只有几个像素，空洞远小于主体自身尺寸，背景层足以盖住。
//
// ★★ uZoom：用【视野放大】替代 margin，修"位移时露出底图"
//   层图尺寸 = 视口尺寸（DepthLayerSplitter 的 margin=0），位移一发生，
//   画面边缘就取到纹理之外 —— 那里没有任何层覆盖，于是直接露出页面底色。
//   三条可行路径：
//     a) 露出就露出（原状）—— 不可接受；
//     b) 越界 clamp 到边缘像素 —— 不露底，但四周会有一圈被拉伸的糊边，
//        位移来回摆动时糊边宽度跟着变，很容易看出来；
//     c) ★ 把采样范围从 [0,1] 收紧到 [c, 1-c] —— 等效于给每层补了 margin。
//   取 c)。末尾仍保留 clamp 兜底。
//   ⚠️ 必须是【除以】uZoom：乘以 uZoom 会把采样范围扩到 [0,1] 之外，
//      越界后被 clamp 拉边 → 整张图四周出现拉伸糊边（实测反馈）。
//
// ⚠️ 所有 sampler 必须【恒绑定】（层数不足时用第 0 层占位），
//    否则 Skia 会判定 shader 失效 —— 这是 lens_refraction.frag 踩过的坑。
#version 460 core
#include <flutter/runtime_effect.glsl>
precision mediump float;

uniform vec2  uSize;
uniform vec2  uShift;
uniform float uAmount;
uniform vec4  uCoefs;
uniform float uCount;
uniform float uZoom;
uniform vec4  uReliefs;

uniform sampler2D uL0;
uniform sampler2D uL1;
uniform sampler2D uL2;
uniform sampler2D uL3;
uniform sampler2D uDepth;

out vec4 fragColor;

// 当前像素的归一化深度（0 = 最远，1 = 最近）。
float depthAt(vec2 uv) {
    return texture(uDepth, clamp(uv, vec2(0.0), vec2(1.0))).r;
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;

    // 视野放大：把采样范围【收窄】到 [c, 1-c]，给每层等效补上 margin。
    vec2 uvz = (uv - 0.5) / uZoom + 0.5;

    float d = depthAt(uvz);
    vec4 acc = vec4(0.0, 0.0, 0.0, 0.0);

    // 层 0（最远）—— 永远绘制，它是铺底的那层
    vec2 off0 = uShift *
        (uCoefs.x + uReliefs.x * (d - 0.5)) * uAmount / uSize;
    vec4 c0 = texture(uL0, clamp(uvz + off0, vec2(0.0), vec2(1.0)));
    acc = mix(acc, c0, c0.a);

    if (uCount > 1.5) {
        vec2 off = uShift *
            (uCoefs.y + uReliefs.y * (d - 0.5)) * uAmount / uSize;
        vec4 c = texture(uL1, clamp(uvz + off, vec2(0.0), vec2(1.0)));
        acc = mix(acc, c, c.a);
    }
    if (uCount > 2.5) {
        vec2 off = uShift *
            (uCoefs.z + uReliefs.z * (d - 0.5)) * uAmount / uSize;
        vec4 c = texture(uL2, clamp(uvz + off, vec2(0.0), vec2(1.0)));
        acc = mix(acc, c, c.a);
    }
    if (uCount > 3.5) {
        vec2 off = uShift *
            (uCoefs.w + uReliefs.w * (d - 0.5)) * uAmount / uSize;
        vec4 c = texture(uL3, clamp(uvz + off, vec2(0.0), vec2(1.0)));
        acc = mix(acc, c, c.a);
    }

    fragColor = acc;
}
