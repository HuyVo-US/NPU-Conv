#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define INPUT_ROWS   28
#define INPUT_COLS   28
#define KERNEL_ROWS   3
#define KERNEL_COLS   3
#define OUTPUT_ROWS  (INPUT_ROWS - KERNEL_ROWS + 1)
#define OUTPUT_COLS  (INPUT_COLS - KERNEL_COLS + 1)

#define INPUT_COUNT  ((size_t)INPUT_ROWS * (size_t)INPUT_COLS)
#define KERNEL_COUNT ((size_t)KERNEL_ROWS * (size_t)KERNEL_COLS)
#define OUTPUT_COUNT ((size_t)OUTPUT_ROWS * (size_t)OUTPUT_COLS)

#define DEFAULT_INPUT_FILE      "conv_input.hex"
#define DEFAULT_KERNEL_FILE     "conv_kernel.hex"
#define DEFAULT_RTL_OUTPUT_FILE "conv_output.hex"
#define DEFAULT_C_OUTPUT_FILE   "conv_c_output.hex"

static uint32_t float_as_u32(float value)
{
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}

static float u32_as_float(uint32_t bits)
{
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static float fp16_to_float(uint16_t x)
{
    const uint32_t e = (x&0x7C00)>>10;
    const uint32_t m = (x&0x03FF)<<13;
    const uint32_t v = float_as_u32((float)m)>>23;
    return u32_as_float((x&0x8000)<<16 | (e!=0)*((e+112)<<23|m) | ((e==0)&(m!=0))*((v-37)<<23|((m<<(150-v))&0x007FE000)));
}

static uint16_t float_to_fp16(float x)
{
    const uint32_t b = float_as_u32(x)+0x00001000;
    const uint32_t e = (b&0x7F800000)>>23;
    const uint32_t m = b&0x007FFFFF;
    return (b&0x80000000)>>16 | (e>112)*((((e-112)<<10)&0x7C00)|m>>13) | ((e<113)&(e>101))*((((0x007FF000+m)>>(125-e))+1)>>1) | (e>143)*0x7FFF;
}

static int read_fp16_hex(const char *path, uint16_t *data, size_t expected_count)
{
    FILE *file = fopen(path, "r");
    size_t index;

    if (file == NULL) {
        fprintf(stderr, "ERROR: cannot open '%s': %s\n", path, strerror(errno));
        return 0;
    }

    for (index = 0; index < expected_count; index++) {
        unsigned int word;
        if (fscanf(file, "%x", &word) != 1) {
            fprintf(stderr,
                    "ERROR: '%s' contains only %zu valid FP16 words; expected %zu\n",
                    path, index, expected_count);
            fclose(file);
            return 0;
        }
        if (word > UINT16_MAX) {
            fprintf(stderr,
                    "ERROR: value 0x%x at index %zu in '%s' exceeds 16 bits\n",
                    word, index, path);
            fclose(file);
            return 0;
        }
        data[index] = (uint16_t)word;
    }

    {
        unsigned int extra_word;
        if (fscanf(file, "%x", &extra_word) == 1) {
            fprintf(stderr,
                    "ERROR: '%s' contains more than the expected %zu FP16 words\n",
                    path, expected_count);
            fclose(file);
            return 0;
        }
    }

    fclose(file);
    return 1;
}

static int write_fp16_hex(const char *path, const uint16_t *data, size_t rows, size_t cols)
{
    FILE *file = fopen(path, "w");
    size_t row;
    size_t col;

    if (file == NULL) {
        fprintf(stderr, "ERROR: cannot create '%s': %s\n", path, strerror(errno));
        return 0;
    }

    for (row = 0; row < rows; row++) {
        for (col = 0; col < cols; col++) {
            const size_t index = row * cols + col;
            fprintf(file, "%04" PRIx16, data[index]);
            fputc((col + 1 == cols) ? '\n' : ' ', file);
        }
    }

    if (fclose(file) != 0) {
        fprintf(stderr, "ERROR: failed to close '%s' after writing\n", path);
        return 0;
    }

    return 1;
}

static void convolution_float32(const float *input, const float *kernel, float *output)
{
    size_t output_row;
    size_t output_col;

    for (output_row = 0; output_row < OUTPUT_ROWS; output_row++) {
        for (output_col = 0; output_col < OUTPUT_COLS; output_col++) {
            float sum = 0.0f;
            size_t kernel_row;
            size_t kernel_col;

            for (kernel_row = 0; kernel_row < KERNEL_ROWS; kernel_row++) {
                for (kernel_col = 0; kernel_col < KERNEL_COLS; kernel_col++) {
                    const size_t input_index =
                        (output_row + kernel_row) * INPUT_COLS +
                        (output_col + kernel_col);
                    const size_t kernel_index =
                        kernel_row * KERNEL_COLS + kernel_col;
                    const float product = input[input_index] * kernel[kernel_index];
                    sum = sum + product;
                }
            }

            output[output_row * OUTPUT_COLS + output_col] = sum;
        }
    }
}

static size_t compare_outputs(const uint16_t *reference,
                              const uint16_t *rtl,
                              double *maximum_absolute_error,
                              size_t *worst_output_index)
{
    size_t index;
    size_t different_count = 0;
    size_t worst_index = 0;
    double largest_absolute_error = 0.0;

    for (index = 0; index < OUTPUT_COUNT; index++) {
        const float reference_float = fp16_to_float(reference[index]);
        const float rtl_float = fp16_to_float(rtl[index]);
        const double absolute_error =
            fabs((double)reference_float - (double)rtl_float);

        if (reference_float != rtl_float) {
            different_count++;
        }

        if (absolute_error > largest_absolute_error) {
            largest_absolute_error = absolute_error;
            worst_index = index;
        }
    }

    *maximum_absolute_error = largest_absolute_error;
    *worst_output_index = worst_index;
    return different_count;
}

int main(void)
{
    uint16_t input_fp16[INPUT_COUNT];
    uint16_t kernel_fp16[KERNEL_COUNT];
    uint16_t rtl_output_fp16[OUTPUT_COUNT];
    uint16_t c_output_fp16[OUTPUT_COUNT];
    float input_float[INPUT_COUNT];
    float kernel_float[KERNEL_COUNT];
    float c_output_float[OUTPUT_COUNT];
    size_t index;
    size_t different_count;
    size_t worst_output_index;
    double maximum_absolute_error;

    if (!read_fp16_hex(DEFAULT_INPUT_FILE, input_fp16, INPUT_COUNT) ||
        !read_fp16_hex(DEFAULT_KERNEL_FILE, kernel_fp16, KERNEL_COUNT) ||
        !read_fp16_hex(DEFAULT_RTL_OUTPUT_FILE,
                       rtl_output_fp16,
                       OUTPUT_COUNT)) {
        return EXIT_FAILURE;
    }

    for (index = 0; index < INPUT_COUNT; index++) {
        input_float[index] = fp16_to_float(input_fp16[index]);
    }
    for (index = 0; index < KERNEL_COUNT; index++) {
        kernel_float[index] = fp16_to_float(kernel_fp16[index]);
    }

    convolution_float32(input_float, kernel_float, c_output_float);

    for (index = 0; index < OUTPUT_COUNT; index++) {
        c_output_fp16[index] = float_to_fp16(c_output_float[index]);
    }

    if (!write_fp16_hex(DEFAULT_C_OUTPUT_FILE,
                        c_output_fp16,
                        OUTPUT_ROWS,
                        OUTPUT_COLS)) {
        return EXIT_FAILURE;
    }

    different_count = compare_outputs(c_output_fp16,
                                      rtl_output_fp16,
                                      &maximum_absolute_error,
                                      &worst_output_index);

    printf("Input       : %s (%dx%d, %zu FP16 values)\n",
           DEFAULT_INPUT_FILE, INPUT_ROWS, INPUT_COLS, INPUT_COUNT);
    printf("Kernel      : %s (%dx%d, %zu FP16 values)\n",
           DEFAULT_KERNEL_FILE, KERNEL_ROWS, KERNEL_COLS, KERNEL_COUNT);
    printf("RTL output  : %s (%dx%d, %zu FP16 values)\n",
           DEFAULT_RTL_OUTPUT_FILE,
           OUTPUT_ROWS,
           OUTPUT_COLS,
           OUTPUT_COUNT);
    printf("C output    : %s\n", DEFAULT_C_OUTPUT_FILE);
    printf("Different pairs   : %zu/%zu\n",
           different_count, OUTPUT_COUNT);
    printf("Largest real error: %.9g\n", maximum_absolute_error);
    printf("Largest-error pair: address=%zu row=%zu col=%zu "
           "c_value=%.9g rtl_value=%.9g\n",
           worst_output_index,
           worst_output_index / OUTPUT_COLS,
           worst_output_index % OUTPUT_COLS,
           (double)fp16_to_float(c_output_fp16[worst_output_index]),
           (double)fp16_to_float(rtl_output_fp16[worst_output_index]));
    return EXIT_SUCCESS;
}
