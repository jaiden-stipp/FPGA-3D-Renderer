`include "renderer_types.svh"

module view_transform_stage (
    input logic clk,
    input logic reset,
    input model_matrix_3x4_t view_matrix,
    input triangle_3d_t in_data,
    input logic in_valid,
    output logic in_ready,
    output triangle_3d_t out_data,
    output logic out_valid,
    input logic out_ready,
    output logic busy
);

    typedef enum logic [1:0] {
        IDLE,
        CALCULATE,
        OUTPUT_VALUE
    } state_t;

    state_t state;
    triangle_3d_t active_triangle;
    model_matrix_3x4_t active_matrix;
    logic [1:0] vertex_index;
    logic [1:0] row_index;
    logic signed [15:0] current_x;
    logic signed [15:0] current_y;
    logic signed [15:0] current_z;
    logic signed [15:0] coefficient_x;
    logic signed [15:0] coefficient_y;
    logic signed [15:0] coefficient_z;
    logic signed [15:0] translation;
    logic signed [31:0] product_x;
    logic signed [31:0] product_y;
    logic signed [31:0] product_z;
    logic signed [34:0] sum_q16_16;
    logic signed [34:0] result_q8_8;
    logic signed [15:0] saturated_result;

    function automatic logic signed [15:0] saturate_q8_8(
        input logic signed [34:0] value
    );
        if (value > 35'sd32767)
            saturate_q8_8 = 16'sh7fff;
        else if (value < -35'sd32768)
            saturate_q8_8 = 16'sh8000;
        else
            saturate_q8_8 = value[15:0];
    endfunction

    always_comb begin
        case (vertex_index)
            2'd0: begin
                current_x = active_triangle.x0;
                current_y = active_triangle.y0;
                current_z = active_triangle.z0;
            end
            2'd1: begin
                current_x = active_triangle.x1;
                current_y = active_triangle.y1;
                current_z = active_triangle.z1;
            end
            default: begin
                current_x = active_triangle.x2;
                current_y = active_triangle.y2;
                current_z = active_triangle.z2;
            end
        endcase

        case (row_index)
            2'd0: begin
                coefficient_x = active_matrix.m00;
                coefficient_y = active_matrix.m01;
                coefficient_z = active_matrix.m02;
                translation = active_matrix.m03;
            end
            2'd1: begin
                coefficient_x = active_matrix.m10;
                coefficient_y = active_matrix.m11;
                coefficient_z = active_matrix.m12;
                translation = active_matrix.m13;
            end
            default: begin
                coefficient_x = active_matrix.m20;
                coefficient_y = active_matrix.m21;
                coefficient_z = active_matrix.m22;
                translation = active_matrix.m23;
            end
        endcase

        product_x = current_x * coefficient_x;
        product_y = current_y * coefficient_y;
        product_z = current_z * coefficient_z;
        sum_q16_16 = product_x + product_y + product_z +
                     ($signed(translation) <<< 8);
        result_q8_8 = sum_q16_16 >>> 8;
        saturated_result = saturate_q8_8(result_q8_8);
        in_ready = state == IDLE;
        out_valid = state == OUTPUT_VALUE;
        busy = state != IDLE;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            active_triangle <= '0;
            active_matrix <= '0;
            out_data <= '0;
            vertex_index <= '0;
            row_index <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (in_valid) begin
                        active_triangle <= in_data;
                        active_matrix <= view_matrix;
                        out_data <= '0;
                        out_data.color <= in_data.color;
                        vertex_index <= '0;
                        row_index <= '0;
                        state <= CALCULATE;
                    end
                end
                CALCULATE: begin
                    case ({vertex_index, row_index})
                        4'b0000: out_data.x0 <= saturated_result;
                        4'b0001: out_data.y0 <= saturated_result;
                        4'b0010: out_data.z0 <= saturated_result;
                        4'b0100: out_data.x1 <= saturated_result;
                        4'b0101: out_data.y1 <= saturated_result;
                        4'b0110: out_data.z1 <= saturated_result;
                        4'b1000: out_data.x2 <= saturated_result;
                        4'b1001: out_data.y2 <= saturated_result;
                        default: out_data.z2 <= saturated_result;
                    endcase
                    if (row_index == 2'd2) begin
                        row_index <= '0;
                        if (vertex_index == 2'd2)
                            state <= OUTPUT_VALUE;
                        else
                            vertex_index <= vertex_index + 1'b1;
                    end else begin
                        row_index <= row_index + 1'b1;
                    end
                end
                OUTPUT_VALUE: begin
                    if (out_ready)
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
