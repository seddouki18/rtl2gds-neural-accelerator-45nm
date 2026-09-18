module fsm_controller (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start_inference,
    
    output logic        dma_start,
    output logic [8:0]  dma_src_addr,
    output logic [8:0]  dma_length,
    output logic        dma_target_bank,
    input  logic        dma_done,
    
    output logic        start_l1,
    output logic        start_l2,
    output logic        start_l3,
    output logic        start_l4,
    input  logic        done_l1,
    input  logic        done_l2,
    input  logic        done_l3,
    input  logic        done_l4,
    
    output logic        bank_select,
    output logic [31:0] stall_cycles
);

    typedef enum logic [3:0] {
        S_BOOT_LOAD_L1   = 4'd0,
        S_BOOT_WAIT      = 4'd1,
        S_IDLE           = 4'd2,
        
        S_L1_START       = 4'd3,
        S_L1_WAIT_BOTH   = 4'd4,
        
        S_L2_START       = 4'd5,
        S_L2_WAIT_BOTH   = 4'd6,
        
        S_L3_START       = 4'd7,
        S_L3_WAIT_BOTH   = 4'd8,
        
        S_L4_START       = 4'd9,
        S_L4_WAIT_BOTH   = 4'd10
    } state_t;

    state_t state;
    logic l1_finished, l2_finished, l3_finished, l4_finished;
    logic dma_finished;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_BOOT_LOAD_L1;
            bank_select     <= 1'b0;
            dma_start       <= 1'b0;
            dma_src_addr    <= 9'd0;
            dma_length      <= 9'd40;
            dma_target_bank <= 1'b0;
            start_l1        <= 1'b0;
            start_l2        <= 1'b0;
            start_l3        <= 1'b0;
            start_l4        <= 1'b0;
            stall_cycles    <= '0;
            l1_finished     <= 1'b0;
            l2_finished     <= 1'b0;
            l3_finished     <= 1'b0;
            l4_finished     <= 1'b0;
            dma_finished    <= 1'b0;
        end else begin
            dma_start <= 1'b0;
            start_l1  <= 1'b0;
            start_l2  <= 1'b0;
            start_l3  <= 1'b0;
            start_l4  <= 1'b0;

            if (done_l1)  l1_finished  <= 1'b1;
            if (done_l2)  l2_finished  <= 1'b1;
            if (done_l3)  l3_finished  <= 1'b1;
            if (done_l4)  l4_finished  <= 1'b1;
            if (dma_done) dma_finished <= 1'b1;

            case (state)
                // PHASE 0 : BOOT L1 (40B dans Bank A : 0 -> 39)
                S_BOOT_LOAD_L1: begin
                    dma_src_addr    <= 9'd0;
                    dma_length      <= 9'd40;
                    dma_target_bank <= 1'b0;
                    dma_start       <= 1'b1;
                    state           <= S_BOOT_WAIT;
                end

                S_BOOT_WAIT: begin
                    if (dma_done || dma_finished) begin
                        dma_finished <= 1'b0;
                        state        <= S_IDLE;
                    end
                end

                S_IDLE: begin
                    if (start_inference) begin
                        state <= S_L1_START;
                    end
                end

                // ETAPE 1 : Calcule L1 & Charge L2 (143B dans Bank B : 40 -> 182)
                S_L1_START: begin
                    bank_select     <= 1'b0;
                    start_l1        <= 1'b1;
                    l1_finished     <= 1'b0;
                    
                    dma_src_addr    <= 9'd40;
                    dma_length      <= 9'd144;
                    dma_target_bank <= 1'b1;
                    dma_start       <= 1'b1;
                    dma_finished    <= 1'b0;
                    
                    state <= S_L1_WAIT_BOTH;
                end

                S_L1_WAIT_BOTH: begin
                    if (l1_finished && !dma_finished)
                        stall_cycles <= stall_cycles + 1'b1;

                    if ((done_l1 || l1_finished) && (dma_done || dma_finished)) begin
                        bank_select  <= 1'b1;
                        l1_finished  <= 1'b0;
                        dma_finished <= 1'b0;
                        state        <= S_L2_START;
                    end
                end

                // ETAPE 2 : Calcule L2 & Charge L3 (273B dans Bank A : 183 -> 455)
                S_L2_START: begin
                    bank_select     <= 1'b1;
                    start_l2        <= 1'b1;
                    l2_finished     <= 1'b0;
                    
                    dma_src_addr    <= 9'd184;
                    dma_length      <= 9'd272;
                    dma_target_bank <= 1'b0;
                    dma_start       <= 1'b1;
                    dma_finished    <= 1'b0;
                    
                    state <= S_L2_WAIT_BOTH;
                end

                S_L2_WAIT_BOTH: begin
                    if (l2_finished && !dma_finished)
                        stall_cycles <= stall_cycles + 1'b1;

                    if ((done_l2 || l2_finished) && (dma_done || dma_finished)) begin
                        bank_select  <= 1'b0;
                        l2_finished  <= 1'b0;
                        dma_finished <= 1'b0;
                        state        <= S_L3_START;
                    end
                end

                // ETAPE 3 : Calcule L3 & Charge L4 (35B dans Bank B : 456 -> 490)
                S_L3_START: begin
                    bank_select     <= 1'b0;
                    start_l3        <= 1'b1;
                    l3_finished     <= 1'b0;
                    
                    dma_src_addr    <= 9'd456;
                    dma_length      <= 9'd34;
                    dma_target_bank <= 1'b1;
                    dma_start       <= 1'b1;
                    dma_finished    <= 1'b0;
                    
                    state <= S_L3_WAIT_BOTH;
                end

                S_L3_WAIT_BOTH: begin
                    if (l3_finished && !dma_finished)
                        stall_cycles <= stall_cycles + 1'b1;

                    if ((done_l3 || l3_finished) && (dma_done || dma_finished)) begin
                        bank_select  <= 1'b1;
                        l3_finished  <= 1'b0;
                        dma_finished <= 1'b0;
                        state        <= S_L4_START;
                    end
                end

                // ETAPE 4 : Calcule L4 & Pre-charge L1 pour trame suivante
                S_L4_START: begin
                    bank_select     <= 1'b1;
                    start_l4        <= 1'b1;
                    l4_finished     <= 1'b0;
                    
                    dma_src_addr    <= 9'd0;
                    dma_length      <= 9'd40;
                    dma_target_bank <= 1'b0;
                    dma_start       <= 1'b1;
                    dma_finished    <= 1'b0;
                    
                    state <= S_L4_WAIT_BOTH;
                end

                S_L4_WAIT_BOTH: begin
                    if ((done_l4 || l4_finished) && (dma_done || dma_finished)) begin
                        bank_select  <= 1'b0;
                        l4_finished  <= 1'b0;
                        dma_finished <= 1'b0;
                        state        <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule