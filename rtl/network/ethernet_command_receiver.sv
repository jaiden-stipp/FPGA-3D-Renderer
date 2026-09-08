`include "renderer_types.svh"

module ethernet_command_receiver (
    input logic system_clk,
    input logic reset,
    input logic mii_rx_clk,
    input logic [3:0] mii_rx_data,
    input logic mii_rx_dv,
    input logic mii_rx_er,
    input logic mii_tx_clk,
    output logic [3:0] mii_tx_data,
    output logic mii_tx_en,
    output logic mii_tx_er,
    output graphics_command_t command_data,
    output logic command_valid,
    input logic command_ready,
    input logic command_error,
    input logic frame_done,
    input logic [31:0] frame_done_id,
    output logic decoder_error,
    output logic receive_overflow,
    output logic packet_seen
);

    localparam logic [47:0] LOCAL_MAC = 48'h020000000001;
    localparam logic [31:0] LOCAL_IP = 32'hC0A80702;
    localparam logic [15:0] LOCAL_PORT = 16'd4000;

    logic [7:0] payload_data;
    logic payload_valid;
    logic payload_ready;
    logic payload_overflow;
    logic packet_received;
    logic arp_request;
    logic [47:0] arp_sender_mac;
    logic [31:0] arp_sender_ip;
    logic arp_request_toggle;
    logic [47:0] arp_request_mac;
    logic [31:0] arp_request_ip;
    logic [7:0] fifo_data;
    logic fifo_valid;
    logic fifo_ready;
    logic [11:0] fifo_free;
    logic [11:0] fifo_free_sync1;
    logic [11:0] fifo_free_sync2;
    logic packet_status;
    logic [47:0] packet_sender_mac;
    logic [31:0] packet_sender_ip;
    logic [15:0] packet_sender_port;
    logic [31:0] packet_frame_id;
    logic [15:0] packet_sequence;
    logic [31:0] packet_status_flags;
    logic [11:0] packet_fifo_free;
    logic packet_status_toggle;
    logic [47:0] packet_status_mac;
    logic [31:0] packet_status_ip;
    logic [15:0] packet_status_port;
    logic [31:0] packet_status_frame_id;
    logic [15:0] packet_status_sequence;
    logic [31:0] packet_status_result;
    logic [11:0] packet_status_free;
    logic frame_status_toggle;
    logic [31:0] frame_status_id;
    logic [31:0] frame_status_flags;
    logic [11:0] frame_status_free;
    logic [31:0] active_error_flags;
    logic packet_toggle;
    logic packet_sync1;
    logic packet_sync2;
    logic packet_previous;
    logic overflow_toggle;
    logic overflow_sync1;
    logic overflow_sync2;
    logic overflow_previous;

    mii_udp_receiver #(
        .LOCAL_MAC(LOCAL_MAC),
        .LOCAL_IP(LOCAL_IP),
        .LOCAL_PORT(LOCAL_PORT)
    ) receiver (
        .rx_clk(mii_rx_clk),
        .reset(reset),
        .rx_data(mii_rx_data),
        .rx_dv(mii_rx_dv),
        .rx_er(mii_rx_er),
        .fifo_free(fifo_free),
        .payload_data(payload_data),
        .payload_valid(payload_valid),
        .payload_ready(payload_ready),
        .payload_overflow(payload_overflow),
        .packet_received(packet_received),
        .packet_status(packet_status),
        .packet_sender_mac(packet_sender_mac),
        .packet_sender_ip(packet_sender_ip),
        .packet_sender_port(packet_sender_port),
        .packet_frame_id(packet_frame_id),
        .packet_sequence(packet_sequence),
        .packet_status_flags(packet_status_flags),
        .packet_fifo_free(packet_fifo_free),
        .arp_request(arp_request),
        .arp_sender_mac(arp_sender_mac),
        .arp_sender_ip(arp_sender_ip)
    );

    always_ff @(posedge mii_rx_clk or posedge reset) begin
        if (reset) begin
            arp_request_toggle <= 1'b0;
            arp_request_mac <= '0;
            arp_request_ip <= '0;
            packet_status_toggle <= 1'b0;
            packet_status_mac <= '0;
            packet_status_ip <= '0;
            packet_status_port <= '0;
            packet_status_frame_id <= '0;
            packet_status_sequence <= '0;
            packet_status_result <= '0;
            packet_status_free <= '0;
            packet_toggle <= 1'b0;
            overflow_toggle <= 1'b0;
        end else begin
            if (arp_request) begin
                arp_request_mac <= arp_sender_mac;
                arp_request_ip <= arp_sender_ip;
                arp_request_toggle <= ~arp_request_toggle;
            end
            if (packet_status) begin
                packet_status_mac <= packet_sender_mac;
                packet_status_ip <= packet_sender_ip;
                packet_status_port <= packet_sender_port;
                packet_status_frame_id <= packet_frame_id;
                packet_status_sequence <= packet_sequence;
                packet_status_result <= packet_status_flags;
                packet_status_free <= packet_fifo_free;
                packet_status_toggle <= ~packet_status_toggle;
            end
            if (packet_received)
                packet_toggle <= ~packet_toggle;
            if (payload_overflow)
                overflow_toggle <= ~overflow_toggle;
        end
    end

    mii_response_transmitter #(
        .LOCAL_MAC(LOCAL_MAC),
        .LOCAL_IP(LOCAL_IP),
        .LOCAL_PORT(LOCAL_PORT)
    ) response_transmitter (
        .tx_clk(mii_tx_clk),
        .reset(reset),
        .arp_toggle(arp_request_toggle),
        .arp_mac(arp_request_mac),
        .arp_ip(arp_request_ip),
        .packet_toggle(packet_status_toggle),
        .packet_mac(packet_status_mac),
        .packet_ip(packet_status_ip),
        .packet_port(packet_status_port),
        .packet_frame_id(packet_status_frame_id),
        .packet_sequence(packet_status_sequence),
        .packet_fifo_free(packet_status_free),
        .packet_flags(packet_status_result),
        .frame_toggle(frame_status_toggle),
        .frame_id(frame_status_id),
        .frame_fifo_free(frame_status_free),
        .frame_flags(frame_status_flags),
        .tx_data(mii_tx_data),
        .tx_en(mii_tx_en),
        .tx_er(mii_tx_er)
    );

    async_byte_fifo #(
        .ADDRESS_WIDTH(11)
    ) receive_fifo (
        .write_clk(mii_rx_clk),
        .write_reset(reset),
        .write_data(payload_data),
        .write_valid(payload_valid),
        .write_ready(payload_ready),
        .write_free(fifo_free),
        .read_clk(system_clk),
        .read_reset(reset),
        .read_data(fifo_data),
        .read_valid(fifo_valid),
        .read_ready(fifo_ready)
    );

    graphics_command_stream_decoder decoder (
        .clk(system_clk),
        .reset(reset),
        .byte_data(fifo_data),
        .byte_valid(fifo_valid),
        .byte_ready(fifo_ready),
        .command_data(command_data),
        .command_valid(command_valid),
        .command_ready(command_ready),
        .decoder_error(decoder_error)
    );

    always_ff @(posedge system_clk or posedge reset) begin
        if (reset) begin
            packet_sync1 <= 1'b0;
            packet_sync2 <= 1'b0;
            packet_previous <= 1'b0;
            overflow_sync1 <= 1'b0;
            overflow_sync2 <= 1'b0;
            overflow_previous <= 1'b0;
            packet_seen <= 1'b0;
            receive_overflow <= 1'b0;
            fifo_free_sync1 <= '0;
            fifo_free_sync2 <= '0;
            frame_status_toggle <= 1'b0;
            frame_status_id <= '0;
            frame_status_flags <= '0;
            frame_status_free <= '0;
            active_error_flags <= '0;
        end else begin
            fifo_free_sync1 <= fifo_free;
            fifo_free_sync2 <= fifo_free_sync1;
            packet_sync1 <= packet_toggle;
            packet_sync2 <= packet_sync1;
            packet_previous <= packet_sync2;
            overflow_sync1 <= overflow_toggle;
            overflow_sync2 <= overflow_sync1;
            overflow_previous <= overflow_sync2;
            if (packet_sync2 != packet_previous)
                packet_seen <= 1'b1;
            if (overflow_sync2 != overflow_previous)
                receive_overflow <= 1'b1;
            if (decoder_error)
                active_error_flags[8] <= 1'b1;
            if (command_error)
                active_error_flags[9] <= 1'b1;
            if (overflow_sync2 != overflow_previous)
                active_error_flags[10] <= 1'b1;
            if (frame_done) begin
                frame_status_id <= frame_done_id;
                frame_status_flags <= active_error_flags;
                frame_status_free <= fifo_free_sync2;
                frame_status_toggle <= ~frame_status_toggle;
                active_error_flags <= '0;
            end
        end
    end

endmodule
