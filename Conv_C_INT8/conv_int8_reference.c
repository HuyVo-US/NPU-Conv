#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int8_t q7_t;
typedef int32_t q31_t;

#define SATURATE_Q7(x) ((x) < -128 ? -128 : ((x) > 127 ? 127 : (x)))

#define INPUT_ROWS       28
#define INPUT_COLS       28
#define KERNEL_ROWS       3
#define KERNEL_COLS       3
#define STRIDE             1
#define PADDING            0
#define INPUT_CHANNELS     1
#define OUTPUT_CHANNELS    1

#define OUTPUT_ROWS \
    (((INPUT_ROWS + 2 * PADDING - KERNEL_ROWS) / STRIDE) + 1)
#define OUTPUT_COLS \
    (((INPUT_COLS + 2 * PADDING - KERNEL_COLS) / STRIDE) + 1)

#define INPUT_COUNT \
    ((size_t)INPUT_ROWS * (size_t)INPUT_COLS * INPUT_CHANNELS)
#define KERNEL_COUNT \
    ((size_t)OUTPUT_CHANNELS * INPUT_CHANNELS * \
     KERNEL_ROWS * KERNEL_COLS)
#define OUTPUT_COUNT \
    ((size_t)OUTPUT_ROWS * (size_t)OUTPUT_COLS * OUTPUT_CHANNELS)

#define INPUT_FILE            "conv_input.hex"
#define KERNEL_FILE           "conv_kernel.hex"
#define RTL_OUTPUT_FILE       "conv_rtl_output.hex"
#define EXPECTED_OUTPUT_FILE  "conv_expected_output.hex"
#define MAX_MISMATCH_REPORTS  20

