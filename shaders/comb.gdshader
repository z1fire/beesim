shader_type spatial;
render_mode cull_disabled;

// Each honeycomb cell is an instance. INSTANCE_CUSTOM.rgb is the colour of what the
// cell holds (honey, pollen, larva...) and .a is how full it is. Vertices of the
// "contents" cap are flagged with UV.x = 1 and slide along the cell to that depth.
uniform float depth = 0.28;

varying float v_content;
varying vec4 v_custom;

void vertex() {
	v_content = UV.x;
	v_custom = INSTANCE_CUSTOM;
	if (UV.x > 0.5) {
		VERTEX.z = -depth + 0.006 + clamp(INSTANCE_CUSTOM.a, 0.0, 1.0) * (depth - 0.02);
	}
}

void fragment() {
	vec3 c = mix(COLOR.rgb, v_custom.rgb, v_content);
	// Liquid contents (anything not filled to the brim) are glossy; caps are waxy.
	float gloss = v_content * (1.0 - step(0.99, v_custom.a));
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	ALBEDO = c;
	ROUGHNESS = mix(0.6, 0.1, gloss);
	SPECULAR = mix(0.35, 0.8, gloss);
	EMISSION = c * gloss * sat * 0.6;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
