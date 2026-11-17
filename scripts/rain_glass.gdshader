shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// 擋風玻璃雨滴：格狀亂數水珠，雨刷刷過的地方暫時變少
uniform float intensity = 0.6;
uniform float wiper = 1.35;

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV * vec2(28.0, 14.0);
	vec2 cell = floor(uv);
	vec2 f = fract(uv) - 0.5;
	float r = h(cell);
	float life = fract(TIME * (0.15 + r * 0.3) + r * 7.0);
	vec2 off = vec2(h(cell + 3.1) - 0.5, h(cell + 7.7) - 0.5) * 0.6;
	off.y += life * life * 0.4 * step(0.7, r);
	float d = length(f - off);
	float drop = smoothstep(0.18 * (0.4 + r), 0.0, d) * step(0.35, h(cell + 1.3));
	// 雨刷角度：以底部為中心，掃過的扇形區域暫時清乾淨
	vec2 p = UV - vec2(0.5, 1.0);
	float ang = atan(p.x, -p.y);
	float wiped = smoothstep(0.35, 0.0, abs(ang + (wiper - 0.1)));
	float a = drop * intensity * (1.0 - wiped) * (0.5 + 0.5 * life);
	ALBEDO = vec3(0.85, 0.9, 0.95);
	ALPHA = a * 0.55;
}
