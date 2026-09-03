module iterative_signed_divider #(
    parameter int NUMERATOR_WIDTH = 32,
    parameter int DENOMINATOR_WIDTH = 32
) (
    input logic clk,
    input logic reset,
    input logic start,
    input logic signed [NUMERATOR_WIDTH-1:0] numerator,
    input logic signed [DENOMINATOR_WIDTH-1:0] denominator,
    output logic busy,
    output logic done,
    output logic signed [NUMERATOR_WIDTH-1:0] quotient
);

    localparam int COUNT_WIDTH = $clog2(NUMERATOR_WIDTH);

    logic result_negative;
    logic [NUMERATOR_WIDTH:0] divisor;
    logic [NUMERATOR_WIDTH:0] remainder;
    logic [NUMERATOR_WIDTH-1:0] quotient_work;
    logic [COUNT_WIDTH-1:0] count;

    logic [NUMERATOR_WIDTH:0] remainder_next;
    logic [NUMERATOR_WIDTH-1:0] quotient_next;
    logic signed [NUMERATOR_WIDTH-1:0] signed_quotient_next;

    function automatic [NUMERATOR_WIDTH-1:0] magnitude_numerator(
        input logic signed [NUMERATOR_WIDTH-1:0] value
    );
        begin
            magnitude_numerator = value[NUMERATOR_WIDTH-1] ? -value : value;
        end
    endfunction

    function automatic [DENOMINATOR_WIDTH-1:0] magnitude_denominator(
        input logic signed [DENOMINATOR_WIDTH-1:0] value
    );
        begin
            magnitude_denominator = value[DENOMINATOR_WIDTH-1] ? -value : value;
        end
    endfunction

    always_comb begin
        remainder_next = {remainder[NUMERATOR_WIDTH-1:0],
                          quotient_work[NUMERATOR_WIDTH-1]};
        quotient_next = {quotient_work[NUMERATOR_WIDTH-2:0], 1'b0};

        if (remainder_next >= divisor) begin
            remainder_next = remainder_next - divisor;
            quotient_next[0] = 1'b1;
        end

        signed_quotient_next = result_negative ?
                               -$signed(quotient_next) :
                               $signed(quotient_next);
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            busy <= 1'b0;
            done <= 1'b0;
            quotient <= '0;
            result_negative <= 1'b0;
            divisor <= '0;
            remainder <= '0;
            quotient_work <= '0;
            count <= '0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                if (denominator == 0) begin
                    quotient <= '0;
                    done <= 1'b1;
                end else begin
                    busy <= 1'b1;
                    result_negative <= numerator[NUMERATOR_WIDTH-1] ^
                                       denominator[DENOMINATOR_WIDTH-1];
                    divisor <= {{(NUMERATOR_WIDTH + 1 - DENOMINATOR_WIDTH){1'b0}},
                                magnitude_denominator(denominator)};
                    remainder <= '0;
                    quotient_work <= magnitude_numerator(numerator);
                    count <= '0;
                end
            end else if (busy) begin
                remainder <= remainder_next;
                quotient_work <= quotient_next;

                if (count == NUMERATOR_WIDTH - 1) begin
                    quotient <= signed_quotient_next;
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    count <= count + 1'b1;
                end
            end
        end
    end

endmodule
