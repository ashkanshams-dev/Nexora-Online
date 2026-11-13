// Goal / impact overlay: anamorphic lens flare, light rays, chromatic fringe ring and vignette.
// Drawn once over the match canvas with BlendMode.plus, so it costs one full-screen pass only when active.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uFlare;    // flare origin (physical px)
uniform float uFlash;   // 0..1 goal flash
uniform float uTime;
uniform float uRipple;  // 0..1 chromatic shock ring progress (1 = just started)
uniform vec3 uColor;    // team colour

out vec4 fragColor;

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 d = (frag - uFlare) / uSize.y;
  float r = length(d);
  // anamorphic streak + soft core
  float streak = exp(-abs(d.y) * 90.0) * exp(-abs(d.x) * 2.2);
  float core = exp(-r * 7.0);
  // god rays
  float ang = atan(d.y, d.x);
  float rays = pow(0.5 + 0.5 * sin(ang * 14.0 + uTime * 1.7), 6.0) * exp(-r * 3.0);
  vec3 col = (vec3(1.0) * streak * 0.9 + mix(uColor, vec3(1.0), 0.4) * core + uColor * rays * 0.6) * uFlash;
  // chromatic shock ring: R, G, B rings at slightly different radii
  if (uRipple > 0.0) {
    float rr = (1.0 - uRipple) * 1.4;
    float w = 0.012 + 0.03 * (1.0 - uRipple);
    vec3 ring = vec3(exp(-pow((r - rr * 1.03) / w, 2.0)), exp(-pow((r - rr) / w, 2.0)), exp(-pow((r - rr * 0.97) / w, 2.0)));
    col += ring * uRipple * 0.75;
  }
  // vignette pulse
  vec2 uv = frag / uSize - 0.5;
  col += uColor * smoothstep(0.35, 0.75, length(uv)) * uFlash * 0.35;
  fragColor = vec4(col, 0.0);
}
