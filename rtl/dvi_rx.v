// Copyright Wenting Zhang 2024 / Modified for Gowin HDMI RX direct integration
//
// Pure Verilog DVI/HDMI Receiver for Gowin FPGA.
// Deserializes 3 TMDS channels and recovers clock.
//
`timescale 1ns / 1ps
`default_nettype none

module dvi_rx (
    input wire rst,
    // Differential HDMI inputs from connector
    input wire hdmi_clk_p,
    input wire hdmi_clk_n,
    input wire [2:0] hdmi_d_p,
    input wire [2:0] hdmi_d_n,
    // Decoded parallel video outputs
    output wire clk_pixel,
    output wire de,
    output wire vsync,
    output wire hsync,
    output wire [23:0] pixel_data,
    output wire locked
);

    // 1. Recover single-ended TMDS clock & data signals
    wire tmds_clk_raw;
    wire [2:0] tmds_d_raw;

    TLVDS_IBUF tmds_clk_ibuf (
        .I(hdmi_clk_p),
        .IB(hdmi_clk_n),
        .O(tmds_clk_raw)
    );

    genvar i;
    generate
        for (i = 0; i < 3; i = i + 1) begin: gen_tmds_ibufs
            TLVDS_IBUF tmds_d_ibuf (
                .I(hdmi_d_p[i]),
                .IB(hdmi_d_n[i]),
                .O(tmds_d_raw[i])
            );
        end
    endgenerate

    // 2. PLL & CLKDIV for Clock Recovery
    // Recover 5x high speed DDR clock (clk_x5) from pixel clock.
    // Assuming standard pixel clock of ~74.25 MHz (720p@60Hz) or ~65 MHz (1024x768@60Hz)
    wire clk_x5;
    wire pll_lock;

    rPLL #(
        .FBDIV_SEL(4),          // Multiply by 5
        .IDIV_SEL(0),
        .ODIV_SEL(2),
        .DEVICE("GW2A-18")
    ) pll_inst (
        .CLKOUT(clk_x5),
        .CLKOUTP(),
        .CLKOUTD(),
        .CLKOUTD3(),
        .LOCK(pll_lock),
        .CLKIN(tmds_clk_raw),
        .CLKFB(1'b0),
        .RESET(rst)
    );

    // Div 5 of high-speed clock to generate phase-aligned pixel clock
    CLKDIV #(
        .DIV_MODE("5")
    ) clk_div_inst (
        .CLKOUT(clk_pixel),
        .HCLKIN(clk_x5),
        .RESETN(pll_lock && !rst),
        .CALIB(1'b0)
    );

    // 3. Deserializers (IDES10)
    wire [9:0] d_10b [0:2];
    wire [2:0] calib;

    generate
        for (i = 0; i < 3; i = i + 1) begin: gen_ides10
            IDES10 ides10_inst (
                .Q0(d_10b[i][0]),
                .Q1(d_10b[i][1]),
                .Q2(d_10b[i][2]),
                .Q3(d_10b[i][3]),
                .Q4(d_10b[i][4]),
                .Q5(d_10b[i][5]),
                .Q6(d_10b[i][6]),
                .Q7(d_10b[i][7]),
                .Q8(d_10b[i][8]),
                .Q9(d_10b[i][9]),
                .D(tmds_d_raw[i]),
                .FCLK(clk_x5),
                .PCLK(clk_pixel),
                .CALIB(calib[i]),
                .RESET(rst || !pll_lock)
            );
        end
    endgenerate

    // 4. Channel Word Aligner (Bitslip Control)
    // DVI Control Tokens:
    // ch0 (Blue): HSYNC (d_10b[0]) & VSYNC (d_10b[1])
    // Tokens are:
    // 10'b1101010100 (c0=0, c1=0)
    // 10'b0010101011 (c0=1, c1=0)
    // 10'b0101010100 (c0=0, c1=1)
    // 10'b1010101011 (c0=1, c1=1)
    reg [5:0] align_counter [0:2];
    reg [2:0] r_calib;
    reg [2:0] r_channel_locked;

    assign calib = r_calib;
    assign locked = pll_lock && (&r_channel_locked);

    integer ch;
    always @(posedge clk_pixel or posedge rst) begin
        if (rst) begin
            for (ch = 0; ch < 3; ch = ch + 1) begin
                align_counter[ch] <= 0;
                r_calib[ch] <= 1'b0;
                r_channel_locked[ch] <= 1'b0;
            end
        end else begin
            for (ch = 0; ch < 3; ch = ch + 1) begin
                if (d_10b[ch] == 10'b1101010100 || d_10b[ch] == 10'b0010101011 ||
                    d_10b[ch] == 10'b0101010100 || d_10b[ch] == 10'b1010101011) begin
                    align_counter[ch] <= 0;
                    r_calib[ch] <= 1'b0;
                    r_channel_locked[ch] <= 1'b1;
                end else begin
                    // Calibrate if token is not found for 60 cycles
                    if (align_counter[ch] == 6'd60) begin
                        align_counter[ch] <= 0;
                        r_calib[ch] <= 1'b1;
                        r_channel_locked[ch] <= 1'b0;
                    end else begin
                        align_counter[ch] <= align_counter[ch] + 1;
                        r_calib[ch] <= 1'b0;
                    end
                end
            end
        end
    end

    // 5. TMDS Channel Decoders
    wire [7:0] dec_r, dec_g, dec_b;
    wire de_r, de_g, de_b;
    wire c0_b, c1_b; // HSYNC, VSYNC from Blue channel
    /* verilator lint_off UNUSEDSIGNAL */
    wire c0_r, c1_r, c0_g, c1_g;
    /* verilator lint_on UNUSEDSIGNAL */

    tmds_decoder dec_ch0 (
        .clk(clk_pixel),
        .rst(rst || !locked),
        .d_in(d_10b[0]),
        .d_out(dec_b),
        .c0(c0_b),
        .c1(c1_b),
        .de(de_b)
    );

    tmds_decoder dec_ch1 (
        .clk(clk_pixel),
        .rst(rst || !locked),
        .d_in(d_10b[1]),
        .d_out(dec_g),
        .c0(c0_g),
        .c1(c1_g),
        .de(de_g)
    );

    tmds_decoder dec_ch2 (
        .clk(clk_pixel),
        .rst(rst || !locked),
        .d_in(d_10b[2]),
        .d_out(dec_r),
        .c0(c0_r),
        .c1(c1_r),
        .de(de_r)
    );

    // Outputs
    assign de = de_b && de_g && de_b; // Data enable
    assign hsync = c0_b;              // Hsync mapped to C0 of Blue channel
    assign vsync = c1_b;              // Vsync mapped to C1 of Blue channel
    assign pixel_data = {dec_r, dec_g, dec_b};

endmodule

// Helper Module: TMDS Decoder
module tmds_decoder (
    input wire clk,
    input wire rst,
    input wire [9:0] d_in,
    output reg [7:0] d_out,
    output reg c0,
    output reg c1,
    output reg de
);

    wire [7:0] d_dec = d_in[9] ? (
        d_in[8] ? (~d_in[7:0]) : d_in[7:0]
    ) : 8'd0;

    wire [7:0] recon;
    assign recon[0] = d_dec[0];
    genvar i;
    generate
        for (i = 1; i < 8; i = i + 1) begin: gen_recon
            assign recon[i] = d_in[8] ? (d_dec[i] ^ d_dec[i-1]) : (d_dec[i] ^~ d_dec[i-1]);
        end
    endgenerate

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            d_out <= 8'd0;
            c0 <= 1'b0;
            c1 <= 1'b0;
            de <= 1'b0;
        end else begin
            de <= d_in[9];
            if (d_in[9]) begin
                d_out <= recon;
                c0 <= 1'b0;
                c1 <= 1'b0;
            end else begin
                d_out <= 8'd0;
                case (d_in[9:0])
                    10'b1101010100: begin c0 <= 1'b0; c1 <= 1'b0; end
                    10'b0010101011: begin c0 <= 1'b1; c1 <= 1'b0; end
                    10'b0101010100: begin c0 <= 1'b0; c1 <= 1'b1; end
                    10'b1010101011: begin c0 <= 1'b1; c1 <= 1'b1; end
                    default: begin c0 <= 1'b0; c1 <= 1'b0; end
                endcase
            end
        end
    end

endmodule
