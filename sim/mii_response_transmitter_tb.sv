`timescale 1ns/1ps
`include "renderer_types.svh"

module mii_response_transmitter_tb;

    logic tx_clk = 1'b0;
    logic reset = 1'b1;
    logic arp_valid = 1'b0;
    logic arp_ready;
    logic [47:0] arp_mac = '0;
    logic [31:0] arp_ip = '0;
    logic packet_valid = 1'b0;
    logic packet_ready;
    logic [47:0] packet_mac = 48'h102030405060;
    logic [31:0] packet_ip = 32'hC0A80701;
    logic [15:0] packet_port = 16'd49152;
    logic [31:0] packet_frame_id = 32'h12345678;
    logic [15:0] packet_sequence = 16'h002A;
    logic [11:0] packet_fifo_free = 12'h5A5;
    logic [31:0] packet_flags = 32'h00000001;
    logic frame_valid = 1'b0;
    logic frame_ready;
    logic [31:0] frame_id = 32'h12345678;
    logic [11:0] frame_fifo_free = 12'h700;
    logic [31:0] frame_flags = 32'h00000300;
    renderer_stats_t frame_statistics;
    logic [3:0] tx_data;
    logic tx_en;
    logic tx_er;
    logic [7:0] captured [0:127];
    integer captured_count;

    always #20 tx_clk = ~tx_clk;

    mii_response_transmitter dut (
        .tx_clk(tx_clk),
        .reset(reset),
        .arp_valid(arp_valid),
        .arp_ready(arp_ready),
        .arp_mac(arp_mac),
        .arp_ip(arp_ip),
        .packet_valid(packet_valid),
        .packet_ready(packet_ready),
        .packet_mac(packet_mac),
        .packet_ip(packet_ip),
        .packet_port(packet_port),
        .packet_frame_id(packet_frame_id),
        .packet_sequence(packet_sequence),
        .packet_fifo_free(packet_fifo_free),
        .packet_flags(packet_flags),
        .frame_valid(frame_valid),
        .frame_ready(frame_ready),
        .frame_id(frame_id),
        .frame_fifo_free(frame_fifo_free),
        .frame_flags(frame_flags),
        .frame_statistics(frame_statistics),
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
            if (captured_count != (event_code == 8'h02 ? 122 : 74))
                $fatal(1, "status response had the wrong byte count: %0d",
                       captured_count);
            if (captured[8] != 8'h10 || captured[13] != 8'h60 ||
                captured[20] != 8'h08 || captured[21] != 8'h00)
                $fatal(1, "status Ethernet header is incorrect");
            if (captured[38] != 8'hC0 || captured[39] != 8'hA8 ||
                captured[40] != 8'h07 || captured[41] != 8'h01 ||
                captured[44] != 8'hC0 || captured[45] != 8'h00)
                $fatal(1, "status IP address or UDP destination port is incorrect");
            if (captured[50] != 8'h47 || captured[51] != 8'h53 ||
                captured[52] != `GFX_STATUS_VERSION || captured[53] != event_code ||
                captured[54] != 8'h12 || captured[55] != 8'h34 ||
                captured[56] != 8'h56 || captured[57] != 8'h78)
                $fatal(1, "status payload header is incorrect");
        end
    endtask

    initial begin
        frame_statistics = '0;
        frame_statistics.triangles_submitted = 32'd1;
        frame_statistics.triangles_clipped = 32'd2;
        frame_statistics.triangles_culled = 32'd3;
        frame_statistics.bounding_box_pixels = 32'd4;
        frame_statistics.pixels_inside = 32'd5;
        frame_statistics.depth_rejected = 32'd6;
        frame_statistics.pixels_written = 32'd7;
        frame_statistics.geometry_cycles = 32'd8;
        frame_statistics.geometry_stall_cycles = 32'd9;
        frame_statistics.raster_cycles = 32'd10;
        frame_statistics.clear_cycles = 32'd11;
        frame_statistics.total_cycles = 32'd12;
        frame_statistics.swap_wait_cycles = 32'd13;
        repeat (3) @(posedge tx_clk);
        reset = 1'b0;
        @(negedge tx_clk);
        packet_valid = 1'b1;
        @(posedge tx_clk);
        #1;
        packet_valid = 1'b0;
        capture_frame();
        check_common_status(8'h01);
        if (captured[58] != 8'h00 || captured[59] != 8'h2A ||
            captured[60] != 8'h05 || captured[61] != 8'hA5 ||
            captured[65] != 8'h01)
            $fatal(1, "packet acknowledgement fields are incorrect");

        wait (!tx_en);
        repeat (30) @(posedge tx_clk);
        frame_valid = 1'b1;
        @(posedge tx_clk);
        #1;
        frame_valid = 1'b0;
        capture_frame();
        check_common_status(8'h02);
        if (captured[60] != 8'h07 || captured[61] != 8'h00 ||
            captured[64] != 8'h03 || captured[65] != 8'h00)
            $fatal(1, "frame completion fields are incorrect");
        if (captured[24] != 8'h00 || captured[25] != 8'h60 ||
            captured[46] != 8'h00 || captured[47] != 8'h4C ||
            captured[69] != 8'h01 || captured[73] != 8'h02 ||
            captured[77] != 8'h03 || captured[81] != 8'h04 ||
            captured[85] != 8'h05 || captured[89] != 8'h06 ||
            captured[93] != 8'h07 || captured[97] != 8'h08 ||
            captured[101] != 8'h09 || captured[105] != 8'h0A ||
            captured[109] != 8'h0B || captured[113] != 8'h0C ||
            captured[117] != 8'h0D)
            $fatal(1, "frame statistics fields are incorrect");
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
