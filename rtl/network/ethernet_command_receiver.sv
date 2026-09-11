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
    input renderer_stats_t frame_statistics,
    output logic decoder_error,
    output logic receive_overflow,
    output logic packet_seen
);

    localparam logic [47:0] LOCAL_MAC = 48'h020000000001;
    localparam logic [31:0] LOCAL_IP = 32'hC0A80702;
    localparam logic [15:0] LOCAL_PORT = `GFX_DEFAULT_UDP_PORT;

    logic [7:0] payload_data;
    logic payload_valid;
    logic payload_ready;
    logic payload_overflow;
    logic packet_received;
    logic arp_request;
    logic [47:0] arp_sender_mac;
    logic [31:0] arp_sender_ip;
    logic [79:0] arp_queue_write_data;
    logic arp_queue_write_ready;
    logic [79:0] arp_queue_read_data;
    logic arp_queue_read_valid;
    logic arp_queue_read_ready;
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
    logic [187:0] packet_queue_write_data;
    logic packet_queue_write_ready;
    logic [187:0] packet_queue_read_data;
    logic packet_queue_read_valid;
    logic packet_queue_read_ready;
    localparam int FRAME_QUEUE_WIDTH = 76 + $bits(renderer_stats_t);
    logic [FRAME_QUEUE_WIDTH-1:0] frame_queue_write_data;
    logic frame_queue_write_ready;
    logic [FRAME_QUEUE_WIDTH-1:0] frame_queue_read_data;
    logic frame_queue_read_valid;
    logic frame_queue_read_ready;
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

    assign arp_queue_write_data = {arp_sender_mac, arp_sender_ip};
    assign packet_queue_write_data = {
        packet_sender_mac, packet_sender_ip, packet_sender_port,
        packet_frame_id, packet_sequence, packet_fifo_free,
        packet_status_flags
    };
    assign frame_queue_write_data = {
        frame_done_id, fifo_free_sync2, active_error_flags, frame_statistics
    };

    always_ff @(posedge mii_rx_clk or posedge reset) begin
        if (reset) begin
            packet_toggle <= 1'b0;
            overflow_toggle <= 1'b0;
        end else begin
            if (packet_received)
                packet_toggle <= ~packet_toggle;
            if (payload_overflow || (arp_request && !arp_queue_write_ready) ||
                (packet_status && !packet_queue_write_ready))
                overflow_toggle <= ~overflow_toggle;
        end
    end

    async_fifo #(.WIDTH(80), .ADDRESS_WIDTH(2)) arp_response_queue (
        .write_clk(mii_rx_clk),
        .write_reset(reset),
        .write_data(arp_queue_write_data),
        .write_valid(arp_request),
        .write_ready(arp_queue_write_ready),
        .write_free(),
        .read_clk(mii_tx_clk),
        .read_reset(reset),
        .read_data(arp_queue_read_data),
        .read_valid(arp_queue_read_valid),
        .read_ready(arp_queue_read_ready)
    );

    async_fifo #(.WIDTH(188), .ADDRESS_WIDTH(2)) packet_response_queue (
        .write_clk(mii_rx_clk),
        .write_reset(reset),
        .write_data(packet_queue_write_data),
        .write_valid(packet_status),
        .write_ready(packet_queue_write_ready),
        .write_free(),
        .read_clk(mii_tx_clk),
        .read_reset(reset),
        .read_data(packet_queue_read_data),
        .read_valid(packet_queue_read_valid),
        .read_ready(packet_queue_read_ready)
    );

    async_fifo #(.WIDTH(FRAME_QUEUE_WIDTH), .ADDRESS_WIDTH(2)) frame_response_queue (
        .write_clk(system_clk),
        .write_reset(reset),
        .write_data(frame_queue_write_data),
        .write_valid(frame_done),
        .write_ready(frame_queue_write_ready),
        .write_free(),
        .read_clk(mii_tx_clk),
        .read_reset(reset),
        .read_data(frame_queue_read_data),
        .read_valid(frame_queue_read_valid),
        .read_ready(frame_queue_read_ready)
    );

    mii_response_transmitter #(
        .LOCAL_MAC(LOCAL_MAC),
        .LOCAL_IP(LOCAL_IP),
        .LOCAL_PORT(LOCAL_PORT)
    ) response_transmitter (
        .tx_clk(mii_tx_clk),
        .reset(reset),
        .arp_valid(arp_queue_read_valid),
        .arp_ready(arp_queue_read_ready),
        .arp_mac(arp_queue_read_data[79:32]),
        .arp_ip(arp_queue_read_data[31:0]),
        .packet_valid(packet_queue_read_valid),
        .packet_ready(packet_queue_read_ready),
        .packet_mac(packet_queue_read_data[187:140]),
        .packet_ip(packet_queue_read_data[139:108]),
        .packet_port(packet_queue_read_data[107:92]),
        .packet_frame_id(packet_queue_read_data[91:60]),
        .packet_sequence(packet_queue_read_data[59:44]),
        .packet_fifo_free(packet_queue_read_data[43:32]),
        .packet_flags(packet_queue_read_data[31:0]),
        .frame_valid(frame_queue_read_valid),
        .frame_ready(frame_queue_read_ready),
        .frame_id(frame_queue_read_data[FRAME_QUEUE_WIDTH-1 -: 32]),
        .frame_fifo_free(frame_queue_read_data[FRAME_QUEUE_WIDTH-33 -: 12]),
        .frame_flags(frame_queue_read_data[FRAME_QUEUE_WIDTH-45 -: 32]),
        .frame_statistics(frame_queue_read_data[$bits(renderer_stats_t)-1:0]),
        .tx_data(mii_tx_data),
        .tx_en(mii_tx_en),
        .tx_er(mii_tx_er)
    );

    async_byte_fifo #(
        .ADDRESS_WIDTH($clog2(`GFX_RECEIVE_FIFO_BYTES))
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
            active_error_flags <= active_error_flags |
                ({32{decoder_error}} & `GFX_STATUS_DECODER_ERROR) |
                ({32{command_error}} & `GFX_STATUS_COMMAND_ERROR) |
                ({32{overflow_sync2 != overflow_previous}} &
                 `GFX_STATUS_RECEIVE_OVERFLOW);
            if (frame_done && !frame_queue_write_ready)
                receive_overflow <= 1'b1;
            if (frame_done) begin
                active_error_flags <= '0;
            end
        end
    end

endmodule
