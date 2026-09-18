module weights_rom (
    input  logic              clk,
    input  logic [8:0]        addr,
    output logic signed [7:0] data_out
);
    logic signed [7:0] memory [0:489];

    initial begin
        $readmemh("weights.txt", memory);
    end

    assign data_out = memory[addr];
endmodule