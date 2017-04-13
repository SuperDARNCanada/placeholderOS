#include <cuComplex.h> //cuComplex type and all cuCmulf/cuCaddf functions.
#include <iostream>
#include <stdint.h>

/*Overloaded __shfl_down function. Default does not recognize cuComplex but
does for equivalent float2 type.
https://devblogs.nvidia.com/parallelforall/faster-parallel-reductions-kepler/
http://docs.nvidia.com/cuda/cuda-c-programming-guide/#warp-shuffle-functions
*/
__device__ inline cuComplex __shfl_down(cuComplex var, unsigned int srcLane, int width=32){
    float2 a = *reinterpret_cast<float2*>(&var);
    a.x = __shfl_down(a.x, srcLane, width); // REVIEW #0 Does this call the original function since the a variable is a float now?
                                            // REPLY Overloading works by allowing the compiler to detect which version of the function to use for different types, so yes.
                                            // This function just shuffles down each real and imag part seperately like how it was done in the linked example.
    a.y = __shfl_down(a.y, srcLane, width);
    return *reinterpret_cast<cuComplex*>(&a);
}

/*Slightly modified version of reduction #5 from NVIDIA examples
/usr/local/cuda/samples/6_Advanced/reduction
*/
__device__ cuComplex parallel_reduce(cuComplex* data, uint32_t tap_offset) { // REVIEW #28 can tap_offset ever be negative? Maybe should make it uint32_t
                                                                        // REPLY tap_offset is always based off threadIdx which is never negative. I will change this to uint32_t though for consistency

    auto filter_tap_num = threadIdx.x;
    auto num_filter_taps = blockDim.x;
    cuComplex total_sum = data[tap_offset];


    if ((num_filter_taps >= 512) && (filter_tap_num < 256))
    {
        total_sum = cuCaddf(total_sum,data[tap_offset  + 256]);
        data[tap_offset] = total_sum; // REVIEW #25 Is it necessary for speed to have two '=' statements on one line? it took a while to see the second one, therefore more confusing. split into two lines
    }                                       // REPLY okay

    __syncthreads();

    if ((num_filter_taps >= 256) && (filter_tap_num < 128))
    {
        total_sum = cuCaddf(total_sum, data[tap_offset + 128]);
        data[tap_offset] = total_sum;
    }

     __syncthreads();

    if ((num_filter_taps >= 128) && (filter_tap_num <  64))
    {
        total_sum = cuCaddf(total_sum, data[tap_offset  +  64]);
        data[tap_offset] = total_sum;
    }

    __syncthreads();

    if ( filter_tap_num < 32 )
    {
        // Fetch final intermediate sum from 2nd warp
        if (num_filter_taps >=  64) total_sum = cuCaddf(total_sum, data[tap_offset + 32]);
        // Reduce final warp using shuffle // REVEW #3 This code depends upon a warp all executing threads at exactly the same time, if it didn't then double the total_sum value for the second half of the threads would be accidentally used. Can be explicit by putting if statement in the for loop [if (filter_tap_num < offset) we think]
                                           // REPLY The CUDA examples dont use that. I think shfl is designed to mark threads inactive if the source lane as they say wraps out of bounds.
                                            //It also happens simultaneously eliminating the need for __syncthreads
        for (int offset = warpSize/2; offset > 0; offset /= 2) // REVIEW #0 Where does warpSize come from? Don't you need to get it from the gpu_properties?
                                                               // REPLY http://docs.nvidia.com/cuda/cuda-c-programming-guide/#built-in-variables
        {
            total_sum = cuCaddf(total_sum,__shfl_down(total_sum, offset)); // REVIEW #3 Very not-obvious. Seems like it needs to know that total_sum is the variable/memory to work on, need a comment to tell us how this works
        }                                                                  // REPLY This __shfl construct was designed non obvious. But it just consistently halves the threads and shuffles a register value to the active threads.
    }

    return total_sum;
}