static int8_t int8_from_bits(uint8_t bits)
{
    int8_t value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static uint8_t int8_to_bits(int8_t value)
{
    uint8_t bits;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}

static int read_int8_hex(const char *path,
                         int8_t *data,
                         size_t expected_count)
{
    FILE *file = fopen(path, "r");
    size_t index;

    if (file == NULL) {
        fprintf(stderr, "ERROR: cannot open '%s': %s\n",
                path, strerror(errno));
        return 0;
    }

    for (index = 0; index < expected_count; index++) {
        unsigned int word;

        if (fscanf(file, "%x", &word) != 1) {
            fprintf(stderr,
                    "ERROR: '%s' contains only %zu values; expected %zu\n",
                    path, index, expected_count);
            fclose(file);
            return 0;
        }
        if (word > UINT8_MAX) {
            fprintf(stderr,
                    "ERROR: value 0x%x at index %zu in '%s' exceeds 8 bits\n",
                    word, index, path);
            fclose(file);
            return 0;
        }

        data[index] = int8_from_bits((uint8_t)word);
    }

    {
        unsigned int extra_word;
        if (fscanf(file, "%x", &extra_word) == 1) {
            fprintf(stderr,
                    "ERROR: '%s' contains more than %zu values\n",
                    path, expected_count);
            fclose(file);
            return 0;
        }
    }

    fclose(file);
    return 1;
}

static int write_int8_hex(const char *path,
                          const int8_t *data,
                          size_t rows,
                          size_t cols)
{
    FILE *file = fopen(path, "w");
    size_t row;
    size_t col;

    if (file == NULL) {
        fprintf(stderr, "ERROR: cannot create '%s': %s\n",
                path, strerror(errno));
        return 0;
    }

    for (row = 0; row < rows; row++) {
        for (col = 0; col < cols; col++) {
            const size_t index = row * cols + col;
            fprintf(file, "%02" PRIx8,
                    (unsigned int)int8_to_bits(data[index]));
            fputc((col + 1 == cols) ? '\n' : ' ', file);
        }
    }

    if (fclose(file) != 0) {
        fprintf(stderr, "ERROR: failed to close '%s'\n", path);
        return 0;
    }

    return 1;
}

static inline q7_t requantize_q7_with_multiplier_shift(q31_t acc, int32_t multiplier, int32_t shift)
{
    if (multiplier == 0) {
        return 0;
    }

    double scaled = (double)acc * (double)multiplier / (double)(1ll << 31);
    if (shift < 0) {
        scaled *= (double)(1ll << (-shift));
    } else if (shift > 0) {
        scaled /= (double)(1ll << shift);
    }

    const int32_t rounded = (int32_t)lrint(scaled);
    return (q7_t)SATURATE_Q7(rounded);
}

static size_t compare_int8_outputs(const int8_t *expected,
                                   const int8_t *rtl,
                                   size_t count)
{
    size_t index;
    size_t mismatch_count = 0;

    for (index = 0; index < count; index++) {
        if (expected[index] != rtl[index]) {
            if (mismatch_count < MAX_MISMATCH_REPORTS) {
                const size_t row = index / OUTPUT_COLS;
                const size_t col = index % OUTPUT_COLS;

                printf("MISMATCH [%zu][%zu] index=%zu: "
                       "expected=%02" PRIx8 " (%" PRId8 "), "
                       "rtl=%02" PRIx8 " (%" PRId8 ")\n",
                       row, col, index,
                       (unsigned int)int8_to_bits(expected[index]),
                       expected[index],
                       (unsigned int)int8_to_bits(rtl[index]),
                       rtl[index]);
            }
            mismatch_count++;
        }
    }

    return mismatch_count;
}

void conv2d_q7(q7_t *input, q7_t *output, q7_t *kernel, q31_t *bias,
               int H, int W, int Cin, int Cout, int K, int stride, int padding,
               const int32_t *out_multiplier, const int32_t *out_shift)
{
    int pad = padding ? K / 2 : 0;
    int Hout = (H + 2*pad - K)/stride + 1;
    int Wout = (W + 2*pad - K)/stride + 1;
    for (int oc = 0; oc < Cout; oc++) {
        for (int h = 0; h < Hout; h++) {
            for (int w = 0; w < Wout; w++) {

                q31_t sum = bias[oc];

                for (int ic = 0; ic < Cin; ic++) {
                    for (int kh = 0; kh < K; kh++) {
                        for (int kw = 0; kw < K; kw++) {

                            int ih = h * stride + kh - pad;
                            int iw = w * stride + kw - pad;

                            if (ih >= 0 && ih < H && iw >= 0 && iw < W) {
                                int in_idx  = (ih*W + iw)*Cin + ic;
                                int k_idx   = ((oc*Cin + ic)*K + kh)*K + kw;
                                sum += (q31_t)input[in_idx] * (q31_t)kernel[k_idx];
                            }
                        }
                    }
                }

                int out_idx = (h*Wout + w)*Cout + oc;
                output[out_idx] = requantize_q7_with_multiplier_shift(sum, out_multiplier[oc], out_shift[oc]);
            }
        }
    }
}

int main(void)
{
    q7_t input[INPUT_COUNT];
    q7_t kernel[KERNEL_COUNT];
    q7_t expected_output[OUTPUT_COUNT];
    q7_t rtl_output[OUTPUT_COUNT];
    q31_t bias[OUTPUT_CHANNELS] = { 37 };
    size_t mismatch_count;

    const q31_t output_multiplier[OUTPUT_CHANNELS] = { 0x02000000 };
    const q31_t output_shift[OUTPUT_CHANNELS] = { 2 };

    if (!read_int8_hex(INPUT_FILE, input, INPUT_COUNT) ||
        !read_int8_hex(KERNEL_FILE, kernel, KERNEL_COUNT) ||
        !read_int8_hex(RTL_OUTPUT_FILE, rtl_output, OUTPUT_COUNT)) {
        return EXIT_FAILURE;
    }

    conv2d_q7(input, expected_output, kernel, bias,
              INPUT_ROWS, INPUT_COLS,
              INPUT_CHANNELS, OUTPUT_CHANNELS,
              KERNEL_ROWS, STRIDE, PADDING,
              output_multiplier, output_shift);

    if (!write_int8_hex(EXPECTED_OUTPUT_FILE, expected_output,
                        OUTPUT_ROWS, OUTPUT_COLS)) {
        return EXIT_FAILURE;
    }

    mismatch_count = compare_int8_outputs(expected_output, rtl_output,
                                          OUTPUT_COUNT);

    printf("INT8 convolution completed\n");
    printf("Input      : %s (%dx%d INT8)\n",
           INPUT_FILE, INPUT_ROWS, INPUT_COLS);
    printf("Kernel     : %s (%dx%d INT8)\n",
           KERNEL_FILE, KERNEL_ROWS, KERNEL_COLS);
    printf("RTL output : %s (%dx%d INT8)\n",
           RTL_OUTPUT_FILE, OUTPUT_ROWS, OUTPUT_COLS);
    printf("Bias       : %" PRId32 "\n", bias[0]);
    printf("Multiplier : %" PRId32 "\n", output_multiplier[0]);
    printf("Shift      : %" PRId32 "\n", output_shift[0]);
    printf("Expected   : %s (%dx%d INT8)\n",
           EXPECTED_OUTPUT_FILE, OUTPUT_ROWS, OUTPUT_COLS);

    if (mismatch_count == 0) {
        printf("Comparison : MATCH (all %zu outputs are identical)\n",
               (size_t)OUTPUT_COUNT);
        return EXIT_SUCCESS;
    }

    printf("Comparison : MISMATCH (%zu of %zu outputs differ)\n",
           mismatch_count, (size_t)OUTPUT_COUNT);
    if (mismatch_count > MAX_MISMATCH_REPORTS) {
        printf("Only the first %d mismatches are shown\n",
               MAX_MISMATCH_REPORTS);
    }
    return EXIT_FAILURE;
}
