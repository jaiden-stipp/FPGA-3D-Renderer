// Reusable DE2-115 3D triangle-to-VGA pipeline.

`include "renderer_types.svh"

module graphics_pipeline #(
    parameter int FPS_PERIOD_CYCLES = 50_000_000
) (
    input  logic        CLOCK_50,
    input  logic        reset,

    input  triangle_3d_t triangle_in_data,
    input  logic         triangle_in_valid,
    output logic         triangle_in_ready,

    input  logic [7:0] rotation_angle,

    input  logic         clear_request,
    output logic         clear_busy,
    input  logic         swap_request,
    output logic         swap_busy,
    output logic         swap_done,
    output logic         pipeline_idle,

    input  logic        palette_write,
    input  logic [7:0] palette_address,
    input  logic [23:0] palette_write_rgb,

    output logic [7:0] VGA_R,
    output logic [7:0] VGA_G,
    output logic [7:0] VGA_B,
    output logic        VGA_CLK,
    output logic        VGA_BLANK_N,
    output logic        VGA_SYNC_N,
    output logic        VGA_HS,
    output logic        VGA_VS
);

    logic pixel_clk;
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
    logic framebuffer_clear_busy;
    logic zbuffer_clear_busy;
    logic display_active;
    logic triangle_fifo_empty;
    logic triangle_fifo_full;
    logic transform_in_valid;
    logic transform_in_ready;
    logic transform_out_valid;
    logic transform_out_ready;
    logic transform_busy;
    logic renderer_triangle_ready;
    logic [25:0] fps_cycle_count;
    logic [7:0] fps_frame_count;
    logic [7:0] fps_value;
    triangle_3d_t transform_in_data;
    triangle_data_t transform_out_data;

    vga_clock_div2 clock_divider (
        .clk_50(CLOCK_50),
        .reset(reset),
        .pixel_clk(pixel_clk)
    );

    triangle_fifo #(
        .DEPTH(64)
    ) triangle_feed (
        .clk(CLOCK_50),
        .reset(reset),
        .in_data(triangle_in_data),
        .in_valid(triangle_in_valid),
        .in_ready(triangle_in_ready),
        .out_data(transform_in_data),
        .out_valid(transform_in_valid),
        .out_ready(transform_in_ready && !clear_request && !clear_busy &&
                   !swap_busy),
        .empty(triangle_fifo_empty),
        .full(triangle_fifo_full)
    );

    transform_3d_pipeline #(
        .SCREEN_WIDTH(320),
        .SCREEN_HEIGHT(240)
    ) transform (
        .clk(CLOCK_50),
        .reset(reset),
        .rotation_angle(rotation_angle),
        .in_data(transform_in_data),
        .in_valid(transform_in_valid && !clear_request && !clear_busy &&
                  !swap_busy),
        .in_ready(transform_in_ready),
        .out_data(transform_out_data),
        .out_valid(transform_out_valid),
        .out_ready(transform_out_ready),
        .busy(transform_busy)
    );

    renderer #(
        .FRAME_WIDTH(320),
        .FRAME_HEIGHT(240)
    ) rasterizer (
        .clk(CLOCK_50),
        .reset(reset),
        .triangle_data(transform_out_data),
        .triangle_valid(transform_out_valid && !clear_busy && !swap_busy),
        .triangle_ready(renderer_triangle_ready),
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
        .depth_write_value(depth_write_value)
    );

    zbuffer depth_memory (
        .reset(reset),
        .raster_clk(CLOCK_50),
        .clear_request(clear_request),
        .clear_busy(zbuffer_clear_busy),
        .read_enable(depth_read_enable),
        .read_x(depth_read_x),
        .read_y(depth_read_y),
        .read_depth(depth_read_value),
        .read_valid(depth_read_valid),
        .write_enable(depth_write_enable),
        .write_x(depth_write_x),
        .write_y(depth_write_y),
        .write_depth(depth_write_value)
    );

    assign clear_busy = framebuffer_clear_busy || zbuffer_clear_busy;

    assign transform_out_ready = renderer_triangle_ready && !clear_busy &&
                                 !swap_busy;
    assign pipeline_idle = triangle_fifo_empty && !transform_busy &&
                           renderer_triangle_ready && !clear_busy &&
                           !clear_request && !swap_busy;

    always_ff @(posedge CLOCK_50 or posedge reset) begin
        if (reset) begin
            fps_cycle_count <= '0;
            fps_frame_count <= '0;
            fps_value <= '0;
        end else if (fps_cycle_count == FPS_PERIOD_CYCLES - 1) begin
            fps_cycle_count <= '0;
            if (swap_done && (fps_frame_count != 8'hFF))
                fps_value <= fps_frame_count + 1'b1;
            else
                fps_value <= fps_frame_count;
            fps_frame_count <= '0;
        end else begin
            fps_cycle_count <= fps_cycle_count + 1'b1;
            if (swap_done && (fps_frame_count != 8'hFF))
                fps_frame_count <= fps_frame_count + 1'b1;
        end
    end

    vga_controller_640x480 #(
        .FRAME_WIDTH(320),
        .FRAME_HEIGHT(240)
    ) display (
        .reset(reset),
        .pixel_clk(pixel_clk),
        .raster_clk(CLOCK_50),
        .raster_write(raster_write),
        .raster_x(raster_x),
        .raster_y(raster_y),
        .raster_color(raster_color),
        .clear_request(clear_request),
        .clear_busy(framebuffer_clear_busy),
        .swap_request(swap_request),
        .swap_busy(swap_busy),
        .swap_done(swap_done),
        .palette_clk(CLOCK_50),
        .palette_write(palette_write),
        .palette_address(palette_address),
        .palette_write_rgb(palette_write_rgb),
        .fps_value(fps_value),
        .vga_r(VGA_R),
        .vga_g(VGA_G),
        .vga_b(VGA_B),
        .vga_hs(VGA_HS),
        .vga_vs(VGA_VS),
        .vga_active(display_active)
    );

    assign VGA_CLK = pixel_clk;
    assign VGA_BLANK_N = display_active;
    assign VGA_SYNC_N = 1'b0;

endmodule