__global__ void decimate1024(cuComplex* original_samples,
    cuComplex* decimated_samples,
    cuComplex* filter_taps, uint32_t dm_rate,
    uint32_t samples_per_channel) //REVIEW #1 describe thread/block/grid dimensions and indices
{                                 //REPLY docstring

    extern __shared__ cuComplex filter_products[]; // REVIEW #4 comment why is this extern and why is it necessary to be dynamically allocated?
                                                   //REPLY Shared memory needs to be dynamically allocated http://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#shared

    auto channel_num = blockIdx.y;
    auto channel_offset = channel_num * samples_per_channel;

    auto dec_sample_num = blockIdx.x;
    auto dec_sample_offset = dec_sample_num * dm_rate;

    auto tap_offset = threadIdx.y * blockDim.x + threadIdx.x; // REVIEW #0 should be blockDim.x
                                                              // REPLY correct

    //If an offset should extend past the length of samples per antenna
    //then zeroes are used as to not segfault or run into the next buffer.
    //output samples using these will be discarded as to not introduce edge effects
    cuComplex sample;
    if ((dec_sample_offset + threadIdx.x) >= samples_per_channel) {
        sample = make_cuComplex(0.0f,0.0f); // REVIEW #1 explain zero-padding, #0, correct this after to throw out edge effects (per stage) ceil((num_samps - num_taps)/dm_rate)
    }                                       // REPLY okay. We decided samples will be corrected at the end so this can stay for now
    else {
        auto final_offset = channel_offset + dec_sample_offset + threadIdx.x;
        sample = original_samples[final_offset];
    }


    filter_products[tap_offset] = cuCmulf(sample,filter_taps[tap_offset]); // REVIEW #4 tell user that this comes from cuComplex.h, any side effects?
                                                                           // REPLY dont think so.
    __syncthreads(); // REVIEW #1 Synchronizes all threads in a block, meaning 1 output sample per rx freq is ready to be calculated with the parallel reduce

    auto calculated_output_sample = parallel_reduce(filter_products, tap_offset); // REVIEW #26 Should this be called something like 'decimated_sample' instead - to indicate that it is going into the array of decimated samples? total_sum could be the variable name in parallel reduce, but not here in this context
                                                                   // REPLY alright

    //this is all wrong now that I think about it. At least for second and third stage
    if (threadIdx.x == 0) { // REVIEW #1 Explain how you're setting up the array of decimated samples
        channel_offset = channel_num * samples_per_channel/dm_rate; // REVIEW #13 gridDimx is already samples_per_channel/dm_rate, use it instead
                                                                    // REPLY it is, yet I've been trying to avoid direct use of CUDA builtin types since it not obvious what they mean
        auto total_channels = blockDim.y; // REVIEW #0 This should be gridDim.y if you intend to use 'total_channels' as antennas (should use 'antennas')
        auto freq_offset = threadIdx.y * total_channels; // REVIEW #0 still need to multiply by gridDim.x here to get index into proper location
        auto total_offset = freq_offset + channel_offset + dec_sample_num;
        decimated_samples[total_offset] = calculated_output_sample;
    }
}

