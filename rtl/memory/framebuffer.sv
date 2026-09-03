module framebuffer #(
    parameter int FRAME_WIDTH = 320,
    parameter int FRAME_HEIGHT = 240
) (
    input logic reset,
    input logic raster_clk,
    input logic raster_write,
    input logic [9:0] raster_x,
    input logic [8:0] raster_y,
    input logic [7:0] raster_color,
    input logic clear_request,
    output logic clear_busy,
    input logic display_clk,
    input logic display_read_enable,
    input logic [9:0] display_x,
    input logic [8:0] display_y,
    output logic [7:0] display_pixel,
    output logic display_pixel_valid
);

    localparam int FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
    localparam int ADDRESS_BITS = $clog2(FRAME_PIXELS);

    logic [ADDRESS_BITS-1:0] raster_address;
    logic [ADDRESS_BITS-1:0] display_address;
    logic [7:0] framebuffer_pixel;
    logic raster_write_in_bounds;
    logic display_read_in_bounds;
    logic [ADDRESS_BITS-1:0] clear_address;
    logic clear_active;
    logic [ADDRESS_BITS-1:0] ram_write_address;
    logic [7:0] ram_write_data;
    logic ram_write_enable;

    always_comb begin
        raster_address = ({8'b0, raster_y} << 8) +
                         ({8'b0, raster_y} << 6) +
                         {7'b0, raster_x};
        display_address = ({8'b0, display_y} << 8) +
                          ({8'b0, display_y} << 6) +
                          {7'b0, display_x};
        raster_write_in_bounds =
            (raster_x < FRAME_WIDTH) && (raster_y < FRAME_HEIGHT);
        display_read_in_bounds =
            (display_x < FRAME_WIDTH) && (display_y < FRAME_HEIGHT);

        if (clear_active) begin
            ram_write_address = clear_address;
            ram_write_data = 8'h00;
            ram_write_enable = 1'b1;
        end else begin
            ram_write_address = raster_address;
            ram_write_data = raster_color;
            ram_write_enable = raster_write && raster_write_in_bounds &&
                               !clear_request;
        end
    end

    assign clear_busy = clear_active;

    always_ff @(posedge raster_clk or posedge reset) begin
        if (reset) begin
            clear_active <= 1'b0;
            clear_address <= '0;
        end else if (!clear_active && clear_request) begin
            clear_active <= 1'b1;
            clear_address <= '0;
        end else if (clear_active) begin
            if (clear_address == FRAME_PIXELS - 1) begin
                clear_active <= 1'b0;
                clear_address <= '0;
            end else begin
                clear_address <= clear_address + 1'b1;
            end
        end
    end

    framebuffer_320x240_8bit framebuffer_ram (
        .clock_a(raster_clk),
        .address_a(ram_write_address),
        .data_a(ram_write_data),
        .wren_a(ram_write_enable),
        .clock_b(display_clk),
        .address_b(display_address),
        .rden_b(display_read_enable && display_read_in_bounds),
        .q_b(framebuffer_pixel)
    );

    always_ff @(posedge display_clk or posedge reset) begin
        if (reset)
            display_pixel_valid <= 1'b0;
        else
            display_pixel_valid <= display_read_enable && display_read_in_bounds;
    end

    always_comb begin
        if (display_pixel_valid)
            display_pixel = framebuffer_pixel;
        else
            display_pixel = 8'h00;
    end

endmodule
