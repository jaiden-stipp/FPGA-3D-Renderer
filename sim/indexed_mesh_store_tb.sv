`timescale 1ns/1ps
`include "renderer_types.svh"

module indexed_mesh_store_tb;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic define_write = 1'b0;
    logic [7:0] define_handle = '0;
    logic [15:0] define_vertex_count = '0;
    logic [15:0] define_triangle_count = '0;
    logic vertex_write = 1'b0;
    logic [7:0] vertex_handle = '0;
    logic [7:0] vertex_number = '0;
    logic signed [15:0] vertex_x = '0;
    logic signed [15:0] vertex_y = '0;
    logic signed [15:0] vertex_z = '0;
    logic index_write = 1'b0;
    logic [7:0] index_handle = '0;
    logic [15:0] index_number = '0;
    logic [7:0] index0 = '0;
    logic [7:0] index1 = '0;
    logic [7:0] index2 = '0;
    logic [7:0] index_color = '0;
    logic upload_error;
    logic draw_valid = 1'b0;
    logic draw_ready;
    logic [7:0] draw_handle = '0;
    model_matrix_3x4_t draw_matrix;
    triangle_3d_t triangle_data;
    logic triangle_valid;
    logic triangle_ready = 1'b1;
    logic draw_busy;
    logic draw_done;
    logic draw_error;
    integer output_count = 0;

    always #1 clk = ~clk;

    indexed_mesh_store dut (
        .clk(clk),
        .reset(reset),
        .define_write(define_write),
        .define_handle(define_handle),
        .define_vertex_count(define_vertex_count),
        .define_triangle_count(define_triangle_count),
        .vertex_write(vertex_write),
        .vertex_handle(vertex_handle),
        .vertex_number(vertex_number),
        .vertex_x(vertex_x),
        .vertex_y(vertex_y),
        .vertex_z(vertex_z),
        .index_write(index_write),
        .index_handle(index_handle),
        .index_number(index_number),
        .index0(index0),
        .index1(index1),
        .index2(index2),
        .index_color(index_color),
        .upload_error(upload_error),
        .draw_valid(draw_valid),
        .draw_ready(draw_ready),
        .draw_handle(draw_handle),
        .draw_matrix(draw_matrix),
        .triangle_data(triangle_data),
        .triangle_valid(triangle_valid),
        .triangle_ready(triangle_ready),
        .draw_busy(draw_busy),
        .draw_done(draw_done),
        .draw_error(draw_error)
    );

    always @(posedge clk) begin
        if (triangle_valid && triangle_ready)
            output_count = output_count + 1;
    end

    task write_vertex(input logic [7:0] number,
                      input logic signed [15:0] x,
                      input logic signed [15:0] y,
                      input logic signed [15:0] z);
        begin
            @(negedge clk);
            vertex_number = number;
            vertex_x = x;
            vertex_y = y;
            vertex_z = z;
            vertex_write = 1'b1;
            @(posedge clk);
            @(negedge clk);
            vertex_write = 1'b0;
        end
    endtask

    task draw_and_check(input logic signed [15:0] translation_x,
                        input logic signed [15:0] expected_x0,
                        input logic signed [15:0] expected_x1,
                        input logic signed [15:0] expected_x2);
        begin
            draw_matrix = '0;
            draw_matrix.m00 = 16'sh0100;
            draw_matrix.m11 = 16'sh0100;
            draw_matrix.m22 = 16'sh0100;
            draw_matrix.m03 = translation_x;
            @(negedge clk);
            draw_valid = 1'b1;
            wait (draw_ready);
            @(posedge clk);
            @(negedge clk);
            draw_valid = 1'b0;
            wait (triangle_valid);
            if (triangle_data.x0 != expected_x0 ||
                triangle_data.x1 != expected_x1 ||
                triangle_data.x2 != expected_x2 ||
                triangle_data.y0 != 16'sh0100 ||
                triangle_data.z0 != 16'shFE00 ||
                triangle_data.color != 8'hA5)
                $fatal(1, "indexed triangle fetch or model transform is incorrect");
            wait (draw_done);
            @(posedge clk);
        end
    endtask

    initial begin
        draw_matrix = '0;
        repeat (3) @(posedge clk);
        reset = 1'b0;

        @(negedge clk);
        define_handle = 8'd2;
        define_vertex_count = 16'd3;
        define_triangle_count = 16'd1;
        define_write = 1'b1;
        if (upload_error)
            $fatal(1, "valid mesh descriptor was rejected");
        @(posedge clk);
        @(negedge clk);
        define_write = 1'b0;

        vertex_handle = 8'd2;
        write_vertex(8'd0, 16'sh0100, 16'sh0200, 16'sh0300);
        write_vertex(8'd1, 16'shFF00, 16'sh0000, 16'sh0080);
        write_vertex(8'd2, 16'sh0000, 16'sh0100, 16'shFE00);

        @(negedge clk);
        index_handle = 8'd2;
        index_number = 16'd0;
        index0 = 8'd2;
        index1 = 8'd0;
        index2 = 8'd1;
        index_color = 8'hA5;
        index_write = 1'b1;
        if (upload_error)
            $fatal(1, "valid triangle index was rejected");
        @(posedge clk);
        @(negedge clk);
        index_write = 1'b0;

        draw_handle = 8'd2;
        draw_and_check(16'sh0000, 16'sh0000, 16'sh0100, 16'shFF00);
        draw_and_check(16'sh0200, 16'sh0200, 16'sh0300, 16'sh0100);
        if (output_count != 2)
            $fatal(1, "expected two transformed copies, got %0d", output_count);

        draw_handle = 8'd7;
        @(negedge clk);
        draw_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        draw_valid = 1'b0;
        wait (draw_done);
        if (!draw_error)
            $fatal(1, "undefined mesh handle did not report an error");

        $display("indexed_mesh_store_tb PASS: one mesh produced two transformed copies");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "indexed_mesh_store_tb timed out");
    end

endmodule
