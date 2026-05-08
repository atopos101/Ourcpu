set script_dir [file dirname [string map {\\ /} [info script]]]
source [file join $script_dir create_project.tcl]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
exit
