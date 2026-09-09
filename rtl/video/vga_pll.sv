module vga_pll (
    input  logic inclk0,
    input  logic areset,
    output logic c0,
    output logic locked
);

`ifdef ALTERA_RESERVED_QIS
    wire [4:0] pll_clocks;
    wire pll_locked;

    altpll altpll_component (
        .areset(areset),
        .inclk({1'b0, inclk0}),
        .clk(pll_clocks),
        .locked(pll_locked),
        .clkena(6'b111111),
        .extclkena(4'b1111),
        .fbin(1'b1),
        .pfdena(1'b1),
        .phasecounterselect(4'b1111),
        .phasestep(1'b1),
        .phaseupdown(1'b1),
        .pllena(1'b1),
        .scanaclr(1'b0),
        .scanclk(1'b0),
        .scanclkena(1'b1),
        .scandata(1'b0),
        .scanread(1'b0),
        .scanwrite(1'b0)
    );

    defparam
        altpll_component.bandwidth_type = "AUTO",
        altpll_component.clk0_divide_by = 288,
        altpll_component.clk0_duty_cycle = 50,
        altpll_component.clk0_multiply_by = 145,
        altpll_component.clk0_phase_shift = "0",
        altpll_component.compensate_clock = "CLK0",
        altpll_component.inclk0_input_frequency = 20000,
        altpll_component.intended_device_family = "Cyclone IV E",
        altpll_component.lpm_type = "altpll",
        altpll_component.operation_mode = "NORMAL",
        altpll_component.pll_type = "AUTO",
        altpll_component.port_areset = "PORT_USED",
        altpll_component.port_inclk0 = "PORT_USED",
        altpll_component.port_locked = "PORT_USED",
        altpll_component.width_clock = 5;

    assign c0 = pll_clocks[0];
    assign locked = pll_locked;
`else
    logic simulated_clock;
    logic [2:0] lock_count;

    always_ff @(posedge inclk0 or posedge areset) begin
        if (areset) begin
            simulated_clock <= 1'b0;
            lock_count <= '0;
            locked <= 1'b0;
        end else begin
            simulated_clock <= ~simulated_clock;
            if (!locked) begin
                if (lock_count == 3'd4)
                    locked <= 1'b1;
                else
                    lock_count <= lock_count + 1'b1;
            end
        end
    end

    assign c0 = simulated_clock;
`endif

endmodule
