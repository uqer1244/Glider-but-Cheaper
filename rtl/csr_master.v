`timescale 1ns / 1ps
`default_nettype none
`include "defines.vh"
//
// csr_master.v
// Internal SPI master for the EPDC control registers.
//
// In the original Glider an STM32 programs the EPDC over SPI. This port has no
// MCU, so this module plays the same role for the one thing bring-up needs:
// issuing a full-screen SETMODE operation when the operator presses the mode
// button.
//
// It drives the same spi_cs / spi_sck / spi_mosi that csr.v already listens on,
// so nothing inside caster.v changes. csr.v samples SCK against the core clock,
// so the bit rate only has to be slower than clk/2; clk/8 is used here.
//
// csr.v auto-increments the register address after every data byte except for
// LUT_WR, OSD_WR and OP_CMD. The whole operation is therefore a single chip
// select: one address byte (OP_LEFT_HI) followed by eleven data bytes walking
// up to OP_CMD, which triggers the operation.
//
// SPI mode 3: SCK idles high, MOSI changes on the falling edge, the slave
// samples on the rising edge.

module csr_master(
    input  wire clk,
    input  wire rst,

    input  wire start,              // one clock pulse
    input  wire [7:0] mode_param,   // SETMODE_* value

    output reg  busy,
    // Active low chip select, matching csr.v
    output reg  spi_cs,
    output reg  spi_sck,
    output reg  spi_mosi
);

    // Region covers the whole VRAM grid.
    localparam integer OP_RIGHT  = `INPUT_HACT * 4;   // 1280
    localparam integer OP_BOTTOM = `INPUT_VACT;       // 960

    // Frames spent clearing the region to white before the new mode is applied.
    // pixel_processing.v applies the mode on the frame where op_framecnt hits 0.
    localparam [7:0] CLEAR_FRAMES = 8'd16;

    localparam integer NBYTES = 12;

    // Byte 0 is the address, bytes 1..11 are data for registers 4..14.
    reg [7:0] stream [0:NBYTES-1];
    always @(*) begin
        stream[0]  = `CSR_OP_LEFT_HI;           // address phase
        stream[1]  = 8'd0;                      // OP_LEFT_HI
        stream[2]  = 8'd0;                      // OP_LEFT_LO
        stream[3]  = OP_RIGHT[11:8];            // OP_RIGHT_HI
        stream[4]  = OP_RIGHT[7:0];             // OP_RIGHT_LO
        stream[5]  = 8'd0;                      // OP_TOP_HI
        stream[6]  = 8'd0;                      // OP_TOP_LO
        stream[7]  = OP_BOTTOM[11:8];           // OP_BOTTOM_HI
        stream[8]  = OP_BOTTOM[7:0];            // OP_BOTTOM_LO
        stream[9]  = mode_param;                // OP_PARAM
        stream[10] = CLEAR_FRAMES;              // OP_LENGTH
        stream[11] = `OP_EXT_SETMODE;           // OP_CMD, fires the operation
    end

    // clk/8 bit clock: one SCK half period every 4 core clocks.
    localparam [1:0] TICK_MAX = 2'd3;
    reg [1:0] tick;

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_LEAD  = 2'd1;   // CS low, SCK high, before the first bit
    localparam [1:0] ST_SHIFT = 2'd2;
    localparam [1:0] ST_TRAIL = 2'd3;   // hold CS low after the last rising edge

    reg [1:0] state;
    reg [3:0] byte_idx;
    reg [2:0] bit_idx;
    reg       phase;                    // 0 = drive on falling, 1 = rise

    wire [7:0] cur_byte = stream[byte_idx];

    always @(posedge clk) begin
        if (rst) begin
            state    <= ST_IDLE;
            busy     <= 1'b0;
            spi_cs   <= 1'b1;
            spi_sck  <= 1'b1;
            spi_mosi <= 1'b0;
            tick     <= 2'd0;
            byte_idx <= 4'd0;
            bit_idx  <= 3'd0;
            phase    <= 1'b0;
        end
        else begin
            case (state)
            ST_IDLE: begin
                spi_cs  <= 1'b1;
                spi_sck <= 1'b1;
                busy    <= 1'b0;
                if (start) begin
                    state    <= ST_LEAD;
                    busy     <= 1'b1;
                    spi_cs   <= 1'b0;
                    byte_idx <= 4'd0;
                    bit_idx  <= 3'd0;
                    phase    <= 1'b0;
                    tick     <= 2'd0;
                end
            end

            ST_LEAD: begin
                // One bit period of setup with CS low and SCK still high.
                if (tick == TICK_MAX) begin
                    tick  <= 2'd0;
                    state <= ST_SHIFT;
                end
                else begin
                    tick <= tick + 1'b1;
                end
            end

            ST_SHIFT: begin
                if (tick != TICK_MAX) begin
                    tick <= tick + 1'b1;
                end
                else begin
                    tick <= 2'd0;
                    if (phase == 1'b0) begin
                        // Falling edge: present the bit, MSB first.
                        spi_sck  <= 1'b0;
                        spi_mosi <= cur_byte[3'd7 - bit_idx];
                        phase    <= 1'b1;
                    end
                    else begin
                        // Rising edge: the slave samples here.
                        spi_sck <= 1'b1;
                        phase   <= 1'b0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            if (byte_idx == NBYTES - 1)
                                state <= ST_TRAIL;
                            else
                                byte_idx <= byte_idx + 1'b1;
                        end
                        else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                end
            end

            ST_TRAIL: begin
                if (tick == TICK_MAX) begin
                    tick   <= 2'd0;
                    spi_cs <= 1'b1;
                    state  <= ST_IDLE;
                end
                else begin
                    tick <= tick + 1'b1;
                end
            end
            endcase
        end
    end

endmodule
`default_nettype wire
