shader_type canvas_item;
// Walking townsfolk (M13). The painted townsfolk have one pose each; while they walk, this moves
// their legs: a scissor step for people facing the viewer, a swinging stride for side-walkers.
// Shared by everyone (a few materials, not one per person, so it stays cheap): every townsfolk
// sheet is 4 x 2 frames, so the shader works out the frame from UV itself, and the walk cycle
// runs on TIME with a per-material phase offset so people don't all step in sync.

uniform float side = 0.0; // 1 = side view (walking left/right), 0 = facing the viewer
uniform float phase_offset = 0.0;
const vec2 FRAME = vec2(0.25, 0.5);

void fragment() {
	vec2 cell = floor(UV / FRAME);
	vec2 local = fract(UV / FRAME);
	float legs = smoothstep(0.6, 0.72, local.y); // only below the hips
	if (legs > 0.0) {
		float down = (local.y - 0.6) / 0.4; // 0 at the hips, 1 at the feet
		float s = sin(TIME * 31.4 + phase_offset);
		vec2 off = vec2(0.0);
		if (side > 0.5) {
			off.x = s * 0.055 * down * legs; // stride
		} else {
			float left = step(local.x, 0.5); // scissor: one leg lifts, then the other
			off.y = (left > 0.5 ? max(s, 0.0) : max(-s, 0.0)) * 0.035 * legs;
			off.x = (left > 0.5 ? -1.0 : 1.0) * abs(s) * 0.012 * legs;
		}
		// Only the displaced leg pixels are re-sampled; everything else keeps Godot's COLOR.
		COLOR = texture(TEXTURE, (cell + clamp(local + off, vec2(0.001), vec2(0.999))) * FRAME);
	}
}
