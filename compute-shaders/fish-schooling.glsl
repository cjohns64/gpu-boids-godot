#[compute]
#version 450

// number of fish in a school, not all elements need to contain a fish
#define ARRAY_LEN 1024
// Invocations in the (x, y, z) dimension
layout(local_size_x = ARRAY_LEN, local_size_y = 1, local_size_z = 1) in;

struct Vector3 {
    float x;
    float y;
    float z;
};

layout(set=0, binding=0, std430) readonly buffer ParamsBuffer {
    // target swim position
    float target_x;
    float target_y;
    float target_z;
    float avg_pos_x;
    float avg_pos_y;
    float avg_pos_z;
    float avg_dir_x;
    float avg_dir_y;
    float avg_dir_z;
    // boids coefficients for scaling weight of each component for whole simulation
    float boids_cohesion_coeff;
    float boids_alignment_coeff;
    float boids_separation_coeff;
    // time since last update
    float delta_time;
} params_buf;

layout(set=0, binding=1, std430) readonly buffer FishMaskBuffer {
    // flag for if the fish gets updated data
    // set to either 1.0 for active, or 0.0 for inactive
    float compute_mask[];
} mask_buf;

layout(set=1, binding=2, std430) restrict buffer FishSwimRateBuffer {
    // the swim speed for each fish in the dispatch
    float rate[];
} rate_buf;

layout(set=1, binding=3, std430) restrict buffer FishPositionBuffer {
    // current position of each fish
    Vector3 position[];
} pos_buf;

layout(set=1, binding=4, std430) restrict buffer FishDirectionBuffer {
    // current swim direction of each fish
    Vector3 direction[];
} dir_buf;

void main() {
    // cohesion
    // -> rotate towards average position
    vec3 position_diff = vec3(
            params_buf.avg_pos_x,
            params_buf.avg_pos_y,
            params_buf.avg_pos_z) 
            - vec3(
            pos_buf.position[gl_GlobalInvocationID.x].x,
            pos_buf.position[gl_GlobalInvocationID.x].y,
            pos_buf.position[gl_GlobalInvocationID.x].z
            );
    vec3 cohesion = params_buf.boids_alignment_coeff * normalize(position_diff);
    // alignment
    // -> rotate towards average direction
    vec3 alignment = params_buf.boids_alignment_coeff * vec3(
                params_buf.avg_dir_x,
                params_buf.avg_dir_y,
                params_buf.avg_dir_z);
    // separation
    // -> rotate away from neighbors
    vec3 separation = vec3(0.0, 0.0, 0.0);
    for (int i=0; i<ARRAY_LEN; i++) {
        // skip the current index
        if (i == gl_GlobalInvocationID.x) continue;
        // calculate the mix factor
        float sep_x = pos_buf.position[gl_GlobalInvocationID.x].x - pos_buf.position[i].x;
        float sep_y = pos_buf.position[gl_GlobalInvocationID.x].y - pos_buf.position[i].y;
        float sep_z = pos_buf.position[gl_GlobalInvocationID.x].z - pos_buf.position[i].z;
        vec3 separation_vector = vec3(sep_x, sep_y, sep_z);
        float separation_len = dot(separation_vector, separation_vector);
        if (separation_len < 5.0) { // only add vectors with a set distance
            separation += separation_vector / (separation_len + 0.001);
        }
    }
    if (dot(separation, separation) > 1.0) {
        // normalize separation if greater then unit length
        separation = params_buf.boids_separation_coeff * normalize(separation) * mask_buf.compute_mask[gl_GlobalInvocationID.x];
    }
    else {
        separation = params_buf.boids_separation_coeff * separation * mask_buf.compute_mask[gl_GlobalInvocationID.x];
    }

    // get direction to flow target
    vec3 target_dir = vec3(0.0, 0.0, 0.0);
    target_dir.x = params_buf.target_x - pos_buf.position[gl_GlobalInvocationID.x].x;
    target_dir.y = params_buf.target_y - pos_buf.position[gl_GlobalInvocationID.x].y;
    target_dir.z = params_buf.target_z - pos_buf.position[gl_GlobalInvocationID.x].z;
    target_dir = normalize(target_dir);
    // calculate goal direction
    target_dir.x = separation.x + alignment.x + cohesion.x + target_dir.x;
    target_dir.y = separation.y + alignment.y + cohesion.y + target_dir.y;
    target_dir.z = separation.z + alignment.z + cohesion.z + target_dir.z;
    vec3 curr_dir = vec3(0.0, 0.0, 0.0);
    curr_dir.x = dir_buf.direction[gl_GlobalInvocationID.x].x;
    curr_dir.y = dir_buf.direction[gl_GlobalInvocationID.x].y;
    curr_dir.z = dir_buf.direction[gl_GlobalInvocationID.x].z;
    // linear interpolation between current direction and goal direction, limited by delta time
    // this prevents instantaneous rotations
    vec3 new_velocity = normalize(curr_dir * (1.0 - params_buf.delta_time * 1.0) + target_dir * (params_buf.delta_time * 1.0));

    // set direction to point towards result
    dir_buf.direction[gl_GlobalInvocationID.x].x = new_velocity.x;
    dir_buf.direction[gl_GlobalInvocationID.x].y = new_velocity.y;
    dir_buf.direction[gl_GlobalInvocationID.x].z = new_velocity.z;
    // update position
    pos_buf.position[gl_GlobalInvocationID.x].x = pos_buf.position[gl_GlobalInvocationID.x].x + new_velocity.x * params_buf.delta_time;
    pos_buf.position[gl_GlobalInvocationID.x].y = pos_buf.position[gl_GlobalInvocationID.x].y + new_velocity.y * params_buf.delta_time;
    pos_buf.position[gl_GlobalInvocationID.x].z = pos_buf.position[gl_GlobalInvocationID.x].z + new_velocity.z * params_buf.delta_time;
}
