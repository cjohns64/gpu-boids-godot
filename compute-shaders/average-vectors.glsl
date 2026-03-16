#[compute]
#version 450

// number of fish in current workgroup, size must be a power of 2 but not all elements need to contain a fish
#define ARRAY_LEN 1024
// Invocations in the (x, y, z) dimension
layout(local_size_x = ARRAY_LEN, local_size_y = 1, local_size_z = 1) in;

struct Vector3 {
    float x;
    float y;
    float z;
};

layout(set=0, binding=1, std430) readonly buffer FishMaskBuffer {
    // flag for if the fish gets updated data
    // set to either 1.0 for active, or 0.0 for inactive
    float compute_mask[];
} mask_buffer;

layout(set=1, binding=3, std430) readonly buffer FishPositionBuffer {
    // current position of each fish
    Vector3 position[];
} pos_buf;

layout(set=1, binding=4, std430) readonly buffer FishDirectionBuffer {
    // current swim direction of each fish
    Vector3 direction[];
} dir_buf;

layout(set=2, binding=5, std430) writeonly buffer PosResultBuffer {
    Vector3 avg_pos[];
} pos_result_buf;

layout(set=2, binding=6, std430) writeonly buffer DirResultBuffer {
    Vector3 avg_dir[];
} dir_result_buf;

layout(set=2, binding=7, std430) writeonly buffer ActiveResultBuffer {
    float num_active[];
} act_result_buf;

shared vec3 sum_pos[ARRAY_LEN/2];
shared vec3 sum_dir[ARRAY_LEN/2];
shared float sum_active[ARRAY_LEN/2];

void main() {
    // calculate average position and direction of the group
    // load sum arrays, do the first reduction now so we use half the shared memory size
    if (gl_LocalInvocationID.x < ARRAY_LEN / 2) {
        sum_dir[gl_LocalInvocationID.x].x = mask_buffer.compute_mask[gl_GlobalInvocationID.x] * dir_buf.direction[gl_GlobalInvocationID.x].x;
        sum_dir[gl_LocalInvocationID.x].y = mask_buffer.compute_mask[gl_GlobalInvocationID.x] * dir_buf.direction[gl_GlobalInvocationID.x].y;
        sum_dir[gl_LocalInvocationID.x].z = mask_buffer.compute_mask[gl_GlobalInvocationID.x] * dir_buf.direction[gl_GlobalInvocationID.x].z;
        sum_pos[gl_LocalInvocationID.x].x = mask_buffer.compute_mask[gl_GlobalInvocationID.x] * pos_buf.position[gl_GlobalInvocationID.x].x;
        sum_pos[gl_LocalInvocationID.x].y = mask_buffer.compute_mask[gl_GlobalInvocationID.x] * pos_buf.position[gl_GlobalInvocationID.x].y;
        sum_pos[gl_LocalInvocationID.x].z = mask_buffer.compute_mask[gl_GlobalInvocationID.x] * pos_buf.position[gl_GlobalInvocationID.x].z;
        sum_active[gl_LocalInvocationID.x] = mask_buffer.compute_mask[gl_GlobalInvocationID.x];
    }
    barrier(); // wait for all threads
    if (gl_LocalInvocationID.x >= ARRAY_LEN / 2) {
        int half_len = ARRAY_LEN / 2;
        sum_dir[gl_LocalInvocationID.x - half_len].x += mask_buffer.compute_mask[gl_GlobalInvocationID.x] * dir_buf.direction[gl_GlobalInvocationID.x].x;
        sum_dir[gl_LocalInvocationID.x - half_len].y += mask_buffer.compute_mask[gl_GlobalInvocationID.x] * dir_buf.direction[gl_GlobalInvocationID.x].y;
        sum_dir[gl_LocalInvocationID.x - half_len].z += mask_buffer.compute_mask[gl_GlobalInvocationID.x] * dir_buf.direction[gl_GlobalInvocationID.x].z;
        sum_pos[gl_LocalInvocationID.x - half_len].x += mask_buffer.compute_mask[gl_GlobalInvocationID.x] * pos_buf.position[gl_GlobalInvocationID.x].x;
        sum_pos[gl_LocalInvocationID.x - half_len].y += mask_buffer.compute_mask[gl_GlobalInvocationID.x] * pos_buf.position[gl_GlobalInvocationID.x].y;
        sum_pos[gl_LocalInvocationID.x - half_len].z += mask_buffer.compute_mask[gl_GlobalInvocationID.x] * pos_buf.position[gl_GlobalInvocationID.x].z;
        sum_active[gl_LocalInvocationID.x - half_len] += mask_buffer.compute_mask[gl_GlobalInvocationID.x];
    }
    barrier(); // wait for all threads
    // reduce the shared arrays with a shuffle down sum
    for (uint x=4; x<=ARRAY_LEN; x*=2) {
        // shuffle pos and dir
        // calculate the shuffle index for this thread
        uint toIndex = gl_LocalInvocationID.x / 2;
        // read sum values
        vec3 pv1 = sum_pos[gl_LocalInvocationID.x];
        vec3 pv2 = sum_pos[toIndex];
        vec3 dv1 = sum_dir[gl_LocalInvocationID.x];
        vec3 dv2 = sum_dir[toIndex];
        float a1 = sum_active[gl_LocalInvocationID.x];
        float a2 = sum_active[toIndex];
        barrier(); // wait for all threads
        // write sum values
        if (gl_LocalInvocationID.x % 2 == 1) {
            sum_pos[toIndex] = pv1 + pv2;
            sum_dir[toIndex] = dv1 + dv2;
            sum_active[toIndex] = a1 + a2;
        }
        barrier(); // wait for all threads
    }
    
    // write the results
    if (gl_LocalInvocationID.x == 0) {
        pos_result_buf.avg_pos[gl_WorkGroupID.x].x = sum_pos[0].x;
        pos_result_buf.avg_pos[gl_WorkGroupID.x].y = sum_pos[0].y;
        pos_result_buf.avg_pos[gl_WorkGroupID.x].z = sum_pos[0].z;
        dir_result_buf.avg_dir[gl_WorkGroupID.x].x = sum_pos[0].x;
        dir_result_buf.avg_dir[gl_WorkGroupID.x].y = sum_pos[0].y;
        dir_result_buf.avg_dir[gl_WorkGroupID.x].z = sum_pos[0].z;
        act_result_buf.num_active[gl_WorkGroupID.x] = sum_active[0];
    }
}
