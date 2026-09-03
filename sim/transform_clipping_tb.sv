`timescale 1ns/1ps

`include "renderer_types.svh"

module transform_clipping_tb;
    logic clk;
    logic reset;
    logic [7:0] rotation_angle;
    triangle_3d_t in_data;
    logic in_valid;
    logic in_ready;
    triangle_data_t out_data;
    logic out_valid;
    logic out_ready;
    logic busy;
    integer output_count;

    transform_3d_pipeline #(
        .BACKFACE_CULL(1'b0),
        .VIEW_PITCH_ANGLE(8'd0)
    ) dut (
        .clk(clk),
        .reset(reset),
        .rotation_angle(rotation_angle),
        .in_data(in_data),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .out_data(out_data),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .busy(busy)
    );

    always #1 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && out_valid && out_ready) begin
            output_count = output_count + 1;
            if ((out_data.x0 > 10'd319) || (out_data.x1 > 10'd319) ||
                (out_data.x2 > 10'd319) || (out_data.y0 > 9'd239) ||
                (out_data.y1 > 9'd239) || (out_data.y2 > 9'd239))
                $fatal(1, "clipped triangle contains an off-screen vertex");
            if ((out_data.z0 == 0) || (out_data.z1 == 0) ||
                (out_data.z2 == 0))
                $fatal(1, "clipped triangle lost inverse depth");
        end
    end

    task automatic submit_and_check(input integer expected_outputs);
        integer starting_count;
        begin
            starting_count = output_count;
            while (!in_ready)
                @(posedge clk);
            @(negedge clk);
            in_valid = 1'b1;
            @(negedge clk);
            in_valid = 1'b0;

            while (!busy)
                @(posedge clk);
            while (busy)
                @(posedge clk);

            if ((output_count - starting_count) != expected_outputs)
                $fatal(1, "expected %0d output triangles, got %0d",
                       expected_outputs, output_count - starting_count);
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        rotation_angle = 8'd0;
        in_valid = 1'b0;
        out_ready = 1'b1;
        in_data = '0;
        output_count = 0;

        repeat (2) @(posedge clk);
        reset = 1'b0;

        in_data.x0 = -16'sh0080;
        in_data.y0 = -16'sh0080;
        in_data.z0 = -16'sh0400;
        in_data.x1 = 16'sh0080;
        in_data.y1 = -16'sh0080;
        in_data.z1 = 16'sh0000;
        in_data.x2 = 16'sh0000;
        in_data.y2 = 16'sh0080;
        in_data.z2 = 16'sh0000;
        in_data.color = 8'hE0;
        submit_and_check(2);

        in_data.x0 = -16'sh0800;
        in_data.y0 = -16'sh0800;
        in_data.z0 = 16'sh0000;
        in_data.x1 = 16'sh0800;
        in_data.y1 = -16'sh0800;
        in_data.z1 = 16'sh0000;
        in_data.x2 = 16'sh0000;
        in_data.y2 = 16'sh0800;
        in_data.z2 = 16'sh0000;
        in_data.color = 8'h1F;
        submit_and_check(4);

        $display("transform_clipping_tb PASS: near and viewport clipping work");
        $finish;
    end
endmodule
