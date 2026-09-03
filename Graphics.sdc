# DE2-115 50 MHz clock.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# The divider produces the 25 MHz VGA clock.
create_generated_clock -name pixel_clk \
    -source [get_ports {CLOCK_50}] \
    -divide_by 2 {graphics_pipeline:pipeline|vga_clock_div2:clock_divider|pixel_clk}

derive_clock_uncertainty
