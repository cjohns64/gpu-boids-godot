#[compute]
#version 450

// number of fish in dispatch, size must be a power of 2 but not all elements need to contain a fish
#define ARRAY_LEN 256
// Invocations in the (x, y, z) dimension
layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(set=0, binding=0, std430) restrict buffer FishPriorityBuffer {
    // the boids priority for each fish in the dispatch
    float priority[ARRAY_LEN];
} priority_buffer;

layout(set=0, binding=1, std430) restrict buffer FishMaskBuffer {
    // flag for if the fish gets updated data
    bool compute_mask[ARRAY_LEN]; //TODO
} mask_buffer;

layout(set=0, binding=2, std430) restrict buffer FishTargetBuffer {
    // target swim position for each fish
    vec3 target[ARRAY_LEN];
} target_buffer;

layout(set=0, binding=3, std430) restrict buffer FishLocationBuffer {
    // current location of each fish
    vec3 location[ARRAY_LEN];
} location_buffer;

layout(set=0, binding=4, std430) restrict buffer FishBoidsBuffer {
    // boids coefficients for scaling weight of each component for each fish
    // x = cohesion, y = alignment, z = separation
    vec3 coeff[ARRAY_LEN];
} boids_buffer;

layout(set=1, binding=5, std430) restrict buffer FishSwimRateBuffer {
    // the swim speed for each fish in the dispatch
    float rate[ARRAY_LEN];
} swimrate_buffer;

layout(set=1, binding=6, std430) restrict buffer FishDirectionBuffer {
    // current swim direction of each fish
    vec3 direction[ARRAY_LEN];
} direction_buffer;

layout(set=2, binding=7, std430) restrict buffer SumBufferPos {
    vec3 sum_pos[ARRAY_LEN];
} sum_buffer_pos;

layout(set=2, binding=8, std430) restrict buffer SumBufferDir {
    vec3 sum_dir[ARRAY_LEN];
} sum_buffer_dir;

// Performs a shuffle XOR operation, summing elements mirrored across the pivot(s).
// A pivot value equal to the array length / 2 will result in
// all the values in the first half being added to the second half
// and all values in the last half being added to the first half.
// A pivot value equal to 1 will result in each pair of values being 
// added to and placed in the other element.
// --- requires ---
// - data must be an array of length == power of 2,
// - the pivot must also be a power of 2,
// - function should be call for each element in the array, one thread per index
void shuffle_xor_sum_pos(int pivot) {
    // calculate the shuffle index for this thread
    uint toIndex = (gl_GlobalInvocationID.x + pivot)%(2*pivot) + (2*pivot)*(int(gl_GlobalInvocationID.x/(2*pivot)));
    // get sum values
    vec3 v1 = sum_buffer_pos.sum_pos[gl_GlobalInvocationID.x];
    vec3 v2 = sum_buffer_pos.sum_pos[toIndex];
    barrier(); // wait for all threads
    // update the array with the sum
    sum_buffer_pos.sum_pos[toIndex] = v1 + v2;
}

void shuffle_xor_sum_dir(int pivot) {
    // calculate the shuffle index for this thread
    uint toIndex = (gl_GlobalInvocationID.x + pivot)%(2*pivot) + (2*pivot)*(int(gl_GlobalInvocationID.x/(2*pivot)));
    // get sum values
    vec3 v1 = sum_buffer_dir.sum_dir[gl_GlobalInvocationID.x];
    vec3 v2 = sum_buffer_dir.sum_dir[toIndex];
    barrier(); // wait for all threads
    // update the array with the sum
    sum_buffer_dir.sum_dir[toIndex] = v1 + v2;
}

void main() {
    // calculate average position and direction of the group
    int x = ARRAY_LEN;
    do {
        x /= 2;
        // shuffle pos and dir
        shuffle_xor_sum_pos(x);
        shuffle_xor_sum_dir(x);
    } while (x > 1);
    
    if (!mask_buffer.compute_mask[gl_GlobalInvocationID.x]) {
        // don't compute this fish if it is masked
        return;
    }

    // normalize
    sum_buffer_pos.sum_pos[gl_GlobalInvocationID.x] = sum_buffer_pos.sum_pos[gl_GlobalInvocationID.x] / float(ARRAY_LEN);
    sum_buffer_dir.sum_dir[gl_GlobalInvocationID.x] = normalize(sum_buffer_dir.sum_dir[gl_GlobalInvocationID.x]);

    // cohesion
    // -> rotate towards average position
    vec3 position_diff = location_buffer.location[gl_GlobalInvocationID.x] - sum_buffer_pos.sum_pos[gl_GlobalInvocationID.x];
    vec3 cohesion = boids_buffer.coeff[gl_GlobalInvocationID.x].x * position_diff;
    // alignment
    // -> rotate towards average direction
    vec3 alignment = boids_buffer.coeff[gl_GlobalInvocationID.x].y * sum_buffer_dir.sum_dir[gl_GlobalInvocationID.x];
    // separation
    // -> rotate away from neighbors
    vec3 separation = vec3(0.0, 0.0, 0.0);
    for (int i=0; i<ARRAY_LEN; i++) {
        // skip the current index
        if (i == gl_GlobalInvocationID.x) continue;
        // calculate the mix factor
        vec3 separation_vector = location_buffer.location[gl_GlobalInvocationID.x] - location_buffer.location[i];
        // vec / dot(vec, vec) instead of normalize to save on the sqrt
        // this function will also -> inf as x -> 0 and -> 0 as x -> inf.
        separation -= separation_vector / dot(separation_vector, separation_vector);
    }
    separation = boids_buffer.coeff[gl_GlobalInvocationID.x].z * normalize(separation);

    // update current fish to the averages by boids_coeff amount
    direction_buffer.direction[gl_GlobalInvocationID.x] = normalize(direction_buffer.direction[gl_GlobalInvocationID.x] + cohesion + alignment + separation);
}
