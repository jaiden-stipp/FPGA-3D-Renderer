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
            command_data.argument[7:0] != 8'h5A)
            $fatal(1, "rotation frame decoded incorrectly");
        repeat (2) @(posedge clk);
        if (!command_valid || byte_ready)
            $fatal(1, "decoder did not hold its command under backpressure");
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
            command_data.argument != 32'h07A1B2C3)
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
            command_data.triangle.x0 != 16'sh0100 ||
            command_data.triangle.y0 != 16'shFF00 ||
            command_data.triangle.z1 != 16'shFF80 ||
            command_data.triangle.x2 != 16'shFE00 ||
            command_data.triangle.color != 8'h2F)
            $fatal(1, "triangle frame decoded incorrectly");
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
