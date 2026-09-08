`include "renderer_types.svh"

module graphics_renderer_core (
    input logic clk,
    input logic reset,
    input logic restart,
    input graphics_command_t command_data,
    input logic command_valid,
    output logic command_ready,
    output logic command_error,
    output logic frame_done,
    output logic [31:0] frame_done_id,
    output logic [7:0] VGA_R,
    output logic [7:0] VGA_G,
    output logic [7:0] VGA_B,
    output logic VGA_CLK,
    output logic VGA_BLANK_N,
    output logic VGA_SYNC_N,
    output logic VGA_HS,
    output logic VGA_VS
);

    logic direct_triangle_valid;
    logic direct_triangle_ready;
    logic pipeline_triangle_valid;
    logic pipeline_triangle_ready;
    logic mesh_triangle_valid;
    logic mesh_triangle_ready;
    logic mesh_define_write;
    logic mesh_vertex_write;
    logic mesh_index_write;
    logic [7:0] mesh_handle;
    logic [15:0] mesh_element;
    logic [15:0] mesh_vertex_count;
    logic [15:0] mesh_triangle_count;
    logic [7:0] mesh_index0;
    logic [7:0] mesh_index1;
    logic [7:0] mesh_index2;
    logic [7:0] mesh_color;
    logic signed [15:0] mesh_vertex_x;
    logic signed [15:0] mesh_vertex_y;
    logic signed [15:0] mesh_vertex_z;
    logic mesh_upload_error;
    logic mesh_draw_valid;
    logic mesh_draw_ready;
    logic mesh_draw_busy;
    logic mesh_draw_done;
    logic mesh_draw_error;
    model_matrix_3x4_t mesh_draw_matrix;
    logic pipeline_idle;
    logic clear_request;
    logic clear_busy;
    logic swap_request;
    logic swap_busy;
    logic swap_done;
    logic [7:0] rotation_angle;
    logic palette_write;
    logic [7:0] palette_address;
    logic [23:0] palette_write_rgb;
    triangle_3d_t direct_triangle_data;
    triangle_3d_t mesh_triangle_data;
    triangle_3d_t pipeline_triangle_data;

    assign pipeline_triangle_data = mesh_triangle_valid ? mesh_triangle_data :
                                    direct_triangle_data;
    assign pipeline_triangle_valid = mesh_triangle_valid || direct_triangle_valid;
    assign mesh_triangle_ready = pipeline_triangle_ready;
    assign direct_triangle_ready = pipeline_triangle_ready && !mesh_triangle_valid;

    graphics_command_processor command_processor (
        .clk(clk),
        .reset(reset),
        .restart(restart),
        .command_data(command_data),
        .command_valid(command_valid),
        .command_ready(command_ready),
        .command_error(command_error),
        .frame_done(frame_done),
        .frame_done_id(frame_done_id),
        .triangle_ready(direct_triangle_ready),
        .pipeline_idle(pipeline_idle),
        .clear_busy(clear_busy),
        .swap_busy(swap_busy),
        .swap_done(swap_done),
        .triangle_data(direct_triangle_data),
        .triangle_valid(direct_triangle_valid),
        .mesh_define_write(mesh_define_write),
        .mesh_vertex_write(mesh_vertex_write),
        .mesh_index_write(mesh_index_write),
        .mesh_handle(mesh_handle),
        .mesh_element(mesh_element),
        .mesh_vertex_count(mesh_vertex_count),
        .mesh_triangle_count(mesh_triangle_count),
        .mesh_index0(mesh_index0),
        .mesh_index1(mesh_index1),
        .mesh_index2(mesh_index2),
        .mesh_color(mesh_color),
        .mesh_vertex_x(mesh_vertex_x),
        .mesh_vertex_y(mesh_vertex_y),
        .mesh_vertex_z(mesh_vertex_z),
        .mesh_upload_error(mesh_upload_error),
        .mesh_draw_valid(mesh_draw_valid),
        .mesh_draw_ready(mesh_draw_ready),
        .mesh_draw_matrix(mesh_draw_matrix),
        .mesh_draw_done(mesh_draw_done),
        .mesh_draw_error(mesh_draw_error),
        .rotation_angle(rotation_angle),
        .palette_write(palette_write),
        .palette_address(palette_address),
        .palette_write_rgb(palette_write_rgb),
        .clear_request(clear_request),
        .swap_request(swap_request)
    );

    indexed_mesh_store mesh_store (
        .clk(clk),
        .reset(reset || restart),
        .define_write(mesh_define_write),
        .define_handle(mesh_handle),
        .define_vertex_count(mesh_vertex_count),
        .define_triangle_count(mesh_triangle_count),
        .vertex_write(mesh_vertex_write),
        .vertex_handle(mesh_handle),
        .vertex_number(mesh_element[7:0]),
        .vertex_x(mesh_vertex_x),
        .vertex_y(mesh_vertex_y),
        .vertex_z(mesh_vertex_z),
        .index_write(mesh_index_write),
        .index_handle(mesh_handle),
        .index_number(mesh_element),
        .index0(mesh_index0),
        .index1(mesh_index1),
        .index2(mesh_index2),
        .index_color(mesh_color),
        .upload_error(mesh_upload_error),
        .draw_valid(mesh_draw_valid),
        .draw_ready(mesh_draw_ready),
        .draw_handle(mesh_handle),
        .draw_matrix(mesh_draw_matrix),
        .triangle_data(mesh_triangle_data),
        .triangle_valid(mesh_triangle_valid),
        .triangle_ready(mesh_triangle_ready),
        .draw_busy(mesh_draw_busy),
        .draw_done(mesh_draw_done),
        .draw_error(mesh_draw_error)
    );

    graphics_pipeline pipeline (
        .CLOCK_50(clk),
        .reset(reset),
        .triangle_in_data(pipeline_triangle_data),
        .triangle_in_valid(pipeline_triangle_valid),
        .triangle_in_ready(pipeline_triangle_ready),
        .rotation_angle(rotation_angle),
        .clear_request(clear_request),
        .clear_busy(clear_busy),
        .swap_request(swap_request),
        .swap_busy(swap_busy),
        .swap_done(swap_done),
        .pipeline_idle(pipeline_idle),
        .palette_write(palette_write),
        .palette_address(palette_address),
        .palette_write_rgb(palette_write_rgb),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_CLK(VGA_CLK),
        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS)
    );

endmodule
