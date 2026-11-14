# https://github.com/tommythorn/AliExpressXCKU5P

# ============================================================================
# Clocks
# ============================================================================
# clk_p: schematic SYS_CLK_P | package T25 | bank 65 | VCCO 1.2 V | DIFF_SSTL12 test
set_property -dict {PACKAGE_PIN T25 IOSTANDARD DIFF_SSTL12} [get_ports clk_p]
# clk_n: schematic SYS_CLK_N | package U25 | bank 65 | VCCO 1.2 V | DIFF_SSTL12 test
set_property -dict {PACKAGE_PIN U25 IOSTANDARD DIFF_SSTL12} [get_ports clk_n]
# Measured 700 MHz differential input (1.428571 ns period).
create_clock -name sys_clk -period 1.428571 [get_ports clk_p]


# uart_tx_pin: J2 pin 23 | schematic AE13 | package AE13 | bank 84 | VCCO 3.3 V | LVCMOS33
set_property PACKAGE_PIN AE13 [get_ports {uart_tx_pin}]
# uart_rx_pin: J2 pin 24 | schematic AE15 | package AE15 | bank 84 | VCCO 3.3 V | LVCMOS33
set_property PACKAGE_PIN AE15 [get_ports {uart_rx_pin}]

set_property IOSTANDARD LVCMOS33	[get_ports {uart_tx_pin uart_rx_pin}]
set_property PULLDOWN true			[get_ports {uart_tx_pin uart_rx_pin}]



# ============================================================================
# LEDs
# ============================================================================
# led[0]: LED V1, active low | package A9  | bank 86 | VCCO 3.3 V | J2 pin 86
# led[1]: LED V2, active low | package B10 | bank 86 | VCCO 3.3 V | J2 pin 82
# led[2]: LED V3, active low | package A10 | bank 86 | VCCO 3.3 V | J2 pin 84
# gpio[116]: J2 pin 81 | schematic A12 | package A12 | bank 87 | VCCO 3.3 V | LVCMOS33
# gpio[114]: J2 pin 79 | schematic B11 | package B11 | bank 86 | VCCO 3.3 V | LVCMOS33
set_property PACKAGE_PIN A9  [get_ports {led[0]}]
set_property PACKAGE_PIN B10 [get_ports {led[1]}]
set_property PACKAGE_PIN A10 [get_ports {led[2]}]
set_property PACKAGE_PIN A12 [get_ports {led[3]}]
set_property PACKAGE_PIN B11 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
set_property SLEW SLOW [get_ports {led[*]}]


# Supply rails from voltages.png:
#   VCCINT/VCCINT_IO/VCCBRAM = 0.85 V
#   VBATT/VCCAUX/VCCAUX_IO   = 1.8 V
#   VCCO bank 0              = 1.8 V (configuration bank)
#   VCCO banks 64/67         = 1.8 V
#   VCCO banks 65/66         = 1.2 V
#   VCCO banks 84/86/87      = 3.3 V
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
# set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
