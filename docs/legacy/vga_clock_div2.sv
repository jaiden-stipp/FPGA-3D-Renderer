module vga_clock_div2 (
    input  logic clk_50,
    input  logic reset,
    output logic pixel_clk
);

    always_ff @(posedge clk_50 or posedge reset) begin
        if (reset)
            pixel_clk <= 1'b0;
        else
            pixel_clk <= ~pixel_clk;
    end

endmodule
