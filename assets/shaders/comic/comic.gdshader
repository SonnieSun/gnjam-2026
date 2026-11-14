// Francisco Cidade | fcidade.com | fcidade.itch.io
// Comic: flat inked colour with the shade printed as halftone dots or pen hatching, a hard highlight and a
// thick brush outline. Light is read from the lights of the scene; nothing is baked. The dots and the lines
// are laid on the screen, like a print, so they keep the same size at any distance.
// Pair it with comic_outline.gdshader as `next_pass`.
shader_type spatial;
render_mode ambient_light_disabled;

group_uniforms surface;
// Base colour. Multiplies the texture.
uniform vec4 albedo : source_color = vec4(1.0);
// The picture of the surface, multiplied by the colour. Without one the surface is plain white.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
// How many times the picture repeats over the surface, across and down.
uniform vec2 uv_scale = vec2(1.0);
// Slides the picture over the surface, as a share of its size.
uniform vec2 uv_offset = vec2(0.0);
// Multiply the colour by the mesh's vertex colours.
uniform bool use_vertex_color = false;
// Light added to the surface whether or not any reaches it.
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);

group_uniforms shading;
// How the shade is drawn: Flat is one solid tone, Halftone prints it as dots, Hatch as pen lines.
uniform int shade_style : hint_enum("Flat", "Halftone", "Hatch") = 1;
// What the surface colour is multiplied by where it is shaded. A dark, warm or cool tint reads as ink.
uniform vec4 shadow_color : source_color = vec4(0.45, 0.4, 0.62, 1.0);
// Where the light gives way to shade, as the cosine of the angle to the light. Raise it to shrink the lit side.
uniform float light_threshold : hint_range(-0.5, 0.9) = 0.6;
// How far past the threshold the dots or lines take to grow into solid shade. Small is graphic, large is gradual.
uniform float shade_reach : hint_range(0.05, 1.5) = 1.0;
// Cut the sun's shadows and the lamps' pools to a crisp edge, one pixel wide. Off keeps them soft.
uniform bool crisp_shadows = true;

group_uniforms halftone;
// Distance between two dots, in screen pixels.
uniform float dot_size : hint_range(3.0, 40.0) = 9.0;
// Angle of the rows of dots in degrees. 45 is the classic print angle.
uniform float dot_angle : hint_range(0.0, 90.0) = 45.0;

group_uniforms hatch;
// Distance between two pen lines, in screen pixels.
uniform float hatch_spacing : hint_range(3.0, 40.0) = 8.0;
// Angle of the lines in degrees.
uniform float hatch_angle : hint_range(0.0, 180.0) = 40.0;
// Where the darkest shade gets a second set of lines across the first. 0 turns the crossing off.
uniform float crosshatch : hint_range(0.0, 1.0) = 0.5;

group_uniforms highlight;
// Strength of the hard specular highlight. 0 turns it off.
uniform float spec_amount : hint_range(0.0, 1.0) = 0.0;
// Size of the highlight: 0 a tiny spot, 1 most of the lit side.
uniform float spec_size : hint_range(0.0, 1.0) = 0.12;
// Colour of the highlight.
uniform vec4 spec_color : source_color = vec4(1.0);

group_uniforms rim;
// Strength of the rim of light round the silhouette. 0 turns it off.
uniform float rim : hint_range(0.0, 1.0) = 0.0;
// Colour of the rim of light.
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
// How far in from the silhouette the rim reaches.
uniform float rim_width : hint_range(0.0, 1.0) = 0.3;

void vertex() {
	UV = UV * uv_scale + uv_offset;
}

float rim_amount(vec3 normal, vec3 view) {
	float facing = 1.0 - clamp(dot(normal, view), 0.0, 1.0);
	return smoothstep(1.0 - rim_width, 1.0 - rim_width + 0.04, facing) * rim;
}

void fragment() {
	vec4 c = albedo * texture(albedo_texture, UV);
	if (use_vertex_color) {
		c *= COLOR;
	}
	ALBEDO = c.rgb;
	// Everything starts in shade; the light adds the lit colour wherever the print leaves it clear.
	EMISSION = c.rgb * shadow_color.rgb + emission.rgb;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

// Light's reach, cut to on or off at a one-pixel edge.
float crisp(float a, bool directional) {
	float at = directional ? 0.5 : 0.04;
	float w = max(fwidth(a), 0.0005);
	return smoothstep(at - w, at + w, a);
}

vec2 rotate(vec2 p, float degrees) {
	float a = radians(degrees);
	return vec2(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y);
}

// 1 where a dot is printed. `shade` is how much shade there is here, 0 (none) to 1 (full): bigger dots in darker places.
float halftone(vec2 screen, float shade) {
	vec2 cell = fract(rotate(screen, dot_angle) / dot_size) * 2.0 - 1.0;
	float edge = 1.5 / dot_size;
	return 1.0 - smoothstep(1.42 * sqrt(shade) - edge, 1.42 * sqrt(shade) + edge, length(cell));
}

// 1 where a pen line is drawn. A thicker line in darker places; a second set across it in the darkest.
float hatching(vec2 screen, float shade) {
	float a = abs(fract(rotate(screen, hatch_angle).x / hatch_spacing) * 2.0 - 1.0);
	float edge = 1.5 / hatch_spacing;
	float line = 1.0 - smoothstep(shade - edge, shade + edge, a);
	if (crosshatch > 0.0) {
		float b = abs(fract(rotate(screen, hatch_angle + 90.0).x / hatch_spacing) * 2.0 - 1.0);
		float cross_shade = clamp((shade - (1.0 - crosshatch)) / max(crosshatch, 0.001), 0.0, 1.0);
		line = max(line, (1.0 - smoothstep(cross_shade - edge, cross_shade + edge, b)) * step(0.001, cross_shade));
	}
	return line * step(0.001, shade);
}

void light() {
	float reach = crisp_shadows ? crisp(ATTENUATION, LIGHT_IS_DIRECTIONAL) : ATTENUATION;
	float facing = dot(NORMAL, LIGHT);
	// shade: 0 well lit, 1 fully in shade, growing over `shade_reach` past the threshold
	float shade = clamp((light_threshold - facing) / shade_reach, 0.0, 1.0);
	shade = max(shade, 1.0 - reach);
	float printed;
	if (shade_style == 1) {
		printed = max(halftone(FRAGCOORD.xy, shade), step(0.999, shade));
	} else if (shade_style == 2) {
		printed = max(hatching(FRAGCOORD.xy, shade), step(0.999, shade));
	} else {
		printed = step(0.5, shade);
	}
	float lit = 1.0 - printed;
	vec3 energy = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += energy * lit * (vec3(1.0) - shadow_color.rgb);
	if (spec_amount > 0.0) {
		float ndh = dot(NORMAL, normalize(LIGHT + VIEW));
		float hl = step(1.0 - spec_size, ndh);
		SPECULAR_LIGHT += energy * spec_color.rgb * hl * spec_amount * (1.0 - step(0.5, shade));
	}
	if (rim > 0.0) {
		SPECULAR_LIGHT += energy * rim_color.rgb * rim_amount(NORMAL, VIEW) * lit;
	}
}
