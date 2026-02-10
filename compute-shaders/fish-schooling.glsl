#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// A binding to the buffer we create in our script
layout(set = 0, binding = 0, std430) restrict buffer FishDataBuffer {
    int array_len;
    float swim_rate[];
    int priority[];
    vec3 target[];
    vec3 pos[];
    vec3 dir[];
    vec3 boids_coeff[];
}
fish_data_buffer;

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
void shuffle_xor_sum(vec3* data, int pivot) {
    // calculate the shuffle index for this thread
    int toIndex = (gl_GlobalInvocationID + pivot)%(2*pivot) + (2*pivot)(int(gl_GlobalInvocationID/(2*pivot)));
    // get sum values
    vec3 v1 = data[gl_GlobalInvocationID];
    vec3 v2 = data[toIndex];
    barrier(); // wait for all threads
    // update the array with the sum
    data[toIndex] = v1 + v2;
}

void main() {
    // calculate average position and direction of the group
    int x = fish_data_buffer.array_len;
    vec3 sum_pos[x];
    vec3 sum_dir[x];
    do {
        x /= 2;
        // shuffle pos and dir
        shuffle_xor_sum(sum_pos, x);
        shuffle_xor_sum(sum_dir, x);
    } while (x > 1);

    // normalize
    sum_pos[gl_GlobalInvocationID] = sum_pos[gl_GlobalInvocationID] / float(fish_data_buffer.array_len);
    sum_dir[gl_GlobalInvocationID] = normalize(sum_dir[gl_GlobalInvocationID]);

    // cohesion
    // -> rotate towards average position
    vec3 position_diff = fish_data_buffer.pos[gl_GlobalInvocationID] - sum_pos[gl_GlobalInvocationID];
    vec3 cohesion = fish_data_buffer.boids_coeff[0] * position_diff;
    // alignment
    // -> rotate towards average direction
    vec3 alignment = fish_data_buffer.boids_coeff[1] * sum_dir[gl_GlobalInvocationID];
    // separation
    // -> rotate away from neighbors
    vec3 separation = vec3(0.0, 0.0, 0.0);
    for (int i=0; i<fish_data_buffer.array_len; i++) {
        // skip the current index
        if (i == gl_GlobalInvocationID) continue;
        // calculate the mix factor
        vec3 separation_vector = fish_data_buffer.pos[gl_GlobalInvocationID] - fish_data_buffer.pos[i];
        // vec / dot(vec, vec) instead of normalize to save on the sqrt
        // this function will also -> inf as x -> 0 and -> 0 as x -> inf.
        separation -= separation_vector / dot(separation_vector, separation_vector);
    }
    separation = fish_data_buffer.boids_coeff[2] * normalize(separation);

    // update current fish to the averages by boids_coeff amount
    fish_data_buffer.dir[gl_GlobalInvocationID] = normalize(fish_data_buffer.dir[gl_GlobalInvocationID] + cohesion + alignment + separation);
}
