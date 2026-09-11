`timescale 1ns/1ps
`include "renderer_types.svh"

module mii_udp_receiver_tb;

    logic rx_clk = 1'b0;
    logic reset = 1'b1;
    logic [3:0] rx_data = '0;
    logic rx_dv = 1'b0;
    logic rx_er = 1'b0;
    logic [11:0] fifo_free = 12'd2048;
    logic [7:0] payload_data;
    logic payload_valid;
    logic payload_ready = 1'b1;
    logic payload_overflow;
    logic packet_received;
    logic packet_status;
    logic [47:0] packet_sender_mac;
    logic [31:0] packet_sender_ip;
    logic [15:0] packet_sender_port;
    logic [31:0] packet_frame_id;
    logic [15:0] packet_sequence;
    logic [31:0] packet_status_flags;
    logic [11:0] packet_fifo_free;
    logic arp_request;
    logic [47:0] arp_sender_mac;
    logic [31:0] arp_sender_ip;
    logic [7:0] captured_payload [0:5];
    integer payload_count = 0;
    integer packet_count = 0;
    integer status_count = 0;
    integer arp_count = 0;

    always #20 rx_clk = ~rx_clk;

    mii_udp_receiver dut (
        .rx_clk(rx_clk),
        .reset(reset),
        .rx_data(rx_data),
        .rx_dv(rx_dv),
        .rx_er(rx_er),
        .fifo_free(fifo_free),
        .payload_data(payload_data),
        .payload_valid(payload_valid),
        .payload_ready(payload_ready),
        .payload_overflow(payload_overflow),
        .packet_received(packet_received),
        .packet_status(packet_status),
        .packet_sender_mac(packet_sender_mac),
        .packet_sender_ip(packet_sender_ip),
        .packet_sender_port(packet_sender_port),
        .packet_frame_id(packet_frame_id),
        .packet_sequence(packet_sequence),
        .packet_status_flags(packet_status_flags),
        .packet_fifo_free(packet_fifo_free),
        .arp_request(arp_request),
        .arp_sender_mac(arp_sender_mac),
        .arp_sender_ip(arp_sender_ip)
    );

    always @(posedge rx_clk) begin
        if (payload_valid) begin
            captured_payload[payload_count] = payload_data;
            payload_count = payload_count + 1;
        end
        if (packet_received)
            packet_count = packet_count + 1;
        if (packet_status)
            status_count = status_count + 1;
        if (arp_request)
            arp_count = arp_count + 1;
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

    task send_udp_second_packet;
        begin
            begin_frame();
            send_byte(8'h02); send_byte(8'h00); send_byte(8'h00);
            send_byte(8'h00); send_byte(8'h00); send_byte(8'h01);
            send_byte(8'h10); send_byte(8'h20); send_byte(8'h30);
            send_byte(8'h40); send_byte(8'h50); send_byte(8'h60);
            send_byte(8'h08); send_byte(8'h00);
            send_byte(8'h45); send_byte(8'h00); send_byte(8'h00); send_byte(8'h2A);
            send_byte(8'h00); send_byte(8'h01); send_byte(8'h00); send_byte(8'h00);
            send_byte(8'h40); send_byte(8'h11); send_byte(8'h00); send_byte(8'h00);
            send_byte(8'hC0); send_byte(8'hA8); send_byte(8'h07); send_byte(8'h01);
            send_byte(8'hC0); send_byte(8'hA8); send_byte(8'h07); send_byte(8'h02);
            send_byte(8'h04); send_byte(8'hD2); send_byte(8'h0F); send_byte(8'hA0);
            send_byte(8'h00); send_byte(8'h16); send_byte(8'h00); send_byte(8'h00);
            send_byte(8'h47); send_byte(8'h50); send_byte(`GFX_TRANSPORT_VERSION); send_byte(8'h02);
            send_byte(8'h00); send_byte(8'h00); send_byte(8'h00); send_byte(8'h2A);
            send_byte(8'h00); send_byte(8'h01); send_byte(8'h00); send_byte(8'h02);
            send_byte(8'hCA); send_byte(8'hFE);
            end_frame();
        end
    endtask

    task begin_frame;
        integer index;
        begin
            for (index = 0; index < 7; index = index + 1)
                send_byte(8'h55);
            send_byte(8'hD5);
        end
    endtask

    task end_frame;
        begin
            @(negedge rx_clk);
            rx_dv = 1'b0;
            rx_data = '0;
            repeat (3) @(posedge rx_clk);
        end
    endtask

    task send_udp_frame;
        begin
            begin_frame();
            send_byte(8'h02); send_byte(8'h00); send_byte(8'h00);
            send_byte(8'h00); send_byte(8'h00); send_byte(8'h01);
            send_byte(8'h10); send_byte(8'h20); send_byte(8'h30);
            send_byte(8'h40); send_byte(8'h50); send_byte(8'h60);
            send_byte(8'h08); send_byte(8'h00);
            send_byte(8'h45); send_byte(8'h00); send_byte(8'h00); send_byte(8'h2C);
            send_byte(8'h00); send_byte(8'h01); send_byte(8'h00); send_byte(8'h00);
            send_byte(8'h40); send_byte(8'h11); send_byte(8'h00); send_byte(8'h00);
            send_byte(8'hC0); send_byte(8'hA8); send_byte(8'h07); send_byte(8'h01);
            send_byte(8'hC0); send_byte(8'hA8); send_byte(8'h07); send_byte(8'h02);
            send_byte(8'h04); send_byte(8'hD2); send_byte(8'h0F); send_byte(8'hA0);
            send_byte(8'h00); send_byte(8'h18); send_byte(8'h00); send_byte(8'h00);
            send_byte(8'h47); send_byte(8'h50); send_byte(`GFX_TRANSPORT_VERSION); send_byte(8'h03);
            send_byte(8'h00); send_byte(8'h00); send_byte(8'h00); send_byte(8'h2A);
            send_byte(8'h00); send_byte(8'h00); send_byte(8'h00); send_byte(8'h04);
            send_byte(8'hDE); send_byte(8'hAD); send_byte(8'hBE); send_byte(8'hEF);
            end_frame();
        end
    endtask

    task send_arp_request;
        integer index;
        begin
            begin_frame();
            for (index = 0; index < 6; index = index + 1)
                send_byte(8'hFF);
            send_byte(8'h10); send_byte(8'h20); send_byte(8'h30);
            send_byte(8'h40); send_byte(8'h50); send_byte(8'h60);
            send_byte(8'h08); send_byte(8'h06);
            send_byte(8'h00); send_byte(8'h01); send_byte(8'h08); send_byte(8'h00);
            send_byte(8'h06); send_byte(8'h04); send_byte(8'h00); send_byte(8'h01);
            send_byte(8'h10); send_byte(8'h20); send_byte(8'h30);
            send_byte(8'h40); send_byte(8'h50); send_byte(8'h60);
            send_byte(8'hC0); send_byte(8'hA8); send_byte(8'h07); send_byte(8'h01);
            for (index = 0; index < 6; index = index + 1)
                send_byte(8'h00);
            send_byte(8'hC0); send_byte(8'hA8); send_byte(8'h07); send_byte(8'h02);
            end_frame();
        end
    endtask

    initial begin
        repeat (3) @(posedge rx_clk);
        reset = 1'b0;
        send_udp_frame();
        if (payload_count != 4)
            $fatal(1, "expected four UDP payload bytes, got %0d", payload_count);
        if (captured_payload[0] != 8'hDE || captured_payload[1] != 8'hAD ||
            captured_payload[2] != 8'hBE || captured_payload[3] != 8'hEF)
            $fatal(1, "UDP payload bytes were not preserved");
        if (packet_count != 1)
            $fatal(1, "expected one accepted UDP packet");
        if (status_count != 1 || packet_frame_id != 32'h0000002A ||
            packet_sequence != 16'd0 || packet_status_flags != 32'h00000001 ||
            packet_fifo_free != 12'd2048 || packet_sender_port != 16'd1234)
            $fatal(1, "packet acknowledgement fields were decoded incorrectly");
        if (payload_overflow)
            $fatal(1, "unexpected payload overflow");

        send_udp_second_packet();
        if (payload_count != 6 || captured_payload[4] != 8'hCA ||
            captured_payload[5] != 8'hFE || packet_count != 2 || status_count != 2 ||
            packet_sequence != 16'd1 || packet_status_flags != 32'h00000001)
            $fatal(1, "sequenced packet was not accepted correctly");

        send_udp_second_packet();
        if (payload_count != 6 || packet_count != 2 || status_count != 3 ||
            packet_status_flags != 32'h00000003)
            $fatal(1, "duplicate packet was not acknowledged without replay");

        send_arp_request();
        if (arp_count != 1)
            $fatal(1, "expected one ARP request event");
        if (arp_sender_mac != 48'h102030405060 || arp_sender_ip != 32'hC0A80701)
            $fatal(1, "ARP sender address was decoded incorrectly");

        $display("mii_udp_receiver_tb PASS");
        $finish;
    end

endmodule