__global__ void decimate2048(cuComplex* original_samples,
    cuComplex* decimated_samples,
    cuComplex* filter_taps, uint32_t dm_rate,
    uint32_t samples_per_channel)
{

    extern __shared__ cuComplex filter_products[];

    auto channel_num = blockIdx.y; // REVIEW #26 -Again here channels/freqs/antennas is confused and needs to be consistent, maybe we avoid the word 'channel' altogether
    auto channel_offset = channel_num * samples_per_channel;

    auto dec_sample_num = blockIdx.x;
    auto dec_sample_offset = dec_sample_num * dm_rate;

    auto tap_offset = threadIdx.y * blockDim.y + 2 * threadIdx.x; //REVIEW #0 should be blockDim.x

    cuComplex sample_1;
    cuComplex sample_2;
    if ((dec_sample_offset + 2 * threadIdx.x) >= samples_per_channel) {
        sample_1 = make_cuComplex(0.0,0.0);
        sample_2 = make_cuComplex(0.0,0.0);
    }
    else {
        auto final_offset = channel_offset + dec_sample_offset + 2*threadIdx.x;
        sample_1 = original_samples[final_offset];
        sample_2 = original_samples[final_offset+1];  // REVIEW #0 what if final_offset = samples_per_channel - 1 so that sample_1 is in bounds but sample_2 is out of bounds
    }


    filter_products[tap_offset] = cuCmulf(sample_1,filter_taps[tap_offset]); //
    filter_products[tap_offset+1] = cuCmulf(sample_2, filter_taps[tap_offset+1]); // REVIEW #0 what if you have an odd number of taps so that in the last thread filter_taps[tap_offset+1] isn't defined ? (unless all filters are of length 2^x)
                                                                                  // REPLY filters will have to be power of 2 in length for this to work.
    filter_products[tap_offset] = cuCaddf(filter_products[tap_offset],filter_products[tap_offset+1]);

    __syncthreads();
    auto calculated_output_sample = parallel_reduce(filter_products, tap_offset); // REVIEW #0 pass new variable for offset in filter products so you are not passing only even values
                                                                  // REPLY this can stay the same, but I missed a line of code that needs to happen first

    //again, wrong for now.
    if (threadIdx.x == 0) { // REVIEW #1 Explain how you're setting up the array of decimated samples
        channel_offset = channel_num * samples_per_channel/dm_rate; // REVIEW #13 gridDimx is already samples_per_channel/dm_rate, use it instead
        auto total_channels = blockDim.y; // REVIEW #0 This should be gridDim.y if you intend to use 'total_channels' as antennas (should use 'antennas')
        auto freq_offset = threadIdx.y * total_channels; // REVIEW #0 still need to multiply by gridDim.x here to get index into proper location
        auto total_offset = freq_offset + channel_offset + dec_sample_num;
        decimated_samples[total_offset] = calculated_output_sample;
    }
}

static dim3 create_grid(uint32_t num_samples, uint32_t dm_rate, uint32_t num_channels) // REVIEW #26 no more channels
{
    auto num_blocks_x = num_samples/dm_rate;
    auto num_blocks_y = num_channels;
    auto num_blocks_z = 1;
    std::cout << "    Grid size: " << num_blocks_x << " x " << num_blocks_y << " x "
        << num_blocks_z << std::endl;
    dim3 dimGrid(num_blocks_x,num_blocks_y,num_blocks_z);

    return dimGrid;
}

static dim3 create_block(uint32_t num_taps, uint32_t num_freqs)
{
    auto num_threads_x = num_taps;
    auto num_threads_y = num_freqs;
    auto num_threads_z = 1;
    std::cout << "    Block size: " << num_threads_x << " x " << num_threads_y << " x "
        << num_threads_z << std::endl;
    dim3 dimBlock(num_threads_x,num_threads_y,num_threads_z);

    return dimBlock;
}

void decimate1024_wrapper(cuComplex* original_samples,
    cuComplex* decimated_samples,
    cuComplex* filter_taps, uint32_t dm_rate,
    uint32_t samples_per_channel, uint32_t num_taps, uint32_t num_freqs,
    uint32_t num_channels, cudaStream_t stream) { // REVIEW #1 describe how this works including choice of blocks and grids

    auto shr_mem_taps = num_freqs * num_taps * sizeof(cuComplex); // REVIEW #32 why do we need this?
    std::cout << "    Number of shared memory bytes: "<< shr_mem_taps << std::endl;

    auto dimGrid = create_grid(samples_per_channel, dm_rate, num_channels);
    auto dimBlock = create_block(num_taps,num_freqs);
    decimate1024<<<dimGrid,dimBlock,shr_mem_taps,stream>>>(original_samples, decimated_samples,
                filter_taps, dm_rate, samples_per_channel);

}

void decimate2048_wrapper(cuComplex* original_samples,
    cuComplex* decimated_samples,
    cuComplex* filter_taps, uint32_t dm_rate,
    uint32_t samples_per_channel, uint32_t num_taps, uint32_t num_freqs,
    uint32_t num_channels, cudaStream_t stream) {

    auto shr_mem_taps = num_freqs * num_taps * sizeof(cuComplex);
    std::cout << "    Number of shared memory bytes: "<< shr_mem_taps << std::endl;

    auto dimGrid = create_grid(samples_per_channel, dm_rate, num_channels);
    auto dimBlock = create_block(num_taps/2, num_freqs);
    decimate2048<<<dimGrid,dimBlock,shr_mem_taps,stream>>>(original_samples, decimated_samples,
        filter_taps, dm_rate, samples_per_channel);
}