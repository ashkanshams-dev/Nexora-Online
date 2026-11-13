// NEXORA ball: textured sphere with studio lighting (port of the Skia SkSL BALL_SKSL in render.ts,
// upgraded with a rim light, clear-coat glint and a subtle environment reflection).
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uCenter;   // ball centre in physical pixels
uniform float uRadius;  // ball radius in physical pixels
uniform vec3 c0;        // rotation matrix columns (R[0],R[3],R[6]) ...
uniform vec3 c1;
uniform vec3 c2;
uniform float aa;       // edge antialias width (unit sphere space)
uniform float uHq;      // 1 = high quality lighting
uniform sampler2D img;

out vec4 fragColor;

void main() {
  vec2 p = (FlutterFragCoord().xy - uCenter) / uRadius;
  float d = length(p);
  float inside = step(d, 1.0);
  d = min(d, 1.0);
  float z = sqrt(max(0.0, 1.0 - d * d));
  vec3 n = vec3(p.x, p.y, z);
  vec3 q = vec3(dot(c0, n), dot(c1, n), dot(c2, n));
  vec2 uv = q.xy;
  float seam = smoothstep(-0.12, 0.12, q.z);
  vec4 cf = texture(img, uv * 0.93 * 0.5 + 0.5);
  vec4 cb = texture(img, vec2(-uv.x, uv.y) * 0.93 * 0.5 + 0.5);
  vec3 base = mix(cb.rgb, cf.rgb, seam);
  vec3 L = normalize(vec3(-0.42, -0.55, 0.72));
  vec3 F = normalize(vec3(0.6, 0.35, 0.7));
  float key = max(dot(n, L), 0.0), fill = max(dot(n, F), 0.0);
  float amb = 0.42 + 0.18 * (-n.y) * 0.5 + 0.12 * z;
  float occ = mix(0.72, 1.0, smoothstep(-0.2, 0.85, -n.y * 0.55 + z * 0.6));
  vec3 lit = base * (amb + 0.62 * key + 0.16 * fill) * occ;
  vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
  float nh = max(dot(n, H), 0.0);
  float sp = pow(nh, 64.0) * 0.65 + pow(nh, 12.0) * 0.10;
  float fres = pow(1.0 - z, 3.0);
  vec3 col = lit * (1.0 - 0.35 * fres) + vec3(sp) + vec3(0.55, 0.75, 1.0) * fres * 0.22;
  if (uHq > 0.5) {
    // cyan stadium rim light from the opposite side + clear-coat micro glint
    float rim = pow(1.0 - z, 2.0) * smoothstep(0.0, 0.8, dot(normalize(p + 1e-4), normalize(vec2(0.7, 0.6))));
    col += vec3(0.30, 0.85, 1.0) * rim * 0.35;
    col += vec3(pow(nh, 220.0) * 0.9);
  }
  float a = smoothstep(1.0, 1.0 - aa, d) * inside;
  fragColor = vec4(col * a, a);
}
