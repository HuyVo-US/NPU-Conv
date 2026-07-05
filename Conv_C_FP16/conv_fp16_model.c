#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define INPUT_ROWS 28
#define INPUT_COLS 28
#define KERNEL_ROWS 3
#define KERNEL_COLS 3
#define OUTPUT_ROWS (INPUT_ROWS - KERNEL_ROWS + 1)
#define OUTPUT_COLS (INPUT_COLS - KERNEL_COLS + 1)
#define ULP_TOLERANCE 4
#define MAX_PRINTED_MISMATCHES 20

typedef uint16_t fp16_t;
typedef uint32_t uint;

static uint as_uint(const float x)
{
    union {
        float f;
        uint u;
    } value;

    value.f = x;
    return value.u;
}

static float as_float(const uint x)
{
    union {
        uint u;
        float f;
    } value;

    value.u = x;
    return value.f;
}

static float half_to_float(const fp16_t x)
{
    const uint e = (x & 0x7c00u) >> 10;
    const uint m = (x & 0x03ffu) << 13;
    const uint v = as_uint((float)m) >> 23;

    return as_float((x & 0x8000u) << 16 |
                    (e != 0) * ((e + 112) << 23 | m) |
                    ((e == 0) & (m != 0)) * ((v - 37) << 23 |
                    ((m << (150 - v)) & 0x007fe000u)));
}

static fp16_t float_to_half(const float x)
{
    const uint b = as_uint(x) + 0x00001000u;
    const uint e = (b & 0x7f800000u) >> 23;
    const uint m = b & 0x007fffffu;

    return (fp16_t)(((b & 0x80000000u) >> 16) |
                    (e > 112) * ((((e - 112) << 10) & 0x7c00u) | (m >> 13)) |
                    ((e < 113) & (e > 101)) *
                    ((((0x007ff000u + m) >> (125 - e)) + 1) >> 1) |
                    (e > 143) * 0x7fffu);
}

static fp16_t fp16_add(fp16_t a, fp16_t b)
{
    float result = half_to_float(a) + half_to_float(b);
    return float_to_half(result);
}

static fp16_t fp16_mul(fp16_t a, fp16_t b)
{
    float result = half_to_float(a) * half_to_float(b);
    return float_to_half(result);
}

static float abs_float(float value)
{
    return value < 0.0f ? -value : value;
}

static int abs_int(int value)
{
    return value < 0 ? -value : value;
}

static int fp16_ordered_key(fp16_t value)
{
    if ((value & 0x8000u) != 0) {
        return 0x8000 - (int)(value & 0x7fffu);
    }

    return 0x8000 + (int)(value & 0x7fffu);
}

static int fp16_ulp_diff(fp16_t a, fp16_t b)
{
    return abs_int(fp16_ordered_key(a) - fp16_ordered_key(b));
}

static int read_hex_matrix(const char *filename, fp16_t *matrix, int rows, int cols)
{
    FILE *file;
    unsigned value;
    int index;

    file = fopen(filename, "r");
    if (file == NULL) {
        fprintf(stderr, "ERROR: cannot open %s\n", filename);
        return 1;
    }

    for (index = 0; index < rows * cols; index++) {
        if (fscanf(file, "%x", &value) != 1) {
            fprintf(stderr, "ERROR: failed to read %s at element %d\n", filename, index);
            fclose(file);
            return 1;
        }
        matrix[index] = (fp16_t)(value & 0xffffu);
    }

    fclose(file);
    return 0;
}

static int write_hex_matrix(const char *filename, const fp16_t *matrix, int rows, int cols)
{
    FILE *file;
    int row;
    int col;

    file = fopen(filename, "w");
    if (file == NULL) {
        fprintf(stderr, "ERROR: cannot open %s for write\n", filename);
        return 1;
    }

    for (row = 0; row < rows; row++) {
        for (col = 0; col < cols; col++) {
            fprintf(file, "%04x%s", matrix[row * cols + col],
                    (col == cols - 1) ? "\n" : " ");
        }
    }

    fclose(file);
    return 0;
}

