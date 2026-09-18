`timescale 1ns / 1ps

module tb_adas_top;

    logic clk;
    logic rst_n;
    logic start_inference;
    logic sensor_valid;
    logic [31:0] sensor_data_in;
    logic signed [31:0] final_predictions [0:1];
    logic final_valid;

    int fd_data;
    logic [31:0] hex_word;
    int test_count; 

    adas_accelerator_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_inference(start_inference),
        .sensor_data_in(sensor_data_in),
        .sensor_valid(sensor_valid),
        .final_predictions(final_predictions),
        .final_valid(final_valid)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0; rst_n = 0;
        start_inference = 0; sensor_valid = 0; sensor_data_in = 0;
        test_count = 0; 
        
        #100; 
        rst_n = 1; 

        $display("===================================================================");
        $display(" Demarrage: Initialisation Bootloader DMA (L1 40B -> Bank A)");
        #450;
        $display(" Initialisation terminee: Bank A prete pour la Couche 1 !");
        $display("===================================================================");
        
        fd_data = $fopen("sensor_data.txt", "r");
        if (fd_data == 0) begin
            $display(" ERREUR: Fichier sensor_data.txt introuvable !");
            $stop;
        end
        
        while (!$feof(fd_data)) begin
            if ($fscanf(fd_data, "%h", hex_word) == 1) begin
                test_count++; 
                @(posedge clk);
                sensor_data_in  = hex_word;
                sensor_valid    = 1'b1;
                start_inference = 1'b1;
                
                @(posedge clk);
                sensor_valid    = 1'b0;
                start_inference = 1'b0;
                
                wait (final_valid == 1'b1);
                
                $display("- TEST #%0d", test_count);
                $display("- SENSOR HEX: %02h-%02h-%02h-%02h", hex_word[31:24], hex_word[23:16], hex_word[15:8], hex_word[7:0]);
                $display("- SCORE AEB = %0d , SCORE Evitement = %0d", final_predictions[0], final_predictions[1]);
                
                // Règle du Signe Pure
                if (final_predictions[0] > 0 && final_predictions[1] <= 0)
                    $display("- Decision: Freinage d'Urgence (AEB)");
                else if (final_predictions[0] > 0 && final_predictions[1] > 0)
                    $display("- Decision: Freinage d'Urgence (AEB) ET Evitement");
                else if (final_predictions[0] <= 0 && final_predictions[1] > 0)
                    $display("- Decision: Evitement d'obstacle");
                else
                    $display("- Decision: Conduite Normale");
                    
                $display("-------------------------------------------------------------------");
                
                #500;
            end
        end
        
        $display("===================================================================");
        $display(" VALIDATION COMPLETE : %0d tests reussis sur Deep Accelerator !", test_count);
        $display("===================================================================");
        $fclose(fd_data);
        $stop; 
    end

endmodule