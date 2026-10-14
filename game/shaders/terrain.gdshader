// One continuous painted ground (decision D-004): no tiles, soft blended surfaces, inked kerbs.
// Placeholder colours are procedural; painted tiling textures will replace the c_* colours later,
// keeping the same masks. Runs on GLES3 (Compatibility renderer).
shader_type canvas_item;

uniform vec2 world_size = vec2(2560.0, 1920.0);
uniform sampler2D noise_lo : repeat_enable, filter_linear;
uniform sampler2D noise_hi : repeat_enable, filter_linear;
uniform float main_y0 = 896.0;
uniform float main_y1 = 1024.0;
uniform float cross_x0 = 1216.0;
uniform float cross_x1 = 1344.0;
uniform float gutter = 10.0;
uniform float walk = 34.0;
uniform int quality = 1; // 0 low, 1 medium, 2 high

// Painted tiling textures (game/art/ground). When use_tex is false the procedural colours are used.
uniform bool use_tex = false;
uniform sampler2D tex_dirt : repeat_enable, filter_linear_mipmap, source_color;
uniform sampler2D tex_grass : repeat_enable, filter_linear_mipmap, source_color;
uniform sampler2D tex_asphalt : repeat_enable, filter_linear_mipmap, source_color;
uniform sampler2D tex_walk : repeat_enable, filter_linear_mipmap, source_color;
uniform float tex_tile = 256.0; // world px per texture repeat
uniform sampler2D tex_sand : repeat_enable, filter_linear_mipmap, source_color;
uniform bool use_sand_tex = false;

// Island coastline (decision D-007). Must match Layout.island_r().
uniform vec2 island_center = vec2(1280.0, 940.0);
uniform vec2 island_radii = vec2(1150.0, 820.0);
uniform float beach_start = 0.86;
uniform float road_end = 0.9;
uniform vec3 c_sand : source_color = vec3(0.86, 0.74, 0.52);
uniform vec3 c_shallow : source_color = vec3(0.29, 0.72, 0.7);
uniform vec3 c_deep : source_color = vec3(0.1, 0.33, 0.47);

uniform vec3 c_dirt : source_color = vec3(0.54, 0.46, 0.34);
uniform vec3 c_laterite : source_color = vec3(0.56, 0.37, 0.25);
uniform vec3 c_grass : source_color = vec3(0.37, 0.48, 0.23);
uniform vec3 c_grass_light : source_color = vec3(0.49, 0.58, 0.28);
uniform vec3 c_asphalt : source_color = vec3(0.29, 0.275, 0.26);
uniform vec3 c_gutter : source_color = vec3(0.17, 0.19, 0.15);
uniform vec3 c_walk : source_color = vec3(0.63, 0.54, 0.41);
uniform vec3 c_kerb : source_color = vec3(0.62, 0.59, 0.54);
uniform vec3 c_ink : source_color = vec3(0.11, 0.085, 0.067);

