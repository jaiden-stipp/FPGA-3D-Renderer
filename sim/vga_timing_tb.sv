`timescale 1ns/1ps

module vga_timing_tb;
    logic pixel_clk;
    logic reset;
    logic [9:0] x;
    logic [9:0] y;
    logic active;
    logic hsync;
    logic vsync;
    integer active_count;
    integer hsync_low_count;
    integer vsync_low_count;

    vga_timing_640x480 dut (
        .pixel_clk(pixel_clk),
        .reset(reset),
        .x(x),
        .y(y),
        .active(active),
        .hsync(hsync),
        .vsync(vsync)
    );

    always #1 pixel_clk = ~pixel_clk;

    initial begin
        pixel_clk = 1'b0;
        reset = 1'b1;
        active_count = 0;
        hsync_low_count = 0;
        vsync_low_count = 0;

        repeat (2) @(posedge pixel_clk);
        reset = 1'b0;

        repeat (800 * 525) begin
            @(posedge pixel_clk);
            if (active)
                active_count = active_count + 1;
            if (!hsync)
                hsync_low_count = hsync_low_count + 1;
            if (!vsync)
                vsync_low_count = vsync_low_count + 1;
        end

        if (active_count != 640 * 480)
            $fatal(1, "expected 307200 active pixels, got %0d", active_count);
        if (hsync_low_count != 96 * 525)
            $fatal(1, "unexpected hsync-low count: %0d", hsync_low_count);
        if (vsync_low_count != 2 * 800)
            $fatal(1, "unexpected vsync-low count: %0d", vsync_low_count);

        $display("vga_timing_tb PASS: 800x525 timing, 640x480 active");
        $finish;
    end
endmodule
