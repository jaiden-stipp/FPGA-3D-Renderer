// Legacy fixed-point 3D transform and screen projection stage.

`include "renderer_types.svh"

module transform_3d #(
    parameter int SCREEN_WIDTH = 640,
    parameter int SCREEN_HEIGHT = 480,
    parameter logic signed [15:0] CAMERA_Z_Q8_8 = 16'sd1024,
    parameter bit BACKFACE_CULL = 1'b1
) (
    input  logic        clk,
    input  logic        reset,
    input  logic [7:0] rotation_angle,

    input  triangle_3d_t in_data,
    input  logic         in_valid,
    output logic         in_ready,

    output triangle_data_t out_data,
    output logic           out_valid,
    input  logic           out_ready,
    output logic           busy
);

    localparam int LAST_X = SCREEN_WIDTH - 1;
    localparam int LAST_Y = SCREEN_HEIGHT - 1;

    typedef enum logic [1:0] {
        IDLE,
        CALCULATE,
        OUTPUT
    } transform_state_t;

    transform_state_t state;
    triangle_3d_t active_triangle;

    logic signed [15:0] sin_y;
    logic signed [15:0] cos_y;
    logic signed [15:0] sin_x;
    logic signed [15:0] cos_x;

    logic signed [15:0] x0_y;
    logic signed [15:0] z0_y;
    logic signed [15:0] x1_y;
    logic signed [15:0] z1_y;
    logic signed [15:0] x2_y;
    logic signed [15:0] z2_y;
    logic signed [15:0] x0_rot;
    logic signed [15:0] y0_rot;
    logic signed [15:0] z0_rot;
    logic signed [15:0] x1_rot;
    logic signed [15:0] y1_rot;
    logic signed [15:0] z1_rot;
    logic signed [15:0] x2_rot;
    logic signed [15:0] y2_rot;
    logic signed [15:0] z2_rot;
    logic signed [15:0] depth0;
    logic signed [15:0] depth1;
    logic signed [15:0] depth2;

    logic [9:0] projected_x0;
    logic [9:0] projected_y0;
    logic [9:0] projected_x1;
    logic [9:0] projected_y1;
    logic [9:0] projected_x2;
    logic [9:0] projected_y2;
    logic signed [21:0] projected_area;

    function automatic logic signed [15:0] sine_quarter_q15(
        input logic [5:0] index
    );
        begin
            case (index)
                6'd0:  sine_quarter_q15 = 16'sd0;
                6'd1:  sine_quarter_q15 = 16'sd804;
                6'd2:  sine_quarter_q15 = 16'sd1608;
                6'd3:  sine_quarter_q15 = 16'sd2410;
                6'd4:  sine_quarter_q15 = 16'sd3212;
                6'd5:  sine_quarter_q15 = 16'sd4011;
                6'd6:  sine_quarter_q15 = 16'sd4808;
                6'd7:  sine_quarter_q15 = 16'sd5602;
                6'd8:  sine_quarter_q15 = 16'sd6393;
                6'd9:  sine_quarter_q15 = 16'sd7179;
                6'd10: sine_quarter_q15 = 16'sd7962;
                6'd11: sine_quarter_q15 = 16'sd8739;
                6'd12: sine_quarter_q15 = 16'sd9512;
                6'd13: sine_quarter_q15 = 16'sd10278;
                6'd14: sine_quarter_q15 = 16'sd11039;
                6'd15: sine_quarter_q15 = 16'sd11793;
                6'd16: sine_quarter_q15 = 16'sd12539;
                6'd17: sine_quarter_q15 = 16'sd13279;
                6'd18: sine_quarter_q15 = 16'sd14010;
                6'd19: sine_quarter_q15 = 16'sd14732;
                6'd20: sine_quarter_q15 = 16'sd15446;
                6'd21: sine_quarter_q15 = 16'sd16151;
                6'd22: sine_quarter_q15 = 16'sd16846;
                6'd23: sine_quarter_q15 = 16'sd17530;
                6'd24: sine_quarter_q15 = 16'sd18204;
                6'd25: sine_quarter_q15 = 16'sd18868;
                6'd26: sine_quarter_q15 = 16'sd19519;
                6'd27: sine_quarter_q15 = 16'sd20159;
                6'd28: sine_quarter_q15 = 16'sd20787;
                6'd29: sine_quarter_q15 = 16'sd21403;
                6'd30: sine_quarter_q15 = 16'sd22005;
                6'd31: sine_quarter_q15 = 16'sd22594;
                6'd32: sine_quarter_q15 = 16'sd23170;
                6'd33: sine_quarter_q15 = 16'sd23731;
                6'd34: sine_quarter_q15 = 16'sd24279;
                6'd35: sine_quarter_q15 = 16'sd24811;
                6'd36: sine_quarter_q15 = 16'sd25329;
                6'd37: sine_quarter_q15 = 16'sd25832;
                6'd38: sine_quarter_q15 = 16'sd26319;
                6'd39: sine_quarter_q15 = 16'sd26790;
                6'd40: sine_quarter_q15 = 16'sd27245;
                6'd41: sine_quarter_q15 = 16'sd27683;
                6'd42: sine_quarter_q15 = 16'sd28105;
                6'd43: sine_quarter_q15 = 16'sd28510;
                6'd44: sine_quarter_q15 = 16'sd28898;
                6'd45: sine_quarter_q15 = 16'sd29268;
                6'd46: sine_quarter_q15 = 16'sd29621;
                6'd47: sine_quarter_q15 = 16'sd29956;
                6'd48: sine_quarter_q15 = 16'sd30273;
                6'd49: sine_quarter_q15 = 16'sd30571;
                6'd50: sine_quarter_q15 = 16'sd30852;
                6'd51: sine_quarter_q15 = 16'sd31113;
                6'd52: sine_quarter_q15 = 16'sd31356;
                6'd53: sine_quarter_q15 = 16'sd31580;
                6'd54: sine_quarter_q15 = 16'sd31785;
                6'd55: sine_quarter_q15 = 16'sd31971;
                6'd56: sine_quarter_q15 = 16'sd32137;
                6'd57: sine_quarter_q15 = 16'sd32285;
                6'd58: sine_quarter_q15 = 16'sd32412;
                6'd59: sine_quarter_q15 = 16'sd32521;
                6'd60: sine_quarter_q15 = 16'sd32609;
                6'd61: sine_quarter_q15 = 16'sd32678;
                6'd62: sine_quarter_q15 = 16'sd32728;
                default: sine_quarter_q15 = 16'sd32757;
            endcase
        end
    endfunction

    function automatic logic signed [15:0] sine_q15(
        input logic [7:0] angle
    );
        logic [5:0] index;
        begin
            case (angle[7:6])
                2'b00: index = angle[5:0];
                2'b01: index = 6'd63 - angle[5:0];
                2'b10: index = angle[5:0];
                default: index = 6'd63 - angle[5:0];
            endcase

            if (angle[7:6] >= 2'b10)
                sine_q15 = -sine_quarter_q15(index);
            else
                sine_q15 = sine_quarter_q15(index);
        end
    endfunction

    function automatic logic signed [15:0] mul_q8_8_q1_15(
        input logic signed [15:0] value_q8_8,
        input logic signed [15:0] factor_q1_15
    );
        logic signed [31:0] product;
        logic signed [31:0] scaled_product;
        begin
            product = value_q8_8 * factor_q1_15;
            scaled_product = product >>> 15;
            mul_q8_8_q1_15 = scaled_product[15:0];
        end
    endfunction

    // A five-step reciprocal approximation avoids a large variable divider.
    // Depth is Q8.8 with a nominal camera distance of 4.0.
    function automatic logic signed [15:0] perspective_scale(
        input logic signed [15:0] depth_q8_8
    );
        begin
            if (depth_q8_8 < 16'sd832)
                perspective_scale = 16'sd210;
            else if (depth_q8_8 < 16'sd960)
                perspective_scale = 16'sd190;
            else if (depth_q8_8 < 16'sd1088)
                perspective_scale = 16'sd170;
            else if (depth_q8_8 < 16'sd1216)
                perspective_scale = 16'sd152;
            else
                perspective_scale = 16'sd138;
        end
    endfunction

    function automatic logic [9:0] project_x(
        input logic signed [15:0] value_q8_8,
        input logic signed [15:0] depth_q8_8
    );
        logic signed [15:0] scale_pixels;
        logic signed [31:0] product;
        logic signed [31:0] screen_value;
        begin
            scale_pixels = perspective_scale(depth_q8_8);
            product = value_q8_8 * scale_pixels;
            screen_value = 32'sd320 + (product >>> 8);
            if (screen_value < 0)
                project_x = 10'd0;
            else if (screen_value > LAST_X)
                project_x = LAST_X[9:0];
            else
                project_x = screen_value[9:0];
        end
    endfunction

    function automatic logic [9:0] project_y(
        input logic signed [15:0] value_q8_8,
        input logic signed [15:0] depth_q8_8
    );
        logic signed [15:0] scale_pixels;
        logic signed [31:0] product;
        logic signed [31:0] screen_value;
        begin
            scale_pixels = perspective_scale(depth_q8_8);
            product = value_q8_8 * scale_pixels;
            screen_value = 32'sd240 - (product >>> 8);
            if (screen_value < 0)
                project_y = 10'd0;
            else if (screen_value > LAST_Y)
                project_y = LAST_Y[9:0];
            else
                project_y = screen_value[9:0];
        end
    endfunction

    function automatic logic signed [21:0] screen_area(
        input logic [9:0] ax,
        input logic [9:0] ay,
        input logic [9:0] bx,
        input logic [9:0] by,
        input logic [9:0] cx,
        input logic [9:0] cy
    );
        logic signed [10:0] bx_ax;
        logic signed [10:0] by_ay;
        logic signed [10:0] cx_ax;
        logic signed [10:0] cy_ay;
        logic signed [21:0] first_product;
        logic signed [21:0] second_product;
        begin
            bx_ax = $signed({1'b0, bx}) - $signed({1'b0, ax});
            by_ay = $signed({1'b0, by}) - $signed({1'b0, ay});
            cx_ax = $signed({1'b0, cx}) - $signed({1'b0, ax});
            cy_ay = $signed({1'b0, cy}) - $signed({1'b0, ay});
            first_product = cx_ax * by_ay;
            second_product = cy_ay * bx_ax;
            screen_area = first_product - second_product;
        end
    endfunction

    always_comb begin
        sin_y = sine_q15(rotation_angle);
        cos_y = sine_q15(rotation_angle + 8'd64);
        sin_x = sine_q15(rotation_angle >> 1);
        cos_x = sine_q15((rotation_angle >> 1) + 8'd64);

        x0_y = mul_q8_8_q1_15(active_triangle.x0, cos_y) +
               mul_q8_8_q1_15(active_triangle.z0, sin_y);
        z0_y = -mul_q8_8_q1_15(active_triangle.x0, sin_y) +
                mul_q8_8_q1_15(active_triangle.z0, cos_y);
        y0_rot = mul_q8_8_q1_15(active_triangle.y0, cos_x) -
                 mul_q8_8_q1_15(z0_y, sin_x);
        z0_rot = mul_q8_8_q1_15(active_triangle.y0, sin_x) +
                 mul_q8_8_q1_15(z0_y, cos_x);
        x0_rot = x0_y;

        x1_y = mul_q8_8_q1_15(active_triangle.x1, cos_y) +
               mul_q8_8_q1_15(active_triangle.z1, sin_y);
        z1_y = -mul_q8_8_q1_15(active_triangle.x1, sin_y) +
                mul_q8_8_q1_15(active_triangle.z1, cos_y);
        y1_rot = mul_q8_8_q1_15(active_triangle.y1, cos_x) -
                 mul_q8_8_q1_15(z1_y, sin_x);
        z1_rot = mul_q8_8_q1_15(active_triangle.y1, sin_x) +
                 mul_q8_8_q1_15(z1_y, cos_x);
        x1_rot = x1_y;

        x2_y = mul_q8_8_q1_15(active_triangle.x2, cos_y) +
               mul_q8_8_q1_15(active_triangle.z2, sin_y);
        z2_y = -mul_q8_8_q1_15(active_triangle.x2, sin_y) +
                mul_q8_8_q1_15(active_triangle.z2, cos_y);
        y2_rot = mul_q8_8_q1_15(active_triangle.y2, cos_x) -
                 mul_q8_8_q1_15(z2_y, sin_x);
        z2_rot = mul_q8_8_q1_15(active_triangle.y2, sin_x) +
                 mul_q8_8_q1_15(z2_y, cos_x);
        x2_rot = x2_y;

        depth0 = z0_rot + CAMERA_Z_Q8_8;
        depth1 = z1_rot + CAMERA_Z_Q8_8;
        depth2 = z2_rot + CAMERA_Z_Q8_8;

        projected_x0 = project_x(x0_rot, depth0);
        projected_y0 = project_y(y0_rot, depth0);
        projected_x1 = project_x(x1_rot, depth1);
        projected_y1 = project_y(y1_rot, depth1);
        projected_x2 = project_x(x2_rot, depth2);
        projected_y2 = project_y(y2_rot, depth2);
        projected_area = screen_area(
            projected_x0, projected_y0,
            projected_x1, projected_y1,
            projected_x2, projected_y2);
    end

    always_comb begin
        in_ready = (state == IDLE) && !out_valid && !reset;
        busy = (state != IDLE) || out_valid;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state          <= IDLE;
            active_triangle <= '0;
            out_data       <= '0;
            out_valid      <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (in_valid && in_ready) begin
                        active_triangle <= in_data;
                        state <= CALCULATE;
                    end
                end

                CALCULATE: begin
                    if (!BACKFACE_CULL || (projected_area > 0)) begin
                        out_data.x0 <= projected_x0;
                        out_data.y0 <= projected_y0[8:0];
                        out_data.x1 <= projected_x1;
                        out_data.y1 <= projected_y1[8:0];
                        out_data.x2 <= projected_x2;
                        out_data.y2 <= projected_y2[8:0];
                        out_data.color <= active_triangle.color;
                        out_valid <= 1'b1;
                        state <= OUTPUT;
                    end else begin
                        state <= IDLE;
                    end
                end

                OUTPUT: begin
                    if (out_valid && out_ready) begin
                        out_valid <= 1'b0;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
