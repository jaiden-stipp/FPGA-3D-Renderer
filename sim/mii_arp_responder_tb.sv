`timescale 1ns/1ps

module mii_arp_responder_tb;

    logic tx_clk = 1'b0;
    logic reset = 1'b1;
    logic request_toggle = 1'b0;
    logic [47:0] request_mac = 48'h102030405060;
    logic [31:0] request_ip = 32'hC0A80701;
    logic [3:0] tx_data;
    logic tx_en;
    logic tx_er;
    logic previous_tx_en = 1'b0;
    logic low_nibble = 1'b1;
    logic [3:0] saved_low;
    logic [7:0] frame [0:71];
    integer byte_count = 0;

    always #20 tx_clk = ~tx_clk;

    mii_arp_responder dut (
        .tx_clk(tx_clk),
        .reset(reset),
        .request_toggle(request_toggle),
        .request_mac(request_mac),
        .request_ip(request_ip),
        .tx_data(tx_data),
        .tx_en(tx_en),
        .tx_er(tx_er)
    );

    always @(negedge tx_clk) begin
        if (tx_en) begin
            if (!previous_tx_en) begin
                low_nibble = 1'b1;
                byte_count = 0;
            end
            if (low_nibble) begin
                saved_low = tx_data;
                low_nibble = 1'b0;
            end else begin
                frame[byte_count] = {tx_data, saved_low};
                byte_count = byte_count + 1;
                low_nibble = 1'b1;
            end
        end
        previous_tx_en = tx_en;
    end

    initial begin
        repeat (3) @(posedge tx_clk);
        reset = 1'b0;
        @(negedge tx_clk);
        request_toggle = 1'b1;
        wait (tx_en);
        wait (!tx_en);
        @(negedge tx_clk);

        if (byte_count != 72)
            $fatal(1, "expected 72 transmitted bytes, got %0d", byte_count);
        if (frame[0] != 8'h55 || frame[6] != 8'h55 || frame[7] != 8'hD5)
            $fatal(1, "preamble or SFD is incorrect");
        if ({frame[8], frame[9], frame[10], frame[11], frame[12], frame[13]} !=
            48'h102030405060)
            $fatal(1, "destination MAC is incorrect");
        if ({frame[14], frame[15], frame[16], frame[17], frame[18], frame[19]} !=
            48'h020000000001)
            $fatal(1, "source MAC is incorrect");
        if (frame[20] != 8'h08 || frame[21] != 8'h06 ||
            frame[28] != 8'h00 || frame[29] != 8'h02)
            $fatal(1, "ARP reply header is incorrect");
        if ({frame[36], frame[37], frame[38], frame[39]} != 32'hC0A80702 ||
            {frame[46], frame[47], frame[48], frame[49]} != 32'hC0A80701)
            $fatal(1, "ARP addresses are incorrect");
        if (tx_er)
            $fatal(1, "TX_ER asserted unexpectedly");

        $display("mii_arp_responder_tb PASS");
        $finish;
    end

endmodule
