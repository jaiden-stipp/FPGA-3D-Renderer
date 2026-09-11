module vga_page_swap_controller #(
    parameter int VERTICAL_ACTIVE = 480
) (
    input logic reset,
    input logic raster_clk,
    input logic pixel_clk,
    input logic swap_request,
    input logic [9:0] scan_x,
    input logic [9:0] scan_y,
    output logic front_page_pixel,
    output logic write_page_raster,
    output logic swap_busy,
    output logic swap_done
);

    logic swap_toggle_raster;
    logic swap_pending_raster;
    logic swap_request_sync1;
    logic swap_request_sync2;
    logic swap_request_seen_pixel;
    logic swap_ack_pixel;
    logic swap_ack_sync1;
    logic swap_ack_sync2;
    logic swap_ack_seen_raster;

    assign swap_busy = swap_pending_raster;

    always_ff @(posedge raster_clk or posedge reset) begin
        if (reset) begin
            write_page_raster <= 1'b1;
            swap_toggle_raster <= 1'b0;
            swap_pending_raster <= 1'b0;
            swap_ack_sync1 <= 1'b0;
            swap_ack_sync2 <= 1'b0;
            swap_ack_seen_raster <= 1'b0;
            swap_done <= 1'b0;
        end else begin
            swap_ack_sync1 <= swap_ack_pixel;
            swap_ack_sync2 <= swap_ack_sync1;
            swap_done <= 1'b0;
            if (swap_pending_raster &&
                swap_ack_sync2 != swap_ack_seen_raster) begin
                write_page_raster <= ~write_page_raster;
                swap_ack_seen_raster <= swap_ack_sync2;
                swap_pending_raster <= 1'b0;
                swap_done <= 1'b1;
            end else if (swap_request && !swap_pending_raster) begin
                swap_toggle_raster <= ~swap_toggle_raster;
                swap_pending_raster <= 1'b1;
            end
        end
    end

    always_ff @(posedge pixel_clk or posedge reset) begin
        if (reset) begin
            front_page_pixel <= 1'b0;
            swap_request_sync1 <= 1'b0;
            swap_request_sync2 <= 1'b0;
            swap_request_seen_pixel <= 1'b0;
            swap_ack_pixel <= 1'b0;
        end else begin
            swap_request_sync1 <= swap_toggle_raster;
            swap_request_sync2 <= swap_request_sync1;
            if (scan_x == 10'd0 && scan_y == VERTICAL_ACTIVE &&
                swap_request_sync2 != swap_request_seen_pixel) begin
                front_page_pixel <= ~front_page_pixel;
                swap_request_seen_pixel <= swap_request_sync2;
                swap_ack_pixel <= swap_request_sync2;
            end
        end
    end

endmodule
