#[compute]
#version 450

// number of fish in dispatch, size must be a power of 2 but not all elements need to contain a fish
#define ARRAY_LEN 256
// Invocations in the (x, y, z) dimension
layout(local_size_x = ARRAY_LEN, local_size_y = 1, local_size_z = 1) in;

struct Vector3 {
    float x;
    float y;
    float z;
};

//priority_buffer s0 b0 float
//compute_mask  s0 b1 bool
//target    s0 b2 vec3
//coeff     s0 b3 vec3
//position     s1 b4 vec3
//rate     s1 b5 float
//direction     s1 b6 vec3
//TODO
layout(set=0, binding=0, std430) readonly buffer FishPriorityBuffer {
    // the boids priority for each fish in the dispatch
    float priority[ARRAY_LEN];
} priority_buffer;

layout(set=0, binding=1, std430) readonly buffer FishMaskBuffer {
    // flag for if the fish gets updated data
    // set to either 1.0 for active, or 0.0 for inactive
    float compute_mask[ARRAY_LEN];
} mask_buffer;

layout(set=0, binding=2, std430) readonly buffer FishTargetBuffer {
    // target swim position
    Vector3 target;
} target_buffer;

layout(set=0, binding=3, std430) readonly buffer FishBoidsBuffer {
    // boids coefficients for scaling weight of each component for each fish
    // x = cohesion, y = alignment, z = separation
    Vector3 coeff[ARRAY_LEN];
} boids_buffer;

layout(set=0, binding=4, std430) readonly buffer DeltaTime {
    float delta_time;
} time_buffer;

layout(set=1, binding=5, std430) restrict buffer FishPositionBuffer {
    // current position of each fish
    Vector3 position[ARRAY_LEN];
} position_buffer;

layout(set=1, binding=6, std430) restrict buffer FishSwimRateBuffer {
    // the swim speed for each fish in the dispatch
    float rate[ARRAY_LEN];
} swimrate_buffer;

layout(set=1, binding=7, std430) restrict buffer FishDirectionBuffer {
    // current swim direction of each fish
    Vector3 direction[ARRAY_LEN];
} dir_buf;

shared vec3 sum_pos[ARRAY_LEN/2];
shared vec3 sum_dir[ARRAY_LEN/2];

