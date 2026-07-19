`timescale 1ns / 1ps

module tb_conv_layer;
    localparam integer INPUT_ROWS  = 28;
    localparam integer INPUT_COLS  = 28;
    localparam integer KERNEL_ROWS = 3;
    localparam integer KERNEL_COLS = 3;
    localparam integer OUTPUT_ROWS = 26;
    localparam integer OUTPUT_COLS = 26;
    localparam integer INPUT_COUNT = INPUT_ROWS * INPUT_COLS;
    localparam integer KERNEL_COUNT = KERNEL_ROWS * KERNEL_COLS;
    localparam integer OUTPUT_COUNT = OUTPUT_ROWS * OUTPUT_COLS;

    localparam [9:0] INPUT_ROWS_CONFIG  = 10'd28;
    localparam [9:0] INPUT_COLS_CONFIG  = 10'd28;
    localparam [5:0] KERNEL_ROWS_CONFIG = 6'd3;
    localparam [5:0] KERNEL_COLS_CONFIG = 6'd3;

    localparam signed [31:0] TEST_BIAS       = 32'sd37;
    localparam signed [31:0] TEST_MULTIPLIER = 32'sh02000000;
    localparam signed [31:0] TEST_SHIFT      = 32'sd2;

    localparam [13:0] SRC1_START_ADDRESS = 14'd0;
    localparam [13:0] SRC2_START_ADDRESS = 14'd0;
    localparam [13:0] DEST_START_ADDRESS = 14'd0;

    reg clk;
    reg clk_300;
    reg reset;
    reg start;

    wire done;
    wire [13:0] src1_address;
    wire signed [7:0] src1_readdata;
    wire [7:0] src1_writedata;
    wire src1_write_en;
    wire [13:0] src2_address;
    wire signed [7:0] src2_readdata;
    wire [7:0] src2_writedata;
    wire src2_write_en;
    wire [13:0] dest_address;
    wire signed [7:0] dest_writedata;
    wire dest_write_en;
    wire signed [31:0] raw_accumulator;

    integer process_log_file;
    integer cycle_count;
    integer write_count;
    reg process_log_enable;

    conv_layer uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),
        .bias(TEST_BIAS),
        .multiplier(TEST_MULTIPLIER),
        .shift(TEST_SHIFT),
        .src1_start_address(SRC1_START_ADDRESS),
        .src1_row_size(INPUT_ROWS_CONFIG),
        .src1_col_size(INPUT_COLS_CONFIG),
        .src1_address(src1_address),
        .src1_readdata(src1_readdata),
        .src1_writedata(src1_writedata),
        .src1_write_en(src1_write_en),
        .src2_start_address(SRC2_START_ADDRESS),
        .src2_row_size(KERNEL_ROWS_CONFIG),
        .src2_col_size(KERNEL_COLS_CONFIG),
        .src2_address(src2_address),
        .src2_readdata(src2_readdata),
        .src2_writedata(src2_writedata),
        .src2_write_en(src2_write_en),
        .dest_start_address(DEST_START_ADDRESS),
        .dest_address(dest_address),
        .dest_writedata(dest_writedata),
        .dest_write_en(dest_write_en),
        .raw_accumulator(raw_accumulator)
    );

    sram_int8 input_sram (
        .clk(clk_300),
        .we(src1_write_en),
        .q(src1_readdata),
        .d(src1_writedata),
        .address(src1_address)
    );

    sram_int8 kernel_sram (
        .clk(clk_300),
        .we(src2_write_en),
        .q(src2_readdata),
        .d(src2_writedata),
        .address(src2_address)
    );

    sram_int8 output_sram (
        .clk(clk_300),
        .we(dest_write_en),
        .q(),
        .d(dest_writedata),
        .address(dest_address)
    );

    task dump_input_matrix;
        integer file_handle;
        integer row_index;
        integer col_index;
        integer address_index;
        begin
            file_handle = $fopen("conv_input.hex", "w");
            if (file_handle == 0) begin
                $display("ERROR: Cannot open conv_input.hex");
                $finish;
            end

            for (row_index = 0; row_index < INPUT_ROWS;
                 row_index = row_index + 1) begin
                for (col_index = 0; col_index < INPUT_COLS;
                     col_index = col_index + 1) begin
                    address_index = SRC1_START_ADDRESS +
                                    row_index * INPUT_COLS + col_index;
                    $fwrite(file_handle, "%02h", input_sram.mem[address_index]);
                    if (col_index == INPUT_COLS - 1)
                        $fwrite(file_handle, "\n");
                    else
                        $fwrite(file_handle, " ");
                end
            end
            $fclose(file_handle);
        end
    endtask

    task dump_kernel_matrix;
        integer file_handle;
        integer row_index;
        integer col_index;
        integer address_index;
        begin
            file_handle = $fopen("conv_kernel.hex", "w");
            if (file_handle == 0) begin
                $display("ERROR: Cannot open conv_kernel.hex");
                $finish;
            end

            for (row_index = 0; row_index < KERNEL_ROWS;
                 row_index = row_index + 1) begin
                for (col_index = 0; col_index < KERNEL_COLS;
                     col_index = col_index + 1) begin
                    address_index = SRC2_START_ADDRESS +
                                    row_index * KERNEL_COLS + col_index;
                    $fwrite(file_handle, "%02h", kernel_sram.mem[address_index]);
                    if (col_index == KERNEL_COLS - 1)
                        $fwrite(file_handle, "\n");
                    else
                        $fwrite(file_handle, " ");
                end
            end
            $fclose(file_handle);
        end
    endtask

    task dump_output_matrix;
        integer file_handle;
        integer row_index;
        integer col_index;
        integer address_index;
        begin
            file_handle = $fopen("conv_rtl_output.hex", "w");
            if (file_handle == 0) begin
                $display("ERROR: Cannot open conv_rtl_output.hex");
                $finish;
            end

            for (row_index = 0; row_index < OUTPUT_ROWS;
                 row_index = row_index + 1) begin
                for (col_index = 0; col_index < OUTPUT_COLS;
                     col_index = col_index + 1) begin
                    address_index = DEST_START_ADDRESS +
                                    row_index * OUTPUT_COLS + col_index;
                    $fwrite(file_handle, "%02h", output_sram.mem[address_index]);
                    if (col_index == OUTPUT_COLS - 1)
                        $fwrite(file_handle, "\n");
                    else
                        $fwrite(file_handle, " ");
                end
            end
            $fclose(file_handle);
        end
    endtask

    always @(posedge clk) begin
        if (process_log_enable && (process_log_file != 0)) begin
            cycle_count = cycle_count + 1;
            if (dest_write_en === 1'b1) begin
                write_count = write_count + 1;
            end

            $fwrite(process_log_file,
                    "cycle=%0d time=%0t state=%0d next_state=%0d start=%b done=%b src1_addr=%0d src1_data=%02h src2_addr=%0d src2_data=%02h kernel_row=%0d kernel_col=%0d output_row=%0d output_col=%0d product=%04h raw_acc=%08h dest_we=%b dest_addr=%0d dest_data=%02h write_count=%0d\n",
                    cycle_count, $time,
                    uut.convolution.current_state,
                    uut.convolution.next_state,
                    start, done,
                    src1_address, src1_readdata,
                    src2_address, src2_readdata,
                    uut.convolution.kernel_row,
                    uut.convolution.kernel_col,
                    uut.convolution.output_row,
                    uut.convolution.output_col,
                    uut.convolution.multiplication_result,
                    raw_accumulator,
                    dest_write_en, dest_address, dest_writedata,
                    write_count);
        end
    end

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    initial begin
        clk_300 = 1'b0;
        forever #2 clk_300 = ~clk_300;
    end

    initial begin
        reset = 1'b1;
        start = 1'b0;
        process_log_file = 0;
        process_log_enable = 1'b0;
        cycle_count = 0;
        write_count = 0;

        // Wait until all SRAM instances finish their own initialization.
        #1;

        dump_input_matrix;
        dump_kernel_matrix;

        process_log_file = $fopen("conv_internal_process.log", "w");
        if (process_log_file == 0) begin
            $display("Cannot open conv_internal_process.log");
            $finish;
        end
        $fwrite(process_log_file,
                "TEST_BIAS=%0d TEST_MULTIPLIER=%0d TEST_SHIFT=%0d\n",
                TEST_BIAS, TEST_MULTIPLIER, TEST_SHIFT);
        process_log_enable = 1'b1;

        $display("TEST_BIAS       = %0d (0x%08h)", TEST_BIAS, TEST_BIAS);
        $display("TEST_MULTIPLIER = %0d (0x%08h)",
                 TEST_MULTIPLIER, TEST_MULTIPLIER);
        $display("TEST_SHIFT      = %0d (0x%08h)", TEST_SHIFT, TEST_SHIFT);

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        @(negedge clk);
        start = 1'b1;

        @(negedge clk);
        start = 1'b0;

        wait (done === 1'b0);
        wait (done === 1'b1);
        repeat (2) @(posedge clk_300);

        dump_output_matrix;
        process_log_enable = 1'b0;
        $fclose(process_log_file);

        $display("Simulation completed");
        $display("Recorded clock cycles: %0d", cycle_count);
        $display("Recorded destination writes: %0d", write_count);
        $display("Generated: conv_input.hex, conv_kernel.hex, conv_rtl_output.hex");
        $display("Process log: conv_internal_process.log");
        $finish;
    end

endmodule
