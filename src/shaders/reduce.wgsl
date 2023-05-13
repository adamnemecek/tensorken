
@group(0) @binding(0)
var<storage, read> input_0: array<f32>;

@group(0) @binding(1)
var<storage, read_write> output_0: array<f32>;

// ndims, input_offset, input_strides, input_contiguous_strides, reducer_strides, input_shape
@group(0) @binding(2)
var<storage, read> strides_and_shape: array<u32>;

const preamble: u32 = 2u;

fn input_strides(i: u32) -> u32 {
    return strides_and_shape[i + preamble];
}

fn input_contiguous_strides(i: u32) -> u32 {
    return strides_and_shape[i + preamble + strides_and_shape[0] ];
}

fn reducer_strides(i: u32) -> u32 {
    return strides_and_shape[i + preamble + strides_and_shape[0] * 2u];
}

fn shape(i: u32) -> u32 {
    return strides_and_shape[i + preamble + strides_and_shape[0] * 3u];
}

// Same parlor trick as in unary_ops.wgsl.
fn replace_me_with_actual_operation(in_1: f32, in_2: f32) -> f32 { discard; }
fn replace_me_with_actual_default() -> f32 { discard; }

// extension to the parlor trick: infix operators are annoying to replace, 
// so we define counterparts for them here.
fn sum(a: f32, b: f32) -> f32 { return a + b; }

// default values for the reduce
const MAX: f32 = -1.17549435082228750797e-38f;
const SUM: f32 = 0.0;

fn input_size() -> u32 {
    var size: u32 = 1u;
    for (var i: u32 = 0u; i < strides_and_shape[0]; i += 1u) {
        size *= shape(i);
    }
    return size;
}

@compute @workgroup_size(64)
fn call(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let gidx = global_id.x;
    // because of workgroup size, gidx is a multiple of 64. Our output array may not be,
    // so we need to make sure we don't go out of bounds. Such acesses are clamped by WGSL,
    // but will typically result in wrong results anyway.
    if(global_id.x >= arrayLength(&output_0)) {
        return;
    }

    // Outline of approach - it's a bit awkward because we'd like to avoid synchronization, so
    // each thread only writes to a single output location in the output buffer. Furthermore, we
    // don't have a way to have an array to represent coordinates, so we need to inline all the calculations.
    //
    // Overview:
    // 1. Iterate over all input elements - note that this is not the same as iterating over
    //    the input _buffer_ - we're iterating over all the possible coordinates in the input tensor, as indicated
    //    by their order input_e.
    // 2. For each input element, compute the real buffer index input_i in the input buffer
    // 3. For each input element, compute the real buffer index output_i in the output buffer.
    // 4. If output_i == gidx, then we're meant to calculate this output and so we reduce the current contents
    //    of output_0[gidx] with the new element.

    // Ok, this is REALLY BAD approach that's probably the reason why matmul is slow and crashes my GPU sometimes. 
    // (see tensor_sum benchmark, which also crashes, and is also slow)
    // The first problem is that the more we reduce, the fewer threads do actual useful work:
    // in the limit, we reduce to a single number which means we're starting 256 threads, only one of which will write the result.
    // IN principle, the more we reduce, the more parallelism we should be able to exploit!
    // Second, this whole thing of iterating over the input elements and only writing to the reduced output is bonkers.
    // Should find a way to 

    var acc = replace_me_with_actual_default();
    for (var input_e: u32 = 0u; input_e < input_size(); input_e += 1u) {
        var output_i: u32 = 0u;
        var input_i: u32 = strides_and_shape[1];
        for (var i: u32 = 0u; i < strides_and_shape[0]; i += 1u) {
            let len = shape(i);
            let stride = input_contiguous_strides(i);
            let coord: u32 = input_e / stride % len;

            input_i += coord * input_strides(i);
            output_i += coord * reducer_strides(i);
        }
        if (output_i == gidx) {
            acc = replace_me_with_actual_operation(acc, input_0[input_i]);
        }
    }
    output_0[gidx] = acc;
}