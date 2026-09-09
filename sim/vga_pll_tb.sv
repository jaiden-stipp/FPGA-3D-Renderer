`timescale 1ns/1ps

module vga_pll_tb;

    logic inclk0;
    logic areset;
    logic c0;
    logic locked;
    int output_edges;

    vga_pll dut (
        .inclk0(inclk0),
        .areset(areset),
        .c0(c0),
        .locked(locked)
    );

    always #10 inclk0 = ~inclk0;
    always @(posedge c0)
        output_edges++;

    initial begin
        inclk0 = 1'b0;
        areset = 1'b1;
        output_edges = 0;

        repeat (2) @(posedge inclk0);
        areset = 1'b0;
        repeat (7) @(posedge inclk0);

        if (!locked)
            $fatal(1, "PLL model did not lock");
        if (output_edges < 2)
            $fatal(1, "PLL model did not generate the pixel clock");

        areset = 1'b1;
        #1;
        if (locked || c0)
            $fatal(1, "PLL model did not reset");

        $display("vga_pll_tb PASS");
        $finish;
    end

endmodule
