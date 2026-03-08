shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 border_color : source_color = vec4(0.0, 0.6, 1.0, 1.0);
uniform float border_thickness : hint_range(0.01, 0.5) = 0.05;

uniform float corner_length : hint_range(0.05, 0.5) = 0.2;

void fragment() {
	vec2 uv = UV;
	bool on_edge_x = uv.x < border_thickness || uv.x > 1.0 - border_thickness;
	bool on_edge_y = uv.y < border_thickness || uv.y > 1.0 - border_thickness;
	bool in_corner_x = uv.x < corner_length || uv.x > 1.0 - corner_length;
	bool in_corner_y = uv.y < corner_length || uv.y > 1.0 - corner_length;
	bool on_corner = (on_edge_x && in_corner_y) || (on_edge_y && in_corner_x);
	if (!on_corner) {
		discard;
	}
	ALBEDO = border_color.rgb;
	ALPHA = border_color.a;
}
