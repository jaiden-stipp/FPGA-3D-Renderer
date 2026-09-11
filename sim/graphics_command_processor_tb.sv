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
    logic [31:0] frame_done_id;
    logic frame_start;
    logic triangle_ready;
    logic pipeline_idle;
    logic clear_busy;
    logic swap_busy;
    logic swap_done;
    logic triangle_valid;
    logic mesh_define_write;
    logic mesh_vertex_write;
    logic mesh_index_write;
    logic [7:0] mesh_handle;
    logic [15:0] mesh_element;
    logic [15:0] mesh_vertex_count;
    logic [15:0] mesh_triangle_count;
    logic [7:0] mesh_index0;
    logic [7:0] mesh_index1;
    logic [7:0] mesh_index2;
    logic [7:0] mesh_color;
    logic signed [15:0] mesh_vertex_x;
    logic signed [15:0] mesh_vertex_y;
    logic signed [15:0] mesh_vertex_z;
    logic mesh_upload_error;
    logic mesh_draw_valid;
    logic mesh_draw_ready;
    model_matrix_3x4_t mesh_draw_matrix;
    logic mesh_draw_done;
    logic mesh_draw_error;
    model_matrix_3x4_t view_matrix;
    projection_config_t projection;
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
        .frame_done_id(frame_done_id),
        .frame_start(frame_start),
        .triangle_ready(triangle_ready),
        .pipeline_idle(pipeline_idle),
        .clear_busy(clear_busy),
        .swap_busy(swap_busy),
        .swap_done(swap_done),
        .triangle_data(triangle_data),
        .triangle_valid(triangle_valid),
        .mesh_define_write(mesh_define_write),
        .mesh_vertex_write(mesh_vertex_write),
        .mesh_index_write(mesh_index_write),
        .mesh_handle(mesh_handle),
        .mesh_element(mesh_element),
        .mesh_vertex_count(mesh_vertex_count),
        .mesh_triangle_count(mesh_triangle_count),
        .mesh_index0(mesh_index0),
        .mesh_index1(mesh_index1),
        .mesh_index2(mesh_index2),
        .mesh_color(mesh_color),
        .mesh_vertex_x(mesh_vertex_x),
        .mesh_vertex_y(mesh_vertex_y),
        .mesh_vertex_z(mesh_vertex_z),
        .mesh_upload_error(mesh_upload_error),
        .mesh_draw_valid(mesh_draw_valid),
        .mesh_draw_ready(mesh_draw_ready),
        .mesh_draw_matrix(mesh_draw_matrix),
        .mesh_draw_done(mesh_draw_done),
        .mesh_draw_error(mesh_draw_error),
        .view_matrix(view_matrix),
        .projection(projection),
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
        mesh_upload_error = 1'b0;
        mesh_draw_ready = 1'b1;
        mesh_draw_done = 1'b0;
        mesh_draw_error = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        command_data.payload = '0;
        command_data.payload[191:176] = 16'sh0100;
        command_data.payload[111:96] = 16'sh0100;
        command_data.payload[31:16] = 16'sh0100;
        command_data.payload[15:0] = 16'sh0500;
        send_command(GFX_CMD_SET_VIEW_MATRIX);
        if (view_matrix.m00 != 16'sh0100 || view_matrix.m23 != 16'sh0500)
            $fatal(1, "view command was not applied");

        command_data.payload[79:0] = {16'sd256, 16'sd256, 16'sd160,
                                     16'sd120, 16'sd512};
        send_command(GFX_CMD_SET_PROJECTION);
        if (projection.focal_x != 16'sd256 || projection.near_z != 16'sd512)
            $fatal(1, "projection command was not applied");

        `GFX_ARGUMENT(command_data) = 32'h07A1B2C3;
        @(negedge clk);
        command_data.opcode = GFX_CMD_SET_PALETTE;
        command_valid = 1'b1;
        #1;
        if (!palette_write || palette_address != 8'h07 ||
            palette_write_rgb != 24'hA1B2C3)
            $fatal(1, "palette command was not applied");
        @(negedge clk);
        command_valid = 1'b0;

        `GFX_MESH_HANDLE(command_data) = 8'd2;
        `GFX_MESH_VERTEX_COUNT(command_data) = 16'd3;
        `GFX_MESH_TRIANGLE_COUNT(command_data) = 16'd1;
        @(negedge clk);
        command_data.opcode = GFX_CMD_DEFINE_MESH;
        command_valid = 1'b1;
        #1;
        if (!mesh_define_write || mesh_handle != 8'd2 ||
            mesh_vertex_count != 16'd3 || mesh_triangle_count != 16'd1)
            $fatal(1, "mesh definition command was not forwarded");
        @(negedge clk);
        command_valid = 1'b0;

        `GFX_ARGUMENT(command_data) = 32'h12345678;
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

        `GFX_TRIANGLE(command_data) = '0;
        command_data.payload[151:136] = 16'sh0123;
        command_data.payload[7:0] = 8'h2F;
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

        `GFX_DRAW_MESH_HANDLE(command_data) = 8'd2;
        `GFX_MODEL_MATRIX(command_data) = '0;
        command_data.payload[191:176] = 16'sh0100;
        command_data.payload[111:96] = 16'sh0100;
        command_data.payload[31:16] = 16'sh0100;
        send_command(GFX_CMD_DRAW_MESH);
        if (command_ready)
            $fatal(1, "processor accepted commands while indexed draw was active");
        @(negedge clk);
        mesh_draw_done = 1'b1;
        @(posedge clk);
        @(negedge clk);
        mesh_draw_done = 1'b0;
        wait (command_ready);

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
        if (frame_done_id != 32'h12345678)
            $fatal(1, "displayed frame ID was not preserved");
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
