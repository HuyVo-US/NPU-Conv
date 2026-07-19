module matrix_conv (
    // Control interface.
    input wire clk,
    input wire reset,
    input wire start,
    output reg done,

    // Source 1
    input wire [13:0] src1_start_address,
    input wire [9:0] src1_row_size,
    input wire [9:0] src1_col_size,
    output reg [13:0] src1_address,
    input wire signed [7:0] src1_readdata,
    output wire [7:0] src1_writedata,
    output wire src1_write_en,

    // Source 2
    input wire [13:0] src2_start_address,
    input wire [5:0] src2_row_size,
    input wire [5:0] src2_col_size,
    output reg [13:0] src2_address,
    input wire signed [7:0] src2_readdata,
    output wire [7:0] src2_writedata,
    output wire src2_write_en,

    // Destination
    input wire [13:0] dest_start_address,
    output reg [13:0] dest_address,
    input wire signed [31:0] dest_readdata,
    output wire signed [31:0] dest_writedata,
    output reg dest_write_en
);
    localparam [2:0] STATE_IDLE        = 3'd0;
    localparam [2:0] STATE_READ_KERNEL = 3'd1;
    localparam [2:0] STATE_CALCULATE   = 3'd2;
    localparam [2:0] STATE_SLIDE       = 3'd3;
    localparam [2:0] STATE_WRITE       = 3'd4;
    localparam [2:0] STATE_DONE        = 3'd5;

    reg [2:0] current_state;
    reg [2:0] next_state;

    reg [5:0] kernel_row;
    reg [5:0] kernel_col;
    reg [9:0] output_row;
    reg [9:0] output_col;

    reg [3:0] kernel_load_row;
    reg [3:0] kernel_load_col;
    reg signed [7:0] kernel_buffer [2:0][2:0];

    reg [13:0] input_window_address;
    reg signed [31:0] accumulator;

    wire signed [15:0] multiplication_result;
    wire signed [31:0] next_accumulator;
    wire [9:0] last_output_row;
    wire [9:0] last_output_col;

    assign src1_write_en = 1'b0;
    assign src2_write_en = 1'b0;
    assign src1_writedata = 8'h00;
    assign src2_writedata = 8'h00;
    assign dest_writedata = accumulator;

    assign last_output_row = src1_row_size - src2_row_size;
    assign last_output_col = src1_col_size - src2_col_size;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= STATE_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    always @(*) begin
        next_state = current_state;
        done = 1'b0;

        case (current_state)
            STATE_IDLE: begin
                done = 1'b1;
                if (start) begin
                    next_state = STATE_READ_KERNEL;
                end
            end

            STATE_READ_KERNEL: begin
                if ((kernel_load_row == src2_row_size - 6'd1) &&
                    (kernel_load_col == src2_col_size - 6'd1)) begin
                    next_state = STATE_CALCULATE;
                end
            end

            STATE_CALCULATE: begin
                if ((kernel_row == src2_row_size - 6'd1) &&
                    (kernel_col == src2_col_size - 6'd1)) begin
                    next_state = STATE_WRITE;
                end
            end

            STATE_SLIDE: begin
                next_state = STATE_CALCULATE;
            end

            STATE_WRITE: begin
                if ((output_row == last_output_row) &&
                    (output_col == last_output_col)) begin
                    next_state = STATE_DONE;
                end else begin
                    next_state = STATE_SLIDE;
                end
            end

            STATE_DONE: begin
                done = 1'b1;
                next_state = STATE_IDLE;
            end

            default: begin
                done = 1'b1;
                next_state = STATE_IDLE;
            end
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            kernel_row <= 6'd0;
            kernel_col <= 6'd0;
            output_row <= 10'd0;
            output_col <= 10'd0;
            kernel_load_row <= 4'd0;
            kernel_load_col <= 4'd0;
            accumulator <= 32'sd0;
            src1_address <= src1_start_address;
            src2_address <= src2_start_address;
            dest_address <= dest_start_address;
            input_window_address <= src1_start_address;
            dest_write_en <= 1'b0;
        end else begin
            case (current_state)
                STATE_IDLE: begin
                    kernel_row <= 6'd0;
                    kernel_col <= 6'd0;
                    output_row <= 10'd0;
                    output_col <= 10'd0;
                    kernel_load_row <= 4'd0;
                    kernel_load_col <= 4'd0;
                    accumulator <= 32'sd0;
                    src1_address <= src1_start_address;
                    src2_address <= src2_start_address;
                    dest_address <= dest_start_address;
                    input_window_address <= src1_start_address;
                    dest_write_en <= 1'b0;
                end

                STATE_READ_KERNEL: begin
                    dest_write_en <= 1'b0;
                    kernel_buffer[kernel_load_row][kernel_load_col] <=
                        src2_readdata;
                    src2_address <= src2_address + 14'd1;

                    if (kernel_load_col == src2_col_size - 6'd1) begin
                        kernel_load_col <= 4'd0;
                        if (kernel_load_row != src2_row_size - 6'd1) begin
                            kernel_load_row <= kernel_load_row + 4'd1;
                        end
                    end else begin
                        kernel_load_col <= kernel_load_col + 4'd1;
                    end
                end

                STATE_CALCULATE: begin
                    dest_write_en <= 1'b0;
                    accumulator <= next_accumulator;

                    if (kernel_col == src2_col_size - 6'd1) begin
                        kernel_col <= 6'd0;
                        if (kernel_row == src2_row_size - 6'd1) begin
                            kernel_row <= 6'd0;
                            dest_write_en <= 1'b1;
                        end else begin
                            kernel_row <= kernel_row + 6'd1;
                            src1_address <= src1_address + src1_col_size -
                                            kernel_col;
                        end
                    end else begin
                        kernel_col <= kernel_col + 6'd1;
                        src1_address <= src1_address + 14'd1;
                    end
                end

                STATE_SLIDE: begin
                    dest_write_en <= 1'b0;
                    if (output_col == last_output_col) begin
                        output_row <= output_row + 10'd1;
                        output_col <= 10'd0;
                        input_window_address <= input_window_address +
                                                src1_col_size - output_col;
                        src1_address <= input_window_address +
                                        src1_col_size - output_col;
                    end else begin
                        output_col <= output_col + 10'd1;
                        input_window_address <= input_window_address + 14'd1;
                        src1_address <= input_window_address + 14'd1;
                    end
                end

                STATE_WRITE: begin
                    dest_write_en <= 1'b0;
                    dest_address <= dest_address + 14'd1;
                    accumulator <= 32'sd0;
                end

                STATE_DONE: begin
                    kernel_row <= 6'd0;
                    kernel_col <= 6'd0;
                    output_row <= 10'd0;
                    output_col <= 10'd0;
                    kernel_load_row <= 4'd0;
                    kernel_load_col <= 4'd0;
                    accumulator <= 32'sd0;
                    src1_address <= src1_start_address;
                    src2_address <= src2_start_address;
                    dest_address <= dest_start_address;
                    input_window_address <= src1_start_address;
                    dest_write_en <= 1'b0;
                end

                default: begin
                    dest_write_en <= 1'b0;
                end
            endcase
        end
    end

    int8_mult multiplier (
        .input_value(src1_readdata),
        .kernel_value(kernel_buffer[kernel_row][kernel_col]),
        .product(multiplication_result)
    );

    int8_add adder (
        .accumulator(accumulator),
        .product(multiplication_result),
        .sum(next_accumulator)
    );

endmodule
