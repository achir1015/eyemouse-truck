shader_type spatial;
// 照片材質（世界座標三軸投影）× 頂點色；給地面、人行道、峭壁、雜項物件用
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale = 0.25;
uniform float tex_mix = 1.0;
uniform float tex_avg = 0.45;
uniform float rough_add = 0.0;
uniform float wet = 0.0;
varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 b = pow(abs(wnrm), vec3(4.0));
	b /= (b.x + b.y + b.z);
	vec2 ux = wpos.zy * scale;
	vec2 uy = wpos.xz * scale;
	vec2 uz = wpos.xy * scale;
	vec3 a = texture(tex_albedo, ux).rgb * b.x + texture(tex_albedo, uy).rgb * b.y + texture(tex_albedo, uz).rgb * b.z;
	float r = texture(tex_rough, ux).r * b.x + texture(tex_rough, uy).r * b.y + texture(tex_rough, uz).r * b.z;
	vec3 tinted = COLOR.rgb * clamp(a / tex_avg, 0.0, 2.0);
	ALBEDO = mix(COLOR.rgb, tinted, tex_mix) * (1.0 - wet * 0.25 * b.y);
	ROUGHNESS = clamp(r + rough_add - wet * 0.55 * b.y, 0.05, 1.0);
	// 主要投影面的法線貼圖（地面、牆面）
	vec2 nuv = b.y > 0.5 ? uy : (b.x > b.z ? ux : uz);
	vec3 tw = b.y > 0.5 ? vec3(1.0, 0.0, 0.0) : (b.x > b.z ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0));
	vec3 bw = b.y > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	TANGENT = normalize((VIEW_MATRIX * vec4(tw, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(bw, 0.0)).xyz);
	NORMAL_MAP = texture(tex_normal, nuv).rgb;
	NORMAL_MAP_DEPTH = 0.8;
}
