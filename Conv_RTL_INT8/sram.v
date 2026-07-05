module M10K_sram
#(
    parameter DATA_WIDTH = 8
)
( 
    output reg signed [DATA_WIDTH-1:0] q,
    input signed [DATA_WIDTH-1:0] d,
    input [13:0] address,
    input we, clk
);
	 // force M10K ram style
    reg signed [DATA_WIDTH-1:0] mem [16384:0]  /* synthesis ramstyle = "no_rw_check, M10K" */;

    integer i;
    initial begin
        for (i = 0; i <= 16383; i = i + 1) begin
            // mem[i] = $random;
            mem[i] = {DATA_WIDTH{1'b0}};
        end
    end
	 
    always @ (posedge clk) begin
        if (we) begin
            mem[address] <= d;
        end
        q <= mem[address]; // q doesn't get d in this clock cycle
    end
endmodule
