`timescale 1ns/1ps
`include "renderer_types.svh"

module ethernet_command_receiver_tb;

    logic system_clk = 1'b0;
    logic rx_clk = 1'b0;
    logic tx_clk = 1'b0;
    logic reset = 1'b1;
    logic [3:0] rx_data = '0;
    logic rx_dv = 1'b0;
    logic rx_er = 1'b0;
    logic [3:0] tx_data;
    logic tx_en;
    logic tx_er;
    graphics_command_t command_data;
    logic command_valid;
    logic command_ready = 1'b1;
    logic command_error = 1'b0;
    logic frame_done = 1'b0;
    logic [31:0] frame_done_id = '0;
    renderer_stats_t frame_statistics;
    logic decoder_error;
    logic receive_overflow;
    logic packet_seen;
    integer command_count = 0;

    always #10 system_clk = ~system_clk;
    always #20 rx_clk = ~rx_clk;
    always #20 tx_clk = ~tx_clk;

    ethernet_command_receiver dut (
        .system_clk(system_clk),
        .reset(reset),
        .mii_rx_clk(rx_clk),
        .mii_rx_data(rx_data),
        .mii_rx_dv(rx_dv),
        .mii_rx_er(rx_er),
        .mii_tx_clk(tx_clk),
        .mii_tx_data(tx_data),
        .mii_tx_en(tx_en),
        .mii_tx_er(tx_er),
        .command_data(command_data),
        .command_valid(command_valid),
        .command_ready(command_ready),
        .command_error(command_error),
        .frame_done(frame_done),
        .frame_done_id(frame_done_id),
        .frame_statistics(frame_statistics),
        .decoder_error(decoder_error),
        .receive_overflow(receive_overflow),
        .packet_seen(packet_seen)
    );

    always @(posedge system_clk) begin
        if (command_valid && command_ready) begin
            if (command_data.opcode != GFX_CMD_SET_PALETTE ||
                `GFX_ARGUMENT(command_data) != 32'h07A1B2C3)
                $fatal(1, "decoded graphics command is incorrect");
            command_count = command_count + 1;
        end
    end

    task send_byte(input logic [7:0] value);
        begin
            @(negedge rx_clk);
            rx_dv = 1'b1;
            rx_data = value[3:0];
            @(negedge rx_clk);
            rx_data = value[7:4];
        end
    endtask

    initial begin
        frame_statistics = '0;
        repeat (3) @(posedge system_clk);
        reset = 1'b0;

        repeat (7) send_byte(8'h55);
        send_byte(8'hD5);
        send_byte(8'h02); send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h00); send_byte(8'h00); send_byte(8'h01);
        send_byte(8'h10); send_byte(8'h20); send_byte(8'h30);
        send_byte(8'h40); send_byte(8'h50); send_byte(8'h60);
        send_byte(8'h08); send_byte(8'h00);
        send_byte(8'h45); send_byte(8'h00); send_byte(8'h00); send_byte(8'h33);
        send_byte(8'h00); send_byte(8'h01); send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h40); send_byte(8'h11); send_byte(8'h00); send_byte(8'h00);
        send_byte(8'hC0); send_byte(8'hA8); send_byte(8'h07); send_byte(8'h01);
        send_byte(8'hC0); send_byte(8'hA8); send_byte(8'h07); send_byte(8'h02);
        send_byte(8'h04); send_byte(8'hD2); send_byte(8'h0F); send_byte(8'hA0);
        send_byte(8'h00); send_byte(8'h1F); send_byte(8'h00); send_byte(8'h00);
        send_byte(8'h47); send_byte(8'h50); send_byte(`GFX_TRANSPORT_VERSION); send_byte(8'h03);
        send_byte(8'h00); send_byte(8'h00); send_byte(8'h00); send_byte(8'h01);
        send_byte(8'h00); send_byte(8'h00); send_byte(8'h00); send_byte(8'h0B);
        send_byte(8'h47); send_byte(8'h46); send_byte(`GFX_COMMAND_VERSION);
        send_byte(`GFX_WIRE_CMD_SET_PALETTE); send_byte(8'h04);
        send_byte(8'h07); send_byte(8'hA1); send_byte(8'hB2); send_byte(8'hC3);
        send_byte(8'h25); send_byte(8'h9E);
        @(negedge rx_clk);
        rx_dv = 1'b0;

        wait (command_count == 1);
        repeat (5) @(posedge system_clk);
        if (!packet_seen)
            $fatal(1, "accepted packet status did not cross clock domains");
        if (decoder_error || receive_overflow || tx_er)
            $fatal(1, "unexpected Ethernet command receiver error");

        @(negedge system_clk);
        command_error = 1'b1;
        @(posedge system_clk);
        @(negedge system_clk);
        command_error = 1'b0;
        frame_done_id = 32'h12345678;
        frame_done = 1'b1;
        #1;
        if (dut.frame_queue_write_data[$bits(renderer_stats_t)+31 -: 32] !=
            32'h00000200)
            $fatal(1, "frame status did not capture the command error");
        @(posedge system_clk);
        @(negedge system_clk);
        frame_done = 1'b0;
        if (receive_overflow)
            $fatal(1, "frame response queue overflowed");

        $display("ethernet_command_receiver_tb PASS");
        $finish;
    end

endmodule
