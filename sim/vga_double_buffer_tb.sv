`timescale 1ns/1ps

module framebuffer #(
    parameter int FRAME_WIDTH = 320,
    parameter int FRAME_HEIGHT = 240
) (
    input logic reset,
    input logic raster_clk,
    input logic raster_write,
    input logic [9:0] raster_x,
    input logic [8:0] raster_y,
    input logic [7:0] raster_color,
    input logic clear_request,
    output logic clear_busy,
    input logic display_clk,
    input logic display_read_enable,
    input logic [9:0] display_x,
    input logic [8:0] display_y,
    output logic [7:0] display_pixel,
    output logic display_pixel_valid
);

    assign clear_busy = 1'b0;
    assign display_pixel = 8'h00;

    always_ff @(posedge display_clk or posedge reset) begin
        if (reset)
            display_pixel_valid <= 1'b0;
        else
            display_pixel_valid <= display_read_enable;
    end

endmodule

module palette_256x24 (
    input logic clock_a,
    input logic [7:0] address_a,
    input logic [23:0] data_a,
    input logic wren_a,
    input logic clock_b,
    input logic [7:0] address_b,
    input logic rden_b,
    output logic [23:0] q_b
);

    assign q_b = 24'h000000;

endmodule

module vga_double_buffer_tb;
    logic raster_clk;
    logic pixel_clk;
    logic reset;
    logic swap_request;
    logic swap_busy;
    logic swap_done;
    logic [7:0] fps_value;
    logic [7:0] vga_r;
    logic [7:0] vga_g;
    logic [7:0] vga_b;
    logic vga_hs;
    logic vga_vs;
    logic vga_active;

    vga_controller_640x480 dut (
        .reset(reset),
        .pixel_clk(pixel_clk),
        .raster_clk(raster_clk),
        .raster_write(1'b0),
        .raster_x(10'd0),
        .raster_y(9'd0),
        .raster_color(8'h00),
        .clear_request(1'b0),
        .clear_busy(),
        .swap_request(swap_request),
        .swap_busy(swap_busy),
        .swap_done(swap_done),
        .palette_clk(raster_clk),
        .palette_write(1'b0),
        .palette_address(8'd0),
        .palette_write_rgb(24'h000000),
        .fps_value(fps_value),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hs(vga_hs),
        .vga_vs(vga_vs),
        .vga_active(vga_active)
    );

    always #5 raster_clk = ~raster_clk;
    always #10 pixel_clk = ~pixel_clk;

    initial begin
        raster_clk = 1'b0;
        pixel_clk = 1'b0;
        reset = 1'b1;
        swap_request = 1'b0;
        fps_value = 8'd42;

        repeat (3) @(posedge raster_clk);
        reset = 1'b0;
        repeat (5) @(posedge raster_clk);

        wait (dut.fps_text_pixel);
        #1;
        if ((vga_r != 8'hFF) || (vga_g != 8'hFF) || (vga_b != 8'hFF))
            $fatal(1, "FPS overlay pixel was not white");

        @(negedge raster_clk);
        swap_request = 1'b1;
        @(negedge raster_clk);
        swap_request = 1'b0;

        wait (swap_busy);
        if (dut.front_page_pixel != 1'b0)
            $fatal(1, "page swapped before vertical blank");

        wait (dut.front_page_pixel == 1'b1);
        if (dut.scan_y != 10'd480)
            $fatal(1, "page did not swap at vertical blank");

        wait (swap_done);
        if (dut.write_page_raster != 1'b0)
            $fatal(1, "raster page did not follow the display page swap");

        $display("vga_double_buffer_tb PASS: FPS overlay and page swap work");
        $finish;
    end
endmodule
