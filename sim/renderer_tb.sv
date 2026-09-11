`timescale 1ns/1ps
`include "renderer_types.svh"

module renderer_tb;
    logic clk;
    logic reset;
    triangle_data_t triangle_data;
    logic triangle_valid;
    logic triangle_ready;
    logic raster_write;
    logic [9:0] raster_x;
    logic [8:0] raster_y;
    logic [7:0] raster_color;
    logic depth_read_enable;
    logic [9:0] depth_read_x;
    logic [8:0] depth_read_y;
    logic [7:0] depth_read_value;
    logic depth_read_valid;
    logic depth_write_enable;
    logic [9:0] depth_write_x;
    logic [8:0] depth_write_y;
    logic [7:0] depth_write_value;
    logic renderer_busy;
    logic bounding_box_pixel;
    logic pixel_inside;
    logic depth_rejected;
    logic pixel_written;
    logic [7:0] depth_memory [0:255];
    integer write_count;
    integer bounding_box_count;
    integer inside_count;
    integer rejected_count;
    integer index;

    renderer #(
        .FRAME_WIDTH(16),
        .FRAME_HEIGHT(16)
    ) dut (
        .clk(clk),
        .reset(reset),
        .triangle_data(triangle_data),
        .triangle_valid(triangle_valid),
        .triangle_ready(triangle_ready),
        .raster_write(raster_write),
        .raster_x(raster_x),
        .raster_y(raster_y),
        .raster_color(raster_color),
        .depth_read_enable(depth_read_enable),
        .depth_read_x(depth_read_x),
        .depth_read_y(depth_read_y),
        .depth_read_value(depth_read_value),
        .depth_read_valid(depth_read_valid),
        .depth_write_enable(depth_write_enable),
        .depth_write_x(depth_write_x),
        .depth_write_y(depth_write_y),
        .depth_write_value(depth_write_value),
        .busy(renderer_busy),
        .bounding_box_pixel(bounding_box_pixel),
        .pixel_inside(pixel_inside),
        .depth_rejected(depth_rejected),
        .pixel_written(pixel_written)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (reset) begin
            depth_read_valid <= 1'b0;
            depth_read_value <= 8'h00;
            for (index = 0; index < 256; index = index + 1)
                depth_memory[index] <= 8'h00;
        end else begin
            depth_read_valid <= depth_read_enable;
            if (depth_read_enable)
                depth_read_value <= depth_memory[depth_read_y * 16 + depth_read_x];
            if (depth_write_enable)
                depth_memory[depth_write_y * 16 + depth_write_x] <= depth_write_value;
        end
    end

    always @(posedge clk) begin
        if (bounding_box_pixel)
            bounding_box_count = bounding_box_count + 1;
        if (pixel_inside)
            inside_count = inside_count + 1;
        if (depth_rejected)
            rejected_count = rejected_count + 1;
        if (raster_write) begin
            write_count = write_count + 1;
            if ((raster_x < 1) || (raster_x > 4) ||
                (raster_y < 1) || (raster_y > 4)) begin
                $fatal(1, "out-of-bounds write at (%0d, %0d)",
                       raster_x, raster_y);
            end
        end
    end

    task automatic submit_triangle(
        input logic [7:0] depth0,
        input logic [7:0] depth1,
        input logic [7:0] depth2,
        input logic [7:0] color
    );
        begin
            while (!triangle_ready)
                @(posedge clk);
            @(negedge clk);
            triangle_data.x0 = 10'd1;
            triangle_data.y0 = 9'd1;
            triangle_data.z0 = depth0;
            triangle_data.x1 = 10'd4;
            triangle_data.y1 = 9'd1;
            triangle_data.z1 = depth1;
            triangle_data.x2 = 10'd1;
            triangle_data.y2 = 9'd4;
            triangle_data.z2 = depth2;
            triangle_data.color = color;
            triangle_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            triangle_valid = 1'b0;
            while (!triangle_ready)
                @(posedge clk);
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        triangle_valid = 1'b0;
        triangle_data = '0;
        write_count = 0;
        bounding_box_count = 0;
        inside_count = 0;
        rejected_count = 0;

        repeat (2) @(posedge clk);
        reset = 1'b0;

        submit_triangle(8'd64, 8'd94, 8'd124, 8'hA5);
        if (write_count != 10)
            $fatal(1, "expected 10 initial pixels, got %0d", write_count);
        if ((depth_memory[17] != 8'd64) || (depth_memory[20] != 8'd94) ||
            (depth_memory[65] != 8'd124))
            $fatal(1, "depth interpolation produced incorrect vertex depths");

        submit_triangle(8'd32, 8'd32, 8'd32, 8'h33);
        if (write_count != 10)
            $fatal(1, "farther triangle passed the Z test");

        submit_triangle(8'd200, 8'd200, 8'd200, 8'hC3);
        if (write_count != 20)
            $fatal(1, "closer triangle did not replace every pixel");
        if (depth_memory[17] != 8'd200)
            $fatal(1, "depth buffer did not retain the closer depth");
        if (bounding_box_count != 48 || inside_count != 30 ||
            rejected_count != 10)
            $fatal(1, "raster event counters were incorrect");

        $display("renderer_tb PASS: Z-tested triangle writes work");
        $finish;
    end
endmodule
