shader_type spatial;

uniform vec3 yellow : source_color = vec3(0.98, 0.72, 0.12);
uniform vec3 dark : source_color = vec3(0.07, 0.05, 0.03);
uniform vec3 fuzz_color : source_color = vec3(0.86, 0.6, 0.25);
uniform float banded = 1.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float z = v_local.z;
	float bands = smoothstep(-0.15, 0.15, sin((z + 0.5) * 21.0 + 1.2));
	vec3 c = mix(dark, yellow, bands);
	c = mix(c, dark, smoothstep(0.3, 0.45, z));
	c = mix(fuzz_color, c, banded);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	// A soft glowing rim reads as fuzz.
	EMISSION = mix(c, vec3(1.0, 0.85, 0.5), 0.5) * rim * 0.35;
}
