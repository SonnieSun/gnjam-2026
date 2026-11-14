// Visible spotlight beam: an open cone mesh (CylinderMesh, narrow end up at the lamp) drawn
// additively. Bright along the axis and fading to the cone's silhouette, strongest at the
// lamp and falling off down the throw, soft where it meets the floor or a model (scene depth)
// and near the camera. A long, slow throw that tails off to nothing before the cone's open
// end, and fades into the floor plane it falls on, so neither the cone's rim nor its cut on the
// floor ever shows as a hard circle - even when the sweep swings the beam off its target. The era trick (Dreamcast light shafts were translucent geometry),
// laid over the real volumetric fog at night and standing in for it by day.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.97, 0.9);
uniform float strength = 0.6;
uniform float height = 10.0;  // cone length, to map VERTEX.y to 0 (lamp) .. 1 (far end)
uniform float edge_softness = 1.6;
uniform float soft_depth = 1.6;  // metres over which the beam fades into surfaces
uniform float fade_start = 0.4;  // along the cone (0 lamp .. 1 open end) where the tail fade begins
uniform float floor_y = -100000.0;  // world height of the floor the beam lands on
uniform float floor_soft = 0.8;  // metres above the floor over which it fades in
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying float along;
varying vec3 wpos;

void vertex() {
	along = clamp(0.5 - VERTEX.y / height, 0.0, 1.0);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Facing ratio: 1 looking straight through the cone's middle, 0 at its silhouette.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, edge_softness);
	// A long, slow throw (light spreads, so it thins with distance) and a soft tail to nothing.
	float tail = 1.0 - smoothstep(fade_start, 0.88, along);
	float falloff = 1.0 / (1.0 + along * 3.0) * tail * tail;
	float on_floor = smoothstep(floor_y, floor_y + floor_soft, wpos.y);
	float start = smoothstep(0.0, 0.06, along);
	// Soft intersection with the scene behind.
	float scene = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene, 1.0);
	float scene_z = -world.z / world.w;
	float frag_z = -VERTEX.z;
	float soft = clamp((scene_z - frag_z) / soft_depth, 0.0, 1.0);
	float near_fade = smoothstep(0.3, 2.0, frag_z);
	ALBEDO = color * core * falloff * start * soft * near_fade * on_floor * strength;
}
