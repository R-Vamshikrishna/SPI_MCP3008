`timescale 1ns/1ns

//==================================================================================
// Module:  MCP3008_SPI
// Author:  Vamshikrishna Redishetty
// Date:    23 Aug 2025
//
// Description:
// This module implements a synthesizable SPI Master controller designed to
// interface with a Microchip MCP3008 8-Channel, 10-bit Analog-to-Digital
// Converter (ADC). It operates based on a 50 MHz system clock and generates
// a ~3.125 MHz SPI clock.
// The Finite State Machine (FSM) strictly follows the half-duplex communication
// protocol outlined in the MCP3008 datasheet:
//   1. Master sends a 6-cycle command/configuration frame.
//   2. Master then receives a 10-cycle data frame from the ADC.
//
//==================================================================================
module MCP3008_SPI (
    // System Signals
    input           clk,            // System clock (assumed 50 MHz)
    input           rst,            // Active-high synchronous reset

    // Control & Configuration
    input           start,          // Single-cycle pulse to begin a new conversion
    input   [2:0]   channel,        // Selects ADC channel (0-7)

    // ADC Data Output
    output reg [9:0] ADC_data,      // 10-bit ADC result
    output reg      data_valid,     // Pulsed high for one cycle when ADC_data is valid

    // SPI Physical Interface
    input           MISO,           // Master-In, Slave-Out data line
    output reg      MOSI,           // Master-Out, Slave-In data line
    output          SCK,            // SPI serial clock
    output reg      CS              // Chip Select (active low)
);

    //--------------------------------------------------------------------------
    // FSM State Definitions
    //--------------------------------------------------------------------------
    localparam S_IDLE          = 4'b0001; // Waiting for start command
    localparam S_SEND_CMD      = 4'b0010; // Phase 1: Master sends command to ADC
    localparam S_RECEIVE_DATA  = 4'b0100; // Phase 2: Master receives data from ADC
    localparam S_FINISH        = 4'b1000; // Final data capture and flag assertion
    localparam S_DONE          = 4'b1001; // Enforces tCSH cool-down period

    reg [3:0] state = S_IDLE;

    //--------------------------------------------------------------------------
    // SPI Clock Generation
    // Generates a ~3.125 MHz SPI clock from a 50 MHz system clock.
    //--------------------------------------------------------------------------
    reg [3:0] sck_divider_reg = 0;
    reg       sck_reg         = 0;
    wire      sck_rising_edge;
    wire      sck_falling_edge;

    assign SCK = sck_reg;
    assign sck_rising_edge  = (sck_divider_reg == 7);
    assign sck_falling_edge = (sck_divider_reg == 15);

    //--------------------------------------------------------------------------
    // Internal Registers
    //--------------------------------------------------------------------------
    reg [4:0]  bit_counter  = 0; // Up-counter for SPI clock cycles per phase
    reg [15:0] mosi_data    = 0; // Shift register for outgoing command data
    reg [9:0]  miso_data    = 0; // Shift register for incoming ADC data
    reg [3:0]  done_counter = 0; // Counter for the S_DONE cool-down state

    //==========================================================================
    // Main FSM and Logic
    //==========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all state registers to a known, idle condition
            state           <= S_IDLE;
            CS              <= 1'b1;
            MOSI            <= 1'b0;
            sck_reg         <= 1'b0;
            data_valid      <= 1'b0;
            bit_counter     <= 0;
            sck_divider_reg <= 0;
            ADC_data        <= 0;
            done_counter    <= 0;
        end else begin
            // Default data_valid to low; it will only be pulsed high in S_FINISH
            data_valid <= 1'b0;

            case (state)

                // S_IDLE: Wait for a 'start' signal from the system.
                // Keep all SPI lines in their idle state (CS high, SCK low for Mode 0).
                S_IDLE: begin
                    CS              <= 1'b1;
                    sck_reg         <= 1'b0;
                    bit_counter     <= 0;
                    sck_divider_reg <= 0;
                    if (start) begin
                        // Load the 5-bit command into the MSB of the MOSI shift register
                        mosi_data <= {1'b1, 1'b1, channel, 11'b0};
                        CS        <= 1'b0; // Assert Chip Select to start the transaction
                        state     <= S_SEND_CMD;
                    end
                end

                // S_SEND_CMD: The master is talking. It sends the 5-bit command and
                // waits an additional clock cycle for the ADC's sample time (t_sample).
                // MISO is ignored during this phase.
                S_SEND_CMD: begin
                    sck_divider_reg <= sck_divider_reg + 1;

                    if (sck_falling_edge) begin
                        sck_reg   <= 1'b0;
                        MOSI      <= mosi_data[15]; // Present MSB on MOSI
                        mosi_data <= mosi_data << 1;  // Shift for the next bit
                    end
                    else if (sck_rising_edge) begin
                        sck_reg      <= 1'b1;
                        bit_counter  <= bit_counter + 1;
                    end

                    // After 6 SCK cycles are complete, transition to the receive phase.
                    if (bit_counter == 6 && sck_rising_edge) begin
                        bit_counter <= 0; // Reset counter for the next phase
                        state       <= S_RECEIVE_DATA;
                    end
                end

                // S_RECEIVE_DATA: The master is listening. It sends dummy bits (zeros)
                // on MOSI while sampling the MISO line on each rising SCK edge to
                // receive the ADC result.
                S_RECEIVE_DATA: begin
                    sck_divider_reg <= sck_divider_reg + 1;
                
                    if (sck_falling_edge) begin
                        sck_reg <= 1'b0;
                        MOSI    <= 1'b0; // Send dummy zero bits
                    end
                    else if (sck_rising_edge) begin
                        sck_reg      <= 1'b1;
                        miso_data    <= {miso_data[8:0], MISO}; // Sample MISO into LSB
                        bit_counter  <= bit_counter + 1;
                    end
                
                    // The ADC sends a null bit followed by 10 data bits.
                    // We only need to capture the final 10 bits. After 10 cycles in
                    // this state, the miso_data register holds the complete result.
                    if (bit_counter == 9 && sck_rising_edge) begin
                        state <= S_FINISH;
                    end
                end

                // S_FINISH: The transaction is complete. De-assert CS, present the
                // final data, and pulse the data_valid flag high for one cycle.
                S_FINISH: begin
                    CS           <= 1'b1;
                    data_valid   <= 1'b1;
                    ADC_data     <= miso_data; // Assign final data to the output
                    done_counter <= 0;
                    state        <= S_DONE;
                end
                
                // S_DONE: Enforce the minimum Chip Select high time (tCSH) to ensure
                // the ADC is ready for the next transaction.
                S_DONE: begin
                    CS           <= 1'b1;
                    sck_reg      <= 1'b0;
                    done_counter <= done_counter + 1;
                    if (done_counter == 13) begin
                        state <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule