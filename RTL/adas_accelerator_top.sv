// ============================================================================
// Module Top : adas_accelerator_top.sv
// Description : Accelerateur Hardware ADAS (AEB / Evitement)
// Architecture : 4 -> 8 -> 16 -> 16 -> 2 avec Double Buffering Ping-Pong
// Surete Fonctionnelle : ISO 26262 Timing Monitor (Hard Real-Time WCET)
// ============================================================================

module adas_accelerator_top (
    input  logic        clk,
    input  logic        rst_n,
    
    input  logic        start_inference,
    input  logic [31:0] sensor_data_in,
    input  logic        sensor_valid,
    
    output logic signed [31:0] final_predictions [0:1],
    output logic               final_valid
);

    // ========================================================================
    // 1. GESTION DES CAPTEURS & ENTREES PHYSIQUES (RAW SENSORS)
    // ========================================================================
    logic signed [31:0] sensor_raw_reg [0:3];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sensor_raw_reg[0] <= 32'sd0;
            sensor_raw_reg[1] <= 32'sd0;
            sensor_raw_reg[2] <= 32'sd0;
            sensor_raw_reg[3] <= 32'sd0;
        end else if (sensor_valid) begin
            sensor_raw_reg[0] <= {24'd0, sensor_data_in[31:24]};
            sensor_raw_reg[1] <= {24'd0, sensor_data_in[23:16]};
            sensor_raw_reg[2] <= {{24{sensor_data_in[15]}}, sensor_data_in[15:8]};
            sensor_raw_reg[3] <= {{24{sensor_data_in[7]}}, sensor_data_in[7:0]};
        end
    end

    // ========================================================================
    // 2. SIGNAUX INTERNES : MEMOIRE, CONTROLE & SURETE
    // ========================================================================
    logic signed [7:0] wgt_bank_wire [0:272];
    logic bank_sel_wire;

    logic start_l1_w, start_l2_w, start_l3_w, start_l4_w;
    logic done_l1_w, done_l2_w, done_l3_w, done_l4_w;

    logic dma_start_w, dma_done_w, dma_target_w;
    logic [8:0] dma_src_w, dma_len_w;
    
    logic [8:0] dma_src_reg;
    logic [8:0] dma_len_reg;
    logic       dma_target_reg;
    logic [8:0] dma_cnt;
    logic       dma_busy;

    logic [8:0] rom_addr;
    logic [8:0] last_addr;
    logic signed [7:0] rom_data;

    logic        mem_wr_en;
    logic        mem_wr_bank;
    logic [8:0]  mem_wr_addr;
    logic signed [7:0] mem_wr_data;

    logic ready_A_wire;
    logic ready_B_wire;
    logic [31:0] stall_cnt;
    logic [31:0] latency_out;
    logic wcet_error;

    // Signaux de monitoring pour run_sim.do
    logic compute_enable_wire;
    logic buffer_ready_wire;

    assign compute_enable_wire = start_l1_w | start_l2_w | start_l3_w | start_l4_w;
    assign buffer_ready_wire   = bank_sel_wire ? ready_B_wire : ready_A_wire;

    // ========================================================================
    // 3. LOGIQUE D'ADRESSAGE DIRECT & INTERFACE DMA
    // ========================================================================
    assign mem_wr_en   = dma_busy;
    assign mem_wr_bank = dma_target_reg;
    assign mem_wr_addr = dma_cnt;
    assign mem_wr_data = rom_data;
    
    assign rom_addr    = dma_busy ? (dma_src_reg + dma_cnt) : last_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_busy       <= 1'b0;
            dma_cnt        <= 9'd0;
            dma_done_w     <= 1'b0;
            dma_src_reg    <= 9'd0;
            dma_len_reg    <= 9'd0;
            dma_target_reg <= 1'b0;
            last_addr      <= 9'd0;
        end else begin
            dma_done_w <= 1'b0;

            if (dma_start_w && !dma_busy) begin
                dma_busy       <= 1'b1;
                dma_cnt        <= 9'd0;
                dma_src_reg    <= dma_src_w;
                dma_len_reg    <= dma_len_w;
                dma_target_reg <= dma_target_w;
                last_addr      <= dma_src_w;
            end else if (dma_busy) begin
                last_addr <= dma_src_reg + dma_cnt;

                if (dma_cnt == dma_len_reg - 1) begin
                    dma_busy   <= 1'b0;
                    dma_cnt    <= 9'd0;
                    dma_done_w <= 1'b1;
                end else begin
                    dma_cnt <= dma_cnt + 1'b1;
                end
            end
        end
    end

    // ========================================================================
    // 4. INSTANCIATION DES MODULES DU SYSTEME
    // ========================================================================

    weights_rom my_rom (
        .clk(clk),
        .addr(rom_addr),
        .data_out(rom_data)
    );

    mem_controller mem_inst (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(mem_wr_en),
        .wr_bank(mem_wr_bank),
        .wr_addr(mem_wr_addr),
        .wr_data(mem_wr_data),
        .bank_select(bank_sel_wire),
        .dma_done(dma_done_w),
        .ready_A(ready_A_wire),
        .ready_B(ready_B_wire),
        .rd_weights(wgt_bank_wire)
    );

    compute_core core_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start_l1(start_l1_w),
        .start_l2(start_l2_w),
        .start_l3(start_l3_w),
        .start_l4(start_l4_w),
        .sensor_raw(sensor_raw_reg),
        .wgt_bank(wgt_bank_wire[0:271]),
        .done_l1(done_l1_w),
        .done_l2(done_l2_w),
        .done_l3(done_l3_w),
        .done_l4(done_l4_w),
        .final_predictions(final_predictions),
        .final_valid(final_valid)
    );

    fsm_controller fsm_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start_inference(start_inference),
        .dma_start(dma_start_w),
        .dma_src_addr(dma_src_w),
        .dma_length(dma_len_w),
        .dma_target_bank(dma_target_w),
        .dma_done(dma_done_w),
        .start_l1(start_l1_w),
        .start_l2(start_l2_w),
        .start_l3(start_l3_w),
        .start_l4(start_l4_w),
        .done_l1(done_l1_w),
        .done_l2(done_l2_w),
        .done_l3(done_l3_w),
        .done_l4(done_l4_w),
        .bank_select(bank_sel_wire),
        .stall_cycles(stall_cnt)
    );

    timing_monitor #(
        .MAX_LATENCY(1000)
    ) monitor_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start_inference(start_inference),
        .final_valid(final_valid),
        .latency_cycles(latency_out),
        .wcet_violation(wcet_error)
    );

endmodule