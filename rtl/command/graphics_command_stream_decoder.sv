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
        OUTPUT_COMMAND
    } decoder_state_t;

    decoder_state_t state;
    logic [7:0] opcode_byte;
    logic [7:0] payload_length;
    logic [7:0] payload_index;
    logic [15:0] crc;
    logic [7:0] received_crc_high;

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

    assign byte_ready = !reset && (state != OUTPUT_COMMAND);
    assign command_valid = (state == OUTPUT_COMMAND);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= SYNC_G;
            opcode_byte <= '0;
            payload_length <= '0;
            payload_index <= '0;
            crc <= 16'hFFFF;
            received_crc_high <= '0;
            command_data <= '0;
            decoder_error <= 1'b0;
        end else begin
            decoder_error <= 1'b0;

            if (state == OUTPUT_COMMAND) begin
                if (command_ready)
                    state <= SYNC_G;
            end else if (byte_valid && byte_ready) begin
                case (state)
                    SYNC_G: begin
                        if (byte_data == 8'h47) begin
                            command_data <= '0;
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
                                command_data.opcode <= GFX_CMD_SET_ROTATION;
                                if (byte_data == 8'd1)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd1: begin
                                command_data.opcode <= GFX_CMD_BEGIN_FRAME;
                                if (byte_data == 8'd4)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd2: begin
                                command_data.opcode <= GFX_CMD_DRAW_TRIANGLE;
                                if (byte_data == 8'd19)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd3: begin
                                command_data.opcode <= GFX_CMD_END_FRAME;
                                if (byte_data == 8'd0)
                                    state <= CRC_HIGH;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd4: begin
                                command_data.opcode <= GFX_CMD_SET_PALETTE;
                                if (byte_data == 8'd4)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd5: begin
                                command_data.opcode <= GFX_CMD_DEFINE_MESH;
                                if (byte_data == 8'd5)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd6: begin
                                command_data.opcode <= GFX_CMD_UPLOAD_VERTEX;
                                if (byte_data == 8'd8)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd7: begin
                                command_data.opcode <= GFX_CMD_UPLOAD_INDEX;
                                if (byte_data == 8'd7)
                                    state <= PAYLOAD;
                                else begin
                                    decoder_error <= 1'b1;
                                    state <= SYNC_G;
                                end
                            end
                            8'd8: begin
                                command_data.opcode <= GFX_CMD_DRAW_MESH;
                                if (byte_data == 8'd25)
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
                            8'd0: command_data.argument[7:0] <= byte_data;
                            8'd1: begin
                                case (payload_index)
                                    8'd0: command_data.argument[31:24] <= byte_data;
                                    8'd1: command_data.argument[23:16] <= byte_data;
                                    8'd2: command_data.argument[15:8] <= byte_data;
                                    default: command_data.argument[7:0] <= byte_data;
                                endcase
                            end
                            8'd2: begin
                                case (payload_index)
                                    8'd0: command_data.triangle.x0[15:8] <= byte_data;
                                    8'd1: command_data.triangle.x0[7:0] <= byte_data;
                                    8'd2: command_data.triangle.y0[15:8] <= byte_data;
                                    8'd3: command_data.triangle.y0[7:0] <= byte_data;
                                    8'd4: command_data.triangle.z0[15:8] <= byte_data;
                                    8'd5: command_data.triangle.z0[7:0] <= byte_data;
                                    8'd6: command_data.triangle.x1[15:8] <= byte_data;
                                    8'd7: command_data.triangle.x1[7:0] <= byte_data;
                                    8'd8: command_data.triangle.y1[15:8] <= byte_data;
                                    8'd9: command_data.triangle.y1[7:0] <= byte_data;
                                    8'd10: command_data.triangle.z1[15:8] <= byte_data;
                                    8'd11: command_data.triangle.z1[7:0] <= byte_data;
                                    8'd12: command_data.triangle.x2[15:8] <= byte_data;
                                    8'd13: command_data.triangle.x2[7:0] <= byte_data;
                                    8'd14: command_data.triangle.y2[15:8] <= byte_data;
                                    8'd15: command_data.triangle.y2[7:0] <= byte_data;
                                    8'd16: command_data.triangle.z2[15:8] <= byte_data;
                                    8'd17: command_data.triangle.z2[7:0] <= byte_data;
                                    default: command_data.triangle.color <= byte_data;
                                endcase
                            end
                            8'd4: begin
                                case (payload_index)
                                    8'd0: command_data.argument[31:24] <= byte_data;
                                    8'd1: command_data.argument[23:16] <= byte_data;
                                    8'd2: command_data.argument[15:8] <= byte_data;
                                    default: command_data.argument[7:0] <= byte_data;
                                endcase
                            end
                            8'd5: begin
                                case (payload_index)
                                    8'd0: command_data.mesh_handle <= byte_data;
                                    8'd1: command_data.mesh_vertex_count[15:8] <= byte_data;
                                    8'd2: command_data.mesh_vertex_count[7:0] <= byte_data;
                                    8'd3: command_data.mesh_triangle_count[15:8] <= byte_data;
                                    default: command_data.mesh_triangle_count[7:0] <= byte_data;
                                endcase
                            end
                            8'd6: begin
                                case (payload_index)
                                    8'd0: command_data.mesh_handle <= byte_data;
                                    8'd1: command_data.mesh_element[7:0] <= byte_data;
                                    8'd2: command_data.vertex_x[15:8] <= byte_data;
                                    8'd3: command_data.vertex_x[7:0] <= byte_data;
                                    8'd4: command_data.vertex_y[15:8] <= byte_data;
                                    8'd5: command_data.vertex_y[7:0] <= byte_data;
                                    8'd6: command_data.vertex_z[15:8] <= byte_data;
                                    default: command_data.vertex_z[7:0] <= byte_data;
                                endcase
                            end
                            8'd7: begin
                                case (payload_index)
                                    8'd0: command_data.mesh_handle <= byte_data;
                                    8'd1: command_data.mesh_element[15:8] <= byte_data;
                                    8'd2: command_data.mesh_element[7:0] <= byte_data;
                                    8'd3: command_data.mesh_index0 <= byte_data;
                                    8'd4: command_data.mesh_index1 <= byte_data;
                                    8'd5: command_data.mesh_index2 <= byte_data;
                                    default: command_data.mesh_color <= byte_data;
                                endcase
                            end
                            8'd8: begin
                                case (payload_index)
                                    8'd0: command_data.mesh_handle <= byte_data;
                                    8'd1: command_data.model_matrix.m00[15:8] <= byte_data;
                                    8'd2: command_data.model_matrix.m00[7:0] <= byte_data;
                                    8'd3: command_data.model_matrix.m01[15:8] <= byte_data;
                                    8'd4: command_data.model_matrix.m01[7:0] <= byte_data;
                                    8'd5: command_data.model_matrix.m02[15:8] <= byte_data;
                                    8'd6: command_data.model_matrix.m02[7:0] <= byte_data;
                                    8'd7: command_data.model_matrix.m03[15:8] <= byte_data;
                                    8'd8: command_data.model_matrix.m03[7:0] <= byte_data;
                                    8'd9: command_data.model_matrix.m10[15:8] <= byte_data;
                                    8'd10: command_data.model_matrix.m10[7:0] <= byte_data;
                                    8'd11: command_data.model_matrix.m11[15:8] <= byte_data;
                                    8'd12: command_data.model_matrix.m11[7:0] <= byte_data;
                                    8'd13: command_data.model_matrix.m12[15:8] <= byte_data;
                                    8'd14: command_data.model_matrix.m12[7:0] <= byte_data;
                                    8'd15: command_data.model_matrix.m13[15:8] <= byte_data;
                                    8'd16: command_data.model_matrix.m13[7:0] <= byte_data;
                                    8'd17: command_data.model_matrix.m20[15:8] <= byte_data;
                                    8'd18: command_data.model_matrix.m20[7:0] <= byte_data;
                                    8'd19: command_data.model_matrix.m21[15:8] <= byte_data;
                                    8'd20: command_data.model_matrix.m21[7:0] <= byte_data;
                                    8'd21: command_data.model_matrix.m22[15:8] <= byte_data;
                                    8'd22: command_data.model_matrix.m22[7:0] <= byte_data;
                                    8'd23: command_data.model_matrix.m23[15:8] <= byte_data;
                                    default: command_data.model_matrix.m23[7:0] <= byte_data;
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
                        if ({received_crc_high, byte_data} == crc)
                            state <= OUTPUT_COMMAND;
                        else begin
                            decoder_error <= 1'b1;
                            state <= SYNC_G;
                        end
                    end

                    default: state <= SYNC_G;
                endcase
            end
        end
    end

endmodule
