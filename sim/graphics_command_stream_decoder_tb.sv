`timescale 1ns/1ps

`include "renderer_types.svh"

module graphics_command_stream_decoder_tb;
    logic clk;
    logic reset;
    logic [7:0] byte_data;
    logic byte_valid;
    logic byte_ready;
    logic command_valid;
    logic command_ready;
    logic decoder_error;
    graphics_command_t command_data;
    triangle_3d_t decoded_triangle;
    model_matrix_3x4_t decoded_matrix;

    assign decoded_triangle = `GFX_TRIANGLE(command_data);
    assign decoded_matrix = `GFX_MODEL_MATRIX(command_data);

    graphics_command_stream_decoder dut (
        .clk(clk),
        .reset(reset),
        .byte_data(byte_data),
        .byte_valid(byte_valid),
        .byte_ready(byte_ready),
        .command_data(command_data),
        .command_valid(command_valid),
        .command_ready(command_ready),
        .decoder_error(decoder_error)
    );

    always #1 clk = ~clk;

    task send_byte(input logic [7:0] value);
        begin
            @(negedge clk);
            byte_data = value;
            byte_valid = 1'b1;
            wait (byte_ready);
            @(posedge clk);
            @(negedge clk);
            byte_valid = 1'b0;
        end
    endtask

    task accept_command;
        begin
            @(negedge clk);
            command_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            command_ready = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        byte_data = '0;
        byte_valid = 1'b0;
        command_ready = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        send_byte(8'h47);
        send_byte(8'h46);
        send_byte(8'h01);
        send_byte(8'h00);
        send_byte(8'h01);
        send_byte(8'h5A);
        send_byte(8'hCE);
        send_byte(8'h96);
        wait (command_valid);
        if (command_data.opcode != GFX_CMD_SET_ROTATION ||
            command_data.payload[7:0] != 8'h5A)
            $fatal(1, "rotation frame decoded incorrectly");
        repeat (2) @(posedge clk);
        if (!command_valid || byte_ready)
            $fatal(1, "decoder did not hold its command under backpressure");
        accept_command();

        send_byte(8'h47);
        send_byte(8'h46);
        send_byte(8'h01);
        send_byte(8'h05);
        send_byte(8'h05);
        send_byte(8'h02);
        send_byte(8'h00);
        send_byte(8'h03);
        send_byte(8'h00);
        send_byte(8'h01);
        send_byte(8'hFA);
        send_byte(8'h0F);
        wait (command_valid);
        if (command_data.opcode != GFX_CMD_DEFINE_MESH ||
            `GFX_MESH_HANDLE(command_data) != 8'd2 ||
            `GFX_MESH_VERTEX_COUNT(command_data) != 16'd3 ||
            `GFX_MESH_TRIANGLE_COUNT(command_data) != 16'd1)
            $fatal(1, "mesh descriptor decoded incorrectly");
        accept_command();

        send_byte(8'h47);
        send_byte(8'h46);
        send_byte(8'h01);
        send_byte(8'h08);
        send_byte(8'h19);
        send_byte(8'h02);
        send_byte(8'h01); send_byte(8'h00);
        send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h02); send_byte(8'h00);
        send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h01); send_byte(8'h00);
        send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h01); send_byte(8'h00);
        send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h88); send_byte(8'h1C);
        wait (command_valid);
        if (command_data.opcode != GFX_CMD_DRAW_MESH ||
            `GFX_DRAW_MESH_HANDLE(command_data) != 8'd2 ||
            decoded_matrix.m00 != 16'sh0100 ||
            decoded_matrix.m03 != 16'sh0200 ||
            decoded_matrix.m11 != 16'sh0100 ||
            decoded_matrix.m22 != 16'sh0100)
            $fatal(1, "indexed draw matrix decoded incorrectly");
        accept_command();

        send_byte(8'h47);
        send_byte(8'h46);
        send_byte(8'h01);
        send_byte(8'h01);
        send_byte(8'h04);
        send_byte(8'h12);
        send_byte(8'h34);
        send_byte(8'h56);
        send_byte(8'h78);
        send_byte(8'h40);
        send_byte(8'hF0);
        wait (command_valid);
        if (command_data.opcode != GFX_CMD_BEGIN_FRAME ||
            `GFX_ARGUMENT(command_data) != 32'h12345678)
            $fatal(1, "begin-frame ID decoded incorrectly");
        accept_command();

        send_byte(8'h47);
        send_byte(8'h46);
        send_byte(8'h01);
        send_byte(8'h04);
        send_byte(8'h04);
        send_byte(8'h07);
        send_byte(8'hA1);
        send_byte(8'hB2);
        send_byte(8'hC3);
        send_byte(8'hFD);
        send_byte(8'h1C);
        wait (command_valid);
        if (command_data.opcode != GFX_CMD_SET_PALETTE ||
            `GFX_ARGUMENT(command_data) != 32'h07A1B2C3)
            $fatal(1, "palette frame decoded incorrectly");
        accept_command();

        send_byte(8'h47);
        send_byte(8'h46);
        send_byte(8'h01);
        send_byte(8'h02);
        send_byte(8'h13);
        send_byte(8'h01);
        send_byte(8'h00);
        send_byte(8'hFF);
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'h80);
        send_byte(8'h02);
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'hFF);
        send_byte(8'h80);
        send_byte(8'hFE);
        send_byte(8'h00);
        send_byte(8'h01);
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'h00);
        send_byte(8'h2F);
        send_byte(8'h58);
        send_byte(8'hD8);
        wait (command_valid);
        if (command_data.opcode != GFX_CMD_DRAW_TRIANGLE ||
            decoded_triangle.x0 != 16'sh0100 ||
            decoded_triangle.y0 != 16'shFF00 ||
            decoded_triangle.z1 != 16'shFF80 ||
            decoded_triangle.x2 != 16'shFE00 ||
            decoded_triangle.color != 8'h2F)
            $fatal(1, "triangle frame decoded incorrectly");
        accept_command();

        send_byte(8'h47); send_byte(8'h46); send_byte(8'h01);
        send_byte(8'h09); send_byte(8'h0F);
        send_byte(8'h02); send_byte(8'h04); send_byte(8'h02);
        send_byte(8'h01); send_byte(8'h00);
        send_byte(8'h02); send_byte(8'h00);
        send_byte(8'h03); send_byte(8'h00);
        send_byte(8'hFF); send_byte(8'h00);
        send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h00); send_byte(8'h80);
        send_byte(8'h12); send_byte(8'h66);
        wait (command_valid);
        @(negedge clk);
        if (command_data.opcode != GFX_CMD_UPLOAD_VERTEX ||
            `GFX_MESH_ELEMENT(command_data) != 16'd4 ||
            `GFX_VERTEX_X(command_data) != 16'sh0100 ||
            `GFX_VERTEX_Z(command_data) != 16'sh0300)
            $fatal(1, "first bulk vertex decoded incorrectly");
        accept_command();
        wait (command_valid);
        @(negedge clk);
        if (!command_valid ||
            `GFX_MESH_ELEMENT(command_data) != 16'd5 ||
            `GFX_VERTEX_X(command_data) != 16'shFF00 ||
            `GFX_VERTEX_Z(command_data) != 16'sh0080)
            $fatal(1, "second bulk vertex decoded incorrectly");
        accept_command();

        send_byte(8'h47); send_byte(8'h46); send_byte(8'h01);
        send_byte(8'h0A); send_byte(8'h0C);
        send_byte(8'h02); send_byte(8'h00); send_byte(8'h07); send_byte(8'h02);
        send_byte(8'h02); send_byte(8'h00); send_byte(8'h01); send_byte(8'hA5);
        send_byte(8'h01); send_byte(8'h02); send_byte(8'h00); send_byte(8'hB6);
        send_byte(8'hFC); send_byte(8'hFC);
        wait (command_valid);
        @(negedge clk);
        if (command_data.opcode != GFX_CMD_UPLOAD_INDEX ||
            `GFX_MESH_ELEMENT(command_data) != 16'd7 ||
            `GFX_MESH_INDEX0(command_data) != 8'd2 ||
            `GFX_MESH_COLOR(command_data) != 8'hA5)
            $fatal(1, "first bulk index decoded incorrectly");
        accept_command();
        wait (command_valid);
        @(negedge clk);
        if (!command_valid ||
            `GFX_MESH_ELEMENT(command_data) != 16'd8 ||
            `GFX_MESH_INDEX0(command_data) != 8'd1 ||
            `GFX_MESH_COLOR(command_data) != 8'hB6)
            $fatal(1, "second bulk index decoded incorrectly");
        accept_command();

        send_byte(8'h47);
        send_byte(8'h46);
        send_byte(8'h01);
        send_byte(8'h03);
        send_byte(8'h00);
        send_byte(8'h4C);
        send_byte(8'h00);
        if (!decoder_error || command_valid)
            $fatal(1, "bad CRC was not rejected");

        $display("graphics_command_stream_decoder_tb PASS");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "graphics_command_stream_decoder_tb timed out");
    end
endmodule
