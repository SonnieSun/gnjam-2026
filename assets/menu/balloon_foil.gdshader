shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 pink : source_color = vec4(0.88, 0.10, 0.57, 1.0);
uniform vec4 purple : source_color = vec4(0.30, 0.025, 0.64, 1.0);
uniform float brightness = 1.0;
uniform float hologram_strength : hint_range(0.0, 1.0) = 0.48;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float facing = abs(dot(n, v));
	float rim = pow(1.0 - facing, 1.7);
	float phase = dot(n, vec3(0.7, 1.8, 0.8)) * 3.6 + facing * 5.0;
	vec3 spectrum = 0.5 + 0.5 * cos(phase + vec3(0.0, 2.1, 4.2));
	vec3 base = mix(purple.rgb, pink.rgb, smoothstep(-0.45, 0.85, n.y + 0.4 * n.x));
	base = mix(base, spectrum, hologram_strength * (0.18 + rim * 0.75));
	// Broad studio softbox reflection follows the inflated surface, not the text UV.
	float strip = pow(max(0.0, dot(n, normalize(vec3(-0.4, 0.65, 0.75)))), 18.0);
	float edge_strip = pow(max(0.0, dot(n, normalize(vec3(0.8, -0.2, 0.55)))), 28.0);
	vec3 foil = base * (0.48 + 0.50 * facing);
	foil = mix(foil, vec3(1.0, 0.87, 1.0), strip * 0.92);
	foil += edge_strip * vec3(0.26, 0.50, 0.55) + rim * vec3(0.20, 0.07, 0.30);
	ALBEDO = foil * brightness;
}
