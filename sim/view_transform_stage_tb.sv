`timescale 1ns/1ps
`include "renderer_types.svh"

module view_transform_stage_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic in_valid = 1'b0;
    logic in_ready;
    logic out_valid;
    logic out_ready = 1'b1;
    logic busy;
    triangle_3d_t input_triangle;
    triangle_3d_t output_triangle;
    model_matrix_3x4_t view_matrix;

    always #1 clk = ~clk;

    view_transform_stage dut (
        .clk(clk),
        .reset(reset),
        .view_matrix(view_matrix),
        .in_data(input_triangle),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .out_data(output_triangle),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .busy(busy)
    );

    initial begin
        input_triangle = '0;
        input_triangle.x0 = 16'sh0100;
        input_triangle.y0 = 16'sh0200;
        input_triangle.z0 = 16'sh0300;
        input_triangle.x1 = -16'sh0100;
        input_triangle.y1 = 16'sh0080;
        input_triangle.z1 = 16'sh0000;
        input_triangle.x2 = 16'sh0000;
        input_triangle.y2 = -16'sh0100;
        input_triangle.z2 = 16'sh0100;
        input_triangle.color = 8'h5A;
        view_matrix = '0;
        view_matrix.m00 = 16'sh0200;
        view_matrix.m03 = 16'sh0100;
        view_matrix.m11 = 16'sh0100;
        view_matrix.m13 = -16'sh0080;
        view_matrix.m22 = 16'sh0100;
        view_matrix.m23 = 16'sh0500;
        repeat (3) @(posedge clk);
        reset = 1'b0;
        @(negedge clk);
        in_valid = 1'b1;
        @(negedge clk);
        in_valid = 1'b0;
        wait (out_valid);
        if (output_triangle.x0 != 16'sh0300 ||
            output_triangle.y0 != 16'sh0180 ||
            output_triangle.z0 != 16'sh0800 ||
            output_triangle.x1 != -16'sh0100 ||
            output_triangle.z2 != 16'sh0600 ||
            output_triangle.color != 8'h5A)
            $fatal(1, "view matrix result was incorrect");
        $display("view_transform_stage_tb PASS: explicit view matrix transformed all vertices");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "view_transform_stage_tb timed out");
    end
endmodule
