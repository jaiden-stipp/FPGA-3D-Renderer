`timescale 1ns/1ps

module async_byte_fifo_tb;

    logic write_clk = 1'b0;
    logic read_clk = 1'b0;
    logic write_reset = 1'b1;
    logic read_reset = 1'b1;
    logic [7:0] write_data = '0;
    logic write_valid = 1'b0;
    logic write_ready;
    logic [7:0] read_data;
    logic read_valid;
    logic read_ready = 1'b0;
    integer received = 0;

    always #20 write_clk = ~write_clk;
    always #10 read_clk = ~read_clk;

    async_byte_fifo #(
        .ADDRESS_WIDTH(4)
    ) dut (
        .write_clk(write_clk),
        .write_reset(write_reset),
        .write_data(write_data),
        .write_valid(write_valid),
        .write_ready(write_ready),
        .read_clk(read_clk),
        .read_reset(read_reset),
        .read_data(read_data),
        .read_valid(read_valid),
        .read_ready(read_ready)
    );

    always @(posedge read_clk) begin
        if (read_valid && read_ready) begin
            if (read_data != received[7:0])
                $fatal(1, "FIFO order error at byte %0d: got %0d", received, read_data);
            received = received + 1;
        end
    end

    initial begin
        repeat (3) @(posedge write_clk);
        write_reset = 1'b0;
        read_reset = 1'b0;
        read_ready = 1'b1;

        for (integer value = 0; value < 12; value = value + 1) begin
            @(negedge write_clk);
            write_data = value[7:0];
            write_valid = 1'b1;
            while (!write_ready)
                @(negedge write_clk);
        end
        @(negedge write_clk);
        write_valid = 1'b0;

        wait (received == 12);
        repeat (3) @(posedge read_clk);
        $display("async_byte_fifo_tb PASS");
        $finish;
    end

endmodule
