module post_process (
    input wire signed [31:0] raw_accumulator,
    input wire signed [31:0] bias,
    input wire signed [31:0] multiplier,
    input wire signed [31:0] shift,
    output reg signed [7:0] output_value
);
    wire signed [31:0] biased_accumulator;
    wire signed [63:0] scaled_product;

    reg [63:0] magnitude;
    reg [63:0] quotient;
    reg [63:0] remainder;
    reg [63:0] half_value;
    reg [63:0] rounded_magnitude;
    reg [63:0] saturation_limit;
    integer total_shift;
    integer left_shift;

    assign biased_accumulator = raw_accumulator + bias;
    assign scaled_product = biased_accumulator * multiplier;

    always @(*) begin
        magnitude = 64'd0;
        quotient = 64'd0;
        remainder = 64'd0;
        half_value = 64'd0;
        rounded_magnitude = 64'd0;
        saturation_limit = 64'd127;
        total_shift = 32'sd31 + shift;
        left_shift = 0;

        if (scaled_product[63]) begin
            magnitude = (~scaled_product) + 64'd1;
            saturation_limit = 64'd128;
        end else begin
            magnitude = scaled_product;
        end

        if (total_shift < 0) begin
            left_shift = -total_shift;

            if (magnitude == 64'd0) begin
                rounded_magnitude = 64'd0;
            end else if (left_shift >= 7) begin
                rounded_magnitude = saturation_limit + 64'd1;
            end else if (magnitude >
                         (saturation_limit >> left_shift)) begin
                rounded_magnitude = saturation_limit + 64'd1;
            end else begin
                rounded_magnitude = magnitude << left_shift;
            end
        end else if (total_shift == 0) begin
            rounded_magnitude = magnitude;
        end else if (total_shift >= 64) begin
            rounded_magnitude = 64'd0;
        end else begin
            quotient = magnitude >> total_shift;
            remainder = magnitude - (quotient << total_shift);
            half_value = 64'd1 << (total_shift - 1);
            rounded_magnitude = quotient;

            if ((remainder > half_value) ||
                ((remainder == half_value) && quotient[0])) begin
                rounded_magnitude = quotient + 64'd1;
            end
        end

        if (scaled_product[63]) begin
            if (rounded_magnitude >= 64'd128) begin
                output_value = 8'sh80;
            end else begin
                output_value = (~rounded_magnitude[7:0]) + 8'd1;
            end
        end else begin
            if (rounded_magnitude > 64'd127) begin
                output_value = 8'sd127;
            end else begin
                output_value = rounded_magnitude[7:0];
            end
        end
    end

endmodule
