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

`endif
