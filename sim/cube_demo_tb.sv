`timescale 1ns/1ps

`include "renderer_types.svh"

module cube_demo_tb;
    logic clk;
    logic reset;
    logic restart;
    logic pipeline_ready;
    logic pipeline_idle;
    logic clear_busy;
    logic swap_busy;
    logic swap_done;
    logic triangle_valid;
    triangle_3d_t triangle_data;
    logic [7:0] rotation_angle;
    logic clear_request;
    logic swap_request;
    integer accepted;

    cube_demo dut (
        .clk(clk),
        .reset(reset),
        .restart(restart),
        .pipeline_ready(pipeline_ready),
        .pipeline_idle(pipeline_idle),
        .clear_busy(clear_busy),
        .swap_busy(swap_busy),
        .swap_done(swap_done),
        .triangle_valid(triangle_valid),
        .triangle_data(triangle_data),
        .rotation_angle(rotation_angle),
        .clear_request(clear_request),
        .swap_request(swap_request)
    );

    always #1 clk = ~clk;

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        restart = 1'b0;
        pipeline_ready = 1'b0;
        pipeline_idle = 1'b0;
        clear_busy = 1'b1;
        swap_busy = 1'b0;
        swap_done = 1'b0;
        accepted = 0;

        repeat (2) @(posedge clk);
        reset = 1'b0;

        if (!clear_request)
            $fatal(1, "cube demo did not request its initial clear");

        repeat (3) @(posedge clk);
        clear_busy = 1'b0;

        wait (triangle_valid);
        @(negedge clk);
        pipeline_ready = 1'b1;
        repeat (24) @(posedge clk);
        @(negedge clk);
        pipeline_ready = 1'b0;
        accepted = 24;

        wait (!triangle_valid && !clear_request);
        @(negedge clk);
        pipeline_idle = 1'b1;
        @(negedge clk);
        pipeline_idle = 1'b0;

        wait (swap_request);
        @(negedge clk);
        swap_done = 1'b1;
        @(negedge clk);
        swap_done = 1'b0;

        wait (clear_request);
        if (rotation_angle != 8'd1)
            $fatal(1, "cube demo did not advance the angle");

        $display("cube_demo_tb PASS: 24 triangles streamed and angle advanced");
        $finish;
    end
endmodule
