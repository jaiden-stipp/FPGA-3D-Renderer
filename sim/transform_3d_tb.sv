`timescale 1ns/1ps

`include "renderer_types.svh"

module transform_3d_tb;
    logic clk;
    logic reset;
    logic [7:0] rotation_angle;
    triangle_3d_t in_data;
    logic in_valid;
    logic in_ready;
    triangle_data_t out_data;
    logic out_valid;
    logic out_ready;
    logic busy;

    transform_3d_pipeline #(
        .BACKFACE_CULL(1'b0)
    ) dut (
        .clk(clk),
        .reset(reset),
        .rotation_angle(rotation_angle),
        .in_data(in_data),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .out_data(out_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .busy(busy)
    );

    always #1 clk = ~clk;

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        rotation_angle = 8'd64;
        in_valid = 1'b0;
        out_ready = 1'b1;
        in_data = '0;

        in_data.x0 = 16'shFF00;
        in_data.y0 = 16'shFF00;
        in_data.z0 = 16'sh0100;
        in_data.x1 = 16'sh0100;
        in_data.y1 = 16'shFF00;
        in_data.z1 = 16'sh0100;
        in_data.x2 = 16'sh0100;
        in_data.y2 = 16'sh0100;
        in_data.z2 = 16'sh0100;
        in_data.color = 8'hE0;

        repeat (2) @(posedge clk);
        reset = 1'b0;

        while (!in_ready)
            @(posedge clk);
        @(negedge clk);
        in_valid = 1'b1;
        @(negedge clk);
        in_valid = 1'b0;

        while (!out_valid)
            @(posedge clk);

        if (out_data.x0 < 10'd196 || out_data.x0 > 10'd202)
            $fatal(1, "unexpected projected x0: %0d", out_data.x0);
        if (out_data.y0 < 10'd136 || out_data.y0 > 10'd144)
            $fatal(1, "unexpected projected y0: %0d", out_data.y0);
        if (out_data.x1 < 10'd212 || out_data.x1 > 10'd218)
            $fatal(1, "unexpected projected x1: %0d", out_data.x1);
        if (out_data.y2 < 10'd82 || out_data.y2 > 10'd90)
            $fatal(1, "unexpected projected y2: %0d", out_data.y2);
        if ((out_data.z0 != 8'd40) || (out_data.z1 != 8'd56) ||
            (out_data.z2 != 8'd68))
            $fatal(1, "unexpected inverse depth");
        if (out_data.color != 8'hE0)
            $fatal(1, "color was not carried through");

        $display("transform_3d_tb PASS: 3D triangle projected and accepted");
        $finish;
    end
endmodule
