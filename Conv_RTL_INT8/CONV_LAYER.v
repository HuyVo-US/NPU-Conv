module conv_layer (
    // Control interface.
    input wire clk,
    input wire reset,
    input wire start,
    output wire done,

    // Post-processing parameters. Keep stable while the layer is running.
    input wire signed [31:0] bias,
    input wire signed [31:0] multiplier,
    input wire signed [31:0] shift,

    // Source 1: input feature map.
    input wire [13:0] src1_start_address,
    input wire [9:0] src1_row_size,
    input wire [9:0] src1_col_size,
    output wire [13:0] src1_address,
    input wire signed [7:0] src1_readdata,
    output wire [7:0] src1_writedata,
    output wire src1_write_en,

    // Source 2: convolution kernel.
    input wire [13:0] src2_start_address,
    input wire [5:0] src2_row_size,
    input wire [5:0] src2_col_size,
    output wire [13:0] src2_address,
    input wire signed [7:0] src2_readdata,
    output wire [7:0] src2_writedata,
    output wire src2_write_en,

    // Destination: final INT8 output and raw INT32 value for debug.
    input wire [13:0] dest_start_address,
    output wire [13:0] dest_address,
    output wire signed [7:0] dest_writedata,
    output wire dest_write_en,
    output wire signed [31:0] raw_accumulator
);

    matrix_conv convolution (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),

        .src1_start_address(src1_start_address),
        .src1_row_size(src1_row_size),
        .src1_col_size(src1_col_size),
        .src1_address(src1_address),
        .src1_readdata(src1_readdata),
        .src1_writedata(src1_writedata),
        .src1_write_en(src1_write_en),

        .src2_start_address(src2_start_address),
        .src2_row_size(src2_row_size),
        .src2_col_size(src2_col_size),
        .src2_address(src2_address),
        .src2_readdata(src2_readdata),
        .src2_writedata(src2_writedata),
        .src2_write_en(src2_write_en),

        .dest_start_address(dest_start_address),
        .dest_address(dest_address),
        .dest_readdata(32'sd0),
        .dest_writedata(raw_accumulator),
        .dest_write_en(dest_write_en)
    );

    post_process output_post_process (
        .raw_accumulator(raw_accumulator),
        .bias(bias),
        .multiplier(multiplier),
        .shift(shift),
        .output_value(dest_writedata)
    );

endmodule
