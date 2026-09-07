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
    output logic [7:0] payload_data,
    output logic payload_valid,
    input logic payload_ready,
    output logic payload_overflow,
    output logic packet_received,
    output logic arp_request,
    output logic [47:0] arp_sender_mac,
    output logic [31:0] arp_sender_ip
);

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
    logic [31:0] destination_ip;
    logic [15:0] udp_destination_port;
    logic [15:0] udp_length;
    logic [15:0] udp_payload_remaining;
    logic udp_selected;
    logic [15:0] arp_opcode;
    logic [31:0] arp_source_ip;
    logic [31:0] arp_target_ip;

    task automatic process_frame_byte(input logic [7:0] value);
        begin
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
                11'd30: destination_ip[31:24] <= value;
                11'd31: destination_ip[23:16] <= value;
                11'd32: destination_ip[15:8] <= value;
                11'd33: destination_ip[7:0] <= value;
                11'd36: udp_destination_port[15:8] <= value;
                11'd37: udp_destination_port[7:0] <= value;
                11'd38: udp_length[15:8] <= value;
                11'd39: begin
                    udp_length[7:0] <= value;
                    if ({udp_length[15:8], value} >= 16'd8)
                        udp_payload_remaining <= {udp_length[15:8], value} - 16'd8;
                    else
                        udp_payload_remaining <= '0;
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
                if (payload_ready) begin
                    payload_data <= value;
                    payload_valid <= 1'b1;
                end else begin
                    payload_overflow <= 1'b1;
                end
                udp_payload_remaining <= udp_payload_remaining - 1'b1;
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
            destination_ip <= '0;
            udp_destination_port <= '0;
            udp_length <= '0;
            udp_payload_remaining <= '0;
            udp_selected <= 1'b0;
            arp_opcode <= '0;
            arp_source_ip <= '0;
            arp_target_ip <= '0;
            payload_data <= '0;
            payload_valid <= 1'b0;
            payload_overflow <= 1'b0;
            packet_received <= 1'b0;
            arp_request <= 1'b0;
            arp_sender_mac <= '0;
            arp_sender_ip <= '0;
        end else begin
            payload_valid <= 1'b0;
            payload_overflow <= 1'b0;
            packet_received <= 1'b0;
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
                            destination_ip <= '0;
                            udp_destination_port <= '0;
                            udp_length <= '0;
                            udp_payload_remaining <= '0;
                            udp_selected <= 1'b0;
                            arp_opcode <= '0;
                            arp_source_ip <= '0;
                            arp_target_ip <= '0;
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
                    if (!frame_error && udp_selected)
                        packet_received <= 1'b1;
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
