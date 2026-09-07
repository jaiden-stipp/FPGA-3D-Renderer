module mii_arp_responder #(
    parameter logic [47:0] LOCAL_MAC = 48'h020000000001,
    parameter logic [31:0] LOCAL_IP = 32'hC0A80702
) (
    input logic tx_clk,
    input logic reset,
    input logic request_toggle,
    input logic [47:0] request_mac,
    input logic [31:0] request_ip,
    output logic [3:0] tx_data,
    output logic tx_en,
    output logic tx_er
);

    typedef enum logic [1:0] {
        IDLE,
        SEND,
        INTERFRAME_GAP
    } tx_state_t;

    tx_state_t state;
    logic request_sync1;
    logic request_sync2;
    logic request_seen;
    logic [47:0] target_mac;
    logic [31:0] target_ip;
    logic [6:0] byte_index;
    logic high_nibble;
    logic [4:0] gap_count;
    logic [31:0] crc;
    logic [7:0] current_byte;

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

    always_comb begin
        current_byte = 8'h00;
        if (byte_index <= 7'd6)
            current_byte = 8'h55;
        else if (byte_index == 7'd7)
            current_byte = 8'hD5;
        else if (byte_index <= 7'd13)
            current_byte = target_mac[47 - (byte_index - 7'd8) * 8 -: 8];
        else if (byte_index <= 7'd19)
            current_byte = LOCAL_MAC[47 - (byte_index - 7'd14) * 8 -: 8];
        else begin
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
                7'd68: current_byte = ~crc[7:0];
                7'd69: current_byte = ~crc[15:8];
                7'd70: current_byte = ~crc[23:16];
                7'd71: current_byte = ~crc[31:24];
                default: current_byte = 8'h00;
            endcase
        end
    end

    assign tx_en = state == SEND;
    assign tx_er = 1'b0;
    assign tx_data = high_nibble ? current_byte[7:4] : current_byte[3:0];

    always_ff @(posedge tx_clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            request_sync1 <= 1'b0;
            request_sync2 <= 1'b0;
            request_seen <= 1'b0;
            target_mac <= '0;
            target_ip <= '0;
            byte_index <= '0;
            high_nibble <= 1'b0;
            gap_count <= '0;
            crc <= 32'hFFFFFFFF;
        end else begin
            request_sync1 <= request_toggle;
            request_sync2 <= request_sync1;

            case (state)
                IDLE: begin
                    if (request_sync2 != request_seen) begin
                        request_seen <= request_sync2;
                        target_mac <= request_mac;
                        target_ip <= request_ip;
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
                        if (byte_index >= 7'd8 && byte_index <= 7'd67)
                            crc <= crc32_byte(crc, current_byte);
                        if (byte_index == 7'd71) begin
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
