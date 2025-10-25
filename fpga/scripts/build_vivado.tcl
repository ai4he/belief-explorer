# Vivado Build Script for PYNQ Z2 Multi-Base HFT Optimizer
# This script automates the FPGA build process for Xilinx Vivado

# Set project name and directory
set proj_name "multi_base_optimizer"
set proj_dir "./vivado_project"
set rtl_dir "../verilog"
set constraints_dir "../constraints"
set output_dir "./output"

# PYNQ Z2 board part
set board_part "tul.com.tw:pynq-z2:part0:1.0"
set fpga_part "xc7z020clg400-1"

puts "======================================================================"
puts "Multi-Base HFT Optimizer - Vivado Build Script"
puts "Target: PYNQ Z2 (Zynq-7000)"
puts "======================================================================"

# Create project
puts "\n[INFO] Creating Vivado project: $proj_name"
create_project $proj_name $proj_dir -part $fpga_part -force

# Set board part
set_property board_part $board_part [current_project]

# Add RTL sources
puts "\n[INFO] Adding RTL sources..."
add_files [glob $rtl_dir/*.v]
set_property top pynq_z2_top [current_fileset]

# Add constraints
puts "\n[INFO] Adding constraint files..."
add_files -fileset constrs_1 [glob $constraints_dir/*.xdc]

# Create block design for Zynq PS
puts "\n[INFO] Creating block design..."
create_bd_design "system"

# Add Zynq Processing System
puts "[INFO] Adding Zynq Processing System IP..."
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

# Configure Zynq PS
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
] [get_bd_cells processing_system7_0]

# Apply Zynq presets for PYNQ-Z2
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
    [get_bd_cells processing_system7_0]

# Add AXI Interconnect
puts "[INFO] Adding AXI Interconnect..."
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property -dict [list CONFIG.NUM_MI {1}] [get_bd_cells axi_interconnect_0]

# Add multi-base optimizer as custom IP
puts "[INFO] Adding Multi-Base Optimizer RTL module..."
create_bd_cell -type module -reference pynq_z2_top optimizer_0

# Connect AXI interfaces
puts "[INFO] Connecting AXI interfaces..."
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
    [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] \
    [get_bd_intf_pins optimizer_0/s_axi]

# Connect clocks
puts "[INFO] Connecting clocks and resets..."
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins axi_interconnect_0/ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins axi_interconnect_0/S00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins axi_interconnect_0/M00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
    [get_bd_pins optimizer_0/clk]

# Connect resets
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins optimizer_0/rst_n]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins axi_interconnect_0/ARESETN]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins axi_interconnect_0/S00_ARESETN]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
    [get_bd_pins axi_interconnect_0/M00_ARESETN]

# Assign address
puts "[INFO] Assigning AXI address..."
assign_bd_address [get_bd_addr_segs {optimizer_0/s_axi/reg0 }]
set_property offset 0x40000000 [get_bd_addr_segs {processing_system7_0/Data/SEG_optimizer_0_reg0}]
set_property range 64K [get_bd_addr_segs {processing_system7_0/Data/SEG_optimizer_0_reg0}]

# Make LED pins external
puts "[INFO] Making LED pins external..."
create_bd_port -dir O -from 3 -to 0 led
connect_bd_net [get_bd_pins optimizer_0/led] [get_bd_ports led]

# Validate and save block design
puts "[INFO] Validating block design..."
validate_bd_design
save_bd_design

# Generate block design wrapper
puts "[INFO] Generating HDL wrapper..."
make_wrapper -files [get_files $proj_dir/$proj_name.srcs/sources_1/bd/system/system.bd] -top
add_files -norecurse $proj_dir/$proj_name.srcs/sources_1/bd/system/hdl/system_wrapper.v
set_property top system_wrapper [current_fileset]

# Update compile order
update_compile_order -fileset sources_1

# Synthesis
puts "\n[INFO] Running synthesis..."
puts "======================================================================"
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "[INFO] Synthesis complete"

# Check synthesis results
open_run synth_1
report_utilization -file $output_dir/utilization_synth.txt
report_timing_summary -file $output_dir/timing_synth.txt

# Implementation
puts "\n[INFO] Running implementation..."
puts "======================================================================"
launch_runs impl_1 -jobs 4
wait_on_run impl_1
puts "[INFO] Implementation complete"

# Check implementation results
open_run impl_1
report_utilization -hierarchical -file $output_dir/utilization_impl.txt
report_timing_summary -file $output_dir/timing_impl.txt
report_power -file $output_dir/power_impl.txt

# Generate bitstream
puts "\n[INFO] Generating bitstream..."
puts "======================================================================"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Copy bitstream to output directory
puts "\n[INFO] Copying bitstream to output directory..."
file mkdir $output_dir
file copy -force $proj_dir/$proj_name.runs/impl_1/system_wrapper.bit \
    $output_dir/multi_base_optimizer.bit

# Generate hardware handoff file for PYNQ
puts "[INFO] Generating hardware handoff file..."
write_hwdef -force -file $output_dir/multi_base_optimizer.hwh

puts "\n======================================================================"
puts "Build Complete!"
puts "======================================================================"
puts "Bitstream: $output_dir/multi_base_optimizer.bit"
puts "HWH file: $output_dir/multi_base_optimizer.hwh"
puts "======================================================================"

# Print resource utilization summary
set util_report [report_utilization -return_string]
puts "\nResource Utilization Summary:"
puts $util_report

# Print timing summary
set timing_report [report_timing_summary -return_string -max_paths 10]
puts "\nTiming Summary:"
puts $timing_report

# Close project
puts "\n[INFO] Build script complete"
# close_project
