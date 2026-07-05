module int8Add
(
    input wire signed [31:0] accA,
    input wire signed [15:0] productB,
    output wire signed [31:0] sum
);

assign sum = accA + {{16{productB[15]}}, productB};

endmodule
