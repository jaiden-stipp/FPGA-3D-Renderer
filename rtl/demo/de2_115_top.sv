// DE2-115 board wrapper for the rotating 3D cube demo.

`include "renderer_types.svh"

module de2_115_top (
    input  logic       CLOCK_50,
    input  logic [1:0] KEY,

    output logic [7:0] VGA_R,
    output logic [7:0] VGA_G,
    output logic [7:0] VGA_B,
    output logic       VGA_CLK,
    output logic       VGA_BLANK_N,
    output logic       VGA_SYNC_N,
    output logic       VGA_HS,
    output logic       VGA_VS
);

    logic reset;
    logic triangle_valid;
    logic triangle_ready;
    logic pipeline_idle;
    logic clear_request;
    logic clear_busy;
    logic swap_request;
    logic swap_busy;
    logic swap_done;
    logic [7:0] rotation_angle;
    logic key1_previous;
    logic demo_restart;
    triangle_3d_t triangle_data;

    assign reset = ~KEY[0];

    always_ff @(posedge CLOCK_50 or posedge reset) begin
        if (reset) begin
            key1_previous <= 1'b1;
        end else begin
            key1_previous <= KEY[1];
        end
    end

    assign demo_restart = key1_previous && !KEY[1];

    cube_demo demo (
        .clk(CLOCK_50),
        .reset(reset),
        .restart(demo_restart),
        .pipeline_ready(triangle_ready),
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

    graphics_pipeline pipeline (
        .CLOCK_50(CLOCK_50),
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
        .palette_write(1'b0),
        .palette_address(8'd0),
        .palette_write_rgb(24'h000000),
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
