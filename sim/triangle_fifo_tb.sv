`timescale 1ns/1ps

`include "renderer_types.svh"

module triangle_fifo_tb;
    logic clk;
    logic reset;
    triangle_3d_t in_data;
    logic in_valid;
    logic in_ready;
    triangle_3d_t out_data;
    logic out_valid;
    logic out_ready;
    logic empty;
    logic full;

    triangle_fifo #(.DEPTH(4)) dut (
        .clk(clk),
        .reset(reset),
        .in_data(in_data),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .out_data(out_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .empty(empty),
        .full(full)
    );

    always #1 clk = ~clk;

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        in_valid = 1'b0;
        out_ready = 1'b0;
        in_data = '0;

        repeat (2) @(posedge clk);
        reset = 1'b0;

        in_data.x0 = 16'shA55A;
        in_data.y0 = 16'sh1357;
        in_data.z0 = 16'sh2468;
        in_data.x1 = 16'shFEDC;
        in_data.y1 = 16'shBEEF;
        in_data.z1 = 16'sh8001;
        in_data.x2 = 16'sh7F01;
        in_data.y2 = 16'sh0102;
        in_data.z2 = 16'shCAFE;
        in_data.color = 8'hC3;

        @(negedge clk);
        in_valid = 1'b1;
        @(posedge clk);
        if (!in_ready)
            $fatal(1, "FIFO was not ready for first triangle");
        @(negedge clk);
        in_valid = 1'b0;
        out_ready = 1'b1;

        wait (out_valid);
        if (out_data.x0 !== 16'shA55A || out_data.y0 !== 16'sh1357 ||
            out_data.z0 !== 16'sh2468 || out_data.x1 !== 16'shFEDC ||
            out_data.y1 !== 16'shBEEF || out_data.z1 !== 16'sh8001 ||
            out_data.x2 !== 16'sh7F01 || out_data.y2 !== 16'sh0102 ||
            out_data.z2 !== 16'shCAFE || out_data.color !== 8'hC3)
            $fatal(1, "FIFO did not preserve the complete triangle record");
        @(posedge clk);
        @(negedge clk);

        if (!empty)
            $fatal(1, "FIFO did not become empty after pop");

        $display("triangle_fifo_tb PASS: complete 152-bit triangle record preserved");
        $finish;
    end
endmodule
