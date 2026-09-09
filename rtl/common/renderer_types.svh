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
    logic [199:0] payload;
} graphics_command_t;

`define GFX_ARGUMENT(command) command.payload[31:0]
`define GFX_TRIANGLE(command) command.payload[151:0]
`define GFX_MESH_HANDLE(command) command.payload[135:128]
`define GFX_MESH_ELEMENT(command) command.payload[127:112]
`define GFX_MESH_VERTEX_COUNT(command) command.payload[111:96]
`define GFX_MESH_TRIANGLE_COUNT(command) command.payload[95:80]
`define GFX_MESH_INDEX0(command) command.payload[79:72]
`define GFX_MESH_INDEX1(command) command.payload[71:64]
`define GFX_MESH_INDEX2(command) command.payload[63:56]
`define GFX_MESH_COLOR(command) command.payload[55:48]
`define GFX_VERTEX_X(command) command.payload[47:32]
`define GFX_VERTEX_Y(command) command.payload[31:16]
`define GFX_VERTEX_Z(command) command.payload[15:0]
`define GFX_DRAW_MESH_HANDLE(command) command.payload[199:192]
`define GFX_MODEL_MATRIX(command) command.payload[191:0]

`endif
