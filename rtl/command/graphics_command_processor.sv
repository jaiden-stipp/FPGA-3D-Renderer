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
    output logic [31:0] frame_done_id,

    input logic triangle_ready,
    input logic pipeline_idle,
    input logic clear_busy,
    input logic swap_busy,
    input logic swap_done,

    output triangle_3d_t triangle_data,
    output logic triangle_valid,
    output logic mesh_define_write,
    output logic mesh_vertex_write,
    output logic mesh_index_write,
    output logic [7:0] mesh_handle,
    output logic [15:0] mesh_element,
    output logic [15:0] mesh_vertex_count,
    output logic [15:0] mesh_triangle_count,
    output logic [7:0] mesh_index0,
    output logic [7:0] mesh_index1,
    output logic [7:0] mesh_index2,
    output logic [7:0] mesh_color,
    output logic signed [15:0] mesh_vertex_x,
    output logic signed [15:0] mesh_vertex_y,
    output logic signed [15:0] mesh_vertex_z,
    input logic mesh_upload_error,
    output logic mesh_draw_valid,
    input logic mesh_draw_ready,
    output model_matrix_3x4_t mesh_draw_matrix,
    input logic mesh_draw_done,
    input logic mesh_draw_error,
    output logic [7:0] rotation_angle,
    output logic palette_write,
    output logic [7:0] palette_address,
    output logic [23:0] palette_write_rgb,
    output logic clear_request,
    output logic swap_request
);

    typedef enum logic [3:0] {
        IDLE,
        CLEAR_START,
        CLEAR_WAIT,
        FRAME_ACTIVE,
        MESH_WAIT,
        DRAIN,
        SWAP_START,
        SWAP_WAIT
    } command_state_t;

    command_state_t state;
    logic [31:0] active_frame_id;

    always_comb begin
        command_ready = 1'b0;
        if (!reset && !restart) begin
            case (state)
                IDLE: command_ready = 1'b1;
                FRAME_ACTIVE: begin
                    if (command_data.opcode == GFX_CMD_DRAW_TRIANGLE)
                        command_ready = triangle_ready;
                    else if (command_data.opcode == GFX_CMD_DRAW_MESH)
                        command_ready = mesh_draw_ready;
                    else
                        command_ready = 1'b1;
                end
                default: command_ready = 1'b0;
            endcase
        end

        triangle_data = command_data.triangle;
        triangle_valid = (state == FRAME_ACTIVE) && command_valid &&
                         (command_data.opcode == GFX_CMD_DRAW_TRIANGLE);
        mesh_define_write = (state == IDLE) && command_valid && command_ready &&
                            (command_data.opcode == GFX_CMD_DEFINE_MESH);
        mesh_vertex_write = (state == IDLE) && command_valid && command_ready &&
                            (command_data.opcode == GFX_CMD_UPLOAD_VERTEX);
        mesh_index_write = (state == IDLE) && command_valid && command_ready &&
                           (command_data.opcode == GFX_CMD_UPLOAD_INDEX);
        mesh_handle = command_data.mesh_handle;
        mesh_element = command_data.mesh_element;
        mesh_vertex_count = command_data.mesh_vertex_count;
        mesh_triangle_count = command_data.mesh_triangle_count;
        mesh_index0 = command_data.mesh_index0;
        mesh_index1 = command_data.mesh_index1;
        mesh_index2 = command_data.mesh_index2;
        mesh_color = command_data.mesh_color;
        mesh_vertex_x = command_data.vertex_x;
        mesh_vertex_y = command_data.vertex_y;
        mesh_vertex_z = command_data.vertex_z;
        mesh_draw_valid = (state == FRAME_ACTIVE) && command_valid &&
                          (command_data.opcode == GFX_CMD_DRAW_MESH);
        mesh_draw_matrix = command_data.model_matrix;
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
            frame_done_id <= '0;
            active_frame_id <= '0;
        end else if (restart) begin
            state <= IDLE;
            rotation_angle <= 8'd0;
            command_error <= 1'b0;
            frame_done <= 1'b0;
            frame_done_id <= '0;
            active_frame_id <= '0;
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
                            GFX_CMD_DEFINE_MESH,
                            GFX_CMD_UPLOAD_VERTEX,
                            GFX_CMD_UPLOAD_INDEX: begin
                                if (mesh_upload_error)
                                    command_error <= 1'b1;
                            end
                            GFX_CMD_BEGIN_FRAME: begin
                                active_frame_id <= command_data.argument;
                                state <= CLEAR_START;
                            end
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
                            GFX_CMD_DRAW_MESH: state <= MESH_WAIT;
                            GFX_CMD_END_FRAME: state <= DRAIN;
                            default: command_error <= 1'b1;
                        endcase
                    end
                end

                MESH_WAIT: begin
                    if (mesh_draw_done) begin
                        if (mesh_draw_error)
                            command_error <= 1'b1;
                        state <= FRAME_ACTIVE;
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
                        frame_done_id <= active_frame_id;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
