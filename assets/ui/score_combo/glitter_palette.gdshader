shader_type canvas_item;
render_mode unshaded;
uniform vec4 stage_color : source_color = vec4(1.0, 0.941, 0.651, 1.0);
uniform bool rainbow = false;
uniform float rainbow_origin = 0.0;
uniform float rainbow_span = 260.0;
uniform float screen_scale = 1.0;
// Logical game-screen pixels, independent of atlas and label scaling.
uniform float coarse_grain_px : hint_range(2.0,8.0) = 4.6;
uniform float fine_grain_strength : hint_range(0.0,0.2) = 0.06;
vec3 spectrum(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0,4.0,2.0),6.0)-3.0)-1.0,0.0,1.0);
}
vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);
}
void fragment() {
	vec4 mask = texture(TEXTURE,UV);
	vec3 base = stage_color.rgb;
	if (rainbow) {
		float x = clamp((FRAGCOORD.x-rainbow_origin)/max(rainbow_span,1.0),0.0,1.0);
		base = mix(spectrum(fract(0.92+x*0.82)),vec3(1.0),0.06);
	}
	vec2 screen = FRAGCOORD.xy / max(screen_scale,0.1);
	vec2 p = screen/coarse_grain_px;
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float first=10.0;
	float second=10.0;
	vec2 grain_id=vec2(0.0);
	vec2 grain_delta=vec2(0.0);
	for (int y=-1;y<=1;y++) {
		for (int x=-1;x<=1;x++) {
			vec2 offset=vec2(float(x),float(y));
			vec2 id=cell+offset;
			vec2 delta=offset+0.15+0.70*hash2(id)-local;
			float d=dot(delta,delta);
			if (d<first) {
				second=first;first=d;grain_id=id;grain_delta=delta;
			} else if (d<second) {second=d;}
		}
	}
	vec2 seed=hash2(grain_id+vec2(29.0,7.0));
	// Irregular colored crystal flakes, with no source-art white dots or TIME.
	float facet=step(grain_delta.x*0.7+grain_delta.y,seed.y*0.32-0.16);
	float brightness=mix(0.55,1.0,seed.x)+facet*0.12;
	vec3 flakes=base*brightness;
	float bright_flake=smoothstep(0.72,0.96,seed.x)*facet;
	flakes=mix(flakes,mix(base,vec3(1.0),0.15),bright_flake*0.75);
	float seam=1.0-smoothstep(0.018,0.085,second-first);
	flakes*=1.0-seam*0.22;
	// Small gaps separate individual coarse flakes from the finer colored backing.
	float flake_coverage=1.0-smoothstep(0.12,0.25,first);
	flakes=mix(base*0.84,flakes,flake_coverage);
	float fine=(hash2(floor(screen*0.8)).x-0.5)*fine_grain_strength;
	flakes*=1.0+fine;
	flakes*=mix(0.80,1.0,mask.g);
	vec3 contour=mix(base,vec3(1.0),0.56);
	COLOR=vec4(mix(contour,flakes,mask.r),mask.a);
}
