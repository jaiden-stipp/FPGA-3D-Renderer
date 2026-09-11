`include "renderer_types.svh"

module render_performance_counters (
    input logic clk,
    input logic reset,
    input logic frame_start,
    input logic frame_complete,
    input logic swap_wait_start,
    input logic triangle_submitted,
    input logic triangle_clipped,
    input logic triangle_culled,
    input logic bounding_box_pixel,
    input logic pixel_inside,
    input logic depth_rejected,
    input logic pixel_written,
    input logic geometry_active,
    input logic geometry_stalled,
    input logic raster_active,
    input logic clear_active,
    output renderer_stats_t completed_stats
);

    renderer_stats_t current_stats;
    logic frame_active;
    logic swap_wait_active;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            current_stats <= '0;
            completed_stats <= '0;
            frame_active <= 1'b0;
            swap_wait_active <= 1'b0;
        end else if (frame_start) begin
            current_stats <= '0;
            frame_active <= 1'b1;
            swap_wait_active <= 1'b0;
        end else if (frame_active) begin
            if (triangle_submitted)
                current_stats.triangles_submitted <=
                    current_stats.triangles_submitted + 1'b1;
            if (triangle_clipped)
                current_stats.triangles_clipped <=
                    current_stats.triangles_clipped + 1'b1;
            if (triangle_culled)
                current_stats.triangles_culled <=
                    current_stats.triangles_culled + 1'b1;
            if (bounding_box_pixel)
                current_stats.bounding_box_pixels <=
                    current_stats.bounding_box_pixels + 1'b1;
            if (pixel_inside)
                current_stats.pixels_inside <= current_stats.pixels_inside + 1'b1;
            if (depth_rejected)
                current_stats.depth_rejected <= current_stats.depth_rejected + 1'b1;
            if (pixel_written)
                current_stats.pixels_written <= current_stats.pixels_written + 1'b1;
            if (geometry_active)
                current_stats.geometry_cycles <= current_stats.geometry_cycles + 1'b1;
            if (geometry_stalled)
                current_stats.geometry_stall_cycles <=
                    current_stats.geometry_stall_cycles + 1'b1;
            if (raster_active)
                current_stats.raster_cycles <= current_stats.raster_cycles + 1'b1;
            if (clear_active)
                current_stats.clear_cycles <= current_stats.clear_cycles + 1'b1;
            current_stats.total_cycles <= current_stats.total_cycles + 1'b1;

            if (swap_wait_start)
                swap_wait_active <= 1'b1;
            if (swap_wait_active)
                current_stats.swap_wait_cycles <=
                    current_stats.swap_wait_cycles + 1'b1;

            if (frame_complete) begin
                completed_stats.triangles_submitted <=
                    current_stats.triangles_submitted + triangle_submitted;
                completed_stats.triangles_clipped <=
                    current_stats.triangles_clipped + triangle_clipped;
                completed_stats.triangles_culled <=
                    current_stats.triangles_culled + triangle_culled;
                completed_stats.bounding_box_pixels <=
                    current_stats.bounding_box_pixels + bounding_box_pixel;
                completed_stats.pixels_inside <=
                    current_stats.pixels_inside + pixel_inside;
                completed_stats.depth_rejected <=
                    current_stats.depth_rejected + depth_rejected;
                completed_stats.pixels_written <=
                    current_stats.pixels_written + pixel_written;
                completed_stats.geometry_cycles <=
                    current_stats.geometry_cycles + geometry_active;
                completed_stats.geometry_stall_cycles <=
                    current_stats.geometry_stall_cycles + geometry_stalled;
                completed_stats.raster_cycles <=
                    current_stats.raster_cycles + raster_active;
                completed_stats.clear_cycles <=
                    current_stats.clear_cycles + clear_active;
                completed_stats.total_cycles <= current_stats.total_cycles + 1'b1;
                completed_stats.swap_wait_cycles <=
                    current_stats.swap_wait_cycles + swap_wait_active;
                frame_active <= 1'b0;
                swap_wait_active <= 1'b0;
            end
        end
    end

endmodule
