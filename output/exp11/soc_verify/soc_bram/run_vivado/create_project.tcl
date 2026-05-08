set script_dir [file dirname [string map {\\ /} [info script]]]
set rtl_dir    [file join $script_dir .. rtl]
set tb_dir     [file join $script_dir .. testbench]
set mycpu_dir  [file join $script_dir .. .. .. myCPU]

create_project -force loongson [file join $script_dir project] -part xc7a200tfbg676-1

# Add conventional sources
set rtl_files [glob -nocomplain \
    [file join $rtl_dir *.v] \
    [file join $rtl_dir BRIDGE *.v] \
    [file join $rtl_dir CONFREG *.v]]
if {[llength $rtl_files] > 0} {
    add_files -scan_for_includes $rtl_files
}

# Add IPs
set ip_files [glob -nocomplain [file join $rtl_dir xilinx_ip * *.xci]]
if {[llength $ip_files] > 0} {
    add_files -quiet $ip_files
}

# Add simulation files
add_files -fileset sim_1 [file join $tb_dir sync_ram.v]
add_files -fileset sim_1 [file join $tb_dir mycpu_tb.v]

# Add myCPU
set mycpu_files [glob -nocomplain [file join $mycpu_dir *.v] [file join $mycpu_dir *.vh]]
if {[llength $mycpu_files] > 0} {
    add_files -quiet -scan_for_includes $mycpu_files
}

# Add constraints
add_files -fileset constrs_1 -quiet [file join $script_dir constraints]

set_property -name "top" -value "tb_top" -objects [get_filesets sim_1]
set_property -name "xsim.simulate.log_all_signals" -value "1" -objects [get_filesets sim_1]
