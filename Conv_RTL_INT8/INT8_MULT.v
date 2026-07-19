module int8_mult (
    input wire signed [7:0] input_value,
    input wire signed [7:0] kernel_value,
    output wire signed [15:0] product
);

    assign product = input_value * kernel_value;

endmodule
