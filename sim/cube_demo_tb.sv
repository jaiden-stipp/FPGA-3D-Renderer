`timescale 1ns/1ps

`include "renderer_types.svh"

module cube_demo_tb;
    logic clk;
    logic reset;
    logic restart;
    logic command_valid;
    logic command_ready;
    logic command_error;
    logic frame_done;
    logic triangle_ready;
    logic pipeline_idle;
    logic clear_busy;
    logic swap_busy;
    logic swap_done;
    logic triangle_valid;
    logic [7:0] rotation_angle;
    logic palette_write;
    logic [7:0] palette_address;
    logic [23:0] palette_write_rgb;
    logic clear_request;
    logic swap_request;
    graphics_command_t command_data;
    triangle_3d_t triangle_data;
    integer accepted;

    cube_demo demo (
        .clk(clk),
        .reset(reset),
        .restart(restart),
        .command_ready(command_ready),
        .frame_done(frame_done),
        .command_valid(command_valid),
        .command_data(command_data)
    );

    graphics_command_processor processor (
        .clk(clk),
        .reset(reset),
        .restart(restart),
        .command_data(command_data),
        .command_valid(command_valid),
        .command_ready(command_ready),
        .command_error(command_error),
        .frame_done(frame_done),
        .triangle_ready(triangle_ready),
        .pipeline_idle(pipeline_idle),
        .clear_busy(clear_busy),
        .swap_busy(swap_busy),
        .swap_done(swap_done),
        .triangle_data(triangle_data),
        .triangle_valid(triangle_valid),
        .rotation_angle(rotation_angle),
        .palette_write(palette_write),
        .palette_address(palette_address),
        .palette_write_rgb(palette_write_rgb),
        .clear_request(clear_request),
        .swap_request(swap_request)
    );

    always #1 clk = ~clk;

    always_ff @(posedge clk) begin
        if (reset)
            accepted <= 0;
        else if (triangle_valid && triangle_ready)
            accepted <= accepted + 1;
    end

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        restart = 1'b0;
        triangle_ready = 1'b0;
        pipeline_idle = 1'b0;
        clear_busy = 1'b0;
        swap_busy = 1'b0;
        swap_done = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        wait (clear_request);
        clear_busy = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk);
        clear_busy = 1'b0;
        triangle_ready = 1'b1;

        wait (accepted == 24);
        wait (!command_valid);
        @(negedge clk);
        pipeline_idle = 1'b1;

        wait (swap_request);
        wait (!swap_request);
        @(negedge clk);
        swap_done = 1'b1;
        @(posedge clk);
        @(negedge clk);
        swap_done = 1'b0;
        pipeline_idle = 1'b0;

        wait (rotation_angle == 8'd1);
        wait (clear_request);

        if (accepted != 24)
            $fatal(1, "demo sent %0d triangles instead of 24", accepted);
        if (command_error)
            $fatal(1, "demo issued an invalid command");

        $display("cube_demo_tb PASS: command-driven frame sent 24 triangles and advanced the angle");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "cube_demo_tb timed out");
    end
endmodule
