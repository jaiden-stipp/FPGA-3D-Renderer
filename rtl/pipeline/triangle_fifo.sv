// Ready/valid FIFO for signed Q8.8 3D triangle commands.

`include "renderer_types.svh"

module triangle_fifo #(
    parameter int DEPTH = 64
) (
    input  logic        clk,
    input  logic        reset,

    input  triangle_3d_t in_data,
    input  logic         in_valid,
    output logic         in_ready,

    output triangle_3d_t out_data,
    output logic         out_valid,
    input  logic         out_ready,

    output logic         empty,
    output logic         full
);

    localparam int PTR_BITS = (DEPTH <= 2) ? 1 : $clog2(DEPTH);

    logic [35:0] storage0 [0:DEPTH-1];
    logic [35:0] storage1 [0:DEPTH-1];
    logic [35:0] storage2 [0:DEPTH-1];
    logic [35:0] storage3 [0:DEPTH-1];
    logic [7:0] storage4 [0:DEPTH-1];
    logic [PTR_BITS-1:0] read_pointer;
    logic [PTR_BITS-1:0] write_pointer;
    logic [PTR_BITS:0] item_count;

    logic push;
    logic pop;

    assign empty = (item_count == 0);
    assign full = (item_count == DEPTH);

    assign in_ready = !full;
    assign out_valid = !empty;
    always_comb begin
        out_data = '0;
        if (!empty) begin
            out_data = {storage4[read_pointer], storage3[read_pointer],
                        storage2[read_pointer], storage1[read_pointer],
                        storage0[read_pointer]};
        end
    end

    assign push = in_valid && in_ready;
    assign pop = out_valid && out_ready;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            read_pointer  <= '0;
            write_pointer <= '0;
            item_count    <= '0;
        end else begin
            if (push) begin
                storage0[write_pointer] <= in_data[35:0];
                storage1[write_pointer] <= in_data[71:36];
                storage2[write_pointer] <= in_data[107:72];
                storage3[write_pointer] <= in_data[143:108];
                storage4[write_pointer] <= in_data[151:144];
                if (write_pointer == DEPTH - 1)
                    write_pointer <= '0;
                else
                    write_pointer <= write_pointer + 1'b1;
            end

            if (pop) begin
                if (read_pointer == DEPTH - 1)
                    read_pointer <= '0;
                else
                    read_pointer <= read_pointer + 1'b1;
            end

            case ({push, pop})
                2'b10: item_count <= item_count + 1'b1;
                2'b01: item_count <= item_count - 1'b1;
                default: item_count <= item_count;
            endcase
        end
    end

endmodule
