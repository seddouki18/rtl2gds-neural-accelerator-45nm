vcom -93 mem_controller.vhd
vcom -93 spm_activations.vhd

# Compilation SystemVerilog
vlog -sv adder_tree_4.sv
vlog -sv adder_tree_8.sv
vlog -sv adder_tree_16.sv
vlog -sv weights_rom.sv
vlog -sv compute_core.sv
vlog -sv fsm_controller.sv
vlog -sv timing_monitor.sv
vlog -sv adas_accelerator_top.sv
vlog -sv tb_adas_top.sv

# Lancement de la Simulation
vsim -voptargs=+acc work.tb_adas_top

# ==============================================================
# 2. CONFIGURATION DES TRACÉS (WAVES)
# ==============================================================

# --- SECTION 1 : HANDSHAKE & CONTROL ---
add wave -divider "=== 1. HANDSHAKE & CONTROL ==="
add wave -color cyan    /tb_adas_top/clk
add wave -color white   /tb_adas_top/rst_n
add wave -color yellow  /tb_adas_top/start_inference
add wave -color yellow  /tb_adas_top/sensor_valid
add wave -color yellow -radix hexadecimal /tb_adas_top/sensor_data_in
add wave -color magenta /tb_adas_top/dut/compute_enable_wire
add wave -color red     /tb_adas_top/dut/buffer_ready_wire
add wave -color green   /tb_adas_top/dut/final_valid

# --- SECTION 2 : DOUBLE BUFFERING (272B) & DMA STREAM ---
add wave -divider "=== 2. DOUBLE BUFFERING & DMA ==="
add wave -color orange  /tb_adas_top/dut/bank_sel_wire
add wave -color white   /tb_adas_top/dut/fsm_inst/state
add wave -color yellow  /tb_adas_top/dut/mem_wr_en
add wave -color yellow -radix unsigned    /tb_adas_top/dut/rom_addr
add wave -color magenta -radix unsigned   /tb_adas_top/dut/fsm_inst/stall_cycles
add wave -color cyan    /tb_adas_top/dut/mem_inst/ready_A
add wave -color pink    /tb_adas_top/dut/mem_inst/ready_B
add wave -color orange  /tb_adas_top/dut/dma_target_w
add wave -color red     /tb_adas_top/dut/dma_busy

# --- SECTION 3 : CONTENU DES BANQUES SRAM (272B) ---
add wave -divider "=== 3. CONTENU DES BANQUES SRAM ==="
add wave -color cyan -radix hexadecimal   /tb_adas_top/dut/mem_inst/ram_bank_A
add wave -color pink -radix hexadecimal   /tb_adas_top/dut/mem_inst/ram_bank_B

# --- SECTION 4 : PIPELINE 4 COUCHES (42 NEURONES) ---
add wave -divider "=== 4. PIPELINE 4 COUCHES ==="
add wave -color magenta /tb_adas_top/dut/done_l1_w
add wave -color cyan    /tb_adas_top/dut/done_l2_w
add wave -color green   /tb_adas_top/dut/done_l3_w
add wave -color white   /tb_adas_top/dut/done_l4_w
add wave -color green   /tb_adas_top/dut/final_valid

# --- SECTION 5 : SÛRETÉ ISO 26262 (WCET) ---
add wave -divider "=== 5. SÛRETÉ ISO 26262 ==="
add wave -color yellow -radix unsigned    /tb_adas_top/dut/monitor_inst/latency_cycles
add wave -color red                       /tb_adas_top/dut/monitor_inst/wcet_violation

# --- SECTION 6 : SORTIES ADAS (AEB / ÉVITEMENT) ---
add wave -divider "=== 6. SORTIES ADAS (AEB / ÉVITEMENT) ==="
add wave -color cyan   -radix decimal     {/tb_adas_top/final_predictions[0]}
add wave -color orange -radix decimal     {/tb_adas_top/final_predictions[1]}

Run -all