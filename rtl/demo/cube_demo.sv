// Rotating cube and pyramid triangle feeder.

`include "renderer_types.svh"

module cube_demo (
    input  logic         clk,
    input  logic         reset,
    input  logic         restart,
    input  logic         command_ready,
    input  logic         frame_done,
    output logic         command_valid,
    output graphics_command_t command_data
);

    localparam logic signed [15:0] NEG_ONE = 16'shFF00;
    localparam logic signed [15:0] POS_ONE = 16'sh0100;
    localparam logic signed [15:0] PYRAMID_LEFT = 16'sh0180;
    localparam logic signed [15:0] PYRAMID_RIGHT = 16'sh0300;
    localparam logic signed [15:0] PYRAMID_CENTER = 16'sh0240;
    localparam logic signed [15:0] PYRAMID_BASE_Y = 16'shFF40;
    localparam logic signed [15:0] PYRAMID_APEX_Y = 16'sh00E0;
    localparam logic signed [15:0] PYRAMID_NEAR_Z = 16'shFF40;
    localparam logic signed [15:0] PYRAMID_FAR_Z = 16'sh00C0;
    localparam logic signed [15:0] TALL_PYRAMID_LEFT = 16'shFD00;
    localparam logic signed [15:0] TALL_PYRAMID_RIGHT = 16'shFE80;
    localparam logic signed [15:0] TALL_PYRAMID_CENTER = 16'shFDC0;
    localparam logic signed [15:0] TALL_PYRAMID_BASE_Y = 16'shFF40;
    localparam logic signed [15:0] TALL_PYRAMID_APEX_Y = 16'sh0120;
    localparam logic signed [15:0] TALL_PYRAMID_NEAR_Z = 16'shFF40;
    localparam logic signed [15:0] TALL_PYRAMID_FAR_Z = 16'sh00C0;
    localparam int TRIANGLE_COUNT = 24;

    typedef enum logic [2:0] {
        SET_VIEW,
        BEGIN_FRAME,
        FEED,
        END_FRAME,
        WAIT_FRAME
    } demo_state_t;

    demo_state_t state;
    logic [4:0] triangle_number;
    logic [7:0] angle;
    logic [31:0] frame_id;
    triangle_3d_t triangle_data;
    model_matrix_3x4_t demo_view_matrix;
    logic signed [15:0] yaw_sine;
    logic signed [15:0] yaw_cosine;

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
        input logic [7:0] value
    );
        logic [3:0] index;
        begin
            case (value[7:6])
                2'b00: index = value[5:2];
                2'b01: index = 4'd15 - value[5:2];
                2'b10: index = value[5:2];
                default: index = 4'd15 - value[5:2];
            endcase
            sine_q15 = value[7] ? -sine_quarter_q15(index) :
                                  sine_quarter_q15(index);
        end
    endfunction

    function automatic logic signed [15:0] q15_to_q8_8(
        input logic signed [15:0] value
    );
        q15_to_q8_8 = value >>> 7;
    endfunction

    function automatic logic signed [15:0] multiply_q8_8(
        input logic signed [15:0] left,
        input logic signed [15:0] right
    );
        logic signed [31:0] product;
        begin
            product = left * right;
            multiply_q8_8 = product[23:8];
        end
    endfunction

    always_comb begin
        yaw_sine = q15_to_q8_8(sine_q15(angle));
        yaw_cosine = q15_to_q8_8(sine_q15(angle + 8'd64));
        demo_view_matrix = '0;
        demo_view_matrix.m00 = yaw_cosine;
        demo_view_matrix.m02 = yaw_sine;
        demo_view_matrix.m10 = multiply_q8_8(-16'sd121, yaw_sine);
        demo_view_matrix.m11 = 16'sd226;
        demo_view_matrix.m12 = multiply_q8_8(16'sd121, yaw_cosine);
        demo_view_matrix.m20 = -multiply_q8_8(16'sd226, yaw_sine);
        demo_view_matrix.m21 = -16'sd121;
        demo_view_matrix.m22 = multiply_q8_8(16'sd226, yaw_cosine);
        demo_view_matrix.m23 = 16'sd1280;
    end

    always_comb begin
        command_data = '0;
        command_valid = 1'b1;

        case (state)
            SET_VIEW: begin
                command_data.opcode = GFX_CMD_SET_VIEW_MATRIX;
                `GFX_VIEW_MATRIX(command_data) = demo_view_matrix;
            end
            BEGIN_FRAME: begin
                command_data.opcode = GFX_CMD_BEGIN_FRAME;
                `GFX_ARGUMENT(command_data) = frame_id;
            end
            FEED: begin
                command_data.opcode = GFX_CMD_DRAW_TRIANGLE;
                `GFX_TRIANGLE(command_data) = triangle_data;
            end
            END_FRAME: command_data.opcode = GFX_CMD_END_FRAME;
            default: command_valid = 1'b0;
        endcase
    end

    always_comb begin
        triangle_data = '0;

        if (triangle_number < 5'd18) begin
            case (triangle_number)
            5'd0: begin
                triangle_data.x0 = NEG_ONE;
                triangle_data.y0 = NEG_ONE;
                triangle_data.z0 = NEG_ONE;
                triangle_data.x1 = POS_ONE;
                triangle_data.y1 = POS_ONE;
                triangle_data.z1 = NEG_ONE;
                triangle_data.x2 = POS_ONE;
                triangle_data.y2 = NEG_ONE;
                triangle_data.z2 = NEG_ONE;
                triangle_data.color = 8'h03;
            end
            5'd1: begin
                triangle_data.x0 = NEG_ONE;
                triangle_data.y0 = NEG_ONE;
                triangle_data.z0 = NEG_ONE;
                triangle_data.x1 = NEG_ONE;
                triangle_data.y1 = POS_ONE;
                triangle_data.z1 = NEG_ONE;
                triangle_data.x2 = POS_ONE;
                triangle_data.y2 = POS_ONE;
                triangle_data.z2 = NEG_ONE;
                triangle_data.color = 8'h03;
            end

            5'd2: begin
                triangle_data.x0 = NEG_ONE;
                triangle_data.y0 = NEG_ONE;
                triangle_data.z0 = POS_ONE;
                triangle_data.x1 = POS_ONE;
                triangle_data.y1 = NEG_ONE;
                triangle_data.z1 = POS_ONE;
                triangle_data.x2 = POS_ONE;
                triangle_data.y2 = POS_ONE;
                triangle_data.z2 = POS_ONE;
                triangle_data.color = 8'hE0;
            end
            5'd3: begin
                triangle_data.x0 = NEG_ONE;
                triangle_data.y0 = NEG_ONE;
                triangle_data.z0 = POS_ONE;
                triangle_data.x1 = POS_ONE;
                triangle_data.y1 = POS_ONE;
                triangle_data.z1 = POS_ONE;
                triangle_data.x2 = NEG_ONE;
                triangle_data.y2 = POS_ONE;
                triangle_data.z2 = POS_ONE;
                triangle_data.color = 8'hE0;
            end

            5'd4: begin
                triangle_data.x0 = POS_ONE;
                triangle_data.y0 = NEG_ONE;
                triangle_data.z0 = NEG_ONE;
                triangle_data.x1 = POS_ONE;
                triangle_data.y1 = POS_ONE;
                triangle_data.z1 = NEG_ONE;
                triangle_data.x2 = POS_ONE;
                triangle_data.y2 = POS_ONE;
                triangle_data.z2 = POS_ONE;
                triangle_data.color = 8'h1C;
            end
            5'd5: begin
                triangle_data.x0 = POS_ONE;
                triangle_data.y0 = NEG_ONE;
                triangle_data.z0 = NEG_ONE;
                triangle_data.x1 = POS_ONE;
                triangle_data.y1 = POS_ONE;
                triangle_data.z1 = POS_ONE;
                triangle_data.x2 = POS_ONE;
                triangle_data.y2 = NEG_ONE;
                triangle_data.z2 = POS_ONE;
                triangle_data.color = 8'h1C;
            end

            5'd6: begin
                triangle_data.x0 = NEG_ONE;
                triangle_data.y0 = NEG_ONE;
                triangle_data.z0 = NEG_ONE;
                triangle_data.x1 = NEG_ONE;
                triangle_data.y1 = NEG_ONE;
                triangle_data.z1 = POS_ONE;
                triangle_data.x2 = NEG_ONE;
                triangle_data.y2 = POS_ONE;
                triangle_data.z2 = POS_ONE;
                triangle_data.color = 8'hE3;
            end
            5'd7: begin
                triangle_data.x0 = NEG_ONE;
                triangle_data.y0 = NEG_ONE;
                triangle_data.z0 = NEG_ONE;
                triangle_data.x1 = NEG_ONE;
                triangle_data.y1 = POS_ONE;
                triangle_data.z1 = POS_ONE;
                triangle_data.x2 = NEG_ONE;
                triangle_data.y2 = POS_ONE;
                triangle_data.z2 = NEG_ONE;
                triangle_data.color = 8'hE3;
            end

            5'd8: begin
                triangle_data.x0 = NEG_ONE;
                triangle_data.y0 = NEG_ONE;
                triangle_data.z0 = NEG_ONE;
                triangle_data.x1 = POS_ONE;
                triangle_data.y1 = NEG_ONE;
                triangle_data.z1 = NEG_ONE;
                triangle_data.x2 = POS_ONE;
                triangle_data.y2 = NEG_ONE;
                triangle_data.z2 = POS_ONE;
                triangle_data.color = 8'hFC;
            end
            5'd9: begin
                triangle_data.x0 = NEG_ONE;
                triangle_data.y0 = NEG_ONE;
                triangle_data.z0 = NEG_ONE;
                triangle_data.x1 = POS_ONE;
                triangle_data.y1 = NEG_ONE;
                triangle_data.z1 = POS_ONE;
                triangle_data.x2 = NEG_ONE;
                triangle_data.y2 = NEG_ONE;
                triangle_data.z2 = POS_ONE;
                triangle_data.color = 8'hFC;
            end

            5'd10: begin
                triangle_data.x0 = NEG_ONE;
                triangle_data.y0 = POS_ONE;
                triangle_data.z0 = NEG_ONE;
                triangle_data.x1 = NEG_ONE;
                triangle_data.y1 = POS_ONE;
                triangle_data.z1 = POS_ONE;
                triangle_data.x2 = POS_ONE;
                triangle_data.y2 = POS_ONE;
                triangle_data.z2 = POS_ONE;
                triangle_data.color = 8'h1F;
            end
            5'd11: begin
                triangle_data.x0 = NEG_ONE;
                triangle_data.y0 = POS_ONE;
                triangle_data.z0 = NEG_ONE;
                triangle_data.x1 = POS_ONE;
                triangle_data.y1 = POS_ONE;
                triangle_data.z1 = POS_ONE;
                triangle_data.x2 = POS_ONE;
                triangle_data.y2 = POS_ONE;
                triangle_data.z2 = NEG_ONE;
                triangle_data.color = 8'h1F;
            end
            5'd12: begin
                triangle_data.x0 = PYRAMID_LEFT;
                triangle_data.y0 = PYRAMID_BASE_Y;
                triangle_data.z0 = PYRAMID_NEAR_Z;
                triangle_data.x1 = PYRAMID_RIGHT;
                triangle_data.y1 = PYRAMID_BASE_Y;
                triangle_data.z1 = PYRAMID_NEAR_Z;
                triangle_data.x2 = PYRAMID_RIGHT;
                triangle_data.y2 = PYRAMID_BASE_Y;
                triangle_data.z2 = PYRAMID_FAR_Z;
                triangle_data.color = 8'hE8;
            end
            5'd13: begin
                triangle_data.x0 = PYRAMID_LEFT;
                triangle_data.y0 = PYRAMID_BASE_Y;
                triangle_data.z0 = PYRAMID_NEAR_Z;
                triangle_data.x1 = PYRAMID_RIGHT;
                triangle_data.y1 = PYRAMID_BASE_Y;
                triangle_data.z1 = PYRAMID_FAR_Z;
                triangle_data.x2 = PYRAMID_LEFT;
                triangle_data.y2 = PYRAMID_BASE_Y;
                triangle_data.z2 = PYRAMID_FAR_Z;
                triangle_data.color = 8'hE8;
            end
            5'd14: begin
                triangle_data.x0 = PYRAMID_LEFT;
                triangle_data.y0 = PYRAMID_BASE_Y;
                triangle_data.z0 = PYRAMID_NEAR_Z;
                triangle_data.x1 = PYRAMID_CENTER;
                triangle_data.y1 = PYRAMID_APEX_Y;
                triangle_data.z1 = 16'sd0;
                triangle_data.x2 = PYRAMID_RIGHT;
                triangle_data.y2 = PYRAMID_BASE_Y;
                triangle_data.z2 = PYRAMID_NEAR_Z;
                triangle_data.color = 8'hF8;
            end
            5'd15: begin
                triangle_data.x0 = PYRAMID_RIGHT;
                triangle_data.y0 = PYRAMID_BASE_Y;
                triangle_data.z0 = PYRAMID_NEAR_Z;
                triangle_data.x1 = PYRAMID_CENTER;
                triangle_data.y1 = PYRAMID_APEX_Y;
                triangle_data.z1 = 16'sd0;
                triangle_data.x2 = PYRAMID_RIGHT;
                triangle_data.y2 = PYRAMID_BASE_Y;
                triangle_data.z2 = PYRAMID_FAR_Z;
                triangle_data.color = 8'h3C;
            end
            5'd16: begin
                triangle_data.x0 = PYRAMID_RIGHT;
                triangle_data.y0 = PYRAMID_BASE_Y;
                triangle_data.z0 = PYRAMID_FAR_Z;
                triangle_data.x1 = PYRAMID_CENTER;
                triangle_data.y1 = PYRAMID_APEX_Y;
                triangle_data.z1 = 16'sd0;
                triangle_data.x2 = PYRAMID_LEFT;
                triangle_data.y2 = PYRAMID_BASE_Y;
                triangle_data.z2 = PYRAMID_FAR_Z;
                triangle_data.color = 8'h3F;
            end
            5'd17: begin
                triangle_data.x0 = PYRAMID_LEFT;
                triangle_data.y0 = PYRAMID_BASE_Y;
                triangle_data.z0 = PYRAMID_FAR_Z;
                triangle_data.x1 = PYRAMID_CENTER;
                triangle_data.y1 = PYRAMID_APEX_Y;
                triangle_data.z1 = 16'sd0;
                triangle_data.x2 = PYRAMID_LEFT;
                triangle_data.y2 = PYRAMID_BASE_Y;
                triangle_data.z2 = PYRAMID_NEAR_Z;
                triangle_data.color = 8'hA3;
            end
            default: begin
            end
            endcase
        end else begin
            case (triangle_number)
            5'd18: begin
                triangle_data.x0 = TALL_PYRAMID_LEFT;
                triangle_data.y0 = TALL_PYRAMID_BASE_Y;
                triangle_data.z0 = TALL_PYRAMID_NEAR_Z;
                triangle_data.x1 = TALL_PYRAMID_RIGHT;
                triangle_data.y1 = TALL_PYRAMID_BASE_Y;
                triangle_data.z1 = TALL_PYRAMID_NEAR_Z;
                triangle_data.x2 = TALL_PYRAMID_RIGHT;
                triangle_data.y2 = TALL_PYRAMID_BASE_Y;
                triangle_data.z2 = TALL_PYRAMID_FAR_Z;
                triangle_data.color = 8'h2C;
            end
            5'd19: begin
                triangle_data.x0 = TALL_PYRAMID_LEFT;
                triangle_data.y0 = TALL_PYRAMID_BASE_Y;
                triangle_data.z0 = TALL_PYRAMID_NEAR_Z;
                triangle_data.x1 = TALL_PYRAMID_RIGHT;
                triangle_data.y1 = TALL_PYRAMID_BASE_Y;
                triangle_data.z1 = TALL_PYRAMID_FAR_Z;
                triangle_data.x2 = TALL_PYRAMID_LEFT;
                triangle_data.y2 = TALL_PYRAMID_BASE_Y;
                triangle_data.z2 = TALL_PYRAMID_FAR_Z;
                triangle_data.color = 8'h2C;
            end
            5'd20: begin
                triangle_data.x0 = TALL_PYRAMID_LEFT;
                triangle_data.y0 = TALL_PYRAMID_BASE_Y;
                triangle_data.z0 = TALL_PYRAMID_NEAR_Z;
                triangle_data.x1 = TALL_PYRAMID_CENTER;
                triangle_data.y1 = TALL_PYRAMID_APEX_Y;
                triangle_data.z1 = 16'sd0;
                triangle_data.x2 = TALL_PYRAMID_RIGHT;
                triangle_data.y2 = TALL_PYRAMID_BASE_Y;
                triangle_data.z2 = TALL_PYRAMID_NEAR_Z;
                triangle_data.color = 8'h2F;
            end
            5'd21: begin
                triangle_data.x0 = TALL_PYRAMID_RIGHT;
                triangle_data.y0 = TALL_PYRAMID_BASE_Y;
                triangle_data.z0 = TALL_PYRAMID_NEAR_Z;
                triangle_data.x1 = TALL_PYRAMID_CENTER;
                triangle_data.y1 = TALL_PYRAMID_APEX_Y;
                triangle_data.z1 = 16'sd0;
                triangle_data.x2 = TALL_PYRAMID_RIGHT;
                triangle_data.y2 = TALL_PYRAMID_BASE_Y;
                triangle_data.z2 = TALL_PYRAMID_FAR_Z;
                triangle_data.color = 8'h4F;
            end
            5'd22: begin
                triangle_data.x0 = TALL_PYRAMID_RIGHT;
                triangle_data.y0 = TALL_PYRAMID_BASE_Y;
                triangle_data.z0 = TALL_PYRAMID_FAR_Z;
                triangle_data.x1 = TALL_PYRAMID_CENTER;
                triangle_data.y1 = TALL_PYRAMID_APEX_Y;
                triangle_data.z1 = 16'sd0;
                triangle_data.x2 = TALL_PYRAMID_LEFT;
                triangle_data.y2 = TALL_PYRAMID_BASE_Y;
                triangle_data.z2 = TALL_PYRAMID_FAR_Z;
                triangle_data.color = 8'h6F;
            end
            5'd23: begin
                triangle_data.x0 = TALL_PYRAMID_LEFT;
                triangle_data.y0 = TALL_PYRAMID_BASE_Y;
                triangle_data.z0 = TALL_PYRAMID_FAR_Z;
                triangle_data.x1 = TALL_PYRAMID_CENTER;
                triangle_data.y1 = TALL_PYRAMID_APEX_Y;
                triangle_data.z1 = 16'sd0;
                triangle_data.x2 = TALL_PYRAMID_LEFT;
                triangle_data.y2 = TALL_PYRAMID_BASE_Y;
                triangle_data.z2 = TALL_PYRAMID_NEAR_Z;
                triangle_data.color = 8'h8F;
            end
            default: begin
            end
            endcase
        end
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= SET_VIEW;
            triangle_number <= 5'd0;
            angle <= 8'd0;
            frame_id <= 32'd0;
        end else if (restart) begin
            state <= SET_VIEW;
            triangle_number <= 5'd0;
            angle <= 8'd0;
            frame_id <= 32'd0;
        end else begin
            case (state)
                SET_VIEW: begin
                    if (command_ready)
                        state <= BEGIN_FRAME;
                end

                BEGIN_FRAME: begin
                    if (command_ready) begin
                        triangle_number <= 5'd0;
                        state <= FEED;
                    end
                end

                FEED: begin
                    if (command_ready) begin
                        if (triangle_number == TRIANGLE_COUNT - 1)
                            state <= END_FRAME;
                        else
                            triangle_number <= triangle_number + 1'b1;
                    end
                end

                END_FRAME: begin
                    if (command_ready)
                        state <= WAIT_FRAME;
                end

                WAIT_FRAME: begin
                    if (frame_done) begin
                        angle <= angle + 8'd1;
                        frame_id <= frame_id + 1'b1;
                        state <= SET_VIEW;
                    end
                end

                default: state <= SET_VIEW;
            endcase
        end
    end

endmodule
