// 空间壁纸视差着色器（P-24）
//
// 原理：单目深度图 + 焦点深度 → 逐像素位移，产生"焦点处钉住、前后景反向移动"
// 的立体感。这是空间壁纸的核心视觉机制 —— 3D 感来自【shader 怎么用深度图】，
// 而不是深度图本身。
//
// ★ 关于 uLayers（深度分层）—— 它是**为几何模板设计的补丁，对 AI 深度图有害**：
//   位移量 = (深度 - 焦点) × 强度。若深度是连续渐变（几何模板就是光滑斜坡），
//   位移量随之连续变化 → 同一物体内部各像素位移不同 → 整体被拉伸成"橡皮膜"。
//   把深度量化成 N 层能让层内刚体平移，对几何模板有效；但**真实深度图的等深线
//   是不规则曲线**，全局按深度值切层会在人物身上切出数条可见的斜向分割线。
//   因此 AI 模式下 uLayers 应置 1（关闭），见 P-24 页面 _runAiDepth。
//
// ★ 关于 uFocusBand（焦点带）—— 让"主体整片钉住"：
//   只有焦点那一条等深线不动是不够的（真实深度图上人物内部深度并不均匀）。
//   焦点带把 |深度-焦点| < band 的整片区域压成"不动"，再向外 smoothstep 平滑
//   过渡到全位移 —— 既得到"主体不动、背景滑动"的观感，又不产生硬分割线。
//
// 坐标约定（与 lens_refraction.frag 一致）：
//   paint 已 scale(1/dpr)，因此 FlutterFragCoord() 直接返回物理像素
//   [0,uSize.x] × [0,uSize.y]。uv = fragCoord / uSize。
//
// uniform 槽位（Flutter setFloat 按【float 分量】顺序编号，sampler 不占位）：
//   0,1  uSize        视口物理像素
//   2,3  uShift       位移向量（-1..1；方向 × 幅度）
//   4    uAmount      最大位移像素
//   5    uFocus       焦点深度 0..1
//   6    uShowDepth   深度可视化（0/1）
//   7    uDepthGamma  深度曲线（1=线性；>1 拉开前景差异）
//   8    uLayers      深度分层数（<=1 = 关闭；>1 = 量化成 N 层）
//   9    uFocusBand   焦点带宽度（0 = 关闭）
//   10   uZoom        视野放大倍率（≥1；给位移等效补 margin，防露底）
//
// ★ uZoom（本轮新增）—— 风景图走这条路时必须要有
//   逐像素位移会让画面边缘取到纹理之外，不处理就露出页面底色。与
//   layer_compose.frag 用同一套办法：把采样范围从 [0,1] 收紧到 [c, 1-c]。
//   ⚠️ 必须是【除以】uZoom：写成乘法会把采样范围扩到 [0,1] 之外，越界被
//      clamp 拉边 → 四周出现一圈拉伸糊边（这个方向极易写反）。
//
// ⚠️ sampler 必须【恒绑定】两个（即使不用深度可视化也要绑），
//    否则 Skia/Impeller 可能整体判定 shader 失效。
#version 460 core
#include <flutter/runtime_effect.glsl>
precision mediump float;

uniform vec2  uSize;
uniform vec2  uShift;
uniform float uAmount;
uniform float uFocus;
uniform float uShowDepth;
uniform float uDepthGamma;
uniform float uLayers;
uniform float uFocusBand;
uniform float uZoom;

uniform sampler2D uTexture;  // 原图（RGBA）
uniform sampler2D uDepth;    // 深度图（灰度，已归一化到 0..1）

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;

    // 视野放大：采样范围【收窄】到 [c, 1-c]，给逐像素位移等效补上 margin。
    vec2 uvz = (uv - 0.5) / uZoom + 0.5;

    // 深度：0 = 最远，1 = 最近（预设模板与 AI 深度图统一约定）
    float d = clamp(texture(uDepth, uvz).r, 0.0, 1.0);
    d = pow(d, uDepthGamma);

    // 深度分层（仅几何模板需要；AI 深度图应关闭）
    if (uLayers > 1.5) {
        d = floor(d * uLayers + 0.5) / uLayers;
    }

    // 相对焦点的深度差
    float rel = d - uFocus;

    // 焦点带：整片"主体"钉住，而非只有一条等深线
    float w = 1.0;
    if (uFocusBand > 0.001) {
        w = smoothstep(0.0, uFocusBand, abs(rel));
    }

    // 反向位移：比焦点近的向 +shift 移，比焦点远的向 -shift 移
    vec2 sampleUv = uvz + (uShift * rel * uAmount * w) / uSize;
    sampleUv = clamp(sampleUv, vec2(0.0), vec2(1.0));

    if (uShowDepth > 0.5) {
        fragColor = vec4(vec3(d), 1.0);
    } else {
        fragColor = texture(uTexture, sampleUv);
    }
}
