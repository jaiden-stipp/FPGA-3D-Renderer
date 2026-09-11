`include "renderer_types.svh"

module transform_3d_pipeline #(
    parameter int SCREEN_WIDTH = 320,
    parameter int SCREEN_HEIGHT = 240,
    parameter bit BACKFACE_CULL = 1'b1
) (
    input logic clk,
    input logic reset,
    input projection_config_t projection,

    input triangle_3d_t in_data,
    input logic in_valid,
    output logic in_ready,

    output triangle_data_t out_data,
    output logic out_valid,
    input logic out_ready,
    output logic busy,
    output logic triangle_clipped,
    output logic triangle_culled
);

    localparam int MAX_VERTICES = 8;
    localparam logic signed [16:0] RIGHT_EDGE = 17'(SCREEN_WIDTH - 1);
    localparam logic signed [16:0] BOTTOM_EDGE = 17'(SCREEN_HEIGHT - 1);

    typedef enum logic [3:0] {
        IDLE,
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
    logic active_clip_reported;

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
    logic signed [33:0] fan_area;

    function automatic logic signed [15:0] project_x(
        input logic signed [15:0] value_q8_8,
        input logic signed [15:0] reciprocal_q8_8
    );
        logic signed [31:0] product;
        logic signed [47:0] scaled;
        logic signed [48:0] screen_value;
        begin
            product = value_q8_8 * reciprocal_q8_8;
            scaled = product * $signed(projection.focal_x);
            screen_value = $signed(projection.center_x) + (scaled >>> 16);
            project_x = screen_value[15:0];
        end
    endfunction

    function automatic logic signed [15:0] project_y(
        input logic signed [15:0] value_q8_8,
        input logic signed [15:0] reciprocal_q8_8
    );
        logic signed [31:0] product;
        logic signed [47:0] scaled;
        logic signed [48:0] screen_value;
        begin
            product = value_q8_8 * reciprocal_q8_8;
            scaled = product * $signed(projection.focal_y);
            screen_value = $signed(projection.center_y) - (scaled >>> 16);
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
            edge_start_plane = $signed(edge_start_z) - $signed(projection.near_z);
            edge_end_plane = $signed(edge_end_z) - $signed(projection.near_z);
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
            intersection_z = projection.near_z;
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
            polygon_count <= '0;
            clipped_count <= '0;
            clip_edge_index <= '0;
            clip_copy_index <= '0;
            clip_is_near <= 1'b0;
            screen_plane <= '0;
            clip_append_end <= 1'b0;
            project_index <= '0;
            fan_index <= '0;
            active_clip_reported <= 1'b0;
            out_data <= '0;
            out_valid <= 1'b0;
            triangle_clipped <= 1'b0;
            triangle_culled <= 1'b0;
        end else begin
            triangle_clipped <= 1'b0;
            triangle_culled <= 1'b0;
            case (state)
                IDLE: begin
                    if (in_valid && in_ready) begin
                        active_triangle <= in_data;
                        polygon_x[0] <= in_data.x0;
                        polygon_y[0] <= in_data.y0;
                        polygon_z[0] <= in_data.z0;
                        polygon_x[1] <= in_data.x1;
                        polygon_y[1] <= in_data.y1;
                        polygon_z[1] <= in_data.z1;
                        polygon_x[2] <= in_data.x2;
                        polygon_y[2] <= in_data.y2;
                        polygon_z[2] <= in_data.z2;
                        polygon_count <= 4'd3;
                        clip_is_near <= 1'b1;
                        screen_plane <= '0;
                        active_clip_reported <= 1'b0;
                        state <= CLIP_SETUP;
                    end
                end

                CLIP_SETUP: begin
                    clipped_count <= '0;
                    clip_edge_index <= '0;
                    state <= CLIP_EDGE;
                end

                CLIP_EDGE: begin
                    if (!(edge_start_inside && edge_end_inside) &&
                        !active_clip_reported) begin
                        triangle_clipped <= 1'b1;
                        active_clip_reported <= 1'b1;
                    end
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
                        triangle_culled <= 1'b1;
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
