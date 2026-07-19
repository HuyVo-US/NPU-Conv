`timescale 1ns / 1ps

module tb_conv;

    reg clk;
    reg clk_300;
    reg reset;
    reg conv_start;
    wire conv_done;
    reg [13:0] conv_src1_start_address;
    reg [13:0] conv_src2_start_address;
    wire [13:0] conv_src1_address;
    wire [15:0] conv_src1_readdata;
    wire [15:0] conv_src2_readdata;
    wire [15:0] sram_src1_readdata;
    wire [15:0] sram_src2_readdata;
    wire [15:0] debug_kernel_value;
    wire [15:0] conv_src1_writedata;
    wire conv_src1_write_en;
    wire [13:0] conv_src2_address;
    wire [15:0] conv_src2_writedata;
    wire conv_src2_write_en;
    reg [15:0] conv_dest_readdata;
    wire [13:0] conv_dest_address;
    wire [15:0] conv_dest_writedata;
    wire conv_dest_write_en;
    reg [9:0] conv_src1_row_size;
    reg [9:0] conv_src1_col_size;
    reg [5:0] conv_src2_row_size;
    reg [5:0] conv_src2_col_size;
    reg [13:0] conv_dest_start_address;

    integer process_log_file;
    integer write_count;
    reg process_log_enable;

    function automatic [15:0] uint16_to_fp16;
        input [15:0] value;
        integer bit_index;
        integer msb_index;
        integer shift_amount;
        reg [11:0] rounded_significand;
        reg [15:0] remainder;
        reg [15:0] halfway;
        reg [4:0] exponent_field;
        reg [9:0] mantissa_field;
        begin
            if (^value === 1'bx) begin
                uint16_to_fp16 = 16'hxxxx;
            end
            else if (value == 16'd0) begin
                uint16_to_fp16 = 16'h0000;
            end
            else begin
                msb_index = -1;
                for (bit_index = 15; bit_index >= 0; bit_index = bit_index - 1) begin
                    if ((msb_index == -1) && value[bit_index]) begin
                        msb_index = bit_index;
                    end
                end

                if (msb_index <= 10) begin
                    exponent_field = msb_index + 15;
                    mantissa_field = value << (10 - msb_index);
                    uint16_to_fp16 = {1'b0, exponent_field, mantissa_field};
                end
                else begin
                    shift_amount = msb_index - 10;
                    rounded_significand = value >> shift_amount;
                    remainder = value & ((16'h0001 << shift_amount) - 1'b1);
                    halfway = 16'h0001 << (shift_amount - 1);

                    if ((remainder > halfway) ||
                        ((remainder == halfway) && rounded_significand[0])) begin
                        rounded_significand = rounded_significand + 1'b1;
                    end

                    if (rounded_significand[11]) begin
                        msb_index = msb_index + 1;
                        rounded_significand = 12'd1024;
                    end

                    if ((msb_index + 15) >= 31) begin
                        uint16_to_fp16 = 16'h7c00;
                    end
                    else begin
                        exponent_field = msb_index + 15;
                        mantissa_field = rounded_significand[9:0];
                        uint16_to_fp16 = {1'b0, exponent_field, mantissa_field};
                    end
                end
            end
        end
    endfunction

    function [8*11-1:0] conv_state_name;
        input [2:0] state_value;
        begin
            case (state_value)
                3'd0: conv_state_name = "IDLE";
                3'd1: conv_state_name = "READ_KERNEL";
                3'd2: conv_state_name = "CALC";
                3'd3: conv_state_name = "SLIDE";
                3'd4: conv_state_name = "WRITE";
                3'd5: conv_state_name = "DONE";
                default: conv_state_name = "UNKNOWN";
            endcase
        end
    endfunction

    assign conv_src1_readdata = uint16_to_fp16(sram_src1_readdata);
    assign conv_src2_readdata = uint16_to_fp16(sram_src2_readdata);


    matrix_conv uut (
        .clk(clk),
        .reset(reset),
        .start(conv_start),
        .done(conv_done),
        .src1_start_address(conv_src1_start_address),
        .src2_start_address(conv_src2_start_address),
        .src1_address(conv_src1_address),
        .src1_readdata(conv_src1_readdata),
        .src1_writedata(conv_src1_writedata),
        .src1_write_en(conv_src1_write_en),
        .src2_address(conv_src2_address),
        .src2_readdata(conv_src2_readdata),
        .src2_writedata(conv_src2_writedata),
        .src2_write_en(conv_src2_write_en),
        .src1_row_size(conv_src1_row_size),
        .src1_col_size(conv_src1_col_size),
        .src2_row_size(conv_src2_row_size),
        .src2_col_size(conv_src2_col_size),
        .dest_start_address(conv_dest_start_address),
        .dest_address(conv_dest_address),
        .dest_readdata(),
        .dest_writedata(conv_dest_writedata),
        .dest_write_en(conv_dest_write_en)
    );

    assign debug_kernel_value = uut.kernel[uut.i][uut.j];

    M10K_sram src1(
        .clk(clk_300),
        .we(conv_src1_write_en),
        .q(sram_src1_readdata),
        .d(conv_src1_writedata),
        .address(conv_src1_address)
    );

    M10K_sram src2(
        .clk(clk_300),
        .we(conv_src2_write_en),
        .q(sram_src2_readdata),
        .d(conv_src2_writedata),
        .address(conv_src2_address)
    );

    M10K_sram dest(
        .clk(clk_300),
        .we(conv_dest_write_en),
        .q(),
        .d(conv_dest_writedata),
        .address(conv_dest_address)
    );

    task dump_input_matrix;
        integer file_handle;
        integer row_index;
        integer col_index;
        integer memory_address;
        begin
            file_handle = $fopen("conv_input.hex", "w");
            if (file_handle == 0) begin
                $display("ERROR: Cannot open conv_input.hex");
                $finish;
            end

            for (row_index = 0; row_index < conv_src1_row_size; row_index = row_index + 1) begin
                memory_address = conv_src1_start_address + row_index * conv_src1_col_size;
                for (col_index = 0; col_index < conv_src1_col_size; col_index = col_index + 1) begin
                    $fwrite(file_handle, "%04h",
                            uint16_to_fp16(src1.mem[memory_address + col_index]));
                    if (col_index == conv_src1_col_size - 1)
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
        integer memory_address;
        begin
            file_handle = $fopen("conv_kernel.hex", "w");
            if (file_handle == 0) begin
                $display("ERROR: Cannot open conv_kernel.hex");
                $finish;
            end

            for (row_index = 0; row_index < conv_src2_row_size; row_index = row_index + 1) begin
                memory_address = conv_src2_start_address + row_index * conv_src2_col_size;
                for (col_index = 0; col_index < conv_src2_col_size; col_index = col_index + 1) begin
                    $fwrite(file_handle, "%04h",
                            uint16_to_fp16(src2.mem[memory_address + col_index]));
                    if (col_index == conv_src2_col_size - 1)
                        $fwrite(file_handle, "\n");
                    else
                        $fwrite(file_handle, " ");
                end
            end
            $fclose(file_handle);
        end
    endtask

    task clear_output_matrix;
        integer output_rows;
        integer output_cols;
        integer output_index;
        begin
            output_rows = conv_src1_row_size - conv_src2_row_size + 1;
            output_cols = conv_src1_col_size - conv_src2_col_size + 1;
            for (output_index = 0; output_index < output_rows * output_cols;
                 output_index = output_index + 1) begin
                dest.mem[conv_dest_start_address + output_index] = 16'hxxxx;
            end
        end
    endtask

    task dump_output_matrix;
        integer file_handle;
        integer output_rows;
        integer output_cols;
        integer row_index;
        integer col_index;
        integer memory_address;
        begin
            output_rows = conv_src1_row_size - conv_src2_row_size + 1;
            output_cols = conv_src1_col_size - conv_src2_col_size + 1;
            file_handle = $fopen("conv_output.hex", "w");
            if (file_handle == 0) begin
                $display("ERROR: Cannot open conv_output.hex");
                $finish;
            end

            for (row_index = 0; row_index < output_rows; row_index = row_index + 1) begin
                memory_address = conv_dest_start_address + row_index * output_cols;
                for (col_index = 0; col_index < output_cols; col_index = col_index + 1) begin
                    $fwrite(file_handle, "%04h", dest.mem[memory_address + col_index]);
                    if (col_index == output_cols - 1)
                        $fwrite(file_handle, "\n");
                    else
                        $fwrite(file_handle, " ");
                end
            end
            $fclose(file_handle);
        end
    endtask

    always @(posedge clk) begin
        if (process_log_enable && (process_log_file != 0) &&
            (conv_dest_write_en === 1'b1)) begin
            write_count = write_count + 1;
            $fwrite(process_log_file,
                    "%0s[%0d] time=%0dns address=%0d output_row=%0d output_col=%0d data=%04h state=%0d next_state=%0d start=%b done=%b src1_addr=%0d src1_data=%04h src2_addr=%0d src2_data=%04h dest_we=%b kernel_row=%0d kernel_col=%0d product=%04h sum=%04h\n",
                    conv_state_name(uut.state), write_count,
                    $time, conv_dest_address, uut.m, uut.n,
                    conv_dest_writedata, uut.state, uut.next_state,
                    conv_start, conv_done, conv_src1_address,
                    conv_src1_readdata, conv_src2_address,
                    conv_src2_readdata, conv_dest_write_en,
                    uut.i, uut.j, uut.product, uut.sum);
        end
    end

    initial begin
        write_count = 0;
        process_log_enable = 1;
        process_log_file = $fopen("conv_internal_process.log", "w");
        if (process_log_file == 0) begin
            $display("ERROR: Cannot open conv_internal_process.log");
            $finish;
        end
        #1;
        dump_input_matrix;
        dump_kernel_matrix;
        clear_output_matrix;

        wait (reset === 1'b0);
        wait (conv_done === 1'b0);
        wait (conv_done === 1'b1);
        repeat (2) @(posedge clk_300);

        dump_output_matrix;
        process_log_enable = 0;
        $fclose(process_log_file);
        $display("Convolution logs written: conv_input.hex, conv_kernel.hex, conv_output.hex, conv_internal_process.log");
        $finish;
    end

    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    initial begin
        clk_300 = 0;
        forever #2 clk_300 = ~clk_300;
    end

    initial begin
        reset = 1;
        conv_start = 0;
        conv_src1_start_address = 0;
        conv_src2_start_address = 0;
        conv_src1_row_size = 28; 
        conv_src1_col_size = 28;
        conv_src2_row_size = 3;
        conv_src2_col_size = 3;
        conv_dest_start_address = 0;


        #10;
        reset = 1;
        #10;
        reset = 0;


        #20;
        conv_start = 1;
        #10;
        conv_start = 0;

    end

endmodule
