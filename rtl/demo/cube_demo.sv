// Rotating cube and pyramid triangle feeder.

`include "renderer_types.svh"

module cube_demo (
    input  logic         clk,
    input  logic         reset,
    input  logic         restart,

    input  logic         pipeline_ready,
    input  logic         pipeline_idle,
    input  logic         clear_busy,
    input  logic         swap_busy,
    input  logic         swap_done,

    output logic         triangle_valid,
    output triangle_3d_t triangle_data,
    output logic [7:0] rotation_angle,
    output logic         clear_request,
    output logic         swap_request
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
        CLEAR_START,
        CLEAR_WAIT,
        FEED,
        DRAIN,
        SWAP_START,
        SWAP_WAIT
    } demo_state_t;

    demo_state_t state;
    logic [4:0] triangle_number;
    logic [7:0] angle;

    assign rotation_angle = angle;
    assign triangle_valid = (state == FEED);
    assign clear_request = (state == CLEAR_START);
    assign swap_request = (state == SWAP_START);

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
            state <= CLEAR_START;
            triangle_number <= 5'd0;
            angle <= 8'd0;
        end else if (restart) begin
            state <= CLEAR_START;
            triangle_number <= 5'd0;
            angle <= 8'd0;
        end else begin
            case (state)
                CLEAR_START: begin
                    state <= CLEAR_WAIT;
                end

                CLEAR_WAIT: begin
                    if (!clear_busy) begin
                        triangle_number <= 5'd0;
                        state <= FEED;
                    end
                end

                FEED: begin
                    if (pipeline_ready) begin
                        if (triangle_number == TRIANGLE_COUNT - 1) begin
                            state <= DRAIN;
                        end else begin
                            triangle_number <= triangle_number + 1'b1;
                        end
                    end
                end

                DRAIN: begin
                    if (pipeline_idle && !clear_busy) begin
                        state <= SWAP_START;
                    end
                end

                SWAP_START: begin
                    state <= SWAP_WAIT;
                end

                SWAP_WAIT: begin
                    if (swap_done && !swap_busy) begin
                        angle <= angle + 8'd1;
                        state <= CLEAR_START;
                    end
                end

                default: state <= CLEAR_START;
            endcase
        end
    end

endmodule
