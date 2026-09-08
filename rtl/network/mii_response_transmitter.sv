module mii_response_transmitter #(
    parameter logic [47:0] LOCAL_MAC = 48'h020000000001,
    parameter logic [31:0] LOCAL_IP = 32'hC0A80702,
    parameter logic [15:0] LOCAL_PORT = 16'd4000
) (
    input logic tx_clk,
    input logic reset,
    input logic arp_toggle,
    input logic [47:0] arp_mac,
    input logic [31:0] arp_ip,
    input logic packet_toggle,
    input logic [47:0] packet_mac,
    input logic [31:0] packet_ip,
    input logic [15:0] packet_port,
    input logic [31:0] packet_frame_id,
    input logic [15:0] packet_sequence,
    input logic [11:0] packet_fifo_free,
    input logic [31:0] packet_flags,
    input logic frame_toggle,
    input logic [31:0] frame_id,
    input logic [11:0] frame_fifo_free,
    input logic [31:0] frame_flags,
    output logic [3:0] tx_data,
    output logic tx_en,
    output logic tx_er
);

    typedef enum logic [1:0] {
        IDLE,
        SEND,
        INTERFRAME_GAP
    } tx_state_t;

    typedef enum logic [1:0] {
        RESPONSE_ARP,
        RESPONSE_PACKET,
        RESPONSE_FRAME
    } response_kind_t;

    tx_state_t state;
    response_kind_t response_kind;
    logic arp_sync1;
    logic arp_sync2;
    logic arp_seen;
    logic packet_sync1;
    logic packet_sync2;
    logic packet_seen;
    logic frame_sync1;
    logic frame_sync2;
    logic frame_seen;
    logic [47:0] target_mac;
    logic [31:0] target_ip;
    logic [15:0] target_port;
    logic [47:0] last_peer_mac;
    logic [31:0] last_peer_ip;
    logic [15:0] last_peer_port;
    logic [15:0] last_packet_sequence;
    logic [31:0] status_frame_id;
    logic [15:0] status_sequence;
    logic [11:0] status_fifo_free;
    logic [31:0] status_flags;
    logic [6:0] byte_index;
    logic [6:0] data_end_index;
    logic [6:0] fcs_start_index;
    logic [6:0] final_index;
    logic high_nibble;
    logic [4:0] gap_count;
    logic [31:0] crc;
    logic [7:0] current_byte;
    logic [15:0] ip_checksum;

    function automatic logic [31:0] crc32_byte(
        input logic [31:0] crc_in,
        input logic [7:0] data
    );
        logic [31:0] value;
        integer bit_number;
        begin
            value = crc_in ^ data;
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                if (value[0])
                    value = (value >> 1) ^ 32'hEDB88320;
                else
                    value = value >> 1;
            end
            crc32_byte = value;
        end
    endfunction

    function automatic logic [15:0] ipv4_checksum(
        input logic [15:0] identification,
        input logic [31:0] destination
    );
        logic [19:0] sum;
        begin
            sum = 20'h04500 + 20'h00030 + identification + 20'h04000 +
                  20'h04011 + LOCAL_IP[31:16] + LOCAL_IP[15:0] +
                  destination[31:16] + destination[15:0];
            sum = sum[15:0] + sum[19:16];
            sum = sum[15:0] + sum[19:16];
            ipv4_checksum = ~sum[15:0];
        end
    endfunction

    always_comb begin
        data_end_index = response_kind == RESPONSE_ARP ? 7'd67 : 7'd69;
        fcs_start_index = data_end_index + 1'b1;
        final_index = fcs_start_index + 7'd3;
        ip_checksum = ipv4_checksum(status_frame_id[15:0], target_ip);
        current_byte = 8'h00;

        if (byte_index <= 7'd6)
            current_byte = 8'h55;
        else if (byte_index == 7'd7)
            current_byte = 8'hD5;
        else if (byte_index <= 7'd13)
            current_byte = target_mac[47 - (byte_index - 7'd8) * 8 -: 8];
        else if (byte_index <= 7'd19)
            current_byte = LOCAL_MAC[47 - (byte_index - 7'd14) * 8 -: 8];
        else if (response_kind == RESPONSE_ARP) begin
            case (byte_index)
                7'd20: current_byte = 8'h08;
                7'd21: current_byte = 8'h06;
                7'd22: current_byte = 8'h00;
                7'd23: current_byte = 8'h01;
                7'd24: current_byte = 8'h08;
                7'd25: current_byte = 8'h00;
                7'd26: current_byte = 8'h06;
                7'd27: current_byte = 8'h04;
                7'd28: current_byte = 8'h00;
                7'd29: current_byte = 8'h02;
                7'd30: current_byte = LOCAL_MAC[47:40];
                7'd31: current_byte = LOCAL_MAC[39:32];
                7'd32: current_byte = LOCAL_MAC[31:24];
                7'd33: current_byte = LOCAL_MAC[23:16];
                7'd34: current_byte = LOCAL_MAC[15:8];
                7'd35: current_byte = LOCAL_MAC[7:0];
                7'd36: current_byte = LOCAL_IP[31:24];
                7'd37: current_byte = LOCAL_IP[23:16];
                7'd38: current_byte = LOCAL_IP[15:8];
                7'd39: current_byte = LOCAL_IP[7:0];
                7'd40: current_byte = target_mac[47:40];
                7'd41: current_byte = target_mac[39:32];
                7'd42: current_byte = target_mac[31:24];
                7'd43: current_byte = target_mac[23:16];
                7'd44: current_byte = target_mac[15:8];
                7'd45: current_byte = target_mac[7:0];
                7'd46: current_byte = target_ip[31:24];
                7'd47: current_byte = target_ip[23:16];
                7'd48: current_byte = target_ip[15:8];
                7'd49: current_byte = target_ip[7:0];
                default: current_byte = 8'h00;
            endcase
        end else begin
            case (byte_index)
                7'd20: current_byte = 8'h08;
                7'd21: current_byte = 8'h00;
                7'd22: current_byte = 8'h45;
                7'd23: current_byte = 8'h00;
                7'd24: current_byte = 8'h00;
                7'd25: current_byte = 8'h30;
                7'd26: current_byte = status_frame_id[15:8];
                7'd27: current_byte = status_frame_id[7:0];
                7'd28: current_byte = 8'h40;
                7'd29: current_byte = 8'h00;
                7'd30: current_byte = 8'h40;
                7'd31: current_byte = 8'h11;
                7'd32: current_byte = ip_checksum[15:8];
                7'd33: current_byte = ip_checksum[7:0];
                7'd34: current_byte = LOCAL_IP[31:24];
                7'd35: current_byte = LOCAL_IP[23:16];
                7'd36: current_byte = LOCAL_IP[15:8];
                7'd37: current_byte = LOCAL_IP[7:0];
                7'd38: current_byte = target_ip[31:24];
                7'd39: current_byte = target_ip[23:16];
                7'd40: current_byte = target_ip[15:8];
                7'd41: current_byte = target_ip[7:0];
                7'd42: current_byte = LOCAL_PORT[15:8];
                7'd43: current_byte = LOCAL_PORT[7:0];
                7'd44: current_byte = target_port[15:8];
                7'd45: current_byte = target_port[7:0];
                7'd46: current_byte = 8'h00;
                7'd47: current_byte = 8'h1C;
                7'd48: current_byte = 8'h00;
                7'd49: current_byte = 8'h00;
                7'd50: current_byte = 8'h47;
                7'd51: current_byte = 8'h53;
                7'd52: current_byte = 8'h01;
                7'd53: current_byte = response_kind == RESPONSE_PACKET ? 8'h01 : 8'h02;
                7'd54: current_byte = status_frame_id[31:24];
                7'd55: current_byte = status_frame_id[23:16];
                7'd56: current_byte = status_frame_id[15:8];
                7'd57: current_byte = status_frame_id[7:0];
                7'd58: current_byte = status_sequence[15:8];
                7'd59: current_byte = status_sequence[7:0];
                7'd60: current_byte = {4'b0000, status_fifo_free[11:8]};
                7'd61: current_byte = status_fifo_free[7:0];
                7'd62: current_byte = status_flags[31:24];
                7'd63: current_byte = status_flags[23:16];
                7'd64: current_byte = status_flags[15:8];
                7'd65: current_byte = status_flags[7:0];
                default: current_byte = 8'h00;
            endcase
        end

        if (byte_index >= fcs_start_index)
            case (byte_index - fcs_start_index)
                7'd0: current_byte = ~crc[7:0];
                7'd1: current_byte = ~crc[15:8];
                7'd2: current_byte = ~crc[23:16];
                default: current_byte = ~crc[31:24];
            endcase
    end

    assign tx_en = state == SEND;
    assign tx_er = 1'b0;
    assign tx_data = high_nibble ? current_byte[7:4] : current_byte[3:0];

    always_ff @(posedge tx_clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            response_kind <= RESPONSE_ARP;
            arp_sync1 <= 1'b0;
            arp_sync2 <= 1'b0;
            arp_seen <= 1'b0;
            packet_sync1 <= 1'b0;
            packet_sync2 <= 1'b0;
            packet_seen <= 1'b0;
            frame_sync1 <= 1'b0;
            frame_sync2 <= 1'b0;
            frame_seen <= 1'b0;
            target_mac <= '0;
            target_ip <= '0;
            target_port <= '0;
            last_peer_mac <= '0;
            last_peer_ip <= '0;
            last_peer_port <= '0;
            last_packet_sequence <= '0;
            status_frame_id <= '0;
            status_sequence <= '0;
            status_fifo_free <= '0;
            status_flags <= '0;
            byte_index <= '0;
            high_nibble <= 1'b0;
            gap_count <= '0;
            crc <= 32'hFFFFFFFF;
        end else begin
            arp_sync1 <= arp_toggle;
            arp_sync2 <= arp_sync1;
            packet_sync1 <= packet_toggle;
            packet_sync2 <= packet_sync1;
            frame_sync1 <= frame_toggle;
            frame_sync2 <= frame_sync1;

            case (state)
                IDLE: begin
                    if (arp_sync2 != arp_seen) begin
                        arp_seen <= arp_sync2;
                        response_kind <= RESPONSE_ARP;
                        target_mac <= arp_mac;
                        target_ip <= arp_ip;
                        byte_index <= '0;
                        high_nibble <= 1'b0;
                        crc <= 32'hFFFFFFFF;
                        state <= SEND;
                    end else if (packet_sync2 != packet_seen) begin
                        packet_seen <= packet_sync2;
                        response_kind <= RESPONSE_PACKET;
                        target_mac <= packet_mac;
                        target_ip <= packet_ip;
                        target_port <= packet_port;
                        last_peer_mac <= packet_mac;
                        last_peer_ip <= packet_ip;
                        last_peer_port <= packet_port;
                        last_packet_sequence <= packet_sequence;
                        status_frame_id <= packet_frame_id;
                        status_sequence <= packet_sequence;
                        status_fifo_free <= packet_fifo_free;
                        status_flags <= packet_flags;
                        byte_index <= '0;
                        high_nibble <= 1'b0;
                        crc <= 32'hFFFFFFFF;
                        state <= SEND;
                    end else if (frame_sync2 != frame_seen) begin
                        frame_seen <= frame_sync2;
                        response_kind <= RESPONSE_FRAME;
                        target_mac <= last_peer_mac;
                        target_ip <= last_peer_ip;
                        target_port <= last_peer_port;
                        status_frame_id <= frame_id;
                        status_sequence <= last_packet_sequence;
                        status_fifo_free <= frame_fifo_free;
                        status_flags <= frame_flags;
                        byte_index <= '0;
                        high_nibble <= 1'b0;
                        crc <= 32'hFFFFFFFF;
                        state <= SEND;
                    end
                end
                SEND: begin
                    if (!high_nibble) begin
                        high_nibble <= 1'b1;
                    end else begin
                        high_nibble <= 1'b0;
                        if (byte_index >= 7'd8 && byte_index <= data_end_index)
                            crc <= crc32_byte(crc, current_byte);
                        if (byte_index == final_index) begin
                            gap_count <= '0;
                            state <= INTERFRAME_GAP;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                        end
                    end
                end
                INTERFRAME_GAP: begin
                    if (gap_count == 5'd23)
                        state <= IDLE;
                    else
                        gap_count <= gap_count + 1'b1;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
