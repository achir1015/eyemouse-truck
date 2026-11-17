shader_type spatial;
// 大樓外牆：照片磁磚／水泥材質＋一格一格會反射天空的玻璃窗；晚上部分窗戶亮燈。
// UV：每 1/8 單位 = 一格窗（寬 4 m、高 3.2 m）。頂點色 = 牆色；alpha < 0.5 = 玻璃帷幕大樓
uniform sampler2D tex_wall : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_wall_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_wall2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float night = 0.0;
uniform float wet = 0.0;

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 cell = UV * 8.0;
	vec2 f = fract(cell);
	vec2 id = floor(cell);
	float bseed = floor(COLOR.r * 97.0 + COLOR.g * 53.0 + COLOR.b * 31.0);
	float rnd = h(id + bseed);
	bool tower = COLOR.a < 0.5;
	vec2 wuv = cell * vec2(4.0, 3.2) / 1.2;
	bool tiled = h(vec2(bseed, 1.0)) > 0.6;
	vec3 wall = tiled ? texture(tex_wall, wuv).rgb : texture(tex_wall2, cell * vec2(4.0, 3.2) / 3.0).rgb;
	float lum = dot(wall, vec3(0.333));
	vec3 base = COLOR.rgb * clamp(mix(vec3(1.0), wall / 0.5, 0.55) * (tiled ? 1.0 : 0.95 + 0.1 * lum), 0.0, 1.6);
	float wx0 = tower ? 0.03 : 0.2;
	float wy0 = tower ? 0.05 : 0.24;
	bool win = f.x > wx0 && f.x < 1.0 - wx0 && f.y > wy0 && f.y < 1.0 - wy0 && UV.x > 0.02;
	bool frame = f.x > wx0 - 0.03 && f.x < 1.0 - wx0 + 0.03 && f.y > wy0 - 0.04 && f.y < 1.0 - wy0 + 0.05;
	if (win) {
		// 玻璃：暗色＋高光澤，Forward+ 會反射天空；有些窗有窗簾
		vec3 glass = tower ? vec3(0.08, 0.13, 0.16) : vec3(0.04, 0.05, 0.06);
		float curtain = step(0.72, rnd) * (tower ? 0.0 : 1.0);
		ALBEDO = mix(glass, vec3(0.75, 0.7, 0.6) * (0.6 + 0.4 * h(id + 3.0)), curtain * 0.7);
		ROUGHNESS = mix(0.04, 0.6, curtain);
		METALLIC = tower ? 0.6 : 0.2;
		SPECULAR = 0.9;
		// 鐵窗（台灣老公寓）
		if (!tower && h(vec2(bseed, 7.0)) > 0.45) {
			float bars = step(0.9, fract(f.x * 9.0)) + step(0.92, fract(f.y * 5.0));
			ALBEDO = mix(ALBEDO, vec3(0.25, 0.26, 0.27), clamp(bars, 0.0, 1.0));
			ROUGHNESS = mix(ROUGHNESS, 0.5, clamp(bars, 0.0, 1.0));
		}
		float lit = step(rnd, 0.45) * night;
		EMISSION = vec3(1.0, 0.78, 0.5) * lit * (0.6 + 0.8 * h(id + 9.0)) * (1.0 - curtain * 0.4);
	} else if (frame) {
		ALBEDO = tower ? vec3(0.55, 0.58, 0.6) : vec3(0.3, 0.3, 0.3);
		ROUGHNESS = 0.4;
		METALLIC = 0.5;
	} else {
		ALBEDO = base * (1.0 - wet * 0.2);
		ROUGHNESS = 0.85 - wet * 0.4;
		NORMAL_MAP = texture(tex_wall_n, wuv).rgb;
		// 樓層之間的雨漬
		ALBEDO *= 1.0 - 0.12 * smoothstep(0.0, 0.2, f.y) * (1.0 - smoothstep(0.2, 0.4, f.y)) * step(0.5, h(vec2(bseed, 2.0)));
	}
}
