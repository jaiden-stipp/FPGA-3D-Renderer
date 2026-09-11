module async_byte_fifo #(
    parameter int ADDRESS_WIDTH = 11
) (
    input logic write_clk,
    input logic write_reset,
    input logic [7:0] write_data,
    input logic write_valid,
    output logic write_ready,
    output logic [ADDRESS_WIDTH:0] write_free,
    input logic read_clk,
    input logic read_reset,
    output logic [7:0] read_data,
    output logic read_valid,
    input logic read_ready
);

    async_fifo #(
        .WIDTH(8),
        .ADDRESS_WIDTH(ADDRESS_WIDTH)
    ) fifo (
        .write_clk(write_clk),
        .write_reset(write_reset),
        .write_data(write_data),
        .write_valid(write_valid),
        .write_ready(write_ready),
        .write_free(write_free),
        .read_clk(read_clk),
        .read_reset(read_reset),
        .read_data(read_data),
        .read_valid(read_valid),
        .read_ready(read_ready)
    );

endmodule
