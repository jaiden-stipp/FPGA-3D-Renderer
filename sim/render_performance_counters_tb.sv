`timescale 1ns/1ps
`include "renderer_types.svh"

module render_performance_counters_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic frame_start = 1'b0;
    logic frame_complete = 1'b0;
    logic swap_wait_start = 1'b0;
    logic triangle_submitted = 1'b0;
    logic triangle_clipped = 1'b0;
    logic triangle_culled = 1'b0;
    logic bounding_box_pixel = 1'b0;
    logic pixel_inside = 1'b0;
    logic depth_rejected = 1'b0;
    logic pixel_written = 1'b0;
    logic geometry_active = 1'b0;
    logic geometry_stalled = 1'b0;
    logic raster_active = 1'b0;
    logic clear_active = 1'b0;
    renderer_stats_t completed_stats;

    always #1 clk = ~clk;

    render_performance_counters dut (
        .clk(clk),
        .reset(reset),
        .frame_start(frame_start),
        .frame_complete(frame_complete),
        .swap_wait_start(swap_wait_start),
        .triangle_submitted(triangle_submitted),
        .triangle_clipped(triangle_clipped),
        .triangle_culled(triangle_culled),
        .bounding_box_pixel(bounding_box_pixel),
        .pixel_inside(pixel_inside),
        .depth_rejected(depth_rejected),
        .pixel_written(pixel_written),
        .geometry_active(geometry_active),
        .geometry_stalled(geometry_stalled),
        .raster_active(raster_active),
        .clear_active(clear_active),
        .completed_stats(completed_stats)
    );

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        frame_start = 1'b1;
        @(negedge clk);
        frame_start = 1'b0;
        triangle_submitted = 1'b1;
        triangle_clipped = 1'b1;
        bounding_box_pixel = 1'b1;
        pixel_inside = 1'b1;
        pixel_written = 1'b1;
        geometry_active = 1'b1;
        raster_active = 1'b1;
        clear_active = 1'b1;
        @(negedge clk);
        triangle_clipped = 1'b0;
        triangle_culled = 1'b1;
        depth_rejected = 1'b1;
        pixel_written = 1'b0;
        geometry_active = 1'b0;
        geometry_stalled = 1'b1;
        @(negedge clk);
        triangle_submitted = 1'b0;
        triangle_culled = 1'b0;
        bounding_box_pixel = 1'b0;
        pixel_inside = 1'b0;
        depth_rejected = 1'b0;
        geometry_stalled = 1'b0;
        raster_active = 1'b0;
        clear_active = 1'b0;
        swap_wait_start = 1'b1;
        @(negedge clk);
        swap_wait_start = 1'b0;
        repeat (2) @(negedge clk);
        frame_complete = 1'b1;
        @(negedge clk);
        frame_complete = 1'b0;

        if (completed_stats.triangles_submitted != 2 ||
            completed_stats.triangles_clipped != 1 ||
            completed_stats.triangles_culled != 1 ||
            completed_stats.bounding_box_pixels != 2 ||
            completed_stats.pixels_inside != 2 ||
            completed_stats.depth_rejected != 1 ||
            completed_stats.pixels_written != 1 ||
            completed_stats.geometry_cycles != 1 ||
            completed_stats.geometry_stall_cycles != 1 ||
            completed_stats.raster_cycles != 2 ||
            completed_stats.clear_cycles != 2 ||
            completed_stats.total_cycles != 6 ||
            completed_stats.swap_wait_cycles != 3)
            $fatal(1, "completed statistics: sub=%0d clip=%0d cull=%0d box=%0d inside=%0d reject=%0d write=%0d geo=%0d stall=%0d raster=%0d clear=%0d total=%0d swap=%0d",
                completed_stats.triangles_submitted,
                completed_stats.triangles_clipped,
                completed_stats.triangles_culled,
                completed_stats.bounding_box_pixels,
                completed_stats.pixels_inside,
                completed_stats.depth_rejected,
                completed_stats.pixels_written,
                completed_stats.geometry_cycles,
                completed_stats.geometry_stall_cycles,
                completed_stats.raster_cycles,
                completed_stats.clear_cycles,
                completed_stats.total_cycles,
                completed_stats.swap_wait_cycles);

        $display("render_performance_counters_tb PASS");
        $finish;
    end

endmodule
