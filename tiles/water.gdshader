shader_type spatial;
render_mode unshaded;

uniform vec4 water_color : source_color = vec4(0.003921569, 1.0, 1.0, 1.0);
uniform float wave_speed : hint_range(0.0, 5.0) = 1.0;
uniform float wave_scale : hint_range(0.1, 10.0) = 0.8;
uniform float noise_scale : hint_range(0.1, 10.0) = 2.5;
uniform float wave_brightness : hint_range(0.0, 1.0) = 0.7;
uniform float corner_radius : hint_range(0.0, 20.0) = 6.0;
uniform int lake_count = 0;
uniform vec2 lake_origins[8];
uniform vec2 lake_sizes[8];

varying vec3 world_pos;

float rounded_rect_sdf(vec2 p, vec2 origin, vec2 size, float radius) {
	vec2 center = origin + size * 0.5;
	vec2 half_size = size * 0.5 - vec2(radius);
	vec2 d = abs(p - center) - half_size;
	return length(max(d, vec2(0.0))) - radius;
}

vec2 grad(vec2 p) {
	float angle = fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453) * 6.2831853;
	return vec2(cos(angle), sin(angle));
}

float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(grad(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

const mat2 ROTATE = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * gradient_noise(p);
		p = ROTATE * p * 2.1;
		amplitude *= 0.45;
	}
	return value;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_xz = vec2(world_pos.x, world_pos.z);

	bool inside = false;
	for (int i = 0; i < lake_count; i++) {
		float dist = rounded_rect_sdf(world_xz, lake_origins[i], lake_sizes[i], corner_radius);
		if (dist <= 0.0) {
			inside = true;
			break;
		}
	}
	if (!inside) {
		discard;
	}

	vec2 wave_uv = world_xz * wave_scale;
	float wave1 = sin(wave_uv.x + TIME * wave_speed);
	float wave2 = sin(wave_uv.y * 0.8 + TIME * wave_speed * 0.65);
	float wave3 = sin((wave_uv.x + wave_uv.y) * 0.7 + TIME * wave_speed * 0.43);
	float wave4 = sin((wave_uv.x - wave_uv.y) * 1.3 + TIME * wave_speed * 0.57);
	float combined = (wave1 + wave2 + wave3 + wave4) * 0.25;

	float noise = fbm(world_xz * noise_scale + TIME * wave_speed * 0.1);

	float brightness = (combined * 0.4 + noise * 0.6) * wave_brightness;
	ALBEDO = clamp(water_color.rgb + brightness, vec3(0.0), vec3(1.0));
}
