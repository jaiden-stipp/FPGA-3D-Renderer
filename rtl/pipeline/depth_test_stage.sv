module depth_test_stage (
    input logic clk,
    input logic reset,
    input logic candidate_valid,
    input logic [9:0] candidate_x,
    input logic [8:0] candidate_y,
    input logic [7:0] candidate_color,
    input logic [7:0] candidate_depth,
    output logic depth_read_enable,
    output logic [9:0] depth_read_x,
    output logic [8:0] depth_read_y,
    input logic [7:0] depth_read_value,
    input logic depth_read_valid,
    output logic raster_write,
    output logic [9:0] raster_x,
    output logic [8:0] raster_y,
    output logic [7:0] raster_color,
    output logic depth_write_enable,
    output logic [9:0] depth_write_x,
    output logic [8:0] depth_write_y,
    output logic [7:0] depth_write_value,
    output logic depth_rejected,
    output logic pixel_written,
    output logic busy
);

    logic pending_valid;
    logic [9:0] pending_x;
    logic [8:0] pending_y;
    logic [7:0] pending_color;
    logic [7:0] pending_depth;

    always_comb begin
        depth_read_enable = candidate_valid;
        depth_read_x = candidate_x;
        depth_read_y = candidate_y;
        raster_write = pending_valid && depth_read_valid &&
                       pending_depth > depth_read_value;
        raster_x = pending_x;
        raster_y = pending_y;
        raster_color = pending_color;
        depth_write_enable = raster_write;
        depth_write_x = pending_x;
        depth_write_y = pending_y;
        depth_write_value = pending_depth;
        depth_rejected = pending_valid && depth_read_valid && !raster_write;
        pixel_written = raster_write;
        busy = pending_valid;
    end

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pending_valid <= 1'b0;
            pending_x <= '0;
            pending_y <= '0;
            pending_color <= '0;
            pending_depth <= '0;
        end else begin
            pending_valid <= candidate_valid;
            if (candidate_valid) begin
                pending_x <= candidate_x;
                pending_y <= candidate_y;
                pending_color <= candidate_color;
                pending_depth <= candidate_depth;
            end
        end
    end

endmodule
