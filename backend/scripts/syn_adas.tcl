# ==============================================================================
# SCRIPT DE SYNTHESE RTL — ADAS ACCELERATOR (GPDK045)
# ==============================================================================

# 1. Bibliotheque Standard 45nm
set_attribute lib_search_path { /home/buet/cadence/EDI/share/FoundationFlows/EXAMPLES/EDI/DESIGN/GPDK/LIBS/GPDK045/timing/ }
set_attribute library { slow.lib }

# 2. Lecture des fichiers VHDL
read_hdl -vhdl {
/home/buet/Desktop/adas/rtl/spm_activations.vhd
/home/buet/Desktop/adas/rtl/mem_controller.vhd
}

# 3. Lecture des fichiers SystemVerilog
read_hdl -sv {
/home/buet/Desktop/adas/rtl/adder_tree_4.sv
/home/buet/Desktop/adas/rtl/adder_tree_8.sv
/home/buet/Desktop/adas/rtl/adder_tree_16.sv
/home/buet/Desktop/adas/rtl/weights_rom.sv
/home/buet/Desktop/adas/rtl/fsm_controller.sv
/home/buet/Desktop/adas/rtl/compute_core.sv
/home/buet/Desktop/adas/rtl/timing_monitor.sv
/home/buet/Desktop/adas/rtl/adas_accelerator_top.sv
}

# 4. Elaboration du Top Module
elaborate adas_accelerator_top

# 5. Contraintes d'Horloge (50 MHz -> Periode = 20000 ps)
define_clock -name clk -period 20000 -design adas_accelerator_top [find / -port clk]

# 6. Synthese et Optimisation ASIC
synthesize -to_mapped -effort high

# 7. Sauvegarde du Gate-Level Netlist
write_hdl -mapped > /home/buet/Desktop/adas/synth/adas_top_synth.v
write_sdc > /home/buet/Desktop/adas/synth/adas_top_synth.sdc

# 8. Rapports de Performance
report area   > /home/buet/Desktop/adas/reports/report_area.rpt
report timing > /home/buet/Desktop/adas/reports/report_timing.rpt
report power  > /home/buet/Desktop/adas/reports/report_power.rpt

puts "======================================================="
puts "SYNTHESE VALIDEE : adas_top_synth.v EST GENERE"
puts "======================================================="
