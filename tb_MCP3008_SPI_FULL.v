`timescale 1ns/1ps

module tb_MCP3008_SPI_FULL();

    //--------------------------------------------------------------------------
    // Testbench Signal Declarations
    //--------------------------------------------------------------------------
    reg         clk     = 0;
    reg         rst     = 0;
    reg         start   = 0;
    reg   [2:0] channel;
    reg         MISO    = 0;

    wire        MOSI;
    wire        SCK;
    wire        CS;
    wire  [9:0] ADC_data;
    wire        data_valid;
    
    // The "Scoreboard" for our self-checking testbench
    integer error_count = 0;

    //--------------------------------------------------------------------------
    // DUT (Device Under Test) Instantiation
    //--------------------------------------------------------------------------
    MCP3008_SPI spi_inst (
        .clk(clk),
        .rst(rst),
        .start(start),
        .channel(channel),
        .MISO(MISO),
        .MOSI(MOSI),
        .SCK(SCK),
        .CS(CS),
        .ADC_data(ADC_data),
        .data_valid(data_valid)
    );

    // 1. Clock Generation: 50 MHz
    always #10 clk = ~clk;

    // 2. Behavioral Slave Model (Unchanged)
    reg [15:0] miso_shift_reg = 16'hD550;
    
    always @(negedge SCK or posedge rst) begin
        if (rst) begin
            miso_shift_reg <= 16'hD550;
            MISO           <= 0;
        end else if (CS == 0) begin
            MISO           <= miso_shift_reg[15];
            miso_shift_reg <= miso_shift_reg << 1;
        end else begin
            miso_shift_reg <= 16'hD550;
        end
    end

    //--------------------------------------------------------------------------
    // 3. Reusable Verification Task
    // This task encapsulates a standard transaction test.
    //--------------------------------------------------------------------------
    task check_transaction(input [2:0] i_channel, input [9:0] expected_data);
        begin
            $display("INFO: Starting transaction for channel %d...", i_channel);
            
            // Apply stimulus
            channel = i_channel;
            start   = 1;
            #20;
            start   = 0;
            
            // Wait for completion
            wait(data_valid == 1);
            #20;
            
            // Check the result
            if (ADC_data === expected_data) begin
                $display("INFO: SUCCESS! Channel %d data (%h) matches expected (%h).",
                         i_channel, ADC_data, expected_data);
            end else begin
                $display("ERROR: FAILURE! Channel %d data (%h) does not match expected (%h).",
                         i_channel, ADC_data, expected_data);
                error_count = error_count + 1; // Increment the scoreboard
            end
            
            // Wait for the FSM to be ready for the next transaction
            wait(spi_inst.state == spi_inst.S_IDLE);
            #100;
        end
    endtask

    //======================================================================
    // 4. Main Test Sequence
    //======================================================================
    initial begin
        // --- Phase 1: Setup and Reset ---
        rst   = 1;
        start = 0;
        error_count = 0; // Initialize scoreboard
        #50;
        rst   = 0;
        #50;
        $display("\n--- Test Suite Starting ---");

        // --- TEST 1: Standard transaction on Channel 2 ---
        check_transaction(3'b010, 10'h150);

        // --- TEST 2: Test another channel (e.g., Channel 7) ---
        // The expected data is still 10'h150 because our slave model is simple
        // and always returns the same data stream (0xD550).
        check_transaction(3'b111, 10'h150);

        // --- TEST 3: Mid-transaction Reset Test ---
        $display("INFO: Starting mid-transaction reset test...");
        channel = 3'b000;
        start   = 1;
        #20;
        start   = 0;
        
        // Wait until the FSM is busy
        wait(spi_inst.state == spi_inst.S_SEND_CMD && spi_inst.bit_counter == 3);
        $display("INFO: FSM is busy. Asserting reset...");
        rst = 1;
        #40;
        rst = 0;
        #40;

        if (spi_inst.state == spi_inst.S_IDLE && CS == 1) begin
            $display("INFO: SUCCESS! FSM correctly returned to IDLE after reset.");
        end else begin
            $display("ERROR: FAILURE! FSM did not return to IDLE after reset.");
            error_count = error_count + 1;
        end
        #100;
        
        // --- Phase 5: Final Report ---
        $display("\n--- Test Suite Complete ---");
        if (error_count == 0) begin
            $display("--------------------------");
            $display("--- ALL TESTS PASSED ---");
            $display("--------------------------");
        end else begin
            $display("--------------------------");
            $display("---  TESTS FAILED: %d errors found ---", error_count);
            $display("--------------------------");
        end

        #200;
        $finish;
    end

endmodule