void main() {
    // calculate average position and direction of the group
    // load sum arrays, do the first reduction now so we use half the shared memory size
    if (gl_GlobalInvocationID.x < ARRAY_LEN / 2) {
        sum_dir[gl_GlobalInvocationID.x].x = mask_buffer.compute_mask[gl_GlobalInvocationID.x] * dir_buf.direction[gl_GlobalInvocationID.x].x;
        sum_dir[gl_GlobalInvocationID.x].y = mask_buffer.compute_mask[gl_GlobalInvocationID.x] * dir_buf.direction[gl_GlobalInvocationID.x].y;
        sum_dir[gl_GlobalInvocationID.x].z = mask_buffer.compute_mask[gl_GlobalInvocationID.x] * dir_buf.direction[gl_GlobalInvocationID.x].z;
        sum_pos[gl_GlobalInvocationID.x].x = mask_buffer.compute_mask[gl_GlobalInvocationID.x] * position_buffer.position[gl_GlobalInvocationID.x].x;
        sum_pos[gl_GlobalInvocationID.x].y = mask_buffer.compute_mask[gl_GlobalInvocationID.x] * position_buffer.position[gl_GlobalInvocationID.x].y;
        sum_pos[gl_GlobalInvocationID.x].z = mask_buffer.compute_mask[gl_GlobalInvocationID.x] * position_buffer.position[gl_GlobalInvocationID.x].z;
    }
    barrier(); // wait for all threads
    if (gl_GlobalInvocationID.x >= ARRAY_LEN / 2 && gl_GlobalInvocationID.x % 2 == 1) {
        sum_dir[gl_GlobalInvocationID.x / 2].x += mask_buffer.compute_mask[gl_GlobalInvocationID.x] * dir_buf.direction[gl_GlobalInvocationID.x].x;
        sum_dir[gl_GlobalInvocationID.x / 2].y += mask_buffer.compute_mask[gl_GlobalInvocationID.x] * dir_buf.direction[gl_GlobalInvocationID.x].y;
        sum_dir[gl_GlobalInvocationID.x / 2].z += mask_buffer.compute_mask[gl_GlobalInvocationID.x] * dir_buf.direction[gl_GlobalInvocationID.x].z;
        sum_pos[gl_GlobalInvocationID.x / 2].x += mask_buffer.compute_mask[gl_GlobalInvocationID.x] * position_buffer.position[gl_GlobalInvocationID.x].x;
        sum_pos[gl_GlobalInvocationID.x / 2].y += mask_buffer.compute_mask[gl_GlobalInvocationID.x] * position_buffer.position[gl_GlobalInvocationID.x].y;
        sum_pos[gl_GlobalInvocationID.x / 2].z += mask_buffer.compute_mask[gl_GlobalInvocationID.x] * position_buffer.position[gl_GlobalInvocationID.x].z;
    }
    barrier(); // wait for all threads
    // reduce the shared arrays with a shuffle down sum
    for (uint x=4; x<=ARRAY_LEN; x*=2) {
        // shuffle pos and dir
        // calculate the shuffle index for this thread
        // uint toIndex = (gl_GlobalInvocationID.x + x)%(2*x) + (2*x)*(int(gl_GlobalInvocationID.x/(2*x)));
        uint toIndex = gl_GlobalInvocationID.x / 2;
        // get sum values
        vec3 pv1 = sum_pos[gl_GlobalInvocationID.x];
        vec3 pv2 = sum_pos[toIndex];
        vec3 dv1 = sum_dir[gl_GlobalInvocationID.x];
        vec3 dv2 = sum_dir[toIndex];
        barrier(); // wait for all threads
        // update the array with the sum
        if (gl_GlobalInvocationID.x % 2 == 1) {
            sum_pos[toIndex] = pv1 + pv2;
            sum_dir[toIndex] = dv1 + dv2;
        }
        barrier(); // wait for all threads
    }
    
    // if (!mask_buffer.compute_mask[gl_GlobalInvocationID.x]) {
    //     // don't compute this fish if it is masked
    //     return;
    // }

    // normalize
    if (gl_GlobalInvocationID.x == 0) {
        sum_pos[0] = sum_pos[0] / float(ARRAY_LEN);
        sum_dir[0] = sum_dir[0] / sqrt(dot(sum_dir[0], sum_dir[0]) + 0.001);
    }
    barrier();

    // cohesion
    // -> rotate towards average position
    vec3 position_diff = sum_pos[0] - vec3(
            position_buffer.position[gl_GlobalInvocationID.x].x,
            position_buffer.position[gl_GlobalInvocationID.x].y,
            position_buffer.position[gl_GlobalInvocationID.x].z
            );
    vec3 cohesion = boids_buffer.coeff[gl_GlobalInvocationID.x].x * normalize(position_diff);
    // alignment
    // -> rotate towards average direction
    vec3 alignment = boids_buffer.coeff[gl_GlobalInvocationID.x].y * sum_dir[0];
    // separation
    // -> rotate away from neighbors
    vec3 separation = vec3(0.0, 0.0, 0.0);
    for (int i=0; i<ARRAY_LEN; i++) {
        // skip the current index
        if (i == gl_GlobalInvocationID.x) continue;
        // calculate the mix factor
        float sep_x = position_buffer.position[gl_GlobalInvocationID.x].x - position_buffer.position[i].x;
        float sep_y = position_buffer.position[gl_GlobalInvocationID.x].y - position_buffer.position[i].y;
        float sep_z = position_buffer.position[gl_GlobalInvocationID.x].z - position_buffer.position[i].z;
        vec3 separation_vector = vec3(sep_x, sep_y, sep_z);
        float separation_len = dot(separation_vector, separation_vector);
        if (separation_len < 5.0) { // only add vectors with a set distance
            separation += separation_vector / (separation_len + 0.001);
        }
    }
    separation =  boids_buffer.coeff[gl_GlobalInvocationID.x].z * normalize(separation) * mask_buffer.compute_mask[gl_GlobalInvocationID.x];

    // get direction to flow target
    vec3 target_dir = vec3(0.0, 0.0, 0.0);
    target_dir.x = target_buffer.target.x - position_buffer.position[gl_GlobalInvocationID.x].x;
    target_dir.y = target_buffer.target.y - position_buffer.position[gl_GlobalInvocationID.x].y;
    target_dir.z = target_buffer.target.z - position_buffer.position[gl_GlobalInvocationID.x].z;
    target_dir = normalize(target_dir);
    // calculate goal direction
    target_dir.x = separation.x + alignment.x + cohesion.x + target_dir.x;
    target_dir.y = separation.y + alignment.y + cohesion.y + target_dir.y;
    target_dir.z = separation.z + alignment.z + cohesion.z + target_dir.z;
    vec3 curr_dir = vec3(0.0, 0.0, 0.0);
    curr_dir.x = dir_buf.direction[gl_GlobalInvocationID.x].x;
    curr_dir.y = dir_buf.direction[gl_GlobalInvocationID.x].y;
    curr_dir.z = dir_buf.direction[gl_GlobalInvocationID.x].z;
    vec3 new_velocity = curr_dir * (1.0 - time_buffer.delta_time * 1.0) + target_dir * (time_buffer.delta_time * 1.0);
    // float current_rato = 2.0;
    // float GdotC = dot(goal_dir, curr_dir);
    // if (GdotC == -1.0){
    //     new_dir = normalize(current_rato * normalize(curr_dir) + vec3(1.0, 0.0, 0.0));
    // }
    // else {
    //     // get perpendicular component
    //     // turn by amount in that direction
    //     vec3 projection =  (GdotC / dot(goal_dir, goal_dir) ) * goal_dir;
    //     new_dir = normalize(current_rato * normalize(curr_dir) + normalize(curr_dir - projection));
    // }

    // set direction to point towards result
    dir_buf.direction[gl_GlobalInvocationID.x].x = new_velocity.x;
    dir_buf.direction[gl_GlobalInvocationID.x].y = new_velocity.y;
    dir_buf.direction[gl_GlobalInvocationID.x].z = new_velocity.z;
    // update position
    position_buffer.position[gl_GlobalInvocationID.x].x = position_buffer.position[gl_GlobalInvocationID.x].x + new_velocity.x * time_buffer.delta_time;
    position_buffer.position[gl_GlobalInvocationID.x].y = position_buffer.position[gl_GlobalInvocationID.x].y + new_velocity.y * time_buffer.delta_time;
    position_buffer.position[gl_GlobalInvocationID.x].z = position_buffer.position[gl_GlobalInvocationID.x].z + new_velocity.z * time_buffer.delta_time;

}
