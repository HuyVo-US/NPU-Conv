`timescale 1ns / 1ps

module tb_conv;

    integer input_file;
    integer kernel_file;
    integer output_file;
    integer trace_file;
    integer row;
    integer col;
    integer output_count;
    integer output_row_size;
    integer output_col_size;
    integer output_index;
    integer output_row;
    integer output_col;
    integer output_addr_offset;

    reg [15:0] output_mem [0:1023];

    localparam INPUT_HEX_FILE = "input.hex";
    localparam KERNEL_HEX_FILE = "kernel.hex";
    localparam OUTPUT_HEX_FILE = "output.hex";
    localparam TRACE_LOG_FILE = "conv_trace.log";

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

    M10K_sram src1(
        .clk(clk_300),
        .we(conv_src1_write_en),
        .q(conv_src1_readdata),
        .d(conv_src1_writedata),
        .address(conv_src1_address)
    );

    M10K_sram src2(
        .clk(clk_300),
        .we(conv_src2_write_en),
        .q(conv_src2_readdata),
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

    function [15:0] int_to_fp16;
        input integer value;
        integer msb;
        integer exponent;
        reg [31:0] temp;
        reg [10:0] normalized;
        begin
            if (value <= 0) begin
                int_to_fp16 = 16'h0000;
            end
            else begin
                temp = value;
                msb = 0;
                while (temp > 1) begin
                    temp = temp >> 1;
                    msb = msb + 1;
                end

                exponent = msb + 15;
                if (msb > 10) begin
                    normalized = value >> (msb - 10);
                end
                else begin
                    normalized = value << (10 - msb);
                end

                int_to_fp16 = {1'b0, exponent[4:0], normalized[9:0]};
            end
        end
    endfunction

    task init_fp16_test_data;
        begin
            for (row = 0; row < conv_src1_row_size; row = row + 1) begin
                for (col = 0; col < conv_src1_col_size; col = col + 1) begin
                    src1.mem[conv_src1_start_address + row * conv_src1_col_size + col] =
                        int_to_fp16(row * conv_src1_col_size + col + 1);
                end
            end

            for (row = 0; row < conv_src2_row_size; row = row + 1) begin
                for (col = 0; col < conv_src2_col_size; col = col + 1) begin
                    src2.mem[conv_src2_start_address + row * conv_src2_col_size + col] =
                        int_to_fp16(row * conv_src2_col_size + col + 1);
                end
            end
        end
    endtask

    task dump_input_data;
        begin
            for (row = 0; row < conv_src1_row_size; row = row + 1) begin
                for (col = 0; col < conv_src1_col_size; col = col + 1) begin
                    if (col == conv_src1_col_size - 1) begin
                        $fdisplay(input_file, "%04h",
                            src1.mem[conv_src1_start_address + row * conv_src1_col_size + col]);
                    end
                    else begin
                        $fwrite(input_file, "%04h ",
                            src1.mem[conv_src1_start_address + row * conv_src1_col_size + col]);
                    end
                end
            end
        end
    endtask

    task dump_kernel_data;
        begin
            for (row = 0; row < conv_src2_row_size; row = row + 1) begin
                for (col = 0; col < conv_src2_col_size; col = col + 1) begin
                    if (col == conv_src2_col_size - 1) begin
                        $fdisplay(kernel_file, "%04h",
                            src2.mem[conv_src2_start_address + row * conv_src2_col_size + col]);
                    end
                    else begin
                        $fwrite(kernel_file, "%04h ",
                            src2.mem[conv_src2_start_address + row * conv_src2_col_size + col]);
                    end
                end
            end
        end
    endtask

    task dump_output_data;
        begin
            for (row = 0; row < output_row_size; row = row + 1) begin
                for (col = 0; col < output_col_size; col = col + 1) begin
                    output_index = row * output_col_size + col;
                    if (col == output_col_size - 1) begin
                        $fdisplay(output_file, "%04h", output_mem[output_index]);
                    end
                    else begin
                        $fwrite(output_file, "%04h ", output_mem[output_index]);
                    end
                end
            end
        end
    endtask

    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    initial begin
        clk_300 = 0;
        forever #2 clk_300 = ~clk_300;
    end

    initial begin
        input_file = $fopen(INPUT_HEX_FILE, "w");
        kernel_file = $fopen(KERNEL_HEX_FILE, "w");
        output_file = $fopen(OUTPUT_HEX_FILE, "w");
        trace_file = $fopen(TRACE_LOG_FILE, "w");

        if (input_file == 0 || kernel_file == 0 || output_file == 0 || trace_file == 0) begin
            $display("ERROR: Could not open one or more output files.");
            $finish;
        end

        output_count = 0;
        for (output_index = 0; output_index < 1024; output_index = output_index + 1) begin
            output_mem[output_index] = 16'h0000;
        end

        reset = 1;
        conv_start = 0;
        conv_src1_start_address = 0;
        conv_src2_start_address = 0;
        conv_src1_row_size = 28; 
        conv_src1_col_size = 28;
        conv_src2_row_size = 3;
        conv_src2_col_size = 3;
        conv_dest_start_address = 0;
        output_row_size = conv_src1_row_size - conv_src2_row_size + 1;
        output_col_size = conv_src1_col_size - conv_src2_col_size + 1;

        init_fp16_test_data();
        dump_input_data();
        dump_kernel_data();
        $fdisplay(trace_file,
            "# WRITE[index] time=<time>ns address=<dest_addr> row=<output_row> col=<output_col> data=<dest_data> state=<state> next_state=<next_state> start=<start> done=<done> src1_addr=<src1_addr> src1_data=<src1_data> src2_addr=<src2_addr> src2_data=<src2_data> dest_we=<dest_we> i=<i> j=<j> m=<m> n=<n> product=<product> sum=<sum>");

        #10;
        reset = 1;
        #10;
        reset = 0;


        #20;
        conv_start = 1;
        #10;
        conv_start = 0;

        wait (conv_done == 0);
        wait (conv_done == 1);
        #40;

        dump_output_data();

        $fclose(input_file);
        $fclose(kernel_file);
        $fclose(output_file);
        $fclose(trace_file);
        $finish;

    end

    always @(posedge clk) begin
        if (conv_dest_write_en) begin
            output_addr_offset = conv_dest_address - conv_dest_start_address;
            output_row = output_addr_offset / output_col_size;
            output_col = output_addr_offset % output_col_size;
            output_mem[output_addr_offset] = conv_dest_writedata;
            output_count = output_count + 1;

            $fdisplay(trace_file,
                "WRITE[%0d] time=%0tns address=%0d row=%0d col=%0d data=%04h state=%0d next_state=%0d start=%0b done=%0b src1_addr=%0d src1_data=%04h src2_addr=%0d src2_data=%04h dest_we=%0b i=%0d j=%0d m=%0d n=%0d product=%04h sum=%04h",
                output_count,
                $time,
                conv_dest_address,
                output_row,
                output_col,
                conv_dest_writedata,
                uut.state,
                uut.next_state,
                conv_start,
                conv_done,
                conv_src1_address,
                conv_src1_readdata,
                conv_src2_address,
                conv_src2_readdata,
                conv_dest_write_en,
                uut.i,
                uut.j,
                uut.m,
                uut.n,
                uut.product,
                uut.sum);
        end
    end

endmodule
