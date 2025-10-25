# PYNQ Z2 Constraints File
# Multi-Base HFT Optimizer
# Xilinx Zynq-7000 XC7Z020-1CLG400C

## Clock Signal (100 MHz from Zynq PS)
# create_clock -period 10.000 -name clk [get_ports clk]

## LEDs (4 LEDs on PYNQ Z2)
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

## RGB LEDs (LD4 and LD5)
# LD4 RGB LED
#set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {rgb_led4[0]}]  ; # Red
#set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports {rgb_led4[1]}]  ; # Green
#set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports {rgb_led4[2]}]  ; # Blue

# LD5 RGB LED
#set_property -dict {PACKAGE_PIN G14 IOSTANDARD LVCMOS33} [get_ports {rgb_led5[0]}]  ; # Red
#set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports {rgb_led5[1]}]  ; # Green
#set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports {rgb_led5[2]}]  ; # Blue

## Buttons (BTN0-BTN3)
#set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports {btn[0]}]
#set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports {btn[1]}]
#set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33} [get_ports {btn[2]}]
#set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports {btn[3]}]

## Switches (SW0-SW1)
#set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
#set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]

## Timing Constraints
# Create clock constraint for 100 MHz system clock
# This will be provided by Zynq PS FCLK_CLK0
create_clock -period 10.000 -name sys_clk_pin [get_nets -hierarchical *processing_system7_0*FCLK_CLK0]

## Input/Output Delays
# AXI interface timing (adjust based on your requirements)
# set_input_delay -clock sys_clk_pin -max 2.000 [get_ports -filter { NAME =~  "*s_axi*" && DIRECTION == "IN" }]
# set_output_delay -clock sys_clk_pin -max 2.000 [get_ports -filter { NAME =~  "*s_axi*" && DIRECTION == "OUT" }]

## False Paths
# LED outputs are asynchronous, no timing requirements
set_false_path -to [get_ports {led[*]}]

## HFT Optimizer Specific Constraints
# High-performance timing constraints for low-latency trading

# Critical path constraints
# Ensure base converter meets sub-10-cycle requirement
set_max_delay -from [get_pins -hierarchical *base_converter*/data_in*] \
              -to [get_pins -hierarchical *base_converter*/data_out*] 10.000

# Optimizer core critical paths
set_max_delay -from [get_pins -hierarchical *optimizer_core*/bid_price*] \
              -to [get_pins -hierarchical *optimizer_core*/optimal_entry_price*] 50.000

# Multi-cycle paths for complex calculations
# Base conversion can take up to 4 cycles
set_multicycle_path -setup 4 -from [get_pins -hierarchical *base_converter*/working_reg*] \
                                -to [get_pins -hierarchical *base_converter*/data_out*]
set_multicycle_path -hold 3 -from [get_pins -hierarchical *base_converter*/working_reg*] \
                               -to [get_pins -hierarchical *base_converter*/data_out*]

# AXI register read/write timing
# Allow 2 cycles for register access
set_multicycle_path -setup 2 -from [get_pins -hierarchical *axi_rdata*] \
                                -to [get_pins -hierarchical *s_axi_rdata*]

## Resource Optimization
# Use DSP48 slices for multiplication
set_property use_dsp48 yes [get_cells -hierarchical *multiply*]

# Use block RAM for lookup tables
set_property ram_style block [get_cells -hierarchical *lut*]

## Power Optimization
# Enable intelligent clock gating
set_property CLOCK_GATING true [get_cells -hierarchical *]

## Placement Constraints
# Group critical path logic together for routing optimization
# create_pblock pblock_optimizer
# resize_pblock pblock_optimizer -add {SLICE_X0Y0:SLICE_X50Y50}
# add_cells_to_pblock pblock_optimizer [get_cells -hierarchical *optimizer_core*]

## High-Performance Settings
# Enable high-performance routing for critical nets
set_property HIGH_PRIORITY true [get_nets -hierarchical *base_converter*/data_out*]
set_property HIGH_PRIORITY true [get_nets -hierarchical *optimizer_core*/optimal_entry_price*]

## DRC Waivers (if needed)
# Waive timing DRC for LED outputs (non-critical)
# create_waiver -type DRC -id {TIMING-18} -objects [get_ports led*] -description "LEDs are non-critical outputs"

## Configuration Settings
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

## HFT Performance Targets
# Target: < 100ns total latency (10 clock cycles @ 100MHz)
# Strategy selection: 1-2 cycles
# Base conversion: 4-8 cycles
# Optimization calculation: 5-10 cycles
# Total budget: ~20 cycles = 200ns (with margin)

puts "PYNQ Z2 Constraints loaded successfully"
puts "Target Performance: < 200ns latency for HFT optimization"
puts "Clock Frequency: 100 MHz (10ns period)"
puts "Critical Path Budget: 10ns"
