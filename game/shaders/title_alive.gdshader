shader_type canvas_item;
// Brings the title painting (art/story/panel-splash.jpg) to life without changing it: each region
// of the painting gets a small, soft-edged displacement (clouds drift, lagoon shimmers, umbrellas
// sway, the crowd bobs, the danfo idles, people breathe). The same shader runs on the foreground
// cut-outs (title_scene.gd) so they move with the painting underneath them.

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec2 img = vec2(1280.0, 853.0);
uniform float motion = 1.0;

// Soft rectangle mask: rect = (x0, y0, x1, y1) in painting pixels, f = feather in pixels.
float box(vec2 p, vec4 r, float f) {
	vec2 a = smoothstep(r.xy - f, r.xy + f, p);
	vec2 b = vec2(1.0) - smoothstep(r.zw - f, r.zw + f, p);
	return a.x * a.y * b.x * b.y;
}

// Sway that grows toward the top of the region (umbrella canopies on fixed poles).
float sway(vec2 p, vec4 r, float t, float speed, float phase, float amp) {
	float k = clamp(1.0 - (p.y - r.y) / (r.w - r.y), 0.0, 1.0);
	return sin(t * speed + phase) * amp * k * box(p, r, 14.0);
}

void fragment() {
	vec2 p = UV * img;
	float t = TIME;
	vec2 off = vec2(0.0);

	// Sky: slow cloud drift (also gives the power lines a little wind).
	float sky = clamp(box(p, vec4(232.0, -60.0, 1340.0, 292.0), 26.0) + box(p, vec4(-60.0, -60.0, 260.0, 112.0), 18.0), 0.0, 1.0);
	vec2 n = texture(noise_tex, p / 650.0 + vec2(t * 0.007, t * 0.0025)).rg - 0.5;
	off += n * 8.0 * sky;

	// Lagoon: ripples.
	float water = box(p, vec4(520.0, 404.0, 1168.0, 470.0), 5.0);
	off.x += sin(p.y * 1.25 + t * 2.3) * 1.5 * water;
	off.y += sin(p.x * 0.045 + t * 1.2) * 0.5 * water;

	// Umbrellas and stall canopies.
	off.x += sway(p, vec4(0.0, 245.0, 258.0, 415.0), t, 1.1, 0.0, 2.6);
	off.x += sway(p, vec4(196.0, 388.0, 388.0, 470.0), t, 1.4, 1.7, 2.0);
	off.x += sway(p, vec4(1150.0, 380.0, 1290.0, 478.0), t, 1.25, 3.1, 2.4);
	off.x += sway(p, vec4(755.0, 490.0, 1010.0, 548.0), t, 1.6, 0.6, 1.3);
	off.x += sway(p, vec4(1090.0, 452.0, 1280.0, 512.0), t, 1.0, 2.2, 1.6);

	// Palm fronds.
	off.x += sway(p, vec4(370.0, 290.0, 510.0, 370.0), t, 0.9, 0.4, 2.2);
	off.x += sway(p, vec4(1195.0, 255.0, 1290.0, 345.0), t, 0.8, 2.8, 2.0);

	// Background crowd and market: everyone shifts their weight a little.
	float crowd = clamp(box(p, vec4(780.0, 498.0, 1010.0, 735.0), 10.0) + box(p, vec4(1100.0, 470.0, 1280.0, 640.0), 10.0) + box(p, vec4(0.0, 420.0, 250.0, 620.0), 10.0), 0.0, 1.0);
	off.y += sin(t * 4.2 + p.x * 0.085) * 1.1 * crowd;
	off.x += sin(t * 2.1 + p.y * 0.05) * 0.6 * crowd;

	// The danfo idles: slow rock on its springs plus engine shiver.
	float bus = box(p, vec4(240.0, 442.0, 800.0, 846.0), 6.0);
	off.y += (sin(t * 1.8) * 0.9 + sin(t * 29.0) * 0.35) * bus;
	// The driver bobs his head to the radio.
	off += vec2(sin(t * 3.6) * 0.8, abs(sin(t * 3.6)) * -1.2) * box(p, vec4(565.0, 482.0, 650.0, 560.0), 10.0);

	// The mama breathes (shoulders up, feet planted) and the boy's phone hand wobbles.
	float mama = box(p, vec4(20.0, 368.0, 292.0, 860.0), 8.0);
	off.y += sin(t * 1.4) * 1.7 * clamp((780.0 - p.y) / 400.0, 0.0, 1.0) * mama;
	float boy = box(p, vec4(1010.0, 455.0, 1290.0, 860.0), 8.0);
	off.y += sin(t * 1.6 + 1.0) * 1.3 * clamp((800.0 - p.y) / 340.0, 0.0, 1.0) * boy;
	off += vec2(sin(t * 2.7), cos(t * 2.1)) * 0.9 * box(p, vec4(1030.0, 505.0, 1125.0, 625.0), 10.0);

	vec4 c = texture(TEXTURE, (p - off * motion) / img);

	// Sun glow breathes and the lagoon sparkles under it.
	float d = distance(p, vec2(1077.0, 300.0));
	c.rgb += vec3(1.0, 0.72, 0.32) * (0.07 + 0.035 * sin(t * 0.7)) * smoothstep(150.0, 0.0, d);
	float glint = smoothstep(0.80, 0.98, texture(noise_tex, p / vec2(18.0, 6.0) + vec2(t * 0.06, t * 0.013)).r);
	c.rgb += vec3(1.0, 0.85, 0.5) * glint * 0.45 * water * smoothstep(170.0, 0.0, abs(p.x - 1078.0));

	COLOR = c * COLOR;
}
