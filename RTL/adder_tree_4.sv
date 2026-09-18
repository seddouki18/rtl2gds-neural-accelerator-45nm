module adder_tree_4 (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               enable,
    input  logic               apply_relu,
    input  logic signed [7:0]  act [0:3],
    input  logic signed [7:0]  wgt [0:3],
    input  logic signed [7:0]  bias,
    output logic signed [31:0] final_result,
    output logic               valid_out
);

    logic signed [15:0] mult [0:3];
    logic signed [31:0] add_lvl1_0, add_lvl1_1;
    logic signed [31:0] add_lvl2;
    logic valid_mult, valid_add1, valid_add2;

    logic signed [31:0] sum_with_bias;
    assign sum_with_bias = add_lvl1_0 + add_lvl1_1 + (32'($signed(bias)) <<<5 );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < 4; k++) mult[k] <= '0;
            add_lvl1_0 <= '0; add_lvl1_1 <= '0; add_lvl2 <= '0;
            valid_mult <= 1'b0; valid_add1 <= 1'b0; valid_add2 <= 1'b0;
        end else begin
            valid_mult <= enable;
            valid_add1 <= valid_mult;
            valid_add2 <= valid_add1;

            if (enable) begin
                for (int k = 0; k < 4; k++)
                    mult[k] <= $signed(act[k]) * $signed(wgt[k]);
            end

            add_lvl1_0 <= 32'(mult[0]) + 32'(mult[1]);
            add_lvl1_1 <= 32'(mult[2]) + 32'(mult[3]);

            if (apply_relu && sum_with_bias < 0)
                add_lvl2 <= '0;
            else
                add_lvl2 <= sum_with_bias;
        end
    end

    assign final_result = add_lvl2;
    assign valid_out    = valid_add2;
endmodule