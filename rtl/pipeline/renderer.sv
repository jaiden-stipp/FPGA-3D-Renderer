`include "renderer_types.svh"

module renderer #(
    parameter int FRAME_WIDTH = 320,
    parameter int FRAME_HEIGHT = 240
) (
    input logic clk,
    input logic reset,
    input triangle_data_t triangle_data,
    input logic triangle_valid,
    output logic triangle_ready,
    output logic raster_write,
    output logic [9:0] raster_x,
    output logic [8:0] raster_y,
    output logic [7:0] raster_color,
    output logic depth_read_enable,
    output logic [9:0] depth_read_x,
    output logic [8:0] depth_read_y,
    input logic [7:0] depth_read_value,
    input logic depth_read_valid,
    output logic depth_write_enable,
    output logic [9:0] depth_write_x,
    output logic [8:0] depth_write_y,
    output logic [7:0] depth_write_value
);

    localparam int LAST_X = FRAME_WIDTH - 1;
    localparam int LAST_Y = FRAME_HEIGHT - 1;

    typedef enum logic [2:0] {
        IDLE,
        SETUP,
        SETUP_DIVIDE_START,
        SETUP_DIVIDE_WAIT,
        SETUP_DEPTH_PRODUCTS,
        SETUP_DEPTH_SUM,
        RASTERIZE,
        DRAIN
    } raster_state_t;

    raster_state_t state;

    logic [9:0] v0_x, v1_x, v2_x;
    logic [8:0] v0_y, v1_y, v2_y;
    logic [7:0] v0_depth, v1_depth, v2_depth;
    logic [7:0] active_color;

    logic [9:0] raw_min_x, raw_max_x, clipped_min_x, clipped_max_x;
    logic [8:0] raw_min_y, raw_max_y, clipped_min_y, clipped_max_y;
    logic bounding_box_valid;

    logic signed [21:0] triangle_area;
    logic signed [21:0] standard_area;
    logic signed [21:0] edge_01;
    logic signed [21:0] edge_12;
    logic signed [21:0] edge_20;
    logic signed [21:0] row_edge_01;
    logic signed [21:0] row_edge_12;
    logic signed [21:0] row_edge_20;
    logic signed [21:0] step_x_01;
    logic signed [21:0] step_x_12;
    logic signed [21:0] step_x_20;
    logic signed [21:0] step_y_01;
    logic signed [21:0] step_y_12;
    logic signed [21:0] step_y_20;

    logic signed [11:0] depth_dx1;
    logic signed [10:0] depth_dy1;
    logic signed [11:0] depth_dx2;
    logic signed [10:0] depth_dy2;
    logic signed [16:0] depth_f0;
    logic signed [16:0] depth_f1;
    logic signed [16:0] depth_f2;
    logic signed [31:0] depth_dx_numerator;
    logic signed [31:0] depth_dy_numerator;
    logic signed [31:0] depth_step_x;
    logic signed [31:0] depth_step_y;
    logic depth_divide_start;
    logic depth_dx_done;
    logic depth_dy_done;
    logic signed [31:0] depth_dx_quotient;
    logic signed [31:0] depth_dy_quotient;
    logic signed [11:0] depth_offset_x;
    logic signed [10:0] depth_offset_y;
    logic signed [11:0] setup_offset_x;
    logic signed [10:0] setup_offset_y;
    logic signed [35:0] setup_base_depth;
    logic signed [35:0] depth_start_x;
    logic signed [35:0] depth_start_y;
    logic signed [35:0] current_depth;
    logic signed [35:0] row_depth;

    logic [9:0] current_x;
    logic [8:0] current_y;
    logic current_pixel_inside;

    logic [9:0] pending_x;
    logic [8:0] pending_y;
    logic [7:0] pending_color;
    logic [7:0] pending_depth;
    logic pending_valid;
    logic [7:0] current_depth_byte;

    function automatic [9:0] min3_x(
        input logic [9:0] a,
        input logic [9:0] b,
        input logic [9:0] c
    );
        begin
            min3_x = (a < b) ? a : b;
            min3_x = (min3_x < c) ? min3_x : c;
        end
    endfunction

    function automatic [8:0] min3_y(
        input logic [8:0] a,
        input logic [8:0] b,
        input logic [8:0] c
    );
        begin
            min3_y = (a < b) ? a : b;
            min3_y = (min3_y < c) ? min3_y : c;
        end
    endfunction

    function automatic [9:0] max3_x(
        input logic [9:0] a,
        input logic [9:0] b,
        input logic [9:0] c
    );
        begin
            max3_x = (a > b) ? a : b;
            max3_x = (max3_x > c) ? max3_x : c;
        end
    endfunction

    function automatic [8:0] max3_y(
        input logic [8:0] a,
        input logic [8:0] b,
        input logic [8:0] c
    );
        begin
            max3_y = (a > b) ? a : b;
            max3_y = (max3_y > c) ? max3_y : c;
        end
    endfunction

    function automatic logic signed [21:0] edge_value(
        input logic [9:0] ax,
        input logic [8:0] ay,
        input logic [9:0] bx,
        input logic [8:0] by,
        input logic [9:0] px,
        input logic [8:0] py
    );
        logic signed [10:0] dx;
        logic signed [9:0] dy;
        logic signed [10:0] x_offset;
        logic signed [9:0] y_offset;
        logic signed [21:0] x_term;
        logic signed [21:0] y_term;
        begin
            dx = $signed({1'b0, bx}) - $signed({1'b0, ax});
            dy = $signed({1'b0, by}) - $signed({1'b0, ay});
            x_offset = $signed({1'b0, px}) - $signed({1'b0, ax});
            y_offset = $signed({1'b0, py}) - $signed({1'b0, ay});
            x_term = x_offset * dy;
            y_term = y_offset * dx;
            edge_value = x_term - y_term;
        end
    endfunction

    function automatic logic signed [21:0] edge_step_x(
        input logic [8:0] ay,
        input logic [8:0] by
    );
        begin
            edge_step_x = $signed({1'b0, by}) - $signed({1'b0, ay});
        end
    endfunction

    function automatic logic signed [21:0] edge_step_y(
        input logic [9:0] ax,
        input logic [9:0] bx
    );
        begin
            edge_step_y = $signed({1'b0, ax}) - $signed({1'b0, bx});
        end
    endfunction

    iterative_signed_divider #(
        .NUMERATOR_WIDTH(32),
        .DENOMINATOR_WIDTH(22)
    ) depth_dx_divider (
        .clk(clk),
        .reset(reset),
        .start(depth_divide_start),
        .numerator(depth_dx_numerator),
        .denominator(standard_area),
        .busy(),
        .done(depth_dx_done),
        .quotient(depth_dx_quotient)
    );

    iterative_signed_divider #(
        .NUMERATOR_WIDTH(32),
        .DENOMINATOR_WIDTH(22)
    ) depth_dy_divider (
        .clk(clk),
        .reset(reset),
        .start(depth_divide_start),
        .numerator(depth_dy_numerator),
        .denominator(standard_area),
        .busy(),
        .done(depth_dy_done),
        .quotient(depth_dy_quotient)
    );

    always_comb begin
        raw_min_x = min3_x(v0_x, v1_x, v2_x);
        raw_max_x = max3_x(v0_x, v1_x, v2_x);
        raw_min_y = min3_y(v0_y, v1_y, v2_y);
        raw_max_y = max3_y(v0_y, v1_y, v2_y);
        clipped_min_x = raw_min_x;
        clipped_min_y = raw_min_y;
        clipped_max_x = (raw_max_x > LAST_X) ? LAST_X[9:0] : raw_max_x;
        clipped_max_y = (raw_max_y > LAST_Y) ? LAST_Y[8:0] : raw_max_y;
        bounding_box_valid = (raw_min_x <= LAST_X) && (raw_min_y <= LAST_Y);
        triangle_area = edge_value(v0_x, v0_y, v1_x, v1_y, v2_x, v2_y);
        standard_area = -triangle_area;
        depth_dx1 = $signed({1'b0, v1_x}) - $signed({1'b0, v0_x});
        depth_dy1 = $signed({1'b0, v1_y}) - $signed({1'b0, v0_y});
        depth_dx2 = $signed({1'b0, v2_x}) - $signed({1'b0, v0_x});
        depth_dy2 = $signed({1'b0, v2_y}) - $signed({1'b0, v0_y});
        depth_f0 = $signed({1'b0, v0_depth, 8'b0});
        depth_f1 = $signed({1'b0, v1_depth, 8'b0});
        depth_f2 = $signed({1'b0, v2_depth, 8'b0});
        depth_dx_numerator = (depth_f1 - depth_f0) * depth_dy2 -
                             (depth_f2 - depth_f0) * depth_dy1;
        depth_dy_numerator = depth_dx1 * (depth_f2 - depth_f0) -
                             depth_dx2 * (depth_f1 - depth_f0);
        depth_offset_x = $signed({1'b0, clipped_min_x}) - $signed({1'b0, v0_x});
        depth_offset_y = $signed({1'b0, clipped_min_y}) - $signed({1'b0, v0_y});
        if (current_depth < 0)
            current_depth_byte = 8'h00;
        else if (current_depth > 36'sd65280)
            current_depth_byte = 8'hff;
        else
            current_depth_byte = current_depth[15:8];
    end

    always_comb begin
        if (triangle_area > 0) begin
            current_pixel_inside =
                (edge_01 >= 0) && (edge_12 >= 0) && (edge_20 >= 0);
        end else if (triangle_area < 0) begin
            current_pixel_inside =
                (edge_01 <= 0) && (edge_12 <= 0) && (edge_20 <= 0);
        end else begin
            current_pixel_inside = 1'b0;
        end

        triangle_ready = (state == IDLE) && !reset;
        depth_read_enable = (state == RASTERIZE) && current_pixel_inside;
        depth_read_x = current_x;
        depth_read_y = current_y;
        raster_write = pending_valid && depth_read_valid &&
                       (pending_depth > depth_read_value);
        raster_x = pending_x;
        raster_y = pending_y;
        raster_color = pending_color;
        depth_write_enable = raster_write;
        depth_write_x = pending_x;
        depth_write_y = pending_y;
        depth_write_value = pending_depth;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            v0_x <= '0;
            v0_y <= '0;
            v1_x <= '0;
            v1_y <= '0;
            v2_x <= '0;
            v2_y <= '0;
            v0_depth <= '0;
            v1_depth <= '0;
            v2_depth <= '0;
            active_color <= '0;
            current_x <= '0;
            current_y <= '0;
            edge_01 <= '0;
            edge_12 <= '0;
            edge_20 <= '0;
            row_edge_01 <= '0;
            row_edge_12 <= '0;
            row_edge_20 <= '0;
            step_x_01 <= '0;
            step_x_12 <= '0;
            step_x_20 <= '0;
            step_y_01 <= '0;
            step_y_12 <= '0;
            step_y_20 <= '0;
            depth_step_x <= '0;
            depth_step_y <= '0;
            setup_offset_x <= '0;
            setup_offset_y <= '0;
            setup_base_depth <= '0;
            depth_start_x <= '0;
            depth_start_y <= '0;
            current_depth <= '0;
            row_depth <= '0;
            depth_divide_start <= 1'b0;
            pending_x <= '0;
            pending_y <= '0;
            pending_color <= '0;
            pending_depth <= '0;
            pending_valid <= 1'b0;
        end else begin
            depth_divide_start <= 1'b0;
            pending_valid <= depth_read_enable;
            if (depth_read_enable) begin
                pending_x <= current_x;
                pending_y <= current_y;
                pending_color <= active_color;
                pending_depth <= current_depth_byte;
            end

            case (state)
                IDLE: begin
                    if (triangle_valid) begin
                        v0_x <= triangle_data.x0;
                        v0_y <= triangle_data.y0;
                        v1_x <= triangle_data.x1;
                        v1_y <= triangle_data.y1;
                        v2_x <= triangle_data.x2;
                        v2_y <= triangle_data.y2;
                        v0_depth <= triangle_data.z0;
                        v1_depth <= triangle_data.z1;
                        v2_depth <= triangle_data.z2;
                        active_color <= triangle_data.color;
                        state <= SETUP;
                    end
                end

                SETUP: begin
                    if (!bounding_box_valid || (triangle_area == 0)) begin
                        state <= IDLE;
                    end else begin
                        current_x <= clipped_min_x;
                        current_y <= clipped_min_y;
                        edge_01 <= edge_value(v0_x, v0_y, v1_x, v1_y,
                                              clipped_min_x, clipped_min_y);
                        edge_12 <= edge_value(v1_x, v1_y, v2_x, v2_y,
                                              clipped_min_x, clipped_min_y);
                        edge_20 <= edge_value(v2_x, v2_y, v0_x, v0_y,
                                              clipped_min_x, clipped_min_y);
                        row_edge_01 <= edge_value(v0_x, v0_y, v1_x, v1_y,
                                                  clipped_min_x, clipped_min_y);
                        row_edge_12 <= edge_value(v1_x, v1_y, v2_x, v2_y,
                                                  clipped_min_x, clipped_min_y);
                        row_edge_20 <= edge_value(v2_x, v2_y, v0_x, v0_y,
                                                  clipped_min_x, clipped_min_y);
                        step_x_01 <= edge_step_x(v0_y, v1_y);
                        step_x_12 <= edge_step_x(v1_y, v2_y);
                        step_x_20 <= edge_step_x(v2_y, v0_y);
                        step_y_01 <= edge_step_y(v0_x, v1_x);
                        step_y_12 <= edge_step_y(v1_x, v2_x);
                        step_y_20 <= edge_step_y(v2_x, v0_x);
                        setup_offset_x <= depth_offset_x;
                        setup_offset_y <= depth_offset_y;
                        setup_base_depth <= $signed({1'b0, v0_depth, 8'b0});
                        state <= SETUP_DIVIDE_START;
                    end
                end

                SETUP_DIVIDE_START: begin
                    depth_divide_start <= 1'b1;
                    state <= SETUP_DIVIDE_WAIT;
                end

                SETUP_DIVIDE_WAIT: begin
                    if (depth_dx_done && depth_dy_done) begin
                        depth_step_x <= depth_dx_quotient;
                        depth_step_y <= depth_dy_quotient;
                        state <= SETUP_DEPTH_PRODUCTS;
                    end
                end

                SETUP_DEPTH_PRODUCTS: begin
                    depth_start_x <= depth_step_x * setup_offset_x;
                    depth_start_y <= depth_step_y * setup_offset_y;
                    state <= SETUP_DEPTH_SUM;
                end

                SETUP_DEPTH_SUM: begin
                    current_depth <= setup_base_depth + depth_start_x + depth_start_y;
                    row_depth <= setup_base_depth + depth_start_x + depth_start_y;
                    state <= RASTERIZE;
                end

                RASTERIZE: begin
                    if (current_x == clipped_max_x) begin
                        if (current_y == clipped_max_y) begin
                            state <= DRAIN;
                        end else begin
                            current_x <= clipped_min_x;
                            current_y <= current_y + 1'b1;
                            row_edge_01 <= row_edge_01 + step_y_01;
                            row_edge_12 <= row_edge_12 + step_y_12;
                            row_edge_20 <= row_edge_20 + step_y_20;
                            edge_01 <= row_edge_01 + step_y_01;
                            edge_12 <= row_edge_12 + step_y_12;
                            edge_20 <= row_edge_20 + step_y_20;
                            row_depth <= row_depth + depth_step_y;
                            current_depth <= row_depth + depth_step_y;
                        end
                    end else begin
                        current_x <= current_x + 1'b1;
                        edge_01 <= edge_01 + step_x_01;
                        edge_12 <= edge_12 + step_x_12;
                        edge_20 <= edge_20 + step_x_20;
                        current_depth <= current_depth + depth_step_x;
                    end
                end

                DRAIN: state <= IDLE;

                default: state <= IDLE;
            endcase
        end
    end

endmodule
