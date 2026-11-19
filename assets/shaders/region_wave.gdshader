shader_type canvas_item;
// Gentle motion for a small cut-out of a building (a hanging banner, an archer breathing).
// The cut-out sits exactly on top of the same pixels in the building art, and the effect fades to nothing at
// its borders, so at rest it is invisible and in motion no seam shows.

uniform float amp_x = 0.03;     // sideways wave size (fraction of the cut-out)
uniform float amp_y = 0.0;      // up/down bob size
uniform float speed = 2.5;
uniform float freq = 7.0;       // how many ripples run down the cloth
uniform float phase = 0.0;
uniform float pin_top = 1.0;    // 1 = the top edge stays put (a hanging banner)
uniform float edge = 0.15;      // width of the still border
uniform vec2 push = vec2(0.0);  // extra shove, used for the archer's lean and recoil

void fragment() {
	float wx = smoothstep(0.0, edge, UV.x) * smoothstep(0.0, edge, 1.0 - UV.x);
	float wy = smoothstep(0.0, edge, UV.y) * smoothstep(0.0, edge, 1.0 - UV.y);
	float hang = mix(1.0, UV.y, pin_top);
	vec2 offset = vec2(
		sin(TIME * speed + UV.y * freq + phase) * amp_x * hang,
		sin(TIME * speed * 0.7 + phase) * amp_y);
	offset += push;
	COLOR = texture(TEXTURE, UV + offset * wx * wy);
}
