module framebuffer_320x240_8bit (
    input wire clock_a,
    input wire [16:0] address_a,
    input wire [7:0] data_a,
    input wire wren_a,
    input wire clock_b,
    input wire [16:0] address_b,
    input wire rden_b,
    output wire [7:0] q_b
);

    altsyncram #(
        .operation_mode("DUAL_PORT"),
        .width_a(8),
        .widthad_a(17),
        .numwords_a(76800),
        .width_b(8),
        .widthad_b(17),
        .numwords_b(76800),
        .address_reg_b("CLOCK1"),
        .rdcontrol_reg_b("CLOCK1"),
        .outdata_reg_b("UNREGISTERED"),
        .ram_block_type("M9K"),
        .intended_device_family("Cyclone IV E"),
        .power_up_uninitialized("FALSE"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .lpm_type("altsyncram")
    ) framebuffer_ram (
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
