// NOTE: Shader automatically converted from Godot Engine 4.5.1.stable's StandardMaterial3D.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform ivec2 albedo_texture_size;
uniform float point_size : hint_range(0.1, 128.0, 0.1);

uniform float roughness : hint_range(0.0, 1.0);
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;

uniform float specular : hint_range(0.0, 1.0, 0.01);
uniform float metallic : hint_range(0.0, 1.0, 0.01);

uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0);

uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

uniform vec3 u1 = vec3(0, 0.707, 0.707);

void vertex() {
	vec3 disp = vec3(0, 0, 0);
	vec3 yrot = vec3(0, 0, 0);
	vec3 xsid = vec3(0, 0, 0);
	vec3 roll = vec3(0, 0, 0);
	vec3 yoff = vec3(0, 0, 0);
	
	float T = 0.5 * sin(TIME * 5.5);
	//disp.x = VERTEX.x * (u1.x * u1.x * (1.0 - cos(T)) + cos(T)) 
			//+ VERTEX.y * (u1.x * u1.y * (1.0 - cos(T)) - u1.z * sin(T))
			//+ VERTEX.z * (u1.x * u1.z * (1.0 - cos(T)) + u1.y * sin(T));
	//disp.y = VERTEX.x * (u1.x * u1.y * (1.0 - cos(T)) + u1.z * sin(T))
			//+ VERTEX.y * (u1.y * u1.y * (1.0 - cos(T)) + cos(T))
			//+ VERTEX.z * (u1.y * u1.z * (1.0 - cos(T)) - u1.x * sin(T));
	//disp.z = VERTEX.x * (u1.x * u1.y * (1.0 - cos(T)) - u1.y * sin(T))
			//+ VERTEX.y * (u1.y * u1.z * (1.0 - cos(T)) + u1.x * sin(T))
			//+ VERTEX.z * (u1.z * u1.z * (1.0 - cos(T)) + cos(T));
	// y-axis rotation 
	yrot.x = VERTEX.x * (cos(T)) + VERTEX.z * (sin(T));
	yrot.y = VERTEX.y;
	yrot.z = VERTEX.z * cos(T) - VERTEX.x * sin(T);
    // side to side motion
	xsid.x = VERTEX.x + 0.25 * sin(T);
	xsid.y = VERTEX.y;
	xsid.z = VERTEX.z;
    // roll rotation f(offset from pivot)
	float offset_roll = 1.0 + 3.0 * sqrt(VERTEX.x*VERTEX.x + VERTEX.y*VERTEX.y);
	roll.x = VERTEX.x * cos(T*offset_roll) - VERTEX.y * sin(T*offset_roll);
	roll.y = VERTEX.x * sin(T*offset_roll) + VERTEX.y * cos(T*offset_roll);
	roll.z = VERTEX.z;
    // y-axis rotation with f(offset from pivot)
	float offset_yrot = 1.0 + 4.0 * sqrt(VERTEX.x*VERTEX.x + VERTEX.z*VERTEX.z);
	yoff.x = VERTEX.x * (cos(T*offset_yrot)) + VERTEX.z * (sin(T*offset_yrot));
	yoff.y = VERTEX.y;
	yoff.z = VERTEX.z * cos(T*offset_yrot) - VERTEX.x * sin(T*offset_yrot);
    // rate controlled by acceleration
	VERTEX = yrot + 2.0 * xsid + 2.0 * roll + 1.5*yoff;
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	vec2 base_uv = UV;

	vec4 albedo_tex = texture(texture_albedo, base_uv);
	ALBEDO = albedo.rgb * albedo_tex.rgb;

	float metallic_tex = dot(texture(texture_metallic, base_uv), metallic_texture_channel);
	METALLIC = metallic_tex * metallic;
	SPECULAR = specular;

	vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
	float roughness_tex = dot(texture(texture_roughness, base_uv), roughness_texture_channel);
	ROUGHNESS = roughness_tex * roughness;

	// Normal Map: Enabled
	NORMAL_MAP = texture(texture_normal, base_uv).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
}
