module async_byte_fifo #(
    parameter int ADDRESS_WIDTH = 11
) (
    input logic write_clk,
    input logic write_reset,
    input logic [7:0] write_data,
    input logic write_valid,
    output logic write_ready,
    input logic read_clk,
    input logic read_reset,
    output logic [7:0] read_data,
    output logic read_valid,
    input logic read_ready
);

    localparam int POINTER_WIDTH = ADDRESS_WIDTH + 1;

    logic [7:0] memory [0:(1 << ADDRESS_WIDTH) - 1];
    logic [POINTER_WIDTH-1:0] write_binary;
    logic [POINTER_WIDTH-1:0] write_gray;
    logic [POINTER_WIDTH-1:0] read_binary;
    logic [POINTER_WIDTH-1:0] read_gray;
    logic [POINTER_WIDTH-1:0] read_gray_write_sync1;
    logic [POINTER_WIDTH-1:0] read_gray_write_sync2;
    logic [POINTER_WIDTH-1:0] write_gray_read_sync1;
    logic [POINTER_WIDTH-1:0] write_gray_read_sync2;
    logic [POINTER_WIDTH-1:0] write_binary_next;
    logic [POINTER_WIDTH-1:0] write_gray_next;
    logic write_full;
    logic write_full_next;
    logic fifo_empty;

    function automatic logic [POINTER_WIDTH-1:0] binary_to_gray(
        input logic [POINTER_WIDTH-1:0] value
    );
        binary_to_gray = (value >> 1) ^ value;
    endfunction

    always_comb begin
        write_binary_next = write_binary + (write_valid && write_ready);
        write_gray_next = binary_to_gray(write_binary_next);
        write_full_next = write_gray_next == {
            ~read_gray_write_sync2[POINTER_WIDTH-1:POINTER_WIDTH-2],
            read_gray_write_sync2[POINTER_WIDTH-3:0]
        };
    end

    assign write_ready = !write_full;
    assign fifo_empty = read_gray == write_gray_read_sync2;

    always_ff @(posedge write_clk or posedge write_reset) begin
        if (write_reset) begin
            write_binary <= '0;
            write_gray <= '0;
            write_full <= 1'b0;
            read_gray_write_sync1 <= '0;
            read_gray_write_sync2 <= '0;
        end else begin
            read_gray_write_sync1 <= read_gray;
            read_gray_write_sync2 <= read_gray_write_sync1;
            write_full <= write_full_next;
            if (write_valid && write_ready) begin
                memory[write_binary[ADDRESS_WIDTH-1:0]] <= write_data;
                write_binary <= write_binary_next;
                write_gray <= write_gray_next;
            end
        end
    end

    always_ff @(posedge read_clk or posedge read_reset) begin
        if (read_reset) begin
            read_binary <= '0;
            read_gray <= '0;
            write_gray_read_sync1 <= '0;
            write_gray_read_sync2 <= '0;
            read_data <= '0;
            read_valid <= 1'b0;
        end else begin
            write_gray_read_sync1 <= write_gray;
            write_gray_read_sync2 <= write_gray_read_sync1;
            if (!read_valid || read_ready) begin
                if (!fifo_empty) begin
                    read_data <= memory[read_binary[ADDRESS_WIDTH-1:0]];
                    read_binary <= read_binary + 1'b1;
                    read_gray <= binary_to_gray(read_binary + 1'b1);
                    read_valid <= 1'b1;
                end else begin
                    read_valid <= 1'b0;
                end
            end
        end
    end

endmodule
