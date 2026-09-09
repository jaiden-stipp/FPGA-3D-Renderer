# DE2-115 50 MHz clock.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
create_clock -name ENET0_RX_CLK -period 40.000 [get_ports {ENET0_RX_CLK}]
create_clock -name ENET0_TX_CLK -period 40.000 [get_ports {ENET0_TX_CLK}]

derive_pll_clocks

set pixel_clock [get_clocks {*|clock_generator|*|clk[0]}]

set_clock_groups -asynchronous \
    -group [get_clocks {CLOCK_50}] \
    -group [get_clocks {*|clock_generator|*|clk[0]}] \
    -group [get_clocks {ENET0_RX_CLK}] \
    -group [get_clocks {ENET0_TX_CLK}]

set mii_receive_ports [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV ENET0_RX_ER}]
set_input_delay -clock ENET0_RX_CLK -max 28.000 $mii_receive_ports
set_input_delay -clock ENET0_RX_CLK -min 12.000 $mii_receive_ports

set mii_transmit_ports [get_ports {ENET0_TX_DATA[*] ENET0_TX_EN}]
set_output_delay -clock ENET0_TX_CLK -max 10.000 $mii_transmit_ports
set_output_delay -clock ENET0_TX_CLK -min 0.000 $mii_transmit_ports

set vga_data_ports [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_BLANK_N VGA_HS VGA_VS}]
set_output_delay -clock $pixel_clock -max 0.500 $vga_data_ports
set_output_delay -clock $pixel_clock -min -1.500 $vga_data_ports

set_false_path -from [get_ports {KEY[*] SW[*] ENET0_LINK100}]
set_false_path -to [get_ports {ENET0_RST_N LEDG[*] VGA_CLK}]

derive_clock_uncertainty
