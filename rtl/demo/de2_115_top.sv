`include "renderer_types.svh"

module de2_115_top (
    input logic CLOCK_50,
    input logic [1:0] KEY,
    input logic [0:0] SW,
    input logic ENET0_RX_CLK,
    input logic [3:0] ENET0_RX_DATA,
    input logic ENET0_RX_DV,
    input logic ENET0_RX_ER,
    input logic ENET0_TX_CLK,
    input logic ENET0_LINK100,
    output logic [3:0] ENET0_TX_DATA,
    output logic ENET0_TX_EN,
    output logic ENET0_TX_ER,
    output logic ENET0_RST_N,
    output logic [3:0] LEDG,
    output logic [7:0] VGA_R,
    output logic [7:0] VGA_G,
    output logic [7:0] VGA_B,
    output logic VGA_CLK,
    output logic VGA_BLANK_N,
    output logic VGA_SYNC_N,
    output logic VGA_HS,
    output logic VGA_VS
);

    logic reset;
    logic command_valid;
    logic command_ready;
    logic command_error;
    logic frame_done;
    logic key1_previous;
    logic demo_restart;
    logic switch_sync1;
    logic network_mode;
    logic network_mode_previous;
    logic mode_changed;
    logic demo_valid;
    logic demo_ready;
    logic network_valid;
    logic network_ready;
    logic network_decoder_error;
    logic network_overflow;
    logic network_packet_seen;
    logic network_error_seen;
    logic [19:0] phy_reset_counter;
    graphics_command_t command_data;
    graphics_command_t demo_command;
    graphics_command_t network_command;

    assign reset = ~KEY[0];

    always_ff @(posedge CLOCK_50 or posedge reset) begin
        if (reset) begin
            key1_previous <= 1'b1;
            switch_sync1 <= 1'b0;
            network_mode <= 1'b0;
            network_mode_previous <= 1'b0;
            network_error_seen <= 1'b0;
            phy_reset_counter <= '0;
        end else begin
            key1_previous <= KEY[1];
            switch_sync1 <= SW[0];
            network_mode <= switch_sync1;
            network_mode_previous <= network_mode;
            if (mode_changed)
                network_error_seen <= 1'b0;
            else if (network_decoder_error || command_error || network_overflow)
                network_error_seen <= 1'b1;
            if (!(&phy_reset_counter))
                phy_reset_counter <= phy_reset_counter + 1'b1;
        end
    end

    assign mode_changed = network_mode != network_mode_previous;
    assign demo_restart = (key1_previous && !KEY[1]) || mode_changed;
    assign ENET0_RST_N = &phy_reset_counter;
    assign command_data = network_mode ? network_command : demo_command;
    assign command_valid = network_mode ? network_valid : demo_valid;
    assign network_ready = network_mode && command_ready;
    assign demo_ready = !network_mode && command_ready;
    assign LEDG[0] = network_mode;
    assign LEDG[1] = network_mode && ENET0_LINK100;
    assign LEDG[2] = network_mode && network_packet_seen;
    assign LEDG[3] = network_mode && network_error_seen;

    cube_demo demo (
        .clk(CLOCK_50),
        .reset(reset || network_mode),
        .restart(demo_restart),
        .command_ready(demo_ready),
        .frame_done(frame_done),
        .command_valid(demo_valid),
        .command_data(demo_command)
    );

    ethernet_command_receiver ethernet (
        .system_clk(CLOCK_50),
        .reset(reset || !network_mode),
        .mii_rx_clk(ENET0_RX_CLK),
        .mii_rx_data(ENET0_RX_DATA),
        .mii_rx_dv(ENET0_RX_DV),
        .mii_rx_er(ENET0_RX_ER),
        .mii_tx_clk(ENET0_TX_CLK),
        .mii_tx_data(ENET0_TX_DATA),
        .mii_tx_en(ENET0_TX_EN),
        .mii_tx_er(ENET0_TX_ER),
        .command_data(network_command),
        .command_valid(network_valid),
        .command_ready(network_ready),
        .decoder_error(network_decoder_error),
        .receive_overflow(network_overflow),
        .packet_seen(network_packet_seen)
    );

    graphics_renderer_core renderer (
        .clk(CLOCK_50),
        .reset(reset),
        .restart(demo_restart),
        .command_data(command_data),
        .command_valid(command_valid),
        .command_ready(command_ready),
        .command_error(command_error),
        .frame_done(frame_done),
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
