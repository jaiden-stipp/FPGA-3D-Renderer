// VESA 640 x 480 VGA timing with active-low sync pulses.

module vga_timing_640x480 (
    input  logic       pixel_clk,
    input  logic       reset,
    output logic [9:0] x,
    output logic [9:0] y,
    output logic       active,
    output logic       hsync,
    output logic       vsync
);

    localparam int H_ACTIVE = 640;
    localparam int H_FRONT = 16;
    localparam int H_SYNC = 96;
    localparam int H_BACK = 48;
    localparam int H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;

    localparam int V_ACTIVE = 480;
    localparam int V_FRONT = 10;
    localparam int V_SYNC = 2;
    localparam int V_BACK = 33;
    localparam int V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    logic [9:0] h_count;
    logic [9:0] v_count;

    always_ff @(posedge pixel_clk or posedge reset) begin
        if (reset) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= 10'd0;
            if (v_count == V_TOTAL - 1)
                v_count <= 10'd0;
            else
                v_count <= v_count + 10'd1;
        end else begin
            h_count <= h_count + 10'd1;
        end
    end

    always_comb begin
        x = h_count;
        y = v_count;

        active = !reset &&
                 (h_count < H_ACTIVE) &&
                 (v_count < V_ACTIVE);

        hsync = !((h_count >= H_ACTIVE + H_FRONT) &&
                   (h_count <  H_ACTIVE + H_FRONT + H_SYNC));
        vsync = !((v_count >= V_ACTIVE + V_FRONT) &&
                   (v_count <  V_ACTIVE + V_FRONT + V_SYNC));

        if (reset) begin
            hsync = 1'b1;
            vsync = 1'b1;
        end
    end

endmodule
