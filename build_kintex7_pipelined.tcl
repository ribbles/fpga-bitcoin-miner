# Vivado non-project build for the independent fully pipelined miner.
source "./constr/build.tlc"

set part_device "xc7k325tffg676-2"
# Kintex-7 pipelined profile:
# - SRL extraction is disabled in sha256_compress_pipeline.sv to avoid
#   LUT-as-Memory over-utilization (UTLZ-1) seen in earlier builds.
# - That shifts storage into FFs, so place_design may report Place 30-770
#   about packing up to 8 FFs per slice. This is acceptable if placement,
#   routing, and timing still complete.
set input_clk_freq 50000000
set clk_freq 200000000
set cores 1
set output_dir "./build_vivado"


file mkdir $output_dir
puts "Starting pipelined compilation for device: $part_device"
puts "Generics -> CLK_FREQ: $clk_freq CORES: $cores"

read_verilog -sv [glob ./src/*.sv]
read_xdc "./constr/kintex7.xdc"

synth_design -top top_kintex7_pipelined \
             -part $part_device \
             -generic [list CLK_FREQ=$clk_freq INPUT_CLK_FREQ=$input_clk_freq CORES=$cores]

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
