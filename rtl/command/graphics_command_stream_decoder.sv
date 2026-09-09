`include "renderer_types.svh"

module graphics_command_stream_decoder (
    input logic clk,
    input logic reset,
    input logic [7:0] byte_data,
    input logic byte_valid,
    output logic byte_ready,
    output graphics_command_t command_data,
    output logic command_valid,
    input logic command_ready,
    output logic decoder_error
);

    typedef enum logic [3:0] {
        SYNC_G,
        SYNC_F,
        VERSION,
        OPCODE,
        LENGTH,
        PAYLOAD,
        CRC_HIGH,
        CRC_LOW,
        OUTPUT_COMMAND,
        BULK_READ_WAIT,
        BULK_READ_CAPTURE,
        OUTPUT_BULK_VERTEX,
        OUTPUT_BULK_INDEX
    } decoder_state_t;

    decoder_state_t state;
    logic [7:0] opcode_byte;
    logic [7:0] payload_length;
    logic [7:0] payload_index;
    logic [15:0] crc;
    logic [7:0] received_crc_high;
    graphics_command_t decoded_command;
    (* ramstyle = "M9K" *)
    logic [7:0] bulk_payload [0:254];
    logic [7:0] bulk_read_address;
    logic [7:0] bulk_read_data;
    logic [2:0] bulk_byte_index;
    logic [7:0] bulk_record_index;
    logic [7:0] bulk_handle;
    logic [15:0] bulk_start;
    logic [7:0] bulk_record_count;

    function automatic logic [15:0] crc16_byte(
        input logic [15:0] crc_in,
        input logic [7:0] data
    );
        logic [15:0] value;
        integer bit_number;
        begin
            value = crc_in ^ {data, 8'h00};
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                if (value[15])
                    value = (value << 1) ^ 16'h1021;
                else
                    value = value << 1;
            end
            crc16_byte = value;
        end
    endfunction

    assign byte_ready = !reset && state != OUTPUT_COMMAND &&
                        state != BULK_READ_WAIT &&
                        state != BULK_READ_CAPTURE &&
                        state != OUTPUT_BULK_VERTEX &&
                        state != OUTPUT_BULK_INDEX;
    assign command_valid = state == OUTPUT_COMMAND ||
                           state == OUTPUT_BULK_VERTEX ||
                           state == OUTPUT_BULK_INDEX;

    always_comb begin
        command_data = decoded_command;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= SYNC_G;
            opcode_byte <= '0;
            payload_length <= '0;
            payload_index <= '0;
            crc <= 16'hFFFF;
            received_crc_high <= '0;
            decoded_command <= '0;
            bulk_read_address <= '0;
            bulk_read_data <= '0;
            bulk_byte_index <= '0;
            bulk_record_index <= '0;
            bulk_handle <= '0;
            bulk_start <= '0;
            bulk_record_count <= '0;
            decoder_error <= 1'b0;
        end else begin
            bulk_read_data <= bulk_payload[bulk_read_address];
            decoder_error <= 1'b0;

            if (state == OUTPUT_COMMAND) begin
                if (command_ready)
                    state <= SYNC_G;
            end else if (state == OUTPUT_BULK_VERTEX ||
                         state == OUTPUT_BULK_INDEX) begin
                if (command_ready) begin
                    if (bulk_record_index + 1'b1 == bulk_record_count)
                        state <= SYNC_G;
                    else begin
                        bulk_record_index <= bulk_record_index + 1'b1;
                        bulk_byte_index <= '0;
                        decoded_command <= '0;
                        `GFX_MESH_HANDLE(decoded_command) <= bulk_handle;
                        `GFX_MESH_ELEMENT(decoded_command) <= bulk_start +
                            {8'b0, bulk_record_index} + 16'd1;
                        if (state == OUTPUT_BULK_VERTEX) begin
                            decoded_command.opcode <= GFX_CMD_UPLOAD_VERTEX;
                            bulk_read_address <= 8'd3 +
                                (bulk_record_index + 1'b1) * 8'd6;
                        end else begin
                            decoded_command.opcode <= GFX_CMD_UPLOAD_INDEX;
                            bulk_read_address <= 8'd4 +
                                (bulk_record_index + 1'b1) * 8'd4;
                        end
                        state <= BULK_READ_WAIT;
                    end
                end
            end else if (state == BULK_READ_WAIT) begin
                state <= BULK_READ_CAPTURE;
            end else if (state == BULK_READ_CAPTURE) begin
                if (opcode_byte == 8'd9) begin
                    case (bulk_byte_index)
                        3'd0: decoded_command.payload[47:40] <= bulk_read_data;
                        3'd1: decoded_command.payload[39:32] <= bulk_read_data;
                        3'd2: decoded_command.payload[31:24] <= bulk_read_data;
                        3'd3: decoded_command.payload[23:16] <= bulk_read_data;
                        3'd4: decoded_command.payload[15:8] <= bulk_read_data;
                        default: decoded_command.payload[7:0] <= bulk_read_data;
                    endcase
                    if (bulk_byte_index == 3'd5)
                        state <= OUTPUT_BULK_VERTEX;
                    else begin
                        bulk_byte_index <= bulk_byte_index + 1'b1;
                        bulk_read_address <= bulk_read_address + 1'b1;
                        state <= BULK_READ_WAIT;
                    end
                end else begin
                    case (bulk_byte_index)
                        3'd0: decoded_command.payload[79:72] <= bulk_read_data;
                        3'd1: decoded_command.payload[71:64] <= bulk_read_data;
                        3'd2: decoded_command.payload[63:56] <= bulk_read_data;
                        default: decoded_command.payload[55:48] <= bulk_read_data;
                    endcase
                    if (bulk_byte_index == 3'd3)
                        state <= OUTPUT_BULK_INDEX;
                    else begin
                        bulk_byte_index <= bulk_byte_index + 1'b1;
                        bulk_read_address <= bulk_read_address + 1'b1;
                        state <= BULK_READ_WAIT;
                    end
                end
            end else if (byte_valid && byte_ready) begin
                case (state)
                    SYNC_G: begin
                        if (byte_data == 8'h47) begin
                            decoded_command <= '0;
                            crc <= crc16_byte(16'hFFFF, byte_data);
                            state <= SYNC_F;
                        end
                    end

                    SYNC_F: begin
                        if (byte_data == 8'h46) begin
                            crc <= crc16_byte(crc, byte_data);
                            state <= VERSION;
                        end else if (byte_data == 8'h47) begin
                            crc <= crc16_byte(16'hFFFF, byte_data);
                        end else begin
                            state <= SYNC_G;
                        end
                    end

                    VERSION: begin
                        if (byte_data == 8'h01) begin
                            crc <= crc16_byte(crc, byte_data);
                            state <= OPCODE;
                        end else begin
                            decoder_error <= 1'b1;
                            state <= SYNC_G;
                        end
                    end

                    OPCODE: begin
                        opcode_byte <= byte_data;
                        crc <= crc16_byte(crc, byte_data);
                        state <= LENGTH;
                    end

                    LENGTH: begin
                        crc <= crc16_byte(crc, byte_data);
                        payload_length <= byte_data;
                        payload_index <= '0;
                        case (opcode_byte)
                            8'd0: begin
                                decoded_command.opcode <= GFX_CMD_SET_ROTATION;
                                if (byte_data == 8'd1)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd1: begin
                                decoded_command.opcode <= GFX_CMD_BEGIN_FRAME;
                                if (byte_data == 8'd4)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd2: begin
                                decoded_command.opcode <= GFX_CMD_DRAW_TRIANGLE;
                                if (byte_data == 8'd19)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd3: begin
                                decoded_command.opcode <= GFX_CMD_END_FRAME;
                                if (byte_data == 8'd0)
                                    state <= CRC_HIGH;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd4: begin
                                decoded_command.opcode <= GFX_CMD_SET_PALETTE;
                                if (byte_data == 8'd4)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd5: begin
                                decoded_command.opcode <= GFX_CMD_DEFINE_MESH;
                                if (byte_data == 8'd5)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd6: begin
                                decoded_command.opcode <= GFX_CMD_UPLOAD_VERTEX;
                                if (byte_data == 8'd8)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd7: begin
                                decoded_command.opcode <= GFX_CMD_UPLOAD_INDEX;
                                if (byte_data == 8'd7)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd8: begin
                                decoded_command.opcode <= GFX_CMD_DRAW_MESH;
                                if (byte_data == 8'd25)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd9: begin
                                if (byte_data >= 8'd9)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd10: begin
                                if (byte_data >= 8'd8)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            default: begin
                                decoder_error <= 1'b1;
                                state <= SYNC_G;
                            end
                        endcase
                    end

                    PAYLOAD: begin
                        crc <= crc16_byte(crc, byte_data);
                        case (opcode_byte)
                            8'd0: decoded_command.payload[7:0] <= byte_data;
                            8'd1: begin
                                case (payload_index)
                                    8'd0: decoded_command.payload[31:24] <= byte_data;
                                    8'd1: decoded_command.payload[23:16] <= byte_data;
                                    8'd2: decoded_command.payload[15:8] <= byte_data;
                                    default: decoded_command.payload[7:0] <= byte_data;
                                endcase
                            end
                            8'd2: decoded_command.payload[
                                151 - payload_index * 8 -: 8] <= byte_data;
                            8'd4: begin
                                case (payload_index)
                                    8'd0: decoded_command.payload[31:24] <= byte_data;
                                    8'd1: decoded_command.payload[23:16] <= byte_data;
                                    8'd2: decoded_command.payload[15:8] <= byte_data;
                                    default: decoded_command.payload[7:0] <= byte_data;
                                endcase
                            end
                            8'd5: begin
                                case (payload_index)
                                    8'd0: decoded_command.payload[135:128] <= byte_data;
                                    8'd1: decoded_command.payload[111:104] <= byte_data;
                                    8'd2: decoded_command.payload[103:96] <= byte_data;
                                    8'd3: decoded_command.payload[95:88] <= byte_data;
                                    default: decoded_command.payload[87:80] <= byte_data;
                                endcase
                            end
                            8'd6: begin
                                case (payload_index)
                                    8'd0: decoded_command.payload[135:128] <= byte_data;
                                    8'd1: decoded_command.payload[119:112] <= byte_data;
                                    8'd2: decoded_command.payload[47:40] <= byte_data;
                                    8'd3: decoded_command.payload[39:32] <= byte_data;
                                    8'd4: decoded_command.payload[31:24] <= byte_data;
                                    8'd5: decoded_command.payload[23:16] <= byte_data;
                                    8'd6: decoded_command.payload[15:8] <= byte_data;
                                    default: decoded_command.payload[7:0] <= byte_data;
                                endcase
                            end
                            8'd7: begin
                                case (payload_index)
                                    8'd0: decoded_command.payload[135:128] <= byte_data;
                                    8'd1: decoded_command.payload[127:120] <= byte_data;
                                    8'd2: decoded_command.payload[119:112] <= byte_data;
                                    8'd3: decoded_command.payload[79:72] <= byte_data;
                                    8'd4: decoded_command.payload[71:64] <= byte_data;
                                    8'd5: decoded_command.payload[63:56] <= byte_data;
                                    default: decoded_command.payload[55:48] <= byte_data;
                                endcase
                            end
                            8'd8: decoded_command.payload[
                                199 - payload_index * 8 -: 8] <= byte_data;
                            8'd9: begin
                                bulk_payload[payload_index] <= byte_data;
                                case (payload_index)
                                    8'd0: bulk_handle <= byte_data;
                                    8'd1: bulk_start <= {8'b0, byte_data};
                                    8'd2: bulk_record_count <= byte_data;
                                    default: begin
                                    end
                                endcase
                            end
                            8'd10: begin
                                bulk_payload[payload_index] <= byte_data;
                                case (payload_index)
                                    8'd0: bulk_handle <= byte_data;
                                    8'd1: bulk_start[15:8] <= byte_data;
                                    8'd2: bulk_start[7:0] <= byte_data;
                                    8'd3: bulk_record_count <= byte_data;
                                    default: begin
                                    end
                                endcase
                            end
                            default: begin
                            end
                        endcase

                        if (payload_index + 1'b1 == payload_length)
                            state <= CRC_HIGH;
                        else
                            payload_index <= payload_index + 1'b1;
                    end

                    CRC_HIGH: begin
                        received_crc_high <= byte_data;
                        state <= CRC_LOW;
                    end

                    CRC_LOW: begin
                        if ({received_crc_high, byte_data} != crc) begin
                            decoder_error <= 1'b1;
                            state <= SYNC_G;
                        end else if (opcode_byte == 8'd9) begin
                            if (bulk_record_count == 0 ||
                                bulk_record_count > 8'd42 ||
                                payload_length != 8'd3 + bulk_record_count * 8'd6 ||
                                {1'b0, bulk_start[7:0]} +
                                    {1'b0, bulk_record_count} > 9'd128) begin
                                decoder_error <= 1'b1;
                                state <= SYNC_G;
                            end else begin
                                bulk_record_index <= '0;
                                bulk_byte_index <= '0;
                                bulk_read_address <= 8'd3;
                                decoded_command <= '0;
                                decoded_command.opcode <= GFX_CMD_UPLOAD_VERTEX;
                                `GFX_MESH_HANDLE(decoded_command) <= bulk_handle;
                                `GFX_MESH_ELEMENT(decoded_command) <= bulk_start;
                                state <= BULK_READ_WAIT;
                            end
                        end else if (opcode_byte == 8'd10) begin
                            if (bulk_record_count == 0 ||
                                bulk_record_count > 8'd62 ||
                                payload_length != 8'd4 + bulk_record_count * 8'd4 ||
                                {1'b0, bulk_start} +
                                    {9'b0, bulk_record_count} > 17'd256) begin
                                decoder_error <= 1'b1;
                                state <= SYNC_G;
                            end else begin
                                bulk_record_index <= '0;
                                bulk_byte_index <= '0;
                                bulk_read_address <= 8'd4;
                                decoded_command <= '0;
                                decoded_command.opcode <= GFX_CMD_UPLOAD_INDEX;
                                `GFX_MESH_HANDLE(decoded_command) <= bulk_handle;
                                `GFX_MESH_ELEMENT(decoded_command) <= bulk_start;
                                state <= BULK_READ_WAIT;
                            end
                        end else begin
                            state <= OUTPUT_COMMAND;
                        end
                    end

                    default: state <= SYNC_G;
                endcase
            end
        end
    end

endmodule
