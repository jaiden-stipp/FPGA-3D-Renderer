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

    // Separate field memories avoid a Quartus 18.1 packed-struct inference bug.
    logic signed [15:0] storage_x0 [0:DEPTH-1];
    logic signed [15:0] storage_y0 [0:DEPTH-1];
    logic signed [15:0] storage_z0 [0:DEPTH-1];
    logic signed [15:0] storage_x1 [0:DEPTH-1];
    logic signed [15:0] storage_y1 [0:DEPTH-1];
    logic signed [15:0] storage_z1 [0:DEPTH-1];
    logic signed [15:0] storage_x2 [0:DEPTH-1];
    logic signed [15:0] storage_y2 [0:DEPTH-1];
    logic signed [15:0] storage_z2 [0:DEPTH-1];
    logic [7:0] storage_color [0:DEPTH-1];
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
            out_data.x0 = storage_x0[read_pointer];
            out_data.y0 = storage_y0[read_pointer];
            out_data.z0 = storage_z0[read_pointer];
            out_data.x1 = storage_x1[read_pointer];
            out_data.y1 = storage_y1[read_pointer];
            out_data.z1 = storage_z1[read_pointer];
            out_data.x2 = storage_x2[read_pointer];
            out_data.y2 = storage_y2[read_pointer];
            out_data.z2 = storage_z2[read_pointer];
            out_data.color = storage_color[read_pointer];
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
                storage_x0[write_pointer] <= in_data.x0;
                storage_y0[write_pointer] <= in_data.y0;
                storage_z0[write_pointer] <= in_data.z0;
                storage_x1[write_pointer] <= in_data.x1;
                storage_y1[write_pointer] <= in_data.y1;
                storage_z1[write_pointer] <= in_data.z1;
                storage_x2[write_pointer] <= in_data.x2;
                storage_y2[write_pointer] <= in_data.y2;
                storage_z2[write_pointer] <= in_data.z2;
                storage_color[write_pointer] <= in_data.color;
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
