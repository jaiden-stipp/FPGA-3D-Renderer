`include "renderer_types.svh"

module indexed_mesh_store (
    input logic clk,
    input logic reset,
    input logic define_write,
    input logic [7:0] define_handle,
    input logic [15:0] define_vertex_count,
    input logic [15:0] define_triangle_count,
    input logic vertex_write,
    input logic [7:0] vertex_handle,
    input logic [7:0] vertex_number,
    input logic signed [15:0] vertex_x,
    input logic signed [15:0] vertex_y,
    input logic signed [15:0] vertex_z,
    input logic index_write,
    input logic [7:0] index_handle,
    input logic [15:0] index_number,
    input logic [7:0] index0,
    input logic [7:0] index1,
    input logic [7:0] index2,
    input logic [7:0] index_color,
    output logic upload_error,
    input logic draw_valid,
    output logic draw_ready,
    input logic [7:0] draw_handle,
    input model_matrix_3x4_t draw_matrix,
    output triangle_3d_t triangle_data,
    output logic triangle_valid,
    input logic triangle_ready,
    output logic draw_busy,
    output logic draw_done,
    output logic draw_error
);

    localparam int MESH_COUNT = 16;
    localparam int VERTICES_PER_MESH = 128;
    localparam int TRIANGLES_PER_MESH = 256;

    typedef enum logic [3:0] {
        IDLE,
        READ_INDEX,
        READ_INDEX_WAIT,
        READ_VERTEX0,
        READ_VERTEX1,
        READ_VERTEX2,
        TRANSFORM_VERTEX,
        OUTPUT_TRIANGLE
    } mesh_state_t;

    mesh_state_t state;
    (* ramstyle = "M9K" *) logic [47:0] vertex_memory
        [0:MESH_COUNT * VERTICES_PER_MESH - 1];
    (* ramstyle = "M9K" *) logic [31:0] index_memory
        [0:MESH_COUNT * TRIANGLES_PER_MESH - 1];
    logic mesh_valid [0:MESH_COUNT - 1];
    logic [7:0] mesh_vertex_count [0:MESH_COUNT - 1];
    logic [8:0] mesh_triangle_count [0:MESH_COUNT - 1];
    logic [3:0] active_handle;
    logic [8:0] active_triangle_count;
    logic [7:0] triangle_number;
    logic [10:0] vertex_read_address;
    logic [47:0] vertex_read_data;
    logic [11:0] index_read_address;
    logic [31:0] index_read_data;
    logic [31:0] index_record;
    logic [47:0] vertex0;
    logic [47:0] vertex1;
    logic [47:0] vertex2;
    logic [1:0] transform_vertex_number;
    model_matrix_3x4_t active_matrix;
    logic signed [15:0] source_x;
    logic signed [15:0] source_y;
    logic signed [15:0] source_z;
    logic signed [31:0] product_x0;
    logic signed [31:0] product_x1;
    logic signed [31:0] product_x2;
    logic signed [31:0] product_y0;
    logic signed [31:0] product_y1;
    logic signed [31:0] product_y2;
    logic signed [31:0] product_z0;
    logic signed [31:0] product_z1;
    logic signed [31:0] product_z2;
    logic signed [33:0] sum_x;
    logic signed [33:0] sum_y;
    logic signed [33:0] sum_z;
    logic signed [34:0] transformed_x;
    logic signed [34:0] transformed_y;
    logic signed [34:0] transformed_z;

    function automatic logic signed [15:0] saturate_q8_8(
        input logic signed [34:0] value
    );
        begin
            if (value > 35'sd32767)
                saturate_q8_8 = 16'sh7FFF;
            else if (value < -35'sd32768)
                saturate_q8_8 = 16'sh8000;
            else
                saturate_q8_8 = value[15:0];
        end
    endfunction

    always_comb begin
        upload_error = 1'b0;
        if (define_write)
            upload_error = define_handle >= MESH_COUNT ||
                           define_vertex_count == 0 ||
                           define_vertex_count > VERTICES_PER_MESH ||
                           define_triangle_count == 0 ||
                           define_triangle_count > TRIANGLES_PER_MESH;
        else if (vertex_write)
            upload_error = vertex_handle >= MESH_COUNT ||
                           !mesh_valid[vertex_handle[3:0]] ||
                           vertex_number >= mesh_vertex_count[vertex_handle[3:0]];
        else if (index_write)
            upload_error = index_handle >= MESH_COUNT ||
                           !mesh_valid[index_handle[3:0]] ||
                           index_number >= mesh_triangle_count[index_handle[3:0]] ||
                           index0 >= mesh_vertex_count[index_handle[3:0]] ||
                           index1 >= mesh_vertex_count[index_handle[3:0]] ||
                           index2 >= mesh_vertex_count[index_handle[3:0]];

        case (transform_vertex_number)
            2'd0: begin
                source_x = vertex0[47:32];
                source_y = vertex0[31:16];
                source_z = vertex0[15:0];
            end
            2'd1: begin
                source_x = vertex1[47:32];
                source_y = vertex1[31:16];
                source_z = vertex1[15:0];
            end
            default: begin
                source_x = vertex2[47:32];
                source_y = vertex2[31:16];
                source_z = vertex2[15:0];
            end
        endcase

        product_x0 = source_x * active_matrix.m00;
        product_x1 = source_y * active_matrix.m01;
        product_x2 = source_z * active_matrix.m02;
        product_y0 = source_x * active_matrix.m10;
        product_y1 = source_y * active_matrix.m11;
        product_y2 = source_z * active_matrix.m12;
        product_z0 = source_x * active_matrix.m20;
        product_z1 = source_y * active_matrix.m21;
        product_z2 = source_z * active_matrix.m22;
        sum_x = {{2{product_x0[31]}}, product_x0} +
                {{2{product_x1[31]}}, product_x1} +
                {{2{product_x2[31]}}, product_x2};
        sum_y = {{2{product_y0[31]}}, product_y0} +
                {{2{product_y1[31]}}, product_y1} +
                {{2{product_y2[31]}}, product_y2};
        sum_z = {{2{product_z0[31]}}, product_z0} +
                {{2{product_z1[31]}}, product_z1} +
                {{2{product_z2[31]}}, product_z2};
        transformed_x = (sum_x >>> 8) + active_matrix.m03;
        transformed_y = (sum_y >>> 8) + active_matrix.m13;
        transformed_z = (sum_z >>> 8) + active_matrix.m23;
    end

    assign draw_ready = state == IDLE;
    assign draw_busy = state != IDLE;

    always_comb begin
        index_read_address = {active_handle, triangle_number};
        case (state)
            READ_INDEX_WAIT:
                vertex_read_address = {active_handle, index_read_data[6:0]};
            READ_VERTEX0:
                vertex_read_address = {active_handle, index_record[14:8]};
            default:
                vertex_read_address = {active_handle, index_record[22:16]};
        endcase
    end

    always_ff @(posedge clk) begin
        if (vertex_write && !upload_error)
            vertex_memory[{vertex_handle[3:0], vertex_number[6:0]}] <=
                {vertex_x, vertex_y, vertex_z};
        if (index_write && !upload_error)
            index_memory[{index_handle[3:0], index_number[7:0]}] <=
                {index_color, index2, index1, index0};
        vertex_read_data <= vertex_memory[vertex_read_address];
        index_read_data <= index_memory[index_read_address];
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            active_handle <= '0;
            active_triangle_count <= '0;
            triangle_number <= '0;
            index_record <= '0;
            vertex0 <= '0;
            vertex1 <= '0;
            vertex2 <= '0;
            transform_vertex_number <= '0;
            active_matrix <= '0;
            triangle_data <= '0;
            triangle_valid <= 1'b0;
            draw_done <= 1'b0;
            draw_error <= 1'b0;
            for (integer mesh_number = 0; mesh_number < MESH_COUNT;
                 mesh_number = mesh_number + 1) begin
                mesh_valid[mesh_number] <= 1'b0;
                mesh_vertex_count[mesh_number] <= '0;
                mesh_triangle_count[mesh_number] <= '0;
            end
        end else begin
            draw_done <= 1'b0;
            draw_error <= 1'b0;

            if (define_write && !upload_error) begin
                mesh_valid[define_handle[3:0]] <= 1'b1;
                mesh_vertex_count[define_handle[3:0]] <= define_vertex_count[7:0];
                mesh_triangle_count[define_handle[3:0]] <= define_triangle_count[8:0];
            end
            case (state)
                IDLE: begin
                    if (draw_valid && draw_ready) begin
                        if (draw_handle >= MESH_COUNT ||
                            !mesh_valid[draw_handle[3:0]]) begin
                            draw_error <= 1'b1;
                            draw_done <= 1'b1;
                        end else begin
                            active_handle <= draw_handle[3:0];
                            active_triangle_count <=
                                mesh_triangle_count[draw_handle[3:0]];
                            active_matrix <= draw_matrix;
                            triangle_number <= '0;
                            state <= READ_INDEX;
                        end
                    end
                end
                READ_INDEX: begin
                    state <= READ_INDEX_WAIT;
                end
                READ_INDEX_WAIT: begin
                    index_record <= index_read_data;
                    state <= READ_VERTEX0;
                end
                READ_VERTEX0: begin
                    vertex0 <= vertex_read_data;
                    state <= READ_VERTEX1;
                end
                READ_VERTEX1: begin
                    vertex1 <= vertex_read_data;
                    state <= READ_VERTEX2;
                end
                READ_VERTEX2: begin
                    vertex2 <= vertex_read_data;
                    transform_vertex_number <= '0;
                    state <= TRANSFORM_VERTEX;
                end
                TRANSFORM_VERTEX: begin
                    case (transform_vertex_number)
                        2'd0: begin
                            triangle_data.x0 <= saturate_q8_8(transformed_x);
                            triangle_data.y0 <= saturate_q8_8(transformed_y);
                            triangle_data.z0 <= saturate_q8_8(transformed_z);
                        end
                        2'd1: begin
                            triangle_data.x1 <= saturate_q8_8(transformed_x);
                            triangle_data.y1 <= saturate_q8_8(transformed_y);
                            triangle_data.z1 <= saturate_q8_8(transformed_z);
                        end
                        default: begin
                            triangle_data.x2 <= saturate_q8_8(transformed_x);
                            triangle_data.y2 <= saturate_q8_8(transformed_y);
                            triangle_data.z2 <= saturate_q8_8(transformed_z);
                            triangle_data.color <= index_record[31:24];
                        end
                    endcase
                    if (transform_vertex_number == 2'd2) begin
                        triangle_valid <= 1'b1;
                        state <= OUTPUT_TRIANGLE;
                    end else begin
                        transform_vertex_number <= transform_vertex_number + 1'b1;
                    end
                end
                OUTPUT_TRIANGLE: begin
                    if (triangle_valid && triangle_ready) begin
                        triangle_valid <= 1'b0;
                        if ({1'b0, triangle_number} + 1'b1 >= active_triangle_count) begin
                            draw_done <= 1'b1;
                            state <= IDLE;
                        end else begin
                            triangle_number <= triangle_number + 1'b1;
                            state <= READ_INDEX;
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
