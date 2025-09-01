`timescale 1ns/1ps

//==================================================================================
// Module:  tb_MCP3008_SPI
// Author:  (Your Name)
// Date:    (Current Date)
//
// Description:
// This is a comprehensive testbench for the MCP3008_SPI master module.
// Its key features are:
//   1. Instantiation of the SPI master module (DUT).
//   2. Generation of the system clock and control signals (reset, start).
//   3. A behavioral model of the MCP3008 ADC slave that accurately mimics its
//      SPI Mode 0 timing by providing data on the falling edge of SCK.
//   4. A test sequence that initiates a transaction and automatically verifies
//      the correctness of the received data against a known expected value.
//
//==================================================================================
module tb_MCP3008_SPI();

    //--------------------------------------------------------------------------
    // Testbench Signal Declarations
    //--------------------------------------------------------------------------
    reg         clk     = 0;
    reg         rst     = 0;
    reg         start   = 0;
    reg   [2:0] channel = 3'b010; // Test target: Channel 2
    reg         MISO    = 0;      // Driven by the slave model

    wire        MOSI;
    wire        SCK;
    wire        CS;
    wire  [9:0] ADC_data;
    wire        data_valid;

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

    //--------------------------------------------------------------------------
    // 1. Clock Generation
    // Generates a 50 MHz clock with a 20 ns period.
    //--------------------------------------------------------------------------
    always #10 clk = ~clk;

    //--------------------------------------------------------------------------
    // 2. Behavioral Slave Model
    // This block models the MCP3008's behavior for SPI Mode 0 by changing its
    // output on the falling edge of the clock, ensuring the master can safely
    // sample on the rising edge.
    //--------------------------------------------------------------------------
    reg [15:0] miso_shift_reg = 16'hD550;  // Pre-defined test data to be sent by the slave
    
    always @(negedge SCK or posedge rst) begin
        if (rst) begin
            // On reset, reload the slave's test data and set MISO low.
            miso_shift_reg <= 16'hD550;
            MISO           <= 0;
        end else if (CS == 0) begin
            // Only when selected, place the next bit onto the MISO line.
            MISO           <= miso_shift_reg[15];
            miso_shift_reg <= miso_shift_reg << 1; // Shift for the next cycle
        end else begin
            // If not selected (transaction is over), reset the test data for the next run.
            miso_shift_reg <= 16'hD550;
        end
    end

    //--------------------------------------------------------------------------
    // 3. Simulation Test Sequence
    // This block orchestrates the entire test from start to finish.
    //--------------------------------------------------------------------------
    initial begin
        // The $monitor task provides a continuous, live trace of key signals
        // in the Tcl console, which is invaluable for debugging.
        $monitor("Time=%t | CS=%b SCK=%b MOSI=%b MISO=%b | state=%h | ADC_data=%h",
                 $time, CS, SCK, MOSI, MISO, spi_inst.state, ADC_data);

        // --- Phase 1: Reset ---
        rst   = 1;
        start = 0;
        #50;
        rst   = 0; // Release the reset
        #50;

        // --- Phase 2: Start Transaction ---
        $display("\nTEST: Starting transaction at time %t...", $time);
        start = 1;
        #20; // Hold 'start' high for one 50MHz clock cycle for a clean pulse
        start = 0;
        
        // --- Phase 3: Wait for Completion and Verify ---
        wait(data_valid == 1); // Pause simulation until the DUT signals it's done
        
        #20; // Wait one more cycle for signals to settle in the waveform viewer
        
        $display("TEST: Transaction complete at time %t", $time);
        $display("Received ADC Data: %b (Hex: %h, Decimal: %d)", ADC_data, ADC_data, ADC_data);

        // Perform the final check against the known correct answer
        if (ADC_data == 10'h150) begin
            $display("SUCCESS: Received data matches expected value (0x150).");
        end else begin
            $display("FAILURE: Received data (%h) does not match expected value (0x150).", ADC_data);
        end

        // --- Phase 4: End Simulation ---
        #300;
        $finish;
    end

endmodule