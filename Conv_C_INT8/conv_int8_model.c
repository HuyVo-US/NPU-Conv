#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define INPUT_ROWS 28
#define INPUT_COLS 28
#define KERNEL_ROWS 3
#define KERNEL_COLS 3
#define OUTPUT_ROWS (INPUT_ROWS - KERNEL_ROWS + 1)
#define OUTPUT_COLS (INPUT_COLS - KERNEL_COLS + 1)
#define MAX_PRINTED_MISMATCHES 20

static int64_t abs_int64(int64_t value)
{
    return value < 0 ? -value : value;
}

static int read_int8_hex_matrix(const char *filename, int8_t *matrix, int rows, int cols)
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
        if (value > 0xffu) {
            fprintf(stderr,
                    "ERROR: %s element %d is 0x%x, expected an 8-bit INT8 hex value (00-ff)\n",
                    filename, index, value);
            fclose(file);
            return 1;
        }
        matrix[index] = (int8_t)(uint8_t)value;
    }

    fclose(file);
    return 0;
}

static int read_int32_hex_matrix(const char *filename, int32_t *matrix, int rows, int cols)
{
    FILE *file;
    uint32_t value;
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
        matrix[index] = (int32_t)value;
    }

    fclose(file);
    return 0;
}

static int write_int32_hex_matrix(const char *filename, const int32_t *matrix, int rows, int cols)
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
            fprintf(file, "%08x%s", (unsigned)(uint32_t)matrix[row * cols + col],
                    (col == cols - 1) ? "\n" : " ");
        }
    }

    fclose(file);
    return 0;
}

static void conv2d_int8_model(const int8_t *input,
                              const int8_t *kernel,
                              int32_t *output)
{
    int out_row;
    int out_col;
    int kernel_row;
    int kernel_col;
    int input_index;
    int kernel_index;
    int output_index;
    int32_t sum;

    for (out_row = 0; out_row < OUTPUT_ROWS; out_row++) {
        for (out_col = 0; out_col < OUTPUT_COLS; out_col++) {
            sum = 0;

            for (kernel_row = 0; kernel_row < KERNEL_ROWS; kernel_row++) {
                for (kernel_col = 0; kernel_col < KERNEL_COLS; kernel_col++) {
                    input_index = (out_row + kernel_row) * INPUT_COLS + (out_col + kernel_col);
                    kernel_index = kernel_row * KERNEL_COLS + kernel_col;
                    sum += (int32_t)input[input_index] * (int32_t)kernel[kernel_index];
                }
            }

            output_index = out_row * OUTPUT_COLS + out_col;
            output[output_index] = sum;
        }
    }
}

static int compare_output(const int32_t *model_output, const int32_t *rtl_output)
{
    int row;
    int col;
    int index;
    int exact_matches = 0;
    int mismatches = 0;
    int64_t signed_diff;
    int64_t abs_diff;
    int64_t max_abs_diff = 0;
    int max_abs_row = 0;
    int max_abs_col = 0;
    int max_abs_index = 0;

    for (row = 0; row < OUTPUT_ROWS; row++) {
        for (col = 0; col < OUTPUT_COLS; col++) {
            index = row * OUTPUT_COLS + col;
            signed_diff = (int64_t)model_output[index] - (int64_t)rtl_output[index];
            abs_diff = abs_int64(signed_diff);

            if (abs_diff > max_abs_diff) {
                max_abs_diff = abs_diff;
                max_abs_row = row;
                max_abs_col = col;
                max_abs_index = index;
            }

            if (model_output[index] == rtl_output[index]) {
                exact_matches++;
            }
            else {
                if (mismatches < MAX_PRINTED_MISMATCHES) {
                    printf("Mismatch [%d][%d] index=%d model=%08x(%d) rtl=%08x(%d) abs_diff=%lld\n",
                           row,
                           col,
                           index,
                           (unsigned)(uint32_t)model_output[index],
                           model_output[index],
                           (unsigned)(uint32_t)rtl_output[index],
                           rtl_output[index],
                           (long long)abs_diff);
                }
                mismatches++;
            }
        }
    }

    if (mismatches > MAX_PRINTED_MISMATCHES) {
        printf("... %d additional mismatches not printed\n",
               mismatches - MAX_PRINTED_MISMATCHES);
    }

    printf("\nCompare detail:\n");
    printf("  total elements     : %d\n", OUTPUT_ROWS * OUTPUT_COLS);
    printf("  exact matches      : %d\n", exact_matches);
    printf("  exact mismatches   : %d\n", mismatches);
    printf("  max signed abs diff: %lld at [%d][%d] index=%d\n",
           (long long)max_abs_diff, max_abs_row, max_abs_col, max_abs_index);

    return mismatches;
}

int main(int argc, char **argv)
{
    const char *input_path = "input.hex";
    const char *kernel_path = "kernel.hex";
    const char *rtl_output_path = "output.hex";
    const char *model_output_path = "output_c_model.hex";
    int8_t input[INPUT_ROWS * INPUT_COLS];
    int8_t kernel[KERNEL_ROWS * KERNEL_COLS];
    int32_t model_output[OUTPUT_ROWS * OUTPUT_COLS];
    int32_t rtl_output[OUTPUT_ROWS * OUTPUT_COLS];
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

    if (read_int8_hex_matrix(input_path, input, INPUT_ROWS, INPUT_COLS) != 0) {
        return 1;
    }
    if (read_int8_hex_matrix(kernel_path, kernel, KERNEL_ROWS, KERNEL_COLS) != 0) {
        return 1;
    }
    if (read_int32_hex_matrix(rtl_output_path, rtl_output, OUTPUT_ROWS, OUTPUT_COLS) != 0) {
        return 1;
    }

    conv2d_int8_model(input, kernel, model_output);

    if (write_int32_hex_matrix(model_output_path, model_output, OUTPUT_ROWS, OUTPUT_COLS) != 0) {
        return 1;
    }

    compare_failures = compare_output(model_output, rtl_output);

    printf("Input:        %s (%dx%d INT8)\n", input_path, INPUT_ROWS, INPUT_COLS);
    printf("Kernel:       %s (%dx%d INT8)\n", kernel_path, KERNEL_ROWS, KERNEL_COLS);
    printf("RTL output:   %s (%dx%d INT32)\n", rtl_output_path, OUTPUT_ROWS, OUTPUT_COLS);
    printf("Model output: %s\n", model_output_path);
    printf("Compare:      exact_mismatches=%d total=%d\n",
           compare_failures, OUTPUT_ROWS * OUTPUT_COLS);

    if (compare_failures == 0) {
        printf("PASS: C INT8-input/INT32-output logic model matches RTL output exactly.\n");
        return 0;
    }

    printf("FAIL: C INT8-input/INT32-output logic model differs from RTL output.\n");
    return 2;
}
