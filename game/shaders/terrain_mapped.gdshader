// Ground of a disc course drawn with its own textures (CrzTerrain, Classic
// look), laid on the ground by the course's texture mappings: the first
// texture at UV, and for a blended material the second at UV2, faded by
// the course's edge mask ("Fairway To Rough Alpha.tga", at the mesh's
// CUSTOM0 coordinates), as Links 2003 draws the edges between fairway and
// rough and round bunkers. Black in the mask is the first texture, white
// the second. The disc textures have no bumps of their own, so a free
// photo texture's normals (tiled in metres) pick out the grain under a low
// sun. Plus the baked ground shade (GroundShade).
shader_type spatial;

#include "res://shaders/ground_shade.gdshaderinc"

uniform sampler2D texture_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D texture_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask_tex : filter_linear_mipmap, repeat_enable;
uniform bool blended = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform float normal_tile = 2.5; // metres per repeat of the normal texture
uniform float normal_strength = 0.35;
uniform vec3 tint_a : source_color = vec3(1.0);
uniform vec3 tint_b : source_color = vec3(1.0);
uniform float roughness_a = 1.0;
uniform float roughness_b = 1.0;

varying vec3 world_pos;
varying vec2 mask_uv;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mask_uv = blended ? CUSTOM0.xy : vec2(0.0);
}

void fragment() {
	float dist = length(VERTEX);
	vec3 col = texture(texture_a, UV).rgb * tint_a;
	float rough = roughness_a;
	if (blended) {
		// The mask runs 0 to 1 across the edge; keep off its border texels.
		float w = texture(mask_tex, vec2(clamp(mask_uv.x, 0.02, 0.98), mask_uv.y)).a;
		col = mix(col, texture(texture_b, UV2).rgb * tint_b, w);
		rough = mix(rough, roughness_b, w);
	}
	if (has_normal) {
		vec3 n = texture(normal_tex, world_pos.xz / normal_tile).rgb * 2.0 - 1.0;
		float near = 1.0 - smoothstep(30.0, 150.0, dist);
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(n.x, 0.0, n.y, 0.0)).xyz * normal_strength * near);
	}
	ALBEDO = col * ground_shading(world_pos.xz, dist);
	ROUGHNESS = max(rough, 0.92);
	SPECULAR = 0.1;  // matt ground, no sheen
}
