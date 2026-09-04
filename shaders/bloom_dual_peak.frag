// Bloom 双峰高光着色器（dualPeak）
// 基于 flutter_miuix 官方 miuix_bloom_stroke.frag（single-peak，验证正确），
// 仅两处差异（对齐 compose-miuix-ui buildBloomStrokeShader(dualPeak=true)）：
//   1. 删除 axis1/axis2 uniform；
//   2. lightBlock = dot(N.xy, L.xy)² → 单光源产生 180° 对峰（双峰）。
#version 460 core
#include <flutter/runtime_effect.glsl>
precision mediump float;

uniform vec2 halfView;          // 区域半尺寸（像素）
uniform vec2 halfViewFloor;     // floor(halfView)
uniform vec4 cornerRadii;       // [TL, TR, BL, BR] 像素圆角
uniform float strokeWidth;      // 描边带宽（像素）
uniform float innerBlurRadius;  // 内发光 halo 深度（像素）
uniform float innerBlurRadiusSq;
uniform float highlightAlpha;   // 整体不透明度
uniform vec4 strokeColor;       // 描边色（rgb，a=1）
uniform float strokeAlphaMul;   // 描边色原始 alpha 乘子
uniform vec3 lightDir1;
uniform vec3 lightColor1;
uniform float lightIntensity1;
uniform vec3 lightDir2;
uniform vec3 lightColor2;
uniform float lightIntensity2;
// dualPeak：无 axis1/axis2 uniform。

out vec4 fragColor;

float pickRadius(vec2 fragCoord, vec4 radii) {
    vec2 up = fragCoord.y < halfView.y ? radii.xy : radii.zw;
    return fragCoord.x < halfView.x ? up.x : up.y;
}

float roundedBoxSDF(vec2 pos, vec2 halfSize, float radius) {
    radius = min(radius, min(halfSize.x, halfSize.y));
    vec2 d = pos - halfSize + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

vec3 getNormal(vec2 fragCoord, float sdf, float R) {
    vec2 xy = fragCoord - halfViewFloor;
    vec2 xy_a = abs(xy);
    float t = smoothstep(-innerBlurRadius, 0.0, sdf);
    float z = sqrt(max(innerBlurRadiusSq - t * t, 0.0));
    vec3 coord = vec3(xy_a, -z);
    vec2 corner = halfView - R;
    corner.x = min(corner.x, xy_a.x);
    corner.y = min(corner.y, xy_a.y);
    vec2 dir = normalize(coord.xy - corner.xy);
    corner += dir * (R - innerBlurRadius);
    if (xy_a.x < corner.x || xy_a.y < corner.y) {
        return vec3(0.0, 0.0, -1.0);
    }
    vec2 signal = sign(xy);
    vec3 n = normalize(coord - vec3(corner, 0.0));
    n.xy *= signal;
    return n;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 xy = abs(fragCoord - halfView);
    float originRadius = pickRadius(fragCoord, cornerRadii);
    float R = max(originRadius, innerBlurRadius);
    if (xy.x < halfView.x - R && xy.y < halfView.y - R) {
        fragColor = vec4(0.0);
        return;
    }
    float sdf = roundedBoxSDF(xy, halfView, originRadius);
    float outMask = smoothstep(0.0, -1.0, sdf);
    float strokeAlpha = smoothstep(-strokeWidth, -strokeWidth + 1.0, sdf);
    vec3 rgb = strokeColor.rgb * (strokeAlphaMul * strokeAlpha * strokeAlpha);
    vec3 n = getNormal(fragCoord, sdf, R);

    // dualPeak：dot(N.xy, L.xy)² → 单光源 180° 对峰，垂向/内部自然归零。
    float l1 = dot(n.xy, lightDir1.xy);
    rgb += (l1 * l1 * lightIntensity1) * lightColor1.rgb;
    float l2 = dot(n.xy, lightDir2.xy);
    rgb += (l2 * l2 * lightIntensity2) * lightColor2.rgb;

    fragColor = vec4(rgb * highlightAlpha, 1.0) * outMask;
}
