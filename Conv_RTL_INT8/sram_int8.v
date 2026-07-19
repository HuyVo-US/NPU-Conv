module sram_int8 (
    output reg signed [7:0] q,
    input wire signed [7:0] d,
    input wire [13:0] address,
    input wire we,
    input wire clk
);
    reg signed [7:0] mem [0:16383]
        /* synthesis ramstyle = "no_rw_check, M10K" */;

    integer index;
    initial begin
        q = 8'sd0;
        for (index = 0; index < 16384; index = index + 1) begin
            mem[index] = index[7:0];
        end
    end

    always @(posedge clk) begin
        if (we) begin
            mem[address] <= d;
        end
        q <= mem[address];
    end

endmodule
