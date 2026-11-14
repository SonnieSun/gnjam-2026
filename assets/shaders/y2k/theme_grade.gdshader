// Per-level theme grade, after the 3D view (era or modern) and under the HUD: split toning -
// shadows pushed toward one hue, highlights toward another, with luminance kept - plus
// saturation and contrast. Each level's theme colour lives here as much as in its lights.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform vec3 shadow_tint : source_color = vec3(0.5);
uniform vec3 highlight_tint : source_color = vec3(0.5);
uniform float shadow_amount = 0.0;
uniform float highlight_amount = 0.0;
uniform float saturation = 1.0;
uniform float contrast = 1.0;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, LUMA);
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	l = clamp(dot(c, LUMA), 0.0, 1.0);
	float ws = (1.0 - l) * (1.0 - l);
	float wh = l * l;
	c += (shadow_tint - dot(shadow_tint, LUMA)) * shadow_amount * ws;
	c += (highlight_tint - dot(highlight_tint, LUMA)) * highlight_amount * wh;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
