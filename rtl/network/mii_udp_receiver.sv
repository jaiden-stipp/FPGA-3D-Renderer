module mii_udp_receiver #(
    parameter logic [47:0] LOCAL_MAC = 48'h020000000001,
    parameter logic [31:0] LOCAL_IP = 32'hC0A80702,
    parameter logic [15:0] LOCAL_PORT = 16'd4000
) (
    input logic rx_clk,
    input logic reset,
    input logic [3:0] rx_data,
    input logic rx_dv,
    input logic rx_er,
    input logic [11:0] fifo_free,
    output logic [7:0] payload_data,
    output logic payload_valid,
    input logic payload_ready,
    output logic payload_overflow,
    output logic packet_received,
    output logic packet_status,
    output logic [47:0] packet_sender_mac,
    output logic [31:0] packet_sender_ip,
    output logic [15:0] packet_sender_port,
    output logic [31:0] packet_frame_id,
    output logic [15:0] packet_sequence,
    output logic [31:0] packet_status_flags,
    output logic [11:0] packet_fifo_free,
    output logic arp_request,
    output logic [47:0] arp_sender_mac,
    output logic [31:0] arp_sender_ip
);

    localparam logic [31:0] STATUS_ACCEPTED = 32'h00000001;
    localparam logic [31:0] STATUS_DUPLICATE = 32'h00000002;
    localparam logic [31:0] STATUS_BUSY = 32'h00000004;
    localparam logic [31:0] STATUS_SEQUENCE_ERROR = 32'h00000008;
    localparam logic [31:0] STATUS_MALFORMED = 32'h00000010;
    localparam logic [31:0] STATUS_OVERFLOW = 32'h00000020;

    logic nibble_high;
    logic [3:0] low_nibble;
    logic in_frame;
    logic [3:0] preamble_count;
    logic [10:0] byte_index;
    logic frame_error;
    logic destination_local;
    logic destination_broadcast;
    logic [47:0] source_mac;
    logic [15:0] ether_type;
    logic ipv4_header_valid;
    logic [7:0] ip_protocol;
    logic [31:0] ipv4_source_ip;
    logic [31:0] destination_ip;
    logic [15:0] udp_source_port;
    logic [15:0] udp_destination_port;
    logic [15:0] udp_payload_length;
    logic [15:0] udp_payload_remaining;
    logic udp_selected;
    logic [15:0] arp_opcode;
    logic [31:0] arp_source_ip;
    logic [31:0] arp_target_ip;
    logic [15:0] transport_offset;
    logic transport_magic_g;
    logic transport_magic_ok;
    logic transport_version_ok;
    logic [7:0] transport_flags;
    logic [31:0] transport_frame_id;
    logic [15:0] transport_sequence;
    logic [15:0] transport_length;
    logic [15:0] transport_payload_remaining;
    logic transport_header_valid;
    logic transport_accept;
    logic transport_overflow;
    logic [31:0] transport_result;
    logic sequence_active;
    logic [31:0] active_transport_frame;
    logic [15:0] expected_sequence;
    logic [15:0] last_sequence;

    task automatic process_frame_byte(input logic [7:0] value);
        logic [15:0] declared_length;
        logic duplicate_packet;
        logic sequence_valid;
        begin
            declared_length = '0;
            duplicate_packet = 1'b0;
            sequence_valid = 1'b0;
            if (byte_index < 11'd6) begin
                if (value != LOCAL_MAC[47 - byte_index * 8 -: 8])
                    destination_local <= 1'b0;
                if (value != 8'hFF)
                    destination_broadcast <= 1'b0;
            end

            if (byte_index >= 11'd6 && byte_index <= 11'd11)
                source_mac <= {source_mac[39:0], value};

            case (byte_index)
                11'd12: ether_type[15:8] <= value;
                11'd13: ether_type[7:0] <= value;
                11'd14: ipv4_header_valid <= value == 8'h45;
                11'd23: ip_protocol <= value;
                11'd26: ipv4_source_ip[31:24] <= value;
                11'd27: ipv4_source_ip[23:16] <= value;
                11'd28: ipv4_source_ip[15:8] <= value;
                11'd29: ipv4_source_ip[7:0] <= value;
                11'd30: destination_ip[31:24] <= value;
                11'd31: destination_ip[23:16] <= value;
                11'd32: destination_ip[15:8] <= value;
                11'd33: destination_ip[7:0] <= value;
                11'd34: udp_source_port[15:8] <= value;
                11'd35: udp_source_port[7:0] <= value;
                11'd36: udp_destination_port[15:8] <= value;
                11'd37: udp_destination_port[7:0] <= value;
                11'd38: udp_payload_length[15:8] <= value;
                11'd39: begin
                    if ({udp_payload_length[15:8], value} >= 16'd8) begin
                        udp_payload_length <= {udp_payload_length[15:8], value} - 16'd8;
                        udp_payload_remaining <= {udp_payload_length[15:8], value} - 16'd8;
                    end else begin
                        udp_payload_length <= '0;
                        udp_payload_remaining <= '0;
                    end
                end
                11'd41: udp_selected <=
                    (destination_local || destination_broadcast) &&
                    ether_type == 16'h0800 &&
                    ipv4_header_valid &&
                    ip_protocol == 8'd17 &&
                    destination_ip == LOCAL_IP &&
                    udp_destination_port == LOCAL_PORT;
                default: begin
                end
            endcase

            if (byte_index == 11'd20)
                arp_opcode[15:8] <= value;
            if (byte_index == 11'd21)
                arp_opcode[7:0] <= value;
            if (byte_index >= 11'd28 && byte_index <= 11'd31)
                arp_source_ip <= {arp_source_ip[23:0], value};
            if (byte_index >= 11'd38 && byte_index <= 11'd41)
                arp_target_ip <= {arp_target_ip[23:0], value};

            if (byte_index >= 11'd42 && udp_selected && udp_payload_remaining != 0) begin
                udp_payload_remaining <= udp_payload_remaining - 1'b1;
                case (transport_offset)
                    16'd0: transport_magic_g <= value == 8'h47;
                    16'd1: transport_magic_ok <= transport_magic_g && value == 8'h50;
                    16'd2: transport_version_ok <= value == 8'h01;
                    16'd3: transport_flags <= value;
                    16'd4, 16'd5, 16'd6, 16'd7:
                        transport_frame_id <= {transport_frame_id[23:0], value};
                    16'd8, 16'd9:
                        transport_sequence <= {transport_sequence[7:0], value};
                    16'd10: transport_length[15:8] <= value;
                    16'd11: begin
                        declared_length = {transport_length[15:8], value};
                        transport_length[7:0] <= value;
                        transport_payload_remaining <= declared_length;
                        transport_header_valid <= transport_magic_ok && transport_version_ok &&
                            udp_payload_length == declared_length + 16'd12;
                        duplicate_packet = sequence_active &&
                            transport_frame_id == active_transport_frame &&
                            transport_sequence == last_sequence;
                        sequence_valid = duplicate_packet ||
                            (transport_flags[0] && transport_sequence == 16'd0 &&
                             (!sequence_active || transport_frame_id != active_transport_frame)) ||
                            (sequence_active && transport_frame_id == active_transport_frame &&
                             transport_sequence == expected_sequence);
                        if (!transport_magic_ok || !transport_version_ok ||
                            udp_payload_length != declared_length + 16'd12) begin
                            transport_result <= STATUS_MALFORMED;
                        end else if (duplicate_packet) begin
                            transport_result <= STATUS_ACCEPTED | STATUS_DUPLICATE;
                        end else if (!sequence_valid) begin
                            transport_result <= STATUS_SEQUENCE_ERROR;
                        end else if (declared_length > fifo_free) begin
                            transport_result <= STATUS_BUSY;
                        end else begin
                            transport_accept <= 1'b1;
                            transport_result <= STATUS_ACCEPTED;
                        end
                    end
                    default: begin
                        if (transport_payload_remaining != 0) begin
                            transport_payload_remaining <= transport_payload_remaining - 1'b1;
                            if (transport_accept) begin
                                if (payload_ready) begin
                                    payload_data <= value;
                                    payload_valid <= 1'b1;
                                end else begin
                                    payload_overflow <= 1'b1;
                                    transport_overflow <= 1'b1;
                                end
                            end
                        end
                    end
                endcase
                transport_offset <= transport_offset + 1'b1;
            end

            byte_index <= byte_index + 1'b1;
        end
    endtask

    always_ff @(posedge rx_clk or posedge reset) begin
        logic [7:0] assembled_byte;
        if (reset) begin
            nibble_high <= 1'b0;
            low_nibble <= '0;
            in_frame <= 1'b0;
            preamble_count <= '0;
            byte_index <= '0;
            frame_error <= 1'b0;
            destination_local <= 1'b1;
            destination_broadcast <= 1'b1;
            source_mac <= '0;
            ether_type <= '0;
            ipv4_header_valid <= 1'b0;
            ip_protocol <= '0;
            ipv4_source_ip <= '0;
            destination_ip <= '0;
            udp_source_port <= '0;
            udp_destination_port <= '0;
            udp_payload_length <= '0;
            udp_payload_remaining <= '0;
            udp_selected <= 1'b0;
            arp_opcode <= '0;
            arp_source_ip <= '0;
            arp_target_ip <= '0;
            transport_offset <= '0;
            transport_magic_g <= 1'b0;
            transport_magic_ok <= 1'b0;
            transport_version_ok <= 1'b0;
            transport_flags <= '0;
            transport_frame_id <= '0;
            transport_sequence <= '0;
            transport_length <= '0;
            transport_payload_remaining <= '0;
            transport_header_valid <= 1'b0;
            transport_accept <= 1'b0;
            transport_overflow <= 1'b0;
            transport_result <= '0;
            sequence_active <= 1'b0;
            active_transport_frame <= '0;
            expected_sequence <= '0;
            last_sequence <= '0;
            payload_data <= '0;
            payload_valid <= 1'b0;
            payload_overflow <= 1'b0;
            packet_received <= 1'b0;
            packet_status <= 1'b0;
            packet_sender_mac <= '0;
            packet_sender_ip <= '0;
            packet_sender_port <= '0;
            packet_frame_id <= '0;
            packet_sequence <= '0;
            packet_status_flags <= '0;
            packet_fifo_free <= '0;
            arp_request <= 1'b0;
            arp_sender_mac <= '0;
            arp_sender_ip <= '0;
        end else begin
            payload_valid <= 1'b0;
            payload_overflow <= 1'b0;
            packet_received <= 1'b0;
            packet_status <= 1'b0;
            arp_request <= 1'b0;

            if (rx_dv) begin
                if (rx_er)
                    frame_error <= 1'b1;
                if (!nibble_high) begin
                    low_nibble <= rx_data;
                    nibble_high <= 1'b1;
                end else begin
                    assembled_byte = {rx_data, low_nibble};
                    nibble_high <= 1'b0;
                    if (!in_frame) begin
                        if (assembled_byte == 8'h55)
                            preamble_count <= preamble_count + 1'b1;
                        else if (assembled_byte == 8'hD5 && preamble_count >= 4'd7) begin
                            in_frame <= 1'b1;
                            byte_index <= '0;
                            frame_error <= 1'b0;
                            destination_local <= 1'b1;
                            destination_broadcast <= 1'b1;
                            source_mac <= '0;
                            ether_type <= '0;
                            ipv4_header_valid <= 1'b0;
                            ip_protocol <= '0;
                            ipv4_source_ip <= '0;
                            destination_ip <= '0;
                            udp_source_port <= '0;
                            udp_destination_port <= '0;
                            udp_payload_length <= '0;
                            udp_payload_remaining <= '0;
                            udp_selected <= 1'b0;
                            arp_opcode <= '0;
                            arp_source_ip <= '0;
                            arp_target_ip <= '0;
                            transport_offset <= '0;
                            transport_magic_g <= 1'b0;
                            transport_magic_ok <= 1'b0;
                            transport_version_ok <= 1'b0;
                            transport_flags <= '0;
                            transport_frame_id <= '0;
                            transport_sequence <= '0;
                            transport_length <= '0;
                            transport_payload_remaining <= '0;
                            transport_header_valid <= 1'b0;
                            transport_accept <= 1'b0;
                            transport_overflow <= 1'b0;
                            transport_result <= '0;
                        end else begin
                            preamble_count <= '0;
                        end
                    end else begin
                        process_frame_byte(assembled_byte);
                    end
                end
            end else begin
                nibble_high <= 1'b0;
                preamble_count <= '0;
                if (in_frame) begin
                    if (udp_selected) begin
                        packet_sender_mac <= source_mac;
                        packet_sender_ip <= ipv4_source_ip;
                        packet_sender_port <= udp_source_port;
                        packet_frame_id <= transport_frame_id;
                        packet_sequence <= transport_sequence;
                        packet_fifo_free <= fifo_free;
                        packet_status_flags <= transport_result;
                        if (frame_error || !transport_header_valid ||
                            transport_payload_remaining != 0) begin
                            packet_status_flags <= STATUS_MALFORMED;
                        end else if (transport_overflow) begin
                            packet_status_flags <= STATUS_OVERFLOW;
                        end else if (transport_accept) begin
                            sequence_active <= 1'b1;
                            active_transport_frame <= transport_frame_id;
                            last_sequence <= transport_sequence;
                            expected_sequence <= transport_sequence + 1'b1;
                            packet_received <= 1'b1;
                        end
                        packet_status <= 1'b1;
                    end
                    if (!frame_error &&
                        (destination_local || destination_broadcast) &&
                        ether_type == 16'h0806 &&
                        arp_opcode == 16'h0001 &&
                        arp_target_ip == LOCAL_IP) begin
                        arp_sender_mac <= source_mac;
                        arp_sender_ip <= arp_source_ip;
                        arp_request <= 1'b1;
                    end
                    in_frame <= 1'b0;
                end
            end
        end
    end

endmodule
