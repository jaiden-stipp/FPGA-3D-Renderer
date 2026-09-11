`include "renderer_types.svh"

module graphics_stream_renderer (
    input logic clk,
    input logic reset,
    input logic restart,
    input logic [7:0] byte_data,
    input logic byte_valid,
    output logic byte_ready,
    output logic decoder_error,
    output logic command_error,
    output logic frame_done,
    output logic [31:0] frame_done_id,
    output renderer_stats_t frame_statistics,
    output logic [7:0] VGA_R,
    output logic [7:0] VGA_G,
    output logic [7:0] VGA_B,
    output logic VGA_CLK,
    output logic VGA_BLANK_N,
    output logic VGA_SYNC_N,
    output logic VGA_HS,
    output logic VGA_VS
);

    logic command_valid;
    logic command_ready;
    logic stream_reset;
    graphics_command_t command_data;

    assign stream_reset = reset || restart;

    graphics_command_stream_decoder decoder (
        .clk(clk),
        .reset(stream_reset),
        .byte_data(byte_data),
        .byte_valid(byte_valid),
        .byte_ready(byte_ready),
        .command_data(command_data),
        .command_valid(command_valid),
        .command_ready(command_ready),
        .decoder_error(decoder_error)
    );

    graphics_renderer_core renderer (
        .clk(clk),
        .reset(reset),
        .restart(restart),
        .command_data(command_data),
        .command_valid(command_valid),
        .command_ready(command_ready),
        .command_error(command_error),
        .frame_done(frame_done),
        .frame_done_id(frame_done_id),
        .frame_statistics(frame_statistics),
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
