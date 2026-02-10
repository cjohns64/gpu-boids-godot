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

uniform float rate : hint_range(2.0, 15.0);

void vertex() {
	vec3 disp = vec3(0, 0, 0);

	// control rate by acceleration
	//float rate = 2.0; // slow swim: 2.0 -> fast swim: 20.0
	float com = 2.5 * ((rate - 2.0) / 18.0) + 0.5 * (1.0 - (rate - 2.0) / 18.0); // 0.5 - 2.5
	float T = fract(TIME * rate * 0.25) * 2.0 * PI;
	// general equation for a rotation by an angle (T) about a pivot (u1)
	//disp.x = VERTEX.x * (u1.x * u1.x * (1.0 - cos(T)) + cos(T))
			//+ VERTEX.y * (u1.x * u1.y * (1.0 - cos(T)) - u1.z * sin(T))
			//+ VERTEX.z * (u1.x * u1.z * (1.0 - cos(T)) + u1.y * sin(T));
	//disp.y = VERTEX.x * (u1.x * u1.y * (1.0 - cos(T)) + u1.z * sin(T))
			//+ VERTEX.y * (u1.y * u1.y * (1.0 - cos(T)) + cos(T))
			//+ VERTEX.z * (u1.y * u1.z * (1.0 - cos(T)) - u1.x * sin(T));
	//disp.z = VERTEX.x * (u1.x * u1.y * (1.0 - cos(T)) - u1.y * sin(T))
			//+ VERTEX.y * (u1.y * u1.z * (1.0 - cos(T)) + u1.x * sin(T))
			//+ VERTEX.z * (u1.z * u1.z * (1.0 - cos(T)) + cos(T));
	// y-axis rotation (u1 = 0,1,0) theta = 0.5*sin(T) //to get the side-to-side rotation
	disp.x += VERTEX.x * (cos(0.5*sin(T))) + VERTEX.z * (sin(0.5*sin(T)));
	disp.y += VERTEX.y;
	disp.z += VERTEX.z * cos(0.5*sin(T)) - VERTEX.x * sin(0.5*sin(T));
    // side to side motion
	disp.x += VERTEX.x + 0.25 * sin(T);
	disp.y += VERTEX.y;
	disp.z += VERTEX.z;
    // roll rotation as a function of offset from pivot (u1 = 0,0,1)
	float offset_roll = 0.5 * sin(T) * (1.0 + 5.0 * (VERTEX.x*VERTEX.x + VERTEX.y*VERTEX.y));
	disp.x += VERTEX.x * cos(offset_roll) - VERTEX.y * sin(offset_roll);
	disp.y += VERTEX.x * sin(offset_roll) + VERTEX.y * cos(offset_roll);
	disp.z += VERTEX.z;
    // y-axis rotation as a function of offset from pivot
	float offset_yrot = sin(T) * (0.25 + 0.5 * (VERTEX.z*VERTEX.z));
	disp.x += VERTEX.x * (cos(offset_yrot)) + (VERTEX.z - com) * (sin(offset_yrot));
	disp.y += VERTEX.y;
	disp.z += VERTEX.z * cos(offset_yrot) - VERTEX.x * sin(offset_yrot);
	// side-to-side sine wave
	disp.x += 1.2 * (VERTEX.z * (sin(T + 2.5*VERTEX.z)));

	//VERTEX = (yrot + xsid + roll + yoff + swav) / 4.0;
	VERTEX = disp / 4.0; // yrot, xsid, roll, yoff all contribute 1 full vertex displacement, need to normalize
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
