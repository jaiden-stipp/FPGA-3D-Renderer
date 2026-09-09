`include "renderer_types.svh"

module transform_3d_pipeline #(
    parameter int SCREEN_WIDTH = 320,
    parameter int SCREEN_HEIGHT = 240,
    parameter logic signed [15:0] CAMERA_Z_Q8_8 = 16'sd1280,
    parameter logic [7:0] VIEW_PITCH_ANGLE = 8'd236,
    parameter logic signed [15:0] NEAR_Z_Q8_8 = 16'sd512,
    parameter bit BACKFACE_CULL = 1'b1
) (
    input logic clk,
    input logic reset,
    input logic [7:0] rotation_angle,

    input triangle_3d_t in_data,
    input logic in_valid,
    output logic in_ready,

    output triangle_data_t out_data,
    output logic out_valid,
    input logic out_ready,
    output logic busy
);

    localparam int CENTER_X = SCREEN_WIDTH / 2;
    localparam int CENTER_Y = SCREEN_HEIGHT / 2;
    localparam int MAX_VERTICES = 8;
    localparam logic signed [16:0] RIGHT_EDGE = 17'(SCREEN_WIDTH - 1);
    localparam logic signed [16:0] BOTTOM_EDGE = 17'(SCREEN_HEIGHT - 1);

    typedef enum logic [3:0] {
        IDLE,
        ROTATE,
        VIEW_PITCH,
        CLIP_SETUP,
        CLIP_EDGE,
        CLIP_INTERSECT_START,
        CLIP_INTERSECT_WAIT,
        CLIP_APPEND_END,
        CLIP_NEXT,
        CLIP_COPY,
        PROJECT_START,
        PROJECT_WAIT,
        TRIANGLE_BUILD,
        OUTPUT
    } transform_state_t;

    transform_state_t state;
    triangle_3d_t active_triangle;
    logic [7:0] active_rotation_angle;
    logic [2:0] vertex_number;

    logic signed [15:0] polygon_x [0:MAX_VERTICES-1];
    logic signed [15:0] polygon_y [0:MAX_VERTICES-1];
    logic signed [15:0] polygon_z [0:MAX_VERTICES-1];
    logic signed [15:0] clipped_x [0:MAX_VERTICES-1];
    logic signed [15:0] clipped_y [0:MAX_VERTICES-1];
    logic signed [15:0] clipped_z [0:MAX_VERTICES-1];
    logic [3:0] polygon_count;
    logic [3:0] clipped_count;
    logic [3:0] clip_edge_index;
    logic [3:0] clip_copy_index;
    logic clip_is_near;
    logic [1:0] screen_plane;
    logic clip_append_end;
    logic [3:0] project_index;
    logic [3:0] fan_index;

    logic signed [15:0] sin_y;
    logic signed [15:0] cos_y;
    logic signed [15:0] sin_pitch;
    logic signed [15:0] cos_pitch;
    logic signed [15:0] current_x;
    logic signed [15:0] current_y;
    logic signed [15:0] current_z;
    logic signed [15:0] yaw_z_result;
    logic signed [15:0] rotate_x_result;
    logic signed [15:0] pitch_y_input;
    logic signed [15:0] pitch_z_input;
    logic signed [15:0] view_y_result;
    logic signed [15:0] view_z_result;
    logic signed [15:0] view_depth_result;

    logic [3:0] edge_start_index;
    logic signed [15:0] edge_start_x;
    logic signed [15:0] edge_start_y;
    logic signed [15:0] edge_start_z;
    logic signed [15:0] edge_end_x;
    logic signed [15:0] edge_end_y;
    logic signed [15:0] edge_end_z;
    logic signed [16:0] edge_start_plane;
    logic signed [16:0] edge_end_plane;
    logic edge_start_inside;
    logic edge_end_inside;

    logic signed [31:0] clip_dividend;
    logic signed [17:0] clip_divisor;
    logic signed [15:0] intersection_x;
    logic signed [15:0] intersection_y;
    logic signed [15:0] intersection_z;

    logic divider_start;
    logic divider_busy;
    logic divider_done;
    logic signed [31:0] divider_numerator;
    logic signed [17:0] divider_denominator;
    logic signed [31:0] divider_quotient;
    logic [7:0] yaw_cosine_angle;
    logic [8:0] pitch_cosine_sum;
    logic [7:0] pitch_cosine_angle;

    logic signed [33:0] fan_area;

    function automatic logic signed [15:0] sine_quarter_q15(
        input logic [3:0] index
    );
        begin
            case (index)
                4'd0: sine_quarter_q15 = 16'sd0;
                4'd1: sine_quarter_q15 = 16'sd3212;
                4'd2: sine_quarter_q15 = 16'sd6393;
                4'd3: sine_quarter_q15 = 16'sd9512;
                4'd4: sine_quarter_q15 = 16'sd12539;
                4'd5: sine_quarter_q15 = 16'sd15446;
                4'd6: sine_quarter_q15 = 16'sd18204;
                4'd7: sine_quarter_q15 = 16'sd20787;
                4'd8: sine_quarter_q15 = 16'sd23170;
                4'd9: sine_quarter_q15 = 16'sd25329;
                4'd10: sine_quarter_q15 = 16'sd27245;
                4'd11: sine_quarter_q15 = 16'sd28898;
                4'd12: sine_quarter_q15 = 16'sd30273;
                4'd13: sine_quarter_q15 = 16'sd31356;
                4'd14: sine_quarter_q15 = 16'sd32137;
                default: sine_quarter_q15 = 16'sd32609;
            endcase
        end
    endfunction

    function automatic logic signed [15:0] sine_q15(
        input logic [7:0] angle
    );
        logic [3:0] index;
        begin
            case (angle[7:6])
                2'b00: index = angle[5:2];
                2'b01: index = 4'd15 - angle[5:2];
                2'b10: index = angle[5:2];
                default: index = 4'd15 - angle[5:2];
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
        begin
            product = value_q8_8 * factor_q1_15;
            mul_q8_8_q1_15 = product[30:15];
        end
    endfunction

    function automatic logic signed [15:0] project_x(
        input logic signed [15:0] value_q8_8,
        input logic signed [15:0] reciprocal_q8_8
    );
        logic signed [31:0] product;
        logic signed [32:0] screen_value;
        begin
            product = value_q8_8 * reciprocal_q8_8;
            screen_value = CENTER_X + (product >>> 8);
            project_x = screen_value[15:0];
        end
    endfunction

    function automatic logic signed [15:0] project_y(
        input logic signed [15:0] value_q8_8,
        input logic signed [15:0] reciprocal_q8_8
    );
        logic signed [31:0] product;
        logic signed [32:0] screen_value;
        begin
            product = value_q8_8 * reciprocal_q8_8;
            screen_value = CENTER_Y - (product >>> 8);
            project_y = screen_value[15:0];
        end
    endfunction

    function automatic logic signed [15:0] interpolate_value(
        input logic signed [15:0] start_value,
        input logic signed [15:0] end_value,
        input logic [16:0] t_q16
    );
        logic signed [16:0] delta;
        logic signed [17:0] fraction;
        logic signed [34:0] product;
        logic signed [35:0] result;
        begin
            delta = $signed({end_value[15], end_value}) -
                    $signed({start_value[15], start_value});
            fraction = $signed({1'b0, t_q16});
            product = delta * fraction;
            result = $signed(start_value) + (product >>> 16);
            interpolate_value = result[15:0];
        end
    endfunction

    function automatic logic signed [33:0] screen_area(
        input logic signed [15:0] ax,
        input logic signed [15:0] ay,
        input logic signed [15:0] bx,
        input logic signed [15:0] by,
        input logic signed [15:0] cx,
        input logic signed [15:0] cy
    );
        logic signed [16:0] bx_ax;
        logic signed [16:0] by_ay;
        logic signed [16:0] cx_ax;
        logic signed [16:0] cy_ay;
        logic signed [33:0] first_product;
        logic signed [33:0] second_product;
        begin
            bx_ax = $signed({bx[15], bx}) - $signed({ax[15], ax});
            by_ay = $signed({by[15], by}) - $signed({ay[15], ay});
            cx_ax = $signed({cx[15], cx}) - $signed({ax[15], ax});
            cy_ay = $signed({cy[15], cy}) - $signed({ay[15], ay});
            first_product = cx_ax * by_ay;
            second_product = cy_ay * bx_ax;
            screen_area = first_product - second_product;
        end
    endfunction

    iterative_signed_divider #(
        .NUMERATOR_WIDTH(32),
        .DENOMINATOR_WIDTH(18)
    ) shared_divider (
        .clk(clk),
        .reset(reset),
        .start(divider_start),
        .numerator(divider_numerator),
        .denominator(divider_denominator),
        .busy(divider_busy),
        .done(divider_done),
        .quotient(divider_quotient)
    );

    always_comb begin
        sin_y = sine_q15(active_rotation_angle);
        yaw_cosine_angle = active_rotation_angle + 8'd64;
        cos_y = sine_q15(yaw_cosine_angle);
        sin_pitch = sine_q15(VIEW_PITCH_ANGLE);
        pitch_cosine_sum = {1'b0, VIEW_PITCH_ANGLE} + 9'd64;
        pitch_cosine_angle = pitch_cosine_sum[7:0];
        cos_pitch = sine_q15(pitch_cosine_angle);

        case (vertex_number)
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

        yaw_z_result =
            -mul_q8_8_q1_15(current_x, sin_y) +
             mul_q8_8_q1_15(current_z, cos_y);
        rotate_x_result =
            mul_q8_8_q1_15(current_x, cos_y) +
            mul_q8_8_q1_15(current_z, sin_y);
        pitch_y_input = polygon_y[vertex_number];
        pitch_z_input = polygon_z[vertex_number];
        view_y_result =
            mul_q8_8_q1_15(pitch_y_input, cos_pitch) -
            mul_q8_8_q1_15(pitch_z_input, sin_pitch);
        view_z_result =
            mul_q8_8_q1_15(pitch_y_input, sin_pitch) +
            mul_q8_8_q1_15(pitch_z_input, cos_pitch);
        view_depth_result = view_z_result + CAMERA_Z_Q8_8;
    end

    always_comb begin
        if (clip_edge_index == 0)
            edge_start_index = polygon_count - 1'b1;
        else
            edge_start_index = clip_edge_index - 1'b1;

        edge_start_x = polygon_x[edge_start_index];
        edge_start_y = polygon_y[edge_start_index];
        edge_start_z = polygon_z[edge_start_index];
        edge_end_x = polygon_x[clip_edge_index];
        edge_end_y = polygon_y[clip_edge_index];
        edge_end_z = polygon_z[clip_edge_index];

        if (clip_is_near) begin
            edge_start_plane = $signed(edge_start_z) - $signed(NEAR_Z_Q8_8);
            edge_end_plane = $signed(edge_end_z) - $signed(NEAR_Z_Q8_8);
        end else begin
            case (screen_plane)
                2'd0: begin
                    edge_start_plane = $signed({edge_start_x[15], edge_start_x});
                    edge_end_plane = $signed({edge_end_x[15], edge_end_x});
                end
                2'd1: begin
                    edge_start_plane = RIGHT_EDGE -
                                       $signed({edge_start_x[15], edge_start_x});
                    edge_end_plane = RIGHT_EDGE -
                                     $signed({edge_end_x[15], edge_end_x});
                end
                2'd2: begin
                    edge_start_plane = $signed({edge_start_y[15], edge_start_y});
                    edge_end_plane = $signed({edge_end_y[15], edge_end_y});
                end
                default: begin
                    edge_start_plane = BOTTOM_EDGE -
                                       $signed({edge_start_y[15], edge_start_y});
                    edge_end_plane = BOTTOM_EDGE -
                                     $signed({edge_end_y[15], edge_end_y});
                end
            endcase
        end

        edge_start_inside = (edge_start_plane >= 0);
        edge_end_inside = (edge_end_plane >= 0);
        clip_dividend =
            $signed({{15{edge_start_plane[16]}}, edge_start_plane}) <<< 16;
        clip_divisor =
            $signed({edge_start_plane[16], edge_start_plane}) -
            $signed({edge_end_plane[16], edge_end_plane});
        intersection_x = interpolate_value(edge_start_x, edge_end_x,
            divider_quotient[16:0]);
        intersection_y = interpolate_value(edge_start_y, edge_end_y,
            divider_quotient[16:0]);
        intersection_z = interpolate_value(edge_start_z, edge_end_z,
            divider_quotient[16:0]);

        if (clip_is_near) begin
            intersection_z = NEAR_Z_Q8_8;
        end else begin
            case (screen_plane)
                2'd0: intersection_x = 16'sd0;
                2'd1: intersection_x = RIGHT_EDGE[15:0];
                2'd2: intersection_y = 16'sd0;
                default: intersection_y = BOTTOM_EDGE[15:0];
            endcase
        end
    end

    always_comb begin
        fan_area = '0;
        if ((fan_index + 1'b1) < polygon_count) begin
            fan_area = screen_area(
                polygon_x[0], polygon_y[0],
                polygon_x[fan_index], polygon_y[fan_index],
                polygon_x[fan_index + 1'b1], polygon_y[fan_index + 1'b1]);
        end

        divider_start = state == CLIP_INTERSECT_START ||
                        (state == PROJECT_START && project_index != polygon_count);
        if (state == CLIP_INTERSECT_START || state == CLIP_INTERSECT_WAIT) begin
            divider_numerator = clip_dividend;
            divider_denominator = clip_divisor;
        end else begin
            divider_numerator = 32'sd65536;
            if (project_index < MAX_VERTICES)
                divider_denominator = {{2{polygon_z[project_index][15]}},
                                       polygon_z[project_index]};
            else
                divider_denominator = 18'sd1;
        end
        in_ready = (state == IDLE) && !out_valid && !reset;
        busy = (state != IDLE) || out_valid || divider_busy;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            active_triangle <= '0;
            active_rotation_angle <= '0;
            vertex_number <= '0;
            polygon_count <= '0;
            clipped_count <= '0;
            clip_edge_index <= '0;
            clip_copy_index <= '0;
            clip_is_near <= 1'b0;
            screen_plane <= '0;
            clip_append_end <= 1'b0;
            project_index <= '0;
            fan_index <= '0;
            out_data <= '0;
            out_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (in_valid && in_ready) begin
                        active_triangle <= in_data;
                        active_rotation_angle <= rotation_angle;
                        vertex_number <= 3'd0;
                        state <= ROTATE;
                    end
                end

                ROTATE: begin
                    polygon_x[vertex_number] <= rotate_x_result;
                    polygon_y[vertex_number] <= current_y;
                    polygon_z[vertex_number] <= yaw_z_result;

                    if (vertex_number == 3'd2) begin
                        vertex_number <= 3'd0;
                        state <= VIEW_PITCH;
                    end else begin
                        vertex_number <= vertex_number + 1'b1;
                    end
                end

                VIEW_PITCH: begin
                    polygon_y[vertex_number] <= view_y_result;
                    polygon_z[vertex_number] <= view_depth_result;

                    if (vertex_number == 3'd2) begin
                        polygon_count <= 4'd3;
                        clip_is_near <= 1'b1;
                        state <= CLIP_SETUP;
                    end else begin
                        vertex_number <= vertex_number + 1'b1;
                    end
                end

                CLIP_SETUP: begin
                    clipped_count <= '0;
                    clip_edge_index <= '0;
                    state <= CLIP_EDGE;
                end

                CLIP_EDGE: begin
                    if (edge_start_inside && edge_end_inside) begin
                        clipped_x[clipped_count] <= edge_end_x;
                        clipped_y[clipped_count] <= edge_end_y;
                        clipped_z[clipped_count] <= edge_end_z;
                        clipped_count <= clipped_count + 1'b1;
                        state <= CLIP_NEXT;
                    end else if (edge_start_inside != edge_end_inside) begin
                        clip_append_end <= !edge_start_inside && edge_end_inside;
                        state <= CLIP_INTERSECT_START;
                    end else begin
                        state <= CLIP_NEXT;
                    end
                end

                CLIP_INTERSECT_START: begin
                    state <= CLIP_INTERSECT_WAIT;
                end

                CLIP_INTERSECT_WAIT: begin
                    if (divider_done) begin
                        clipped_x[clipped_count] <= intersection_x;
                        clipped_y[clipped_count] <= intersection_y;
                        clipped_z[clipped_count] <= intersection_z;
                        clipped_count <= clipped_count + 1'b1;

                        if (clip_append_end)
                            state <= CLIP_APPEND_END;
                        else
                            state <= CLIP_NEXT;
                    end
                end

                CLIP_APPEND_END: begin
                    clipped_x[clipped_count] <= edge_end_x;
                    clipped_y[clipped_count] <= edge_end_y;
                    clipped_z[clipped_count] <= edge_end_z;
                    clipped_count <= clipped_count + 1'b1;
                    state <= CLIP_NEXT;
                end

                CLIP_NEXT: begin
                    if (clip_edge_index == polygon_count - 1'b1) begin
                        clip_copy_index <= '0;
                        state <= CLIP_COPY;
                    end else begin
                        clip_edge_index <= clip_edge_index + 1'b1;
                        state <= CLIP_EDGE;
                    end
                end

                CLIP_COPY: begin
                    if (clip_copy_index < clipped_count) begin
                        polygon_x[clip_copy_index] <= clipped_x[clip_copy_index];
                        polygon_y[clip_copy_index] <= clipped_y[clip_copy_index];
                        polygon_z[clip_copy_index] <= clipped_z[clip_copy_index];
                        clip_copy_index <= clip_copy_index + 1'b1;
                    end else if (clipped_count < 4'd3) begin
                        state <= IDLE;
                    end else begin
                        polygon_count <= clipped_count;

                        if (clip_is_near) begin
                            project_index <= '0;
                            state <= PROJECT_START;
                        end else if (screen_plane == 2'd3) begin
                            fan_index <= 4'd1;
                            state <= TRIANGLE_BUILD;
                        end else begin
                            screen_plane <= screen_plane + 1'b1;
                            state <= CLIP_SETUP;
                        end
                    end
                end

                PROJECT_START: begin
                    if (project_index == polygon_count) begin
                        clip_is_near <= 1'b0;
                        screen_plane <= '0;
                        state <= CLIP_SETUP;
                    end else begin
                        state <= PROJECT_WAIT;
                    end
                end

                PROJECT_WAIT: begin
                    if (divider_done) begin
                        polygon_x[project_index] <=
                            project_x(polygon_x[project_index],
                                      divider_quotient[15:0]);
                        polygon_y[project_index] <=
                            project_y(polygon_y[project_index],
                                      divider_quotient[15:0]);
                        polygon_z[project_index] <= divider_quotient[15:0];
                        project_index <= project_index + 1'b1;
                        state <= PROJECT_START;
                    end
                end

                TRIANGLE_BUILD: begin
                    if (fan_index >= polygon_count - 1'b1) begin
                        state <= IDLE;
                    end else if (!BACKFACE_CULL || (fan_area < 0)) begin
                        out_data.x0 <= polygon_x[0][9:0];
                        out_data.y0 <= polygon_y[0][8:0];
                        out_data.z0 <= polygon_z[0][7:0];
                        out_data.x1 <= polygon_x[fan_index][9:0];
                        out_data.y1 <= polygon_y[fan_index][8:0];
                        out_data.z1 <= polygon_z[fan_index][7:0];
                        out_data.x2 <= polygon_x[fan_index + 1'b1][9:0];
                        out_data.y2 <= polygon_y[fan_index + 1'b1][8:0];
                        out_data.z2 <= polygon_z[fan_index + 1'b1][7:0];
                        out_data.color <= active_triangle.color;
                        out_valid <= 1'b1;
                        state <= OUTPUT;
                    end else begin
                        fan_index <= fan_index + 1'b1;
                    end
                end

                OUTPUT: begin
                    if (out_valid && out_ready) begin
                        out_valid <= 1'b0;
                        fan_index <= fan_index + 1'b1;
                        state <= TRIANGLE_BUILD;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
