module matrix_conv(
    input clk,
    input reset,
    input start,
    output reg done,
    input wire [13:0] src1_start_address,
    input wire [13:0] src2_start_address,
    output reg [13:0] src1_address,
    input wire signed [7:0] src1_readdata,
    output wire signed [7:0] src1_writedata,
    output wire src1_write_en,
    output reg [13:0] src2_address,
    input wire signed [7:0] src2_readdata,
    output wire signed [7:0] src2_writedata,
    output wire src2_write_en,
    input wire [9:0] src1_row_size, // input matrix
    input wire [9:0] src1_col_size,
    input wire [5:0] src2_row_size, // kernel
    input wire [5:0] src2_col_size,
    input wire [13:0] dest_start_address,
    output reg [13:0] dest_address,
    input wire signed [31:0] dest_readdata,
    output wire signed [31:0] dest_writedata,
    output reg dest_write_en
);
    localparam KERNEL_ROWS = 3;
    localparam KERNEL_COLS = 3;

    localparam IDLE = 3'd0,
               READ_KERNEL = 3'd1,
               CALC = 3'd2,
               SLIDE = 3'd3,
               WRITE = 3'd4,
               DONE = 3'd5;

    reg [9:0] kernel_row_index;
    reg [9:0] kernel_col_index;
    reg [9:0] output_row_index;
    reg [9:0] output_col_index;

    reg [3:0] kernel_load_row;
    reg [3:0] kernel_load_col;

    reg signed [7:0] kernel [0:KERNEL_ROWS-1][0:KERNEL_COLS-1];
    reg [13:0] window_base_address;

    reg [2:0] state, next_state;

    reg signed [31:0] sum;
    wire signed [15:0] product;
    wire signed [31:0] sum_plus_product;

    assign src1_write_en = 0;
    assign src2_write_en = 0;
    assign src1_writedata = 8'sd0;
    assign src2_writedata = 8'sd0;

    assign dest_writedata = sum;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            state <= IDLE;
        end
        else begin
            state <= next_state;
        end
    end

    always @(*) begin
        case (state)
            IDLE: begin
                done = 1;
                if (start) begin
                    next_state = READ_KERNEL;
                end
                else begin
                    next_state = IDLE;
                end
            end

            READ_KERNEL: begin
                done = 0;
                if ((kernel_load_row == KERNEL_ROWS - 1) &&
                    (kernel_load_col == KERNEL_COLS - 1)) begin
                    next_state = CALC;
                end
                else begin
                    next_state = READ_KERNEL;
                end
            end

            CALC: begin
                done = 0;
                if ((kernel_row_index == KERNEL_ROWS - 1) &&
                    (kernel_col_index == KERNEL_COLS - 1)) begin
                    next_state = WRITE;
                end
                else begin
                    next_state = CALC;
                end
            end

            SLIDE: begin
                done = 0;
                next_state = CALC;
            end

            WRITE: begin
                done = 0;
                if ((output_row_index == src1_row_size - KERNEL_ROWS) &&
                    (output_col_index == src1_col_size - KERNEL_COLS)) begin
                    next_state = DONE;
                end
                else begin
                    next_state = SLIDE;
                end
            end

            DONE: begin
                next_state = IDLE;
                done = 1;
            end

            default: begin
                next_state = IDLE;
                done = 1;
            end
        endcase
    end

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                dest_write_en <= 0;
                kernel_row_index <= 0;
                kernel_col_index <= 0;
                output_row_index <= 0;
                output_col_index <= 0;
                kernel_load_row <= 0;
                kernel_load_col <= 0;
                sum <= 0;
                src1_address <= src1_start_address;
                src2_address <= src2_start_address;
                dest_address <= dest_start_address;
                window_base_address <= src1_start_address;
            end

            READ_KERNEL: begin
                src2_address <= src2_address + 1;
                kernel[kernel_load_row][kernel_load_col] <= src2_readdata;

                if (kernel_load_col == KERNEL_COLS - 1) begin
                    kernel_load_col <= 0;
                    kernel_load_row <= kernel_load_row + 1;
                end
                else begin
                    kernel_load_col <= kernel_load_col + 1;
                end
            end

            CALC: begin
                sum <= sum_plus_product;

                if (kernel_col_index == KERNEL_COLS - 1) begin
                    kernel_col_index <= 0;

                    if (kernel_row_index == KERNEL_ROWS - 1) begin
                        dest_write_en <= 1;
                        kernel_row_index <= 0;
                    end
                    else begin
                        dest_write_en <= 0;
                        src1_address <= src1_address + src1_col_size - kernel_col_index;
                        kernel_row_index <= kernel_row_index + 1;
                    end
                end
                else begin
                    dest_write_en <= 0;
                    src1_address <= src1_address + 1;
                    kernel_col_index <= kernel_col_index + 1;
                end
            end

            SLIDE: begin
                if (output_col_index == src1_col_size - KERNEL_COLS) begin
                    output_col_index <= 0;
                    output_row_index <= output_row_index + 1;
                    window_base_address <= window_base_address + src1_col_size - output_col_index;
                    src1_address <= window_base_address + src1_col_size - output_col_index;
                end
                else begin
                    output_col_index <= output_col_index + 1;
                    window_base_address <= window_base_address + 1;
                    src1_address <= window_base_address + 1;
                end
            end

            WRITE: begin
                dest_write_en <= 0;
                dest_address <= dest_address + 1;
                sum <= 0;
            end

            DONE: begin
                kernel_row_index <= 0;
                kernel_col_index <= 0;
                output_row_index <= 0;
                output_col_index <= 0;
                dest_address <= dest_start_address;
                src1_address <= src1_start_address;
                src2_address <= src2_start_address;
                dest_write_en <= 0;
            end
        endcase
    end

    int8Mult mul(
        .intA(src1_readdata),
        .intB(kernel[kernel_row_index][kernel_col_index]),
        .product(product)
    );

    int8Add intadd (
        .accA(sum),
        .productB(product),
        .sum(sum_plus_product)
    );

endmodule