float nlo(vec2 p, float s) { return texture(noise_lo, p / s).r; }
float nhi(vec2 p, float s) { return texture(noise_hi, p / s).r; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

float island_r(vec2 p, out float a) {
	vec2 d = (p - island_center) / island_radii;
	a = atan(d.y, d.x);
	return length(d) + 0.05 * sin(a * 5.0 + 1.3) + 0.035 * sin(a * 9.0 + 0.4) + 0.02 * sin(a * 13.0 + 2.1);
}

vec3 sand_at(vec2 p, float r) {
	vec3 s = use_sand_tex ? texture(tex_sand, p / tex_tile).rgb : c_sand * (0.9 + 0.2 * texture(noise_hi, p / 40.0).r);
	// Wet, darker sand near the waterline.
	return mix(s, s * vec3(0.78, 0.74, 0.7), smoothstep(0.965, 1.0, r));
}

vec3 sea_at(vec2 p, float r, float a) {
	float depth = smoothstep(1.0, 1.16, r);
	vec2 flow = vec2(TIME * 6.0, TIME * 3.5);
	float w1 = texture(noise_hi, (p + flow) / 70.0).r;
	float w2 = texture(noise_hi, (p * vec2(1.0, 1.6) - flow * 0.7) / 45.0).r;
	vec3 col = mix(c_shallow, c_deep, depth);
	col *= 0.88 + 0.22 * w1;
	// Sun glints and painterly wave strokes.
	col = mix(col, vec3(0.9, 0.97, 0.95), smoothstep(0.78, 0.86, w2) * 0.45 * (1.0 - depth * 0.6));
	// Foam line that breathes in and out along the shore.
	float edge = 1.0 + 0.012 + 0.008 * sin(TIME * 1.4 + a * 18.0);
	float foam = 1.0 - smoothstep(0.0, 0.012, abs(r - edge));
	col = mix(col, vec3(0.96, 0.97, 0.94), foam * (0.65 + 0.35 * w1));
	return col;
}

void fragment() {
	vec2 p = UV * world_size;
	float ang;
	float ir = island_r(p, ang);
	vec3 final_col;
	if (ir > 1.0) {
		final_col = sea_at(p, ir, ang);
	} else if (ir > road_end) {
		final_col = sand_at(p, ir) * (0.9 + 0.16 * nhi(p, 21.0));
	} else {
		float jit = (nhi(p, 160.0) - 0.5) * 7.0;

		// Signed distance to the road network (negative inside a road).
		float d_main = max(main_y0 - p.y, p.y - main_y1);
		float d_cross = max(cross_x0 - p.x, p.x - cross_x1);
		float d = min(d_main, d_cross) + jit * 0.35;
		bool near_j = p.x > cross_x0 - walk - gutter && p.x < cross_x1 + walk + gutter && p.y > main_y0 - walk - gutter && p.y < main_y1 + walk + gutter;
		bool in_junction = p.x > cross_x0 && p.x < cross_x1 && p.y > main_y0 && p.y < main_y1;

		// Painterly breakup shared by every surface: two scales of soft dabs plus brush streaks.
		float dab = nhi(p, 21.0);
		float dab2 = nhi(p * vec2(1.0, 2.4) + 311.0, 47.0);
		float paint_mod = 0.86 + 0.26 * dab + (quality > 0 ? 0.08 * (dab2 - 0.5) : 0.0);

		vec3 col;
		if (d < 0.0) {
			// Worn asphalt with patches, potholes and faded lane paint.
			col = use_tex ? texture(tex_asphalt, p / tex_tile).rgb : c_asphalt * (0.9 + 0.22 * nlo(p, 140.0));
			float patchy = smoothstep(0.62, 0.7, nlo(p + 91.0, 90.0));
			col = mix(col, col * 1.18, patchy * 0.6);
			float ph = nhi(p + 57.0, 62.0);
			if (ph > 0.79 && !in_junction) {
				col = mix(vec3(0.12, 0.11, 0.1), vec3(0.32, 0.35, 0.27), smoothstep(0.83, 0.9, ph));
			} else if (ph > 0.765) {
				col = mix(col, c_ink, 0.75);
			}
			float mid_main = (main_y0 + main_y1) * 0.5;
			float mid_cross = (cross_x0 + cross_x1) * 0.5;
			bool dash_main = abs(p.y - mid_main) < 1.8 && mod(p.x, 48.0) < 22.0 && !near_j;
			bool dash_cross = abs(p.x - mid_cross) < 1.8 && mod(p.y, 48.0) < 22.0 && !near_j;
			if ((dash_main || dash_cross) && nhi(p, 9.0) > 0.25) {
				col = mix(col, vec3(0.81, 0.76, 0.6), 0.65);
			}
			// Inked kerb edge just inside the road.
			col = mix(col, c_ink, smoothstep(-2.2, -0.2, d) * (near_j ? 0.0 : 0.85));
		} else if (d < gutter && !near_j) {
			// Open drain: dark water with a dull sheen and a concrete lip.
			col = c_gutter * (0.8 + 0.4 * nhi(p, 13.0));
			col = mix(col, c_kerb, smoothstep(gutter - 3.5, gutter - 1.0, d));
			col = mix(col, c_kerb, 1.0 - smoothstep(0.0, 2.5, d));
			col = mix(col, c_ink, smoothstep(gutter - 1.2, gutter, d) * 0.8);
		} else if (d < gutter + walk) {
			// Interlocking paving with dusty mortar lines.
			if (use_tex) {
				col = texture(tex_walk, p / (tex_tile * 0.5)).rgb;
			} else {
				vec2 b = p / vec2(16.0, 9.0);
				b.x += mod(floor(b.y), 2.0) * 0.5;
				vec2 f = fract(b);
				float mortar = (f.x < 0.07 || f.y < 0.12) ? 1.0 : 0.0;
				col = c_walk * (0.88 + 0.2 * hash(floor(b)));
				col = mix(col, col * 0.7, mortar * 0.6);
			}
			col = mix(col, c_dirt, smoothstep(0.55, 0.75, nlo(p + 17.0, 110.0)) * 0.5); // dust drifts
		} else {
			// Ground: dirt, red laterite and patchy grass, blended softly.
			float lat = smoothstep(0.5, 0.62, nlo(p + vec2(731.0, 219.0), 620.0));
			float grass = smoothstep(0.5, 0.6, nlo(p, 480.0) + (dab - 0.5) * 0.12);
			vec3 g = use_tex ? texture(tex_grass, p / tex_tile).rgb : mix(c_grass, c_grass_light, nhi(p + 5.0, 34.0));
			vec3 dirt = use_tex ? texture(tex_dirt, p / tex_tile).rgb : c_dirt;
			col = mix(dirt, use_tex ? dirt * vec3(1.05, 0.9, 0.82) : c_laterite, lat);
			col = mix(col, g, grass);
			// Land turns to beach toward the coast, blending softly.
			col = mix(col, sand_at(p, ir), smoothstep(beach_start - 0.02, beach_start + 0.01, ir));
			// Grass blades: short dark strokes in grassy areas.
			if (quality > 0 && !use_tex) {
				float blade = nhi(p * vec2(3.0, 0.6), 9.0);
				col = mix(col, col * 0.62, step(0.8, blade) * grass * 0.8);
			}
			// Stones and litter specks.
			float h = hash(floor(p / 3.0));
			if (h > 0.9965) col = mix(col, vec3(0.86, 0.86, 0.84), 0.85);
			else if (h < 0.0025) col = mix(col, vec3(0.55, 0.53, 0.5), 0.8);
		}

		col *= use_tex ? mix(1.0, paint_mod, 0.35) : paint_mod;

		// Grime: large soft stains plus fine specks.
		float grime = smoothstep(0.55, 0.85, nlo(p + 1234.0, 300.0));
		col = mix(col, col * vec3(0.78, 0.74, 0.68), grime * 0.7); // warm brown stains, not black
		if (quality > 0) {
			float speck = hash(floor(p / 1.6) + 7.0);
			if (speck > 0.985) col *= 0.7;
			else if (speck < 0.004) col = mix(col, vec3(0.92, 0.88, 0.78), 0.4);
		}

		final_col = col;
	}
	COLOR = vec4(final_col, 1.0);
}
