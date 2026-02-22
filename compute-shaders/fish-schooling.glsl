#[compute]
#version 450

// number of fish in dispatch, size must be a power of 2 but not all elements need to contain a fish
#define ARRAY_LEN 256
// Invocations in the (x, y, z) dimension
layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// A binding to the buffer we create in our script
layout(set = 0, binding = 0, std430) restrict buffer FishDataBuffer {
    // the swim speed for each fish in the dispatch
    float swim_rate[ARRAY_LEN];
    // the boids priority for each fish in the dispatch
    int priority[ARRAY_LEN]; // TODO
    // flag for if the fish gets updated data
    bool compute_mask[ARRAY_LEN]; //TODO
    // target swim position for each fish
    vec3 target[ARRAY_LEN];
    // current location of each fish
    vec3 pos[ARRAY_LEN];
    // current swim direction of each fish
    vec3 dir[ARRAY_LEN];
    // boids coefficents for scaling weight of each component for each fish
    // x = cohesion, y = alignment, z = separation
    vec3 boids_coeff[ARRAY_LEN];
}
fish_data_buffer;

uniform vec3 sum_pos[ARRAY_LEN];
uniform vec3 sum_dir[ARRAY_LEN];

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
    int toIndex = (gl_GlobalInvocationID + pivot)%(2*pivot) + (2*pivot)(int(gl_GlobalInvocationID/(2*pivot)));
    // get sum values
    vec3 v1 = sum_pos[gl_GlobalInvocationID];
    vec3 v2 = sum_pos[toIndex];
    barrier(); // wait for all threads
    // update the array with the sum
    sum_pos[toIndex] = v1 + v2;
}

void shuffle_xor_sum_dir(int pivot) {
    // calculate the shuffle index for this thread
    int toIndex = (gl_GlobalInvocationID + pivot)%(2*pivot) + (2*pivot)(int(gl_GlobalInvocationID/(2*pivot)));
    // get sum values
    vec3 v1 = sum_dir[gl_GlobalInvocationID];
    vec3 v2 = sum_dir[toIndex];
    barrier(); // wait for all threads
    // update the array with the sum
    sum_dir[toIndex] = v1 + v2;
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
    
    if (!fish_data_buffer.compute_mask[gl_GlobalInvocationID]) {
        // don't compute this fish if it is masked
        return;
    }

    // normalize
    sum_pos[gl_GlobalInvocationID] = sum_pos[gl_GlobalInvocationID] / float(ARRAY_LEN);
    sum_dir[gl_GlobalInvocationID] = normalize(sum_dir[gl_GlobalInvocationID]);

    // cohesion
    // -> rotate towards average position
    vec3 position_diff = fish_data_buffer.pos[gl_GlobalInvocationID] - sum_pos[gl_GlobalInvocationID];
    vec3 cohesion = fish_data_buffer.boids_coeff[gl_GlobalInvocationID].x * position_diff;
    // alignment
    // -> rotate towards average direction
    vec3 alignment = fish_data_buffer.boids_coeff[gl_GlobalInvocationID].y * sum_dir[gl_GlobalInvocationID];
    // separation
    // -> rotate away from neighbors
    vec3 separation = vec3(0.0, 0.0, 0.0);
    for (int i=0; i<ARRAY_LEN; i++) {
        // skip the current index
        if (i == gl_GlobalInvocationID) continue;
        // calculate the mix factor
        vec3 separation_vector = fish_data_buffer.pos[gl_GlobalInvocationID] - fish_data_buffer.pos[i];
        // vec / dot(vec, vec) instead of normalize to save on the sqrt
        // this function will also -> inf as x -> 0 and -> 0 as x -> inf.
        separation -= separation_vector / dot(separation_vector, separation_vector);
    }
    separation = fish_data_buffer.boids_coeff[gl_GlobalInvocationID].z * normalize(separation);

    // update current fish to the averages by boids_coeff amount
    fish_data_buffer.dir[gl_GlobalInvocationID] = normalize(fish_data_buffer.dir[gl_GlobalInvocationID] + cohesion + alignment + separation);
}
