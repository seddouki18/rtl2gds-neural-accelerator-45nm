# ####################################################################

#  Created by Encounter(R) RTL Compiler v12.10-s012_1 on Thu Sep 03 02:10:55 +0600 2026

# ####################################################################

set sdc_version 1.7

set_units -capacitance 1000.0fF
set_units -time 1000.0ps

# Set the current design
current_design adas_accelerator_top

create_clock -name "clk" -add -period 20.0 -waveform {0.0 10.0} [get_ports clk]
set_clock_gating_check -setup 0.0 
set_wire_load_mode "enclosed"
set_dont_use [get_lib_cells gpdk045bc/HOLDX1]
