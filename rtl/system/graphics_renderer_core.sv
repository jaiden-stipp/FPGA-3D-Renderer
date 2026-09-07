`include "renderer_types.svh"

module graphics_renderer_core (
    input logic clk,
    input logic reset,
    input logic restart,
    input graphics_command_t command_data,
    input logic command_valid,
    output logic command_ready,
    output logic command_error,
    output logic frame_done,
    output logic [7:0] VGA_R,
    output logic [7:0] VGA_G,
    output logic [7:0] VGA_B,
    output logic VGA_CLK,
    output logic VGA_BLANK_N,
    output logic VGA_SYNC_N,
    output logic VGA_HS,
    output logic VGA_VS
);

    logic triangle_valid;
    logic triangle_ready;
    logic pipeline_idle;
    logic clear_request;
    logic clear_busy;
    logic swap_request;
    logic swap_busy;
    logic swap_done;
    logic [7:0] rotation_angle;
    logic palette_write;
    logic [7:0] palette_address;
    logic [23:0] palette_write_rgb;
    triangle_3d_t triangle_data;

    graphics_command_processor command_processor (
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

    graphics_pipeline pipeline (
        .CLOCK_50(clk),
        .reset(reset),
        .triangle_in_data(triangle_data),
        .triangle_in_valid(triangle_valid),
        .triangle_in_ready(triangle_ready),
        .rotation_angle(rotation_angle),
        .clear_request(clear_request),
        .clear_busy(clear_busy),
        .swap_request(swap_request),
        .swap_busy(swap_busy),
        .swap_done(swap_done),
        .pipeline_idle(pipeline_idle),
        .palette_write(palette_write),
        .palette_address(palette_address),
        .palette_write_rgb(palette_write_rgb),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_CLK(VGA_CLK),
        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS)
    );

endmodule
