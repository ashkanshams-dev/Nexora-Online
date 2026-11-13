// Animated deep-space layer drawn over the nebula art: drifting procedural nebula glow + twinkling stars.
// Additive and cheap (no texture reads); quality uniform drops the fbm octaves on low settings.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uQ;      // 0 low .. 1 high
uniform vec3 uTint;    // theme tint

out vec4 fragColor;

float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 5; i++) { if (float(i) > 2.0 + uQ * 2.0) break; v += a * noise(p); p *= 2.03; a *= 0.5; }
  return v;
}
void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize.y;
  float t = uTime * 0.02;
  float n = fbm(uv * 2.2 + vec2(t, -t * 0.6));
  float n2 = fbm(uv * 3.7 - vec2(t * 0.7, t));
  vec3 neb = uTint * pow(n, 2.6) * 0.55 + vec3(0.45, 0.25, 0.9) * pow(n2, 3.0) * 0.35;
  // twinkling star grid
  vec2 g = uv * 90.0; vec2 id = floor(g); vec2 f = fract(g) - 0.5;
  float r = h21(id);
  float star = 0.0;
  if (r > 0.965) {
    float tw = 0.55 + 0.45 * sin(uTime * (1.0 + r * 3.0) + r * 40.0);
    star = smoothstep(0.09, 0.0, length(f)) * tw * (r - 0.965) * 28.0;
  }
  vec3 col = neb + vec3(0.85, 0.92, 1.0) * star;
  fragColor = vec4(col, 0.0); // additive premultiplied (alpha 0 keeps it purely additive with BlendMode.plus)
}
