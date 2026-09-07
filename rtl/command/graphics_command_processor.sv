`include "renderer_types.svh"

module graphics_command_processor (
    input logic clk,
    input logic reset,
    input logic restart,

    input graphics_command_t command_data,
    input logic command_valid,
    output logic command_ready,
    output logic command_error,
    output logic frame_done,

    input logic triangle_ready,
    input logic pipeline_idle,
    input logic clear_busy,
    input logic swap_busy,
    input logic swap_done,

    output triangle_3d_t triangle_data,
    output logic triangle_valid,
    output logic [7:0] rotation_angle,
    output logic palette_write,
    output logic [7:0] palette_address,
    output logic [23:0] palette_write_rgb,
    output logic clear_request,
    output logic swap_request
);

    typedef enum logic [2:0] {
        IDLE,
        CLEAR_START,
        CLEAR_WAIT,
        FRAME_ACTIVE,
        DRAIN,
        SWAP_START,
        SWAP_WAIT
    } command_state_t;

    command_state_t state;

    always_comb begin
        command_ready = 1'b0;
        if (!reset && !restart) begin
            case (state)
                IDLE: command_ready = 1'b1;
                FRAME_ACTIVE: begin
                    if (command_data.opcode == GFX_CMD_DRAW_TRIANGLE)
                        command_ready = triangle_ready;
                    else
                        command_ready = 1'b1;
                end
                default: command_ready = 1'b0;
            endcase
        end

        triangle_data = command_data.triangle;
        triangle_valid = (state == FRAME_ACTIVE) && command_valid &&
                         (command_data.opcode == GFX_CMD_DRAW_TRIANGLE);
        palette_write = (state == IDLE) && command_valid && command_ready &&
                        (command_data.opcode == GFX_CMD_SET_PALETTE);
        palette_address = command_data.argument[31:24];
        palette_write_rgb = command_data.argument[23:0];
        clear_request = (state == CLEAR_START);
        swap_request = (state == SWAP_START);
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            rotation_angle <= 8'd0;
            command_error <= 1'b0;
            frame_done <= 1'b0;
        end else if (restart) begin
            state <= IDLE;
            rotation_angle <= 8'd0;
            command_error <= 1'b0;
            frame_done <= 1'b0;
        end else begin
            command_error <= 1'b0;
            frame_done <= 1'b0;

            case (state)
                IDLE: begin
                    if (command_valid && command_ready) begin
                        case (command_data.opcode)
                            GFX_CMD_SET_ROTATION:
                                rotation_angle <= command_data.argument[7:0];
                            GFX_CMD_SET_PALETTE:
                                state <= IDLE;
                            GFX_CMD_BEGIN_FRAME:
                                state <= CLEAR_START;
                            default:
                                command_error <= 1'b1;
                        endcase
                    end
                end

                CLEAR_START: state <= CLEAR_WAIT;

                CLEAR_WAIT: begin
                    if (!clear_busy)
                        state <= FRAME_ACTIVE;
                end

                FRAME_ACTIVE: begin
                    if (command_valid && command_ready) begin
                        case (command_data.opcode)
                            GFX_CMD_DRAW_TRIANGLE: state <= FRAME_ACTIVE;
                            GFX_CMD_END_FRAME: state <= DRAIN;
                            default: command_error <= 1'b1;
                        endcase
                    end
                end

                DRAIN: begin
                    if (pipeline_idle && !clear_busy)
                        state <= SWAP_START;
                end

                SWAP_START: state <= SWAP_WAIT;

                SWAP_WAIT: begin
                    if (swap_done && !swap_busy) begin
                        frame_done <= 1'b1;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
