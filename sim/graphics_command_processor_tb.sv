`timescale 1ns/1ps

`include "renderer_types.svh"

module graphics_command_processor_tb;
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

    graphics_command_processor dut (
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

    task send_command(input graphics_command_opcode_t opcode);
        begin
            @(negedge clk);
            command_data.opcode = opcode;
            command_valid = 1'b1;
            wait (command_ready);
            @(posedge clk);
            @(negedge clk);
            command_valid = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        restart = 1'b0;
        command_valid = 1'b0;
        command_data = '0;
        triangle_ready = 1'b0;
        pipeline_idle = 1'b0;
        clear_busy = 1'b0;
        swap_busy = 1'b0;
        swap_done = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        command_data.argument = 24'h00005A;
        send_command(GFX_CMD_SET_ROTATION);
        if (rotation_angle != 8'h5A)
            $fatal(1, "rotation command was not applied");

        command_data.argument = 32'h07A1B2C3;
        @(negedge clk);
        command_data.opcode = GFX_CMD_SET_PALETTE;
        command_valid = 1'b1;
        #1;
        if (!palette_write || palette_address != 8'h07 ||
            palette_write_rgb != 24'hA1B2C3)
            $fatal(1, "palette command was not applied");
        @(negedge clk);
        command_valid = 1'b0;

        fork
            send_command(GFX_CMD_BEGIN_FRAME);
            begin
                wait (clear_request);
                clear_busy = 1'b1;
                repeat (3) @(posedge clk);
                @(negedge clk);
                clear_busy = 1'b0;
            end
        join

        command_data.triangle = '0;
        command_data.triangle.x0 = 16'sh0123;
        command_data.triangle.color = 8'h2F;
        @(negedge clk);
        command_data.opcode = GFX_CMD_DRAW_TRIANGLE;
        command_valid = 1'b1;
        repeat (2) @(posedge clk);
        if (command_ready)
            $fatal(1, "draw command ignored downstream backpressure");
        if (!triangle_valid)
            $fatal(1, "draw command was not presented downstream");

        @(negedge clk);
        triangle_ready = 1'b1;
        @(posedge clk);
        if (!triangle_valid || triangle_data.x0 != 16'sh0123 || triangle_data.color != 8'h2F)
            $fatal(1, "draw command payload was corrupted");
        @(negedge clk);
        command_valid = 1'b0;
        triangle_ready = 1'b0;

        send_command(GFX_CMD_END_FRAME);
        repeat (2) @(posedge clk);
        if (swap_request)
            $fatal(1, "page swap started before the pipeline drained");

        @(negedge clk);
        pipeline_idle = 1'b1;
        wait (swap_request);
        swap_busy = 1'b1;
        wait (!swap_request);
        @(negedge clk);
        swap_busy = 1'b0;
        swap_done = 1'b1;
        @(posedge clk);
        @(negedge clk);
        swap_done = 1'b0;
        pipeline_idle = 1'b0;

        wait (frame_done);
        @(posedge clk);

        send_command(GFX_CMD_DRAW_TRIANGLE);
        if (!command_error)
            $fatal(1, "out-of-frame draw did not report an error");

        $display("graphics_command_processor_tb PASS");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "graphics_command_processor_tb timed out");
    end
endmodule
