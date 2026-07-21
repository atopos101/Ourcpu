# Vivado 2023.2 RTL compile/elaboration check.
# Run from the RTL directory:
#   vivado -mode batch -source vivado_compile_check.tcl

set script_dir [file dirname [file normalize [info script]]]
cd $script_dir

set rtl_files [lsort [glob -nocomplain *.v]]
if {[llength $rtl_files] == 0} {
    error "No Verilog RTL files found in $script_dir"
}

read_verilog -sv $rtl_files
# -rtl stops after RTL elaboration.  It is the fast check needed to catch
# source, include, parameter and port-connection errors before implementation.
synth_design -rtl -top core_top -part xc7a100tcsg324-1
puts "Vivado RTL compile/elaboration completed successfully."
