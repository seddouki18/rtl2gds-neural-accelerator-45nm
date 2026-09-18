module adder_tree_8 (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               enable,
    input  logic               apply_relu,
    input  logic signed [7:0]  act [0:7],
    input  logic signed [7:0]  wgt [0:7],
    input  logic signed [7:0]  bias,
    output logic signed [31:0] final_result,
    output logic               valid_out
);

    logic signed [15:0] mult [0:7];
    logic signed [31:0] add_lvl1 [0:3];
    logic signed [31:0] add_lvl2_0, add_lvl2_1;
    logic signed [31:0] add_lvl3;
    logic valid_mult, valid_add1, valid_add2, valid_add3;

    logic signed [31:0] sum_with_bias;
    assign sum_with_bias = add_lvl2_0 + add_lvl2_1 + (32'($signed(bias)) <<<5 );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < 8; k++) mult[k] <= '0;
            for (int k = 0; k < 4; k++) add_lvl1[k] <= '0;
            add_lvl2_0 <= '0; add_lvl2_1 <= '0; add_lvl3 <= '0;
            valid_mult <= 1'b0; valid_add1 <= 1'b0; valid_add2 <= 1'b0; valid_add3 <= 1'b0;
        end else begin
            valid_mult <= enable;
            valid_add1 <= valid_mult;
            valid_add2 <= valid_add1;
            valid_add3 <= valid_add2;

            if (enable) begin
                for (int k = 0; k < 8; k++)
                    mult[k] <= $signed(act[k]) * $signed(wgt[k]);
            end

            for (int k = 0; k < 4; k++)
                add_lvl1[k] <= 32'(mult[2*k]) + 32'(mult[2*k+1]);

            add_lvl2_0 <= add_lvl1[0] + add_lvl1[1];
            add_lvl2_1 <= add_lvl1[2] + add_lvl1[3];

            if (apply_relu && sum_with_bias < 0)
                add_lvl3 <= '0;
            else
                add_lvl3 <= sum_with_bias;
        end
    end

    assign final_result = add_lvl3;
    assign valid_out    = valid_add3;
endmodule