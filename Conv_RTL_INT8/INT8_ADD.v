module int8_add (
    input wire signed [31:0] accumulator,
    input wire signed [15:0] product,
    output wire signed [31:0] sum
);

    assign sum = accumulator + {{16{product[15]}}, product};

endmodule
