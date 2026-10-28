shader_type sky;

uniform vec3 top_color : source_color = vec3(0.28, 0.5, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.84, 0.95);
uniform vec3 ground_color : source_color = vec3(0.35, 0.4, 0.3);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.75);
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.65, 0.7, 0.8);
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.3);
uniform float night = 0.0;
uniform float cloud_offset = 0.0;
uniform float cloud_coverage = 0.45;
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.5));
	col = mix(col, ground_color, smoothstep(0.0, 0.1, -h));

	vec3 sd = normalize(sun_dir);
	float cos_sun = max(dot(dir, sd), 0.0);
	float disc = smoothstep(0.9994, 0.9997, cos_sun);
	float halo = pow(cos_sun, 64.0) * 0.6 + pow(cos_sun, 6.0) * 0.2;
	float sun_up = smoothstep(-0.1, 0.05, sd.y);
	col += sun_color * (disc * 18.0 + halo) * sun_up;

	// Moon on the opposite side of the sky.
	float cos_moon = max(dot(dir, -sd), 0.0);
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9995, 0.9997, cos_moon) * 3.0 * night;

	if (h > 0.0) {
		if (!AT_CUBEMAP_PASS) {
			vec3 cell = floor(dir * 320.0);
			float star = step(0.9975, hash(cell)) * smoothstep(0.0, 0.25, h);
			col += vec3(star) * night * (0.6 + 0.6 * hash(cell + 1.0));
		}
		vec2 uv = dir.xz / (h + 0.12);
		float n = texture(cloud_noise, uv * 0.11 + vec2(cloud_offset, cloud_offset * 0.3)).r;
		float n2 = texture(cloud_noise, uv * 0.37 - vec2(cloud_offset * 1.7, 0.0)).r;
		float d = n * 0.7 + n2 * 0.3;
		float cloud = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.28, d) * smoothstep(0.0, 0.18, h);
		vec3 cc = mix(cloud_shade, cloud_light, smoothstep(0.35, 0.8, d));
		cc += sun_color * pow(cos_sun, 8.0) * 0.5 * sun_up;
		col = mix(col, cc, cloud * 0.92);
	}
	COLOR = col;
}
