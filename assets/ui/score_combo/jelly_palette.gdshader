shader_type canvas_item;
render_mode unshaded;
uniform vec4 stage_color : source_color = vec4(1.0,0.941,0.651,1.0);
uniform bool rainbow = false;
uniform float rainbow_origin = 0.0;
uniform float rainbow_span = 180.0;
vec3 spectrum(float h) {
	return clamp(abs(mod(h*6.0+vec3(0.0,4.0,2.0),6.0)-3.0)-1.0,0.0,1.0);
}
void fragment() {
	vec4 source=texture(TEXTURE,UV);
	float v=max(source.r,max(source.g,source.b));
	float low=min(source.r,min(source.g,source.b));
	float sat=(v-low)/max(v,0.001);
	vec3 base=stage_color.rgb;
	if (rainbow) {
		float x=clamp((FRAGCOORD.x-rainbow_origin)/max(rainbow_span,1.0),0.0,1.0);
		base=mix(spectrum(fract(0.92+x*0.82)),vec3(1.0),0.06);
	}
	// Baked smooth jelly shading / highlights, with the broad dark rim intact.
	float pigment=smoothstep(0.04,0.55,sat);
	vec3 gel=mix(vec3(1.0),base,pigment)*v;
	float rim=1.0-smoothstep(0.14,0.30,v);
	gel=mix(gel,vec3(v*0.65,v*0.25,v*0.45),rim);
	COLOR=vec4(gel,source.a);
}
