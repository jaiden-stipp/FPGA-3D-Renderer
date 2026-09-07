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

typedef enum logic [2:0] {
    GFX_CMD_SET_ROTATION = 3'd0,
    GFX_CMD_BEGIN_FRAME = 3'd1,
    GFX_CMD_DRAW_TRIANGLE = 3'd2,
    GFX_CMD_END_FRAME = 3'd3,
    GFX_CMD_SET_PALETTE = 3'd4
} graphics_command_opcode_t;

typedef struct packed {
    graphics_command_opcode_t opcode;
    triangle_3d_t triangle;
    logic [31:0] argument;
} graphics_command_t;

`endif