static void conv2d_fp16_model(const fp16_t *input, const fp16_t *kernel, fp16_t *output)
{
    int out_row;
    int out_col;
    int kernel_row;
    int kernel_col;
    int input_index;
    int kernel_index;
    int output_index;
    fp16_t product;
    fp16_t sum;

    for (out_row = 0; out_row < OUTPUT_ROWS; out_row++) {
        for (out_col = 0; out_col < OUTPUT_COLS; out_col++) {
            sum = 0;

            for (kernel_row = 0; kernel_row < KERNEL_ROWS; kernel_row++) {
                for (kernel_col = 0; kernel_col < KERNEL_COLS; kernel_col++) {
                    input_index = (out_row + kernel_row) * INPUT_COLS + (out_col + kernel_col);
                    kernel_index = kernel_row * KERNEL_COLS + kernel_col;
                    product = fp16_mul(input[input_index], kernel[kernel_index]);
                    sum = fp16_add(sum, product);
                }
            }

            output_index = out_row * OUTPUT_COLS + out_col;
            output[output_index] = sum;
        }
    }
}

static int compare_output(const fp16_t *model_output, const fp16_t *rtl_output)
{
    int row;
    int col;
    int index;
    int ulp_diff;
    int exact_matches = 0;
    int mismatches = 0;
    int ulp_1 = 0;
    int ulp_2 = 0;
    int ulp_3_to_tolerance = 0;
    int over_tolerance = 0;
    int max_ulp_diff = 0;
    int max_ulp_row = 0;
    int max_ulp_col = 0;
    int max_ulp_index = 0;
    float model_value;
    float rtl_value;
    float abs_diff;
    float rel_diff;
    float rel_denominator;
    float max_abs_diff = 0.0f;
    float max_rel_diff = 0.0f;
    int max_abs_row = 0;
    int max_abs_col = 0;
    int max_rel_row = 0;
    int max_rel_col = 0;

    for (row = 0; row < OUTPUT_ROWS; row++) {
        for (col = 0; col < OUTPUT_COLS; col++) {
            index = row * OUTPUT_COLS + col;
            ulp_diff = fp16_ulp_diff(model_output[index], rtl_output[index]);
            model_value = half_to_float(model_output[index]);
            rtl_value = half_to_float(rtl_output[index]);
            abs_diff = abs_float(model_value - rtl_value);
            rel_denominator = abs_float(rtl_value);
            if (rel_denominator < 1.0e-12f) {
                rel_denominator = 1.0f;
            }
            rel_diff = abs_diff / rel_denominator;

            if (ulp_diff > max_ulp_diff) {
                max_ulp_diff = ulp_diff;
                max_ulp_row = row;
                max_ulp_col = col;
                max_ulp_index = index;
            }

            if (abs_diff > max_abs_diff) {
                max_abs_diff = abs_diff;
                max_abs_row = row;
                max_abs_col = col;
            }

            if (rel_diff > max_rel_diff) {
                max_rel_diff = rel_diff;
                max_rel_row = row;
                max_rel_col = col;
            }

            if (ulp_diff == 0) {
                exact_matches++;
            }
            else {
                if (mismatches < MAX_PRINTED_MISMATCHES) {
                    printf("Mismatch [%d][%d] index=%d model=%04x rtl=%04x ulp=%d model_f=%f rtl_f=%f abs_diff=%f\n",
                           row, col, index, model_output[index], rtl_output[index],
                           ulp_diff, model_value, rtl_value, abs_diff);
                }

                mismatches++;
                if (ulp_diff == 1) {
                    ulp_1++;
                }
                else if (ulp_diff == 2) {
                    ulp_2++;
                }
                else if (ulp_diff <= ULP_TOLERANCE) {
                    ulp_3_to_tolerance++;
                }
                else {
                    over_tolerance++;
                }
            }
        }
    }

    if (mismatches > MAX_PRINTED_MISMATCHES) {
        printf("... %d additional mismatches not printed\n",
               mismatches - MAX_PRINTED_MISMATCHES);
    }

    printf("\nCompare detail:\n");
    printf("  total elements          : %d\n", OUTPUT_ROWS * OUTPUT_COLS);
    printf("  exact matches           : %d\n", exact_matches);
    printf("  exact mismatches        : %d\n", mismatches);
    printf("  mismatches with ULP = 1 : %d\n", ulp_1);
    printf("  mismatches with ULP = 2 : %d\n", ulp_2);
    printf("  mismatches with ULP 3-%d: %d\n", ULP_TOLERANCE, ulp_3_to_tolerance);
    printf("  over tolerance          : %d (tolerance <= %d ULP)\n", over_tolerance, ULP_TOLERANCE);
    printf("  max ULP diff            : %d at [%d][%d] index=%d\n",
           max_ulp_diff, max_ulp_row, max_ulp_col, max_ulp_index);
    printf("  max abs float diff      : %f at [%d][%d]\n",
           max_abs_diff, max_abs_row, max_abs_col);
    printf("  max relative float diff : %f at [%d][%d]\n",
           max_rel_diff, max_rel_row, max_rel_col);

    return over_tolerance;
}

