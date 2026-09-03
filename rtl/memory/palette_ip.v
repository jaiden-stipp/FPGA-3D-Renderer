// Intel Quartus altsyncram IP for a programmable 256-entry RGB888 palette.

module palette_256x24 (
    input  wire        clock_a,
    input wire [7:0] address_a,
    input  wire [23:0] data_a,
    input  wire        wren_a,

    input  wire        clock_b,
    input wire [7:0] address_b,
    input  wire        rden_b,
    output wire [23:0] q_b
);

    altsyncram #(
        .operation_mode("DUAL_PORT"),
        .width_a(24),
        .widthad_a(8),
        .numwords_a(256),
        .width_b(24),
        .widthad_b(8),
        .numwords_b(256),
        .address_reg_b("CLOCK1"),
        .rdcontrol_reg_b("CLOCK1"),
        .outdata_reg_b("UNREGISTERED"),
        .ram_block_type("M9K"),
        .intended_device_family("Cyclone IV E"),
        .init_file("rtl/memory/palette_default.mif"),
        .power_up_uninitialized("FALSE"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .lpm_type("altsyncram")
    ) palette_ram (
        .address_a(address_a),
        .address_b(address_b),
        .clock0(clock_a),
        .clock1(clock_b),
        .clocken0(1'b1),
        .clocken1(1'b1),
        .data_a(data_a),
        .rden_b(rden_b),
        .wren_a(wren_a),
        .q_b(q_b)
    );

endmodule
