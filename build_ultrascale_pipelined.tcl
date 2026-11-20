# Vivado non-project build for the independent fully pipelined miner.
source "./constr/build.tlc"

set part_device "xcku5p-ffvb676-1-i"
# Three cores route at 200 MHz, but the physical board failed mining under
# that switching load. 100 MHz is hardware-verified at approximately 300 MH/s.
set clk_freq 100000000
set cores 3
set output_dir "./build_vivado"

# Optional diagnostic/tuning overrides keep the normal target unchanged while
# allowing smaller or slower builds without editing this file.
if {[info exists ::env(PIPELINED_CLK_FREQ)]} {
    set clk_freq $::env(PIPELINED_CLK_FREQ)
}
if {[info exists ::env(PIPELINED_CORES)]} {
    set cores $::env(PIPELINED_CORES)
}

file mkdir $output_dir
puts "Starting pipelined compilation for device: $part_device"
puts "Generics -> CLK_FREQ: $clk_freq CORES: $cores"

read_verilog -sv [glob ./src/*.sv]
read_xdc "./constr/kintex-ultrascale.xdc"

synth_design -top top_ultrascale_pipelined \
             -part $part_device \
             -generic [list CLK_FREQ=$clk_freq INPUT_CLK_FREQ=700000000 CORES=$cores]

report_utilization -file "${output_dir}/utilization_synth.rpt"
report_utilization -hierarchical -file "${output_dir}/utilization_synth_hier.rpt"

opt_design
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore

source ./capture_floorplan.tcl
report_design_analysis -file "${output_dir}/design_analysis_report.rpt"
report_clocks -file "${output_dir}/post_route_clocks.txt"
report_timing_summary -file "${output_dir}/post_route_timing_summary.txt"
report_timing -max_paths 20 -file "${output_dir}/post_route_timing_paths.txt"
report_drc -file "${output_dir}/post_route_drc.txt"
write_bitstream -force "${output_dir}/pack.bit"

puts "Pipelined build complete"
exit
