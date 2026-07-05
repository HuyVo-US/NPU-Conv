module int8Mult
(
    input wire signed [7:0] intA,
    input wire signed [7:0] intB,
    output wire signed [15:0] product
);

assign product = intA * intB;

endmodule
