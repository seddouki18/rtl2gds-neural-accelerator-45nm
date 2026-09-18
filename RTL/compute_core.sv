// ============================================================================
// compute_core.sv - Version Match Exact PyTorch (Sorties Signées Directes)
// Architecture : 4 -> 8 -> 16 -> 16 -> 2
// ============================================================================

module compute_core (
    input  logic                clk,
    input  logic                rst_n,
    
    input  logic                start_l1,
    input  logic                start_l2,
    input  logic                start_l3,
    input  logic                start_l4,
    
    input  logic signed [31:0]  sensor_raw [0:3],
    input  logic signed [7:0]   wgt_bank [0:271],
    
    output logic                done_l1,
    output logic                done_l2,
    output logic                done_l3,
    output logic                done_l4,
    
    // Sorties Signées Directes : Score AEB & Score Evitement
    output logic signed [31:0]  final_predictions [0:1],
    output logic                final_valid
);

    // 1. Constantes de normalisation (Scale 32.0 -> [-32, +32])
    localparam signed [31:0] DIST_MIN   = 32'sd2;
    localparam signed [31:0] DIST_SCALE = 32'sd42799;

    localparam signed [31:0] SPEED_MIN   = 32'sd10;
    localparam signed [31:0] SPEED_SCALE = 32'sd38130;

    localparam signed [31:0] ANGLE_MIN   = -32'sd30;
    localparam signed [31:0] ANGLE_SCALE = 32'sd69905;

    localparam signed [31:0] REL_MIN     = -32'sd33;
    localparam signed [31:0] REL_SCALE   = 32'sd62915;

    // 2. Normalisation Hardware
    logic signed [7:0] act_in [0:3];
    logic signed [63:0] d_mult, s_mult, a_mult, r_mult;
    logic signed [31:0] d_val,  s_val,  a_val,  r_val;

    always_comb begin
        d_mult = (sensor_raw[0] - DIST_MIN) * DIST_SCALE;
        d_val  = (d_mult >>> 16) - 32'sd32;
        if (d_val > 32)        act_in[0] = 8'sd32;
        else if (d_val < -32)  act_in[0] = -8'sd32;
        else                   act_in[0] = d_val[7:0];

        s_mult = (sensor_raw[1] - SPEED_MIN) * SPEED_SCALE;
        s_val  = (s_mult >>> 16) - 32'sd32;
        if (s_val > 32)        act_in[1] = 8'sd32;
        else if (s_val < -32)  act_in[1] = -8'sd32;
        else                   act_in[1] = s_val[7:0];

        a_mult = (sensor_raw[2] - ANGLE_MIN) * ANGLE_SCALE;
        a_val  = (a_mult >>> 16) - 32'sd32;
        if (a_val > 32)        act_in[2] = 8'sd32;
        else if (a_val < -32)  act_in[2] = -8'sd32;
        else                   act_in[2] = a_val[7:0];

        r_mult = (sensor_raw[3] - REL_MIN) * REL_SCALE;
        r_val  = (r_mult >>> 16) - 32'sd32;
        if (r_val > 32)        act_in[3] = 8'sd32;
        else if (r_val < -32)  act_in[3] = -8'sd32;
        else                   act_in[3] = r_val[7:0];
    end

    // Registres d'activations
    logic signed [7:0] act_l1 [0:7];
    logic signed [7:0] act_l2 [0:15];
    logic signed [7:0] act_l3 [0:15];

    // 3. Couche 1 (4 -> 8)
    logic signed [31:0] l1_res [0:7];
    logic l1_vld [0:7];
    logic signed [31:0] l1_shifted [0:7];

    genvar i;
    generate
        for (i = 0; i < 8; i++) begin : gen_l1
            logic signed [7:0] wgt_tmp [0:3];
            assign wgt_tmp[0] = wgt_bank[i*4 + 0];
            assign wgt_tmp[1] = wgt_bank[i*4 + 1];
            assign wgt_tmp[2] = wgt_bank[i*4 + 2];
            assign wgt_tmp[3] = wgt_bank[i*4 + 3];

            adder_tree_4 neuron_l1 (
                .clk(clk), .rst_n(rst_n),
                .enable(start_l1), .apply_relu(1'b1),
                .act(act_in), .wgt(wgt_tmp),
                .bias(wgt_bank[32 + i]),
                .final_result(l1_res[i]), .valid_out(l1_vld[i])
            );

            assign l1_shifted[i] = l1_res[i] >>> 5;
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < 8; k++) act_l1[k] <= 8'sd0;
            done_l1 <= 1'b0;
        end else begin
            done_l1 <= l1_vld[0];
            if (l1_vld[0]) begin
                for (int k = 0; k < 8; k++) begin
                    if (l1_shifted[k] > 127)        act_l1[k] <= 8'sd127;
                    else if (l1_shifted[k] < -128)  act_l1[k] <= -8'sd128;
                    else                           act_l1[k] <= l1_shifted[k][7:0];
                end
            end
        end
    end

    // 4. Couche 2 (8 -> 16)
    logic signed [31:0] l2_res [0:15];
    logic l2_vld [0:15];
    logic signed [31:0] l2_shifted [0:15];

    generate
        for (i = 0; i < 16; i++) begin : gen_l2
            logic signed [7:0] wgt_tmp [0:7];
            for (genvar j = 0; j < 8; j++) 
                assign wgt_tmp[j] = wgt_bank[i*8 + j];

            adder_tree_8 neuron_l2 (
                .clk(clk), .rst_n(rst_n),
                .enable(start_l2), .apply_relu(1'b1),
                .act(act_l1), .wgt(wgt_tmp),
                .bias(wgt_bank[128 + i]),
                .final_result(l2_res[i]), .valid_out(l2_vld[i])
            );

            assign l2_shifted[i] = l2_res[i] >>> 5;
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < 16; k++) act_l2[k] <= 8'sd0;
            done_l2 <= 1'b0;
        end else begin
            done_l2 <= l2_vld[0];
            if (l2_vld[0]) begin
                for (int k = 0; k < 16; k++) begin
                    if (l2_shifted[k] > 127)        act_l2[k] <= 8'sd127;
                    else if (l2_shifted[k] < -128)  act_l2[k] <= -8'sd128;
                    else                           act_l2[k] <= l2_shifted[k][7:0];
                end
            end
        end
    end

    // 5. Couche 3 (16 -> 16)
    logic signed [31:0] l3_res [0:15];
    logic l3_vld [0:15];
    logic signed [31:0] l3_shifted [0:15];

    generate
        for (i = 0; i < 16; i++) begin : gen_l3
            logic signed [7:0] wgt_tmp [0:15];
            for (genvar j = 0; j < 16; j++) 
                assign wgt_tmp[j] = wgt_bank[i*16 + j];

            adder_tree_16 neuron_l3 (
                .clk(clk), .rst_n(rst_n),
                .enable(start_l3), .apply_relu(1'b1),
                .act(act_l2), .wgt(wgt_tmp),
                .bias(wgt_bank[256 + i]),
                .final_result(l3_res[i]), .valid_out(l3_vld[i])
            );

            assign l3_shifted[i] = l3_res[i] >>> 5;
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < 16; k++) act_l3[k] <= 8'sd0;
            done_l3 <= 1'b0;
        end else begin
            done_l3 <= l3_vld[0];
            if (l3_vld[0]) begin
                for (int k = 0; k < 16; k++) begin
                    if (l3_shifted[k] > 127)        act_l3[k] <= 8'sd127;
                    else if (l3_shifted[k] < -128)  act_l3[k] <= -8'sd128;
                    else                           act_l3[k] <= l3_shifted[k][7:0];
                end
            end
        end
    end

    // 6. Couche 4 (16 -> 2 Sorties)
    logic signed [31:0] l4_res [0:1];
    logic l4_vld [0:1];

    generate
        for (i = 0; i < 2; i++) begin : gen_l4
            logic signed [7:0] wgt_tmp [0:15];
            for (genvar j = 0; j < 16; j++) 
                assign wgt_tmp[j] = wgt_bank[i*16 + j];

            adder_tree_16 neuron_l4 (
                .clk(clk), .rst_n(rst_n),
                .enable(start_l4), .apply_relu(1'b0),
                .act(act_l3), .wgt(wgt_tmp),
                .bias(wgt_bank[32 + i]),
                .final_result(l4_res[i]), .valid_out(l4_vld[i])
            );
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) done_l4 <= 1'b0;
        else        done_l4 <= l4_vld[0];
    end

    // 7. Sorties Directes (Bit-Exact PyTorch)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            final_predictions[0] <= 32'sd0;
            final_predictions[1] <= 32'sd0;
            final_valid          <= 1'b0;
        end else begin
            final_valid <= l4_vld[0];
            if (l4_vld[0]) begin
                final_predictions[0] <= l4_res[0] >>> 5; // Score AEB Signé
                final_predictions[1] <= l4_res[1] >>> 5; // Score Evitement Signé
            end
        end
    end

endmodule