int main(int argc, char **argv)
{
    const char *input_path = "input.hex";
    const char *kernel_path = "kernel.hex";
    const char *rtl_output_path = "output.hex";
    const char *model_output_path = "output_c_model.hex";
    fp16_t input[INPUT_ROWS * INPUT_COLS];
    fp16_t kernel[KERNEL_ROWS * KERNEL_COLS];
    fp16_t model_output[OUTPUT_ROWS * OUTPUT_COLS];
    fp16_t rtl_output[OUTPUT_ROWS * OUTPUT_COLS];
    int compare_failures;

    if (argc > 1) {
        input_path = argv[1];
    }
    if (argc > 2) {
        kernel_path = argv[2];
    }
    if (argc > 3) {
        rtl_output_path = argv[3];
    }
    if (argc > 4) {
        model_output_path = argv[4];
    }

    if (read_hex_matrix(input_path, input, INPUT_ROWS, INPUT_COLS) != 0) {
        return 1;
    }
    if (read_hex_matrix(kernel_path, kernel, KERNEL_ROWS, KERNEL_COLS) != 0) {
        return 1;
    }
    if (read_hex_matrix(rtl_output_path, rtl_output, OUTPUT_ROWS, OUTPUT_COLS) != 0) {
        return 1;
    }

    conv2d_fp16_model(input, kernel, model_output);

    if (write_hex_matrix(model_output_path, model_output, OUTPUT_ROWS, OUTPUT_COLS) != 0) {
        return 1;
    }

    compare_failures = compare_output(model_output, rtl_output);

    printf("Input:        %s (%dx%d FP16)\n", input_path, INPUT_ROWS, INPUT_COLS);
    printf("Kernel:       %s (%dx%d FP16)\n", kernel_path, KERNEL_ROWS, KERNEL_COLS);
    printf("RTL output:   %s (%dx%d FP16)\n", rtl_output_path, OUTPUT_ROWS, OUTPUT_COLS);
    printf("Model output: %s\n", model_output_path);
    printf("Compare:      failures_over_tolerance=%d total=%d tolerance=%d ULP\n",
           compare_failures, OUTPUT_ROWS * OUTPUT_COLS, ULP_TOLERANCE);

    if (compare_failures == 0) {
        printf("PASS: C FP16 logic model matches RTL output within tolerance.\n");
        return 0;
    }

    printf("FAIL: C FP16 logic model differs from RTL output beyond tolerance.\n");
    return 2;
}
