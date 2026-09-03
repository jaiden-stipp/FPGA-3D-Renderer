module vga_controller_640x480 #(
    parameter int FRAME_WIDTH = 320,
    parameter int FRAME_HEIGHT = 240
) (
    input logic reset,
    input logic pixel_clk,
    input logic raster_clk,
    input logic raster_write,
    input logic [9:0] raster_x,
    input logic [8:0] raster_y,
    input logic [7:0] raster_color,
    input logic clear_request,
    output logic clear_busy,
    input logic swap_request,
    output logic swap_busy,
    output logic swap_done,
    input logic palette_clk,
    input logic palette_write,
    input logic [7:0] palette_address,
    input logic [23:0] palette_write_rgb,
    input logic [7:0] fps_value,
    output logic [7:0] vga_r,
    output logic [7:0] vga_g,
    output logic [7:0] vga_b,
    output logic vga_hs,
    output logic vga_vs,
    output logic vga_active
);

    localparam int V_ACTIVE = 480;

    logic [9:0] scan_x;
    logic [9:0] scan_y;
    logic scan_active;
    logic scan_hs;
    logic scan_vs;
    logic [9:0] framebuffer_x;
    logic [8:0] framebuffer_y;
    logic [7:0] framebuffer_index0;
    logic [7:0] framebuffer_index1;
    logic framebuffer_index_valid0;
    logic framebuffer_index_valid1;
    logic framebuffer_clear_busy0;
    logic framebuffer_clear_busy1;
    logic [7:0] framebuffer_index;
    logic framebuffer_index_valid;
    logic [23:0] palette_rgb;
    logic [7:0] fps_sync1;
    logic [7:0] fps_sync2;
    logic [9:0] scan_x_d1;
    logic [9:0] scan_x_d2;
    logic [9:0] scan_y_d1;
    logic [9:0] scan_y_d2;
    logic active_d1;
    logic active_d2;
    logic hs_d1;
    logic hs_d2;
    logic vs_d1;
    logic vs_d2;

    logic front_page_pixel;
    logic write_page_raster;
    logic swap_toggle_raster;
    logic swap_pending_raster;
    logic swap_request_sync1;
    logic swap_request_sync2;
    logic swap_request_seen_pixel;
    logic swap_ack_pixel;
    logic swap_ack_sync1;
    logic swap_ack_sync2;
    logic swap_ack_seen_raster;
    logic fps_text_pixel;

    function automatic logic [4:0] glyph_row(
        input logic [3:0] glyph,
        input logic [2:0] row
    );
        begin
            glyph_row = 5'b00000;
            case (glyph)
                4'd0: case (row)
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10011;
                    3'd3: glyph_row = 5'b10101;
                    3'd4: glyph_row = 5'b11001;
                    3'd5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b01110;
                endcase
                4'd1: case (row)
                    3'd0: glyph_row = 5'b00100;
                    3'd1: glyph_row = 5'b01100;
                    3'd2: glyph_row = 5'b00100;
                    3'd3: glyph_row = 5'b00100;
                    3'd4: glyph_row = 5'b00100;
                    3'd5: glyph_row = 5'b00100;
                    default: glyph_row = 5'b01110;
                endcase
                4'd2: case (row)
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b00001;
                    3'd3: glyph_row = 5'b00010;
                    3'd4: glyph_row = 5'b00100;
                    3'd5: glyph_row = 5'b01000;
                    default: glyph_row = 5'b11111;
                endcase
                4'd3: case (row)
                    3'd0: glyph_row = 5'b11110;
                    3'd1: glyph_row = 5'b00001;
                    3'd2: glyph_row = 5'b00001;
                    3'd3: glyph_row = 5'b01110;
                    3'd4: glyph_row = 5'b00001;
                    3'd5: glyph_row = 5'b00001;
                    default: glyph_row = 5'b11110;
                endcase
                4'd4: case (row)
                    3'd0: glyph_row = 5'b00010;
                    3'd1: glyph_row = 5'b00110;
                    3'd2: glyph_row = 5'b01010;
                    3'd3: glyph_row = 5'b10010;
                    3'd4: glyph_row = 5'b11111;
                    3'd5: glyph_row = 5'b00010;
                    default: glyph_row = 5'b00010;
                endcase
                4'd5: case (row)
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b00001;
                    3'd5: glyph_row = 5'b00001;
                    default: glyph_row = 5'b11110;
                endcase
                4'd6: case (row)
                    3'd0: glyph_row = 5'b00110;
                    3'd1: glyph_row = 5'b01000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b01110;
                endcase
                4'd7: case (row)
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b00001;
                    3'd2: glyph_row = 5'b00010;
                    3'd3: glyph_row = 5'b00100;
                    3'd4: glyph_row = 5'b01000;
                    3'd5: glyph_row = 5'b01000;
                    default: glyph_row = 5'b01000;
                endcase
                4'd8: case (row)
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b01110;
                    3'd4: glyph_row = 5'b10001;
                    3'd5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b01110;
                endcase
                4'd9: case (row)
                    3'd0: glyph_row = 5'b01110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b01111;
                    3'd4: glyph_row = 5'b00001;
                    3'd5: glyph_row = 5'b00010;
                    default: glyph_row = 5'b11100;
                endcase
                4'd10: case (row)
                    3'd0: glyph_row = 5'b11111;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10000;
                    3'd5: glyph_row = 5'b10000;
                    default: glyph_row = 5'b10000;
                endcase
                4'd11: case (row)
                    3'd0: glyph_row = 5'b11110;
                    3'd1: glyph_row = 5'b10001;
                    3'd2: glyph_row = 5'b10001;
                    3'd3: glyph_row = 5'b11110;
                    3'd4: glyph_row = 5'b10000;
                    3'd5: glyph_row = 5'b10000;
                    default: glyph_row = 5'b10000;
                endcase
                default: case (row)
                    3'd0: glyph_row = 5'b01111;
                    3'd1: glyph_row = 5'b10000;
                    3'd2: glyph_row = 5'b10000;
                    3'd3: glyph_row = 5'b01110;
                    3'd4: glyph_row = 5'b00001;
                    3'd5: glyph_row = 5'b00001;
                    default: glyph_row = 5'b11110;
                endcase
            endcase
        end
    endfunction

    function automatic logic [11:0] fps_digits(input logic [7:0] value);
        logic [7:0] remainder;
        logic [3:0] hundreds;
        logic [3:0] tens;
        begin
            if (value >= 8'd200) begin
                hundreds = 4'd2;
                remainder = value - 8'd200;
            end else if (value >= 8'd100) begin
                hundreds = 4'd1;
                remainder = value - 8'd100;
            end else begin
                hundreds = 4'd0;
                remainder = value;
            end

            if (remainder >= 8'd90) begin
                tens = 4'd9;
            end else if (remainder >= 8'd80) begin
                tens = 4'd8;
            end else if (remainder >= 8'd70) begin
                tens = 4'd7;
            end else if (remainder >= 8'd60) begin
                tens = 4'd6;
            end else if (remainder >= 8'd50) begin
                tens = 4'd5;
            end else if (remainder >= 8'd40) begin
                tens = 4'd4;
            end else if (remainder >= 8'd30) begin
                tens = 4'd3;
            end else if (remainder >= 8'd20) begin
                tens = 4'd2;
            end else if (remainder >= 8'd10) begin
                tens = 4'd1;
            end else begin
                tens = 4'd0;
            end

            fps_digits = {hundreds, tens,
                          remainder - ((tens << 3) + (tens << 1))};
        end
    endfunction

    function automatic logic fps_overlay_pixel(
        input logic [9:0] x,
        input logic [9:0] y,
        input logic [7:0] value
    );
        logic [9:0] x_offset;
        logic [9:0] y_offset;
        logic [3:0] glyph;
        logic [2:0] glyph_column;
        logic [4:0] active_glyph_row;
        logic [11:0] digits;
        begin
            fps_overlay_pixel = 1'b0;
            glyph = 4'd0;
            glyph_column = 3'd0;
            digits = fps_digits(value);

            if ((x >= 10'd8) && (x < 10'd78) &&
                (y >= 10'd8) && (y < 10'd22)) begin
                x_offset = x - 10'd8;
                y_offset = y - 10'd8;

                if (x_offset < 10'd10) begin
                    glyph = 4'd10;
                    glyph_column = x_offset[3:1];
                end else if ((x_offset >= 10'd12) && (x_offset < 10'd22)) begin
                    glyph = 4'd11;
                    glyph_column = (x_offset - 10'd12) >> 1;
                end else if ((x_offset >= 10'd24) && (x_offset < 10'd34)) begin
                    glyph = 4'd12;
                    glyph_column = (x_offset - 10'd24) >> 1;
                end else if ((x_offset >= 10'd36) && (x_offset < 10'd46)) begin
                    glyph = digits[11:8];
                    glyph_column = (x_offset - 10'd36) >> 1;
                end else if ((x_offset >= 10'd48) && (x_offset < 10'd58)) begin
                    glyph = digits[7:4];
                    glyph_column = (x_offset - 10'd48) >> 1;
                end else if ((x_offset >= 10'd60) && (x_offset < 10'd70)) begin
                    glyph = digits[3:0];
                    glyph_column = (x_offset - 10'd60) >> 1;
                end else begin
                    glyph = 4'd15;
                end

                active_glyph_row = glyph_row(glyph, y_offset[3:1]);
                if (glyph != 4'd15)
                    fps_overlay_pixel = active_glyph_row[4 - glyph_column];
            end
        end
    endfunction

    vga_timing_640x480 timing (
        .pixel_clk(pixel_clk),
        .reset(reset),
        .x(scan_x),
        .y(scan_y),
        .active(scan_active),
        .hsync(scan_hs),
        .vsync(scan_vs)
    );

    always_comb begin
        if (scan_active) begin
            framebuffer_x = scan_x >> 1;
            framebuffer_y = scan_y[9:1];
        end else begin
            framebuffer_x = 10'd0;
            framebuffer_y = 9'd0;
        end

        if (front_page_pixel) begin
            framebuffer_index = framebuffer_index1;
            framebuffer_index_valid = framebuffer_index_valid1;
        end else begin
            framebuffer_index = framebuffer_index0;
            framebuffer_index_valid = framebuffer_index_valid0;
        end
    end

    framebuffer #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) framebuffer0 (
        .reset(reset),
        .raster_clk(raster_clk),
        .raster_write(raster_write && !write_page_raster),
        .raster_x(raster_x),
        .raster_y(raster_y),
        .raster_color(raster_color),
        .clear_request(clear_request && !write_page_raster),
        .clear_busy(framebuffer_clear_busy0),
        .display_clk(pixel_clk),
        .display_read_enable(scan_active && !front_page_pixel),
        .display_x(framebuffer_x),
        .display_y(framebuffer_y),
        .display_pixel(framebuffer_index0),
        .display_pixel_valid(framebuffer_index_valid0)
    );

    framebuffer #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) framebuffer1 (
        .reset(reset),
        .raster_clk(raster_clk),
        .raster_write(raster_write && write_page_raster),
        .raster_x(raster_x),
        .raster_y(raster_y),
        .raster_color(raster_color),
        .clear_request(clear_request && write_page_raster),
        .clear_busy(framebuffer_clear_busy1),
        .display_clk(pixel_clk),
        .display_read_enable(scan_active && front_page_pixel),
        .display_x(framebuffer_x),
        .display_y(framebuffer_y),
        .display_pixel(framebuffer_index1),
        .display_pixel_valid(framebuffer_index_valid1)
    );

    assign clear_busy = framebuffer_clear_busy0 || framebuffer_clear_busy1;
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
                (swap_ack_sync2 != swap_ack_seen_raster)) begin
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

            if ((scan_x == 10'd0) && (scan_y == V_ACTIVE) &&
                (swap_request_sync2 != swap_request_seen_pixel)) begin
                front_page_pixel <= ~front_page_pixel;
                swap_request_seen_pixel <= swap_request_sync2;
                swap_ack_pixel <= swap_request_sync2;
            end
        end
    end

    palette_256x24 palette (
        .clock_a(palette_clk),
        .address_a(palette_address),
        .data_a(palette_write_rgb),
        .wren_a(palette_write),
        .clock_b(pixel_clk),
        .address_b(framebuffer_index),
        .rden_b(framebuffer_index_valid),
        .q_b(palette_rgb)
    );

    always_ff @(posedge pixel_clk or posedge reset) begin
        if (reset) begin
            fps_sync1 <= '0;
            fps_sync2 <= '0;
            scan_x_d1 <= '0;
            scan_x_d2 <= '0;
            scan_y_d1 <= '0;
            scan_y_d2 <= '0;
            active_d1 <= 1'b0;
            active_d2 <= 1'b0;
            hs_d1 <= 1'b1;
            hs_d2 <= 1'b1;
            vs_d1 <= 1'b1;
            vs_d2 <= 1'b1;
        end else begin
            fps_sync1 <= fps_value;
            fps_sync2 <= fps_sync1;
            scan_x_d1 <= scan_x;
            scan_x_d2 <= scan_x_d1;
            scan_y_d1 <= scan_y;
            scan_y_d2 <= scan_y_d1;
            active_d1 <= scan_active;
            active_d2 <= active_d1;
            hs_d1 <= scan_hs;
            hs_d2 <= hs_d1;
            vs_d1 <= scan_vs;
            vs_d2 <= vs_d1;
        end
    end

    always_comb begin
        fps_text_pixel = fps_overlay_pixel(scan_x_d2, scan_y_d2, fps_sync2);
    end

    always_comb begin
        vga_hs = hs_d2;
        vga_vs = vs_d2;
        vga_active = active_d2;

        if (active_d2) begin
            if (fps_text_pixel) begin
                vga_r = 8'hFF;
                vga_g = 8'hFF;
                vga_b = 8'hFF;
            end else begin
                vga_r = palette_rgb[23:16];
                vga_g = palette_rgb[15:8];
                vga_b = palette_rgb[7:0];
            end
        end else begin
            vga_r = 8'd0;
            vga_g = 8'd0;
            vga_b = 8'd0;
        end
    end

endmodule
