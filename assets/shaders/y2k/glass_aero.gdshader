// Era glass: nearly clear face-on, bright and tinted at grazing angles, very sharp highlights.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 tint : source_color = vec3(0.7, 0.92, 1.0);
uniform float face_alpha = 0.12;
uniform float edge_alpha = 0.75;
uniform float rim_glow = 0.15;

void fragment() {
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = tint;
	ALPHA = mix(face_alpha, edge_alpha, fresnel);
	ROUGHNESS = 0.02;
	METALLIC = 0.0;
	SPECULAR = 1.0;
	EMISSION = tint * fresnel * rim_glow;
}
