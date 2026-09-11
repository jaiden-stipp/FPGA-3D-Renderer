`timescale 1ns/1ps

module async_fifo_tb;
    logic write_clk = 1'b0;
    logic read_clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] write_data = '0;
    logic write_valid = 1'b0;
    logic write_ready;
    logic [2:0] write_free;
    logic [31:0] read_data;
    logic read_valid;
    logic read_ready = 1'b0;
    integer expected = 0;

    always #3 write_clk = ~write_clk;
    always #5 read_clk = ~read_clk;

    async_fifo #(.WIDTH(32), .ADDRESS_WIDTH(2)) dut (
        .write_clk(write_clk),
        .write_reset(reset),
        .write_data(write_data),
        .write_valid(write_valid),
        .write_ready(write_ready),
        .write_free(write_free),
        .read_clk(read_clk),
        .read_reset(reset),
        .read_data(read_data),
        .read_valid(read_valid),
        .read_ready(read_ready)
    );

    always @(posedge read_clk) begin
        if (!reset && read_valid && read_ready) begin
            if (read_data != 32'hA5000000 + expected)
                $fatal(1, "asynchronous FIFO reordered entry %0d", expected);
            expected = expected + 1;
        end
    end

    initial begin
        repeat (3) @(posedge write_clk);
        reset = 1'b0;
        repeat (2) @(posedge write_clk);
        for (integer index = 0; index < 4; index = index + 1) begin
            @(negedge write_clk);
            write_data = 32'hA5000000 + index;
            write_valid = 1'b1;
            wait (write_ready);
            @(posedge write_clk);
        end
        @(negedge write_clk);
        write_valid = 1'b0;
        read_ready = 1'b1;
        wait (expected == 4);
        repeat (2) @(posedge read_clk);
        if (read_valid)
            $fatal(1, "asynchronous FIFO did not empty");
        $display("async_fifo_tb PASS: multi-bit entries crossed clocks in order");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "async_fifo_tb timed out");
    end
endmodule
