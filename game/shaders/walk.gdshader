shader_type canvas_item;
// Walking townsfolk (M13). The painted townsfolk have one pose each; while they walk, this moves
// their legs: a scissor step (left and right leg lift in turn) for people facing the viewer, and a
// swinging stride for side-walkers. Samples stay inside the person's own frame of the sheet.

uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0); // u0, v0, u1, v1 of this frame in the sheet
uniform float phase = 0.0; // walk cycle, radians
uniform float amount = 0.0; // 0 standing, 1 walking
uniform float side = 0.0; // 1 = side view (walking left/right), 0 = facing the viewer

void fragment() {
	vec2 sz = frame_rect.zw - frame_rect.xy;
	vec2 local = (UV - frame_rect.xy) / sz;
	float legs = smoothstep(0.6, 0.72, local.y); // only below the hips
	float down = (local.y - 0.6) / 0.4; // 0 at the hips, 1 at the feet
	vec2 off = vec2(0.0);
	float s = sin(phase) * amount;
	if (side > 0.5) {
		// Stride: the lower legs swing forward and back, feet furthest.
		off.x = s * 0.055 * down * legs;
	} else {
		// Scissor: the left leg lifts while the right plants, then they swap.
		float left = step(local.x, 0.5);
		off.y = (left > 0.5 ? max(s, 0.0) : max(-s, 0.0)) * 0.035 * legs;
		off.x = (left > 0.5 ? -1.0 : 1.0) * abs(s) * 0.012 * legs;
	}
	vec2 uv = frame_rect.xy + clamp(local + off, vec2(0.001), vec2(0.999)) * sz;
	COLOR = texture(TEXTURE, uv) * COLOR;
}
