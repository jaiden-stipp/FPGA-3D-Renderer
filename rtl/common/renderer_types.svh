`ifndef RENDERER_TYPES_SVH
`define RENDERER_TYPES_SVH

typedef struct packed {
    logic [9:0] x0;
    logic [9:0] x1;
    logic [9:0] x2;
    logic [8:0] y0;
    logic [8:0] y1;
    logic [8:0] y2;
    logic [7:0] z0;
    logic [7:0] z1;
    logic [7:0] z2;
    logic [7:0] color;
} triangle_data_t;

typedef struct packed {
    logic signed [15:0] x0;
    logic signed [15:0] y0;
    logic signed [15:0] z0;
    logic signed [15:0] x1;
    logic signed [15:0] y1;
    logic signed [15:0] z1;
    logic signed [15:0] x2;
    logic signed [15:0] y2;
    logic signed [15:0] z2;
    logic [7:0] color;
} triangle_3d_t;

typedef struct packed {
    logic signed [15:0] m00;
    logic signed [15:0] m01;
    logic signed [15:0] m02;
    logic signed [15:0] m03;
    logic signed [15:0] m10;
    logic signed [15:0] m11;
    logic signed [15:0] m12;
    logic signed [15:0] m13;
    logic signed [15:0] m20;
    logic signed [15:0] m21;
    logic signed [15:0] m22;
    logic signed [15:0] m23;
} model_matrix_3x4_t;

typedef enum logic [3:0] {
    GFX_CMD_SET_ROTATION = 4'd0,
    GFX_CMD_BEGIN_FRAME = 4'd1,
    GFX_CMD_DRAW_TRIANGLE = 4'd2,
    GFX_CMD_END_FRAME = 4'd3,
    GFX_CMD_SET_PALETTE = 4'd4,
    GFX_CMD_DEFINE_MESH = 4'd5,
    GFX_CMD_UPLOAD_VERTEX = 4'd6,
    GFX_CMD_UPLOAD_INDEX = 4'd7,
    GFX_CMD_DRAW_MESH = 4'd8
} graphics_command_opcode_t;

typedef struct packed {
    graphics_command_opcode_t opcode;
    triangle_3d_t triangle;
    logic [31:0] argument;
    logic [7:0] mesh_handle;
    logic [15:0] mesh_element;
    logic [15:0] mesh_vertex_count;
    logic [15:0] mesh_triangle_count;
    logic [7:0] mesh_index0;
    logic [7:0] mesh_index1;
    logic [7:0] mesh_index2;
    logic [7:0] mesh_color;
    logic signed [15:0] vertex_x;
    logic signed [15:0] vertex_y;
    logic signed [15:0] vertex_z;
    model_matrix_3x4_t model_matrix;
} graphics_command_t;

`endif
