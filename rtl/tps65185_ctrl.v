// tps65185_ctrl.v
// Drive the TPS65185 PMIC via I2C to configure E-Ink voltages
//
// Sequence:
// 1. Hold WAKEUP low for 5ms.
// 2. Drive WAKEUP high and wait 5ms for PMIC standby.
// 3. Write VADJ (0x03) = VADJ_VAL via I2C to set VCOM.
// 4. Write ENABLE (0x02) = ENABLE_VAL via I2C to enable VCOM buffer.
// 5. Drive PWRUP high to trigger boost converters.

`default_nettype none

module tps65185_ctrl #(
    parameter SYS_CLK_FREQ = 27000000,    // 27 MHz system clock
    parameter I2C_CLK_FREQ = 100000,      // 100 kHz I2C SCL
    parameter [7:0] VADJ_VAL = 8'h14,     // Default VCOM = -1.50V (formula: -0.5V - VADJ*0.05V)
    parameter [7:0] ENABLE_VAL = 8'h80    // Default ENABLE = 8'h80 (VCOM_EN = 1)
)(
    input wire clk,
    input wire rst,

    // I2C interface (open-drain, externally or internally pulled up)
    inout wire PMIC_SCL,
    inout wire PMIC_SDA,

    // PMIC Control GPIOs
    output reg PMIC_WAKEUP,
    output reg PMIC_PWRUP,

    // Status outputs
    output reg done
);

    // I2C Open-drain behavior mapping
    reg scl_out;
    reg sda_out;

    assign PMIC_SCL = (scl_out == 1'b0) ? 1'b0 : 1'bz;
    assign PMIC_SDA = (sda_out == 1'b0) ? 1'b0 : 1'bz;

    // FSM States
    localparam STATE_POWERON       = 4'h0;
    localparam STATE_WAKEUP_DELAY  = 4'h1;
    localparam STATE_START         = 4'h2;
    localparam STATE_BYTE          = 4'h3;
    localparam STATE_STOP          = 4'h4;
    localparam STATE_GAP           = 4'h5;
    localparam STATE_PWRUP         = 4'h6;
    localparam STATE_DONE          = 4'h7;

    reg [3:0] state;

    // 5ms delay counter (5ms @ 27MHz is 135,000 cycles)
    localparam DELAY_5MS = (SYS_CLK_FREQ / 200); 
    reg [23:0] delay_counter;

    // I2C Tick Generator (4x I2C Clock Frequency)
    // 27MHz / 400kHz = 67.5 -> Tick every 67 clock cycles
    localparam TICK_DIVIDER = (SYS_CLK_FREQ / (I2C_CLK_FREQ * 4));
    reg [7:0] tick_cnt;
    wire tick = (tick_cnt == (TICK_DIVIDER - 1));

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_cnt <= 0;
        end else if (tick) begin
            tick_cnt <= 0;
        end else begin
            tick_cnt <= tick_cnt + 1;
        end
    end

    // I2C sequence data ROM (6 bytes total in 2 transactions of 3 bytes)
    reg [7:0] tx_data [0:5];
    always @(*) begin
        tx_data[0] = 8'hD0;         // Slave Address Write
        tx_data[1] = 8'h03;         // Reg Address VADJ
        tx_data[2] = VADJ_VAL;      // Reg Value
        tx_data[3] = 8'hD0;         // Slave Address Write
        tx_data[4] = 8'h02;         // Reg Address ENABLE
        tx_data[5] = ENABLE_VAL;    // Reg Value
    end

    reg [2:0] byte_idx;
    reg [3:0] bit_cnt;
    reg [1:0] phase;
    reg [7:0] tx_byte;

    // Control FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= STATE_POWERON;
            PMIC_WAKEUP    <= 1'b0;
            PMIC_PWRUP     <= 1'b0;
            done           <= 1'b0;
            scl_out        <= 1'b1;
            sda_out        <= 1'b1;
            delay_counter  <= 0;
            byte_idx       <= 0;
            bit_cnt        <= 0;
            phase          <= 0;
            tx_byte        <= 8'h00;
        end else begin
            case (state)
                // 1. Initial power-on: Hold WAKEUP low for 5ms
                STATE_POWERON: begin
                    PMIC_WAKEUP <= 1'b0;
                    PMIC_PWRUP  <= 1'b0;
                    scl_out     <= 1'b1;
                    sda_out     <= 1'b1;
                    if (delay_counter >= DELAY_5MS) begin
                        PMIC_WAKEUP   <= 1'b1;
                        delay_counter <= 0;
                        state         <= STATE_WAKEUP_DELAY;
                    end else begin
                        delay_counter <= delay_counter + 1;
                    end
                end

                // 2. Wakeup delay: Wait 5ms with WAKEUP high for PMIC initialization
                STATE_WAKEUP_DELAY: begin
                    PMIC_WAKEUP <= 1'b1;
                    PMIC_PWRUP  <= 1'b0;
                    scl_out     <= 1'b1;
                    sda_out     <= 1'b1;
                    if (delay_counter >= DELAY_5MS) begin
                        delay_counter <= 0;
                        byte_idx      <= 0;
                        state         <= STATE_START;
                    end else begin
                        delay_counter <= delay_counter + 1;
                    end
                end

                // 3. I2C START Condition
                STATE_START: begin
                    if (tick) begin
                        phase <= phase + 1;
                        if (phase == 2'd0) begin
                            scl_out <= 1'b1;
                            sda_out <= 1'b1;
                        end else if (phase == 2'd1) begin
                            scl_out <= 1'b1;
                            sda_out <= 1'b0; // SDA goes low while SCL is high
                        end else if (phase == 2'd2) begin
                            scl_out <= 1'b1;
                            sda_out <= 1'b0;
                        end else if (phase == 2'd3) begin
                            scl_out <= 1'b0; // SCL goes low
                            sda_out <= 1'b0;
                            bit_cnt <= 0;
                            phase   <= 0;
                            tx_byte <= tx_data[byte_idx];
                            state   <= STATE_BYTE;
                        end
                    end
                end

                // 4. Send 8 Data bits + 1 ACK bit
                STATE_BYTE: begin
                    if (tick) begin
                        phase <= phase + 1;
                        if (phase == 2'd0) begin
                            scl_out <= 1'b0;
                            if (bit_cnt < 4'd8) begin
                                sda_out <= tx_byte[7 - bit_cnt]; // Shift MSB first
                            end else begin
                                sda_out <= 1'b1; // Release SDA for ACK
                            end
                        end else if (phase == 2'd1) begin
                            scl_out <= 1'b1; // SCL goes high
                        end else if (phase == 2'd2) begin
                            scl_out <= 1'b1; // Keep SCL high (SDA should be stable/read)
                        end else if (phase == 2'd3) begin
                            scl_out <= 1'b0; // SCL goes low
                            phase   <= 0;
                            if (bit_cnt == 4'd8) begin
                                bit_cnt <= 0;
                                // If at end of a 3-byte packet (byte 2 or 5), send STOP
                                if (byte_idx == 3'd2 || byte_idx == 3'd5) begin
                                    state <= STATE_STOP;
                                end else begin
                                    byte_idx <= byte_idx + 1;
                                    tx_byte  <= tx_data[byte_idx + 1];
                                    state    <= STATE_BYTE;
                                end
                            end else begin
                                bit_cnt <= bit_cnt + 1;
                            end
                        end
                    end
                end

                // 5. I2C STOP Condition
                STATE_STOP: begin
                    if (tick) begin
                        phase <= phase + 1;
                        if (phase == 2'd0) begin
                            scl_out <= 1'b0;
                            sda_out <= 1'b0;
                        end else if (phase == 2'd1) begin
                            scl_out <= 1'b1; // SCL goes high
                            sda_out <= 1'b0;
                        end else if (phase == 2'd2) begin
                            scl_out <= 1'b1;
                            sda_out <= 1'b1; // SDA goes high while SCL is high
                        end else if (phase == 2'd3) begin
                            scl_out <= 1'b1;
                            sda_out <= 1'b1;
                            phase   <= 0;
                            if (byte_idx == 3'd5) begin
                                state <= STATE_PWRUP;
                            end else begin
                                byte_idx      <= byte_idx + 1;
                                delay_counter <= 0;
                                state         <= STATE_GAP;
                            end
                        end
                    end
                end

                // 6. Gap between I2C transactions (Bus Free Time)
                STATE_GAP: begin
                    scl_out <= 1'b1;
                    sda_out <= 1'b1;
                    // Wait a short gap (e.g. 500 clock cycles, ~18us) before next transaction
                    if (delay_counter >= 500) begin
                        delay_counter <= 0;
                        state         <= STATE_START;
                    end else begin
                        delay_counter <= delay_counter + 1;
                    end
                end

                // 7. Power-up trigger: Drive PWRUP high
                STATE_PWRUP: begin
                    scl_out    <= 1'b1;
                    sda_out    <= 1'b1;
                    PMIC_PWRUP <= 1'b1;
                    state      <= STATE_DONE;
                end

                // 8. Done: Hold signals
                STATE_DONE: begin
                    scl_out    <= 1'b1;
                    sda_out    <= 1'b1;
                    PMIC_PWRUP <= 1'b1;
                    PMIC_WAKEUP<= 1'b1;
                    done       <= 1'b1;
                end

                default: state <= STATE_POWERON;
            endcase
        end
    end

endmodule

`default_nettype wire
