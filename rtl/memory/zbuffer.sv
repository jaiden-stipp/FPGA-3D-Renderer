module zbuffer (
    input logic reset,
    input logic raster_clk,
    input logic clear_request,
    output logic clear_busy,
    input logic read_enable,
    input logic [9:0] read_x,
    input logic [8:0] read_y,
    output logic [7:0] read_depth,
    output logic read_valid,
    input logic write_enable,
    input logic [9:0] write_x,
    input logic [8:0] write_y,
    input logic [7:0] write_depth
);

    localparam int FRAME_WIDTH = 320;
    localparam int FRAME_HEIGHT = 240;
    localparam int FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;

    logic [16:0] read_address;
    logic [16:0] write_address;
    logic [16:0] clear_address;
    logic [16:0] ram_write_address;
    logic [7:0] ram_write_depth;
    logic ram_read_enable;
    logic ram_write_enable;
    logic read_in_bounds;
    logic write_in_bounds;
    logic clear_active;
    logic [7:0] ram_read_depth;

    always_comb begin
        read_address = ({8'b0, read_y} << 8) +
                       ({8'b0, read_y} << 6) +
                       {7'b0, read_x};
        write_address = ({8'b0, write_y} << 8) +
                        ({8'b0, write_y} << 6) +
                        {7'b0, write_x};
        read_in_bounds = (read_x < FRAME_WIDTH) && (read_y < FRAME_HEIGHT);
        write_in_bounds = (write_x < FRAME_WIDTH) && (write_y < FRAME_HEIGHT);
        ram_read_enable = read_enable && read_in_bounds && !clear_active &&
                          !clear_request;

        if (clear_active) begin
            ram_write_address = clear_address;
            ram_write_depth = 8'h00;
            ram_write_enable = 1'b1;
        end else begin
            ram_write_address = write_address;
            ram_write_depth = write_depth;
            ram_write_enable = write_enable && write_in_bounds &&
                               !clear_request;
        end
    end

    assign clear_busy = clear_active;
    assign read_depth = ram_read_depth;

    always_ff @(posedge raster_clk or posedge reset) begin
        if (reset) begin
            clear_active <= 1'b0;
            clear_address <= '0;
            read_valid <= 1'b0;
        end else begin
            read_valid <= ram_read_enable;
            if (!clear_active && clear_request) begin
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
    end

    zbuffer_320x240_8bit zbuffer_ram (
        .clock_a(raster_clk),
        .address_a(ram_write_address),
        .data_a(ram_write_depth),
        .wren_a(ram_write_enable),
        .clock_b(raster_clk),
        .address_b(read_address),
        .rden_b(ram_read_enable),
        .q_b(ram_read_depth)
    );

endmodule
