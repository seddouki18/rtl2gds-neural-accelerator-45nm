module timing_monitor #(
    parameter int MAX_LATENCY = 1000
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start_inference,
    input  logic        final_valid,
    output logic [31:0] latency_cycles,
    output logic        wcet_violation
);

    logic [31:0] counter;
    logic        is_counting;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter        <= '0;
            latency_cycles <= '0;
            is_counting    <= 1'b0;
            wcet_violation <= 1'b0;
        end else begin
            if (start_inference && final_valid) begin
                latency_cycles <= counter + 1;
                counter        <= 32'd1;
                is_counting    <= 1'b1;
                wcet_violation <= 1'b0;
            end else if (start_inference) begin
                counter        <= 32'd1;
                is_counting    <= 1'b1;
                wcet_violation <= 1'b0;
            end else if (final_valid && is_counting) begin
                latency_cycles <= counter;
                is_counting    <= 1'b0;
            end else if (is_counting) begin
                counter <= counter + 1;
                if (counter >= MAX_LATENCY) begin
                    wcet_violation <= 1'b1;
                end
            end
        end
    end

endmodule