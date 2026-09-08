`timescale 1ns/1ps

module mii_response_transmitter_tb;

    logic tx_clk = 1'b0;
    logic reset = 1'b1;
    logic arp_toggle = 1'b0;
    logic [47:0] arp_mac = '0;
    logic [31:0] arp_ip = '0;
    logic packet_toggle = 1'b0;
    logic [47:0] packet_mac = 48'h102030405060;
    logic [31:0] packet_ip = 32'hC0A80701;
    logic [15:0] packet_port = 16'd49152;
    logic [31:0] packet_frame_id = 32'h12345678;
    logic [15:0] packet_sequence = 16'h002A;
    logic [11:0] packet_fifo_free = 12'h5A5;
    logic [31:0] packet_flags = 32'h00000001;
    logic frame_toggle = 1'b0;
    logic [31:0] frame_id = 32'h12345678;
    logic [11:0] frame_fifo_free = 12'h700;
    logic [31:0] frame_flags = 32'h00000300;
    logic [3:0] tx_data;
    logic tx_en;
    logic tx_er;
    logic [7:0] captured [0:127];
    integer captured_count;

    always #20 tx_clk = ~tx_clk;

    mii_response_transmitter dut (
        .tx_clk(tx_clk),
        .reset(reset),
        .arp_toggle(arp_toggle),
        .arp_mac(arp_mac),
        .arp_ip(arp_ip),
        .packet_toggle(packet_toggle),
        .packet_mac(packet_mac),
        .packet_ip(packet_ip),
        .packet_port(packet_port),
        .packet_frame_id(packet_frame_id),
        .packet_sequence(packet_sequence),
        .packet_fifo_free(packet_fifo_free),
        .packet_flags(packet_flags),
        .frame_toggle(frame_toggle),
        .frame_id(frame_id),
        .frame_fifo_free(frame_fifo_free),
        .frame_flags(frame_flags),
        .tx_data(tx_data),
        .tx_en(tx_en),
        .tx_er(tx_er)
    );

    task capture_frame;
        logic [3:0] low_nibble;
        begin
            captured_count = 0;
            wait (tx_en);
            while (tx_en) begin
                @(negedge tx_clk);
                if (tx_en) begin
                    low_nibble = tx_data;
                    @(negedge tx_clk);
                    if (tx_en) begin
                        captured[captured_count] = {tx_data, low_nibble};
                        captured_count = captured_count + 1;
                    end
                end
            end
        end
    endtask

    task check_common_status(input logic [7:0] event_code);
        begin
            if (captured_count != 74)
                $fatal(1, "status response had %0d bytes instead of 74", captured_count);
            if (captured[8] != 8'h10 || captured[13] != 8'h60 ||
                captured[20] != 8'h08 || captured[21] != 8'h00)
                $fatal(1, "status Ethernet header is incorrect");
            if (captured[38] != 8'hC0 || captured[39] != 8'hA8 ||
                captured[40] != 8'h07 || captured[41] != 8'h01 ||
                captured[44] != 8'hC0 || captured[45] != 8'h00)
                $fatal(1, "status IP address or UDP destination port is incorrect");
            if (captured[50] != 8'h47 || captured[51] != 8'h53 ||
                captured[52] != 8'h01 || captured[53] != event_code ||
                captured[54] != 8'h12 || captured[55] != 8'h34 ||
                captured[56] != 8'h56 || captured[57] != 8'h78)
                $fatal(1, "status payload header is incorrect");
        end
    endtask

    initial begin
        repeat (3) @(posedge tx_clk);
        reset = 1'b0;
        @(negedge tx_clk);
        packet_toggle = 1'b1;
        capture_frame();
        check_common_status(8'h01);
        if (captured[58] != 8'h00 || captured[59] != 8'h2A ||
            captured[60] != 8'h05 || captured[61] != 8'hA5 ||
            captured[65] != 8'h01)
            $fatal(1, "packet acknowledgement fields are incorrect");

        wait (!tx_en);
        repeat (30) @(posedge tx_clk);
        frame_toggle = 1'b1;
        capture_frame();
        check_common_status(8'h02);
        if (captured[60] != 8'h07 || captured[61] != 8'h00 ||
            captured[64] != 8'h03 || captured[65] != 8'h00)
            $fatal(1, "frame completion fields are incorrect");
        if (tx_er)
            $fatal(1, "transmitter asserted TX error");

        $display("mii_response_transmitter_tb PASS");
        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "mii_response_transmitter_tb timed out");
    end

endmodule
