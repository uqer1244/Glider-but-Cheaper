// Copyright Wenting Zhang 2024
//
// This source describes Open Hardware and is licensed under the CERN-OHL-P v2
//
// You may redistribute and modify this documentation and make products using
// it under the terms of the CERN-OHL-P v2 (https:/cern.ch/cern-ohl). This
// documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
// INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
// PARTICULAR PURPOSE. Please see the CERN-OHL-P v2 for applicable conditions
//
// top.v
// Glider top-level
`default_nettype none
`timescale 1ns / 1ps
`include "defines.vh"

module top(
    // Global clock input
    input wire CLK_IN,
    // DDR3/MCB interface
    inout wire [15:0] DDR_DQ,
    output wire [12:0] DDR_A,
    output wire [2:0] DDR_BA,
    output wire DDR_RAS_N,
    output wire DDR_CAS_N,
    output wire DDR_WE_N,
    output wire DDR_ODT,
    output wire DDR_RESET_N,
    output wire DDR_CKE,
    output wire DDR_LDM,
    output wire DDR_UDM,
    inout wire DDR_UDQS_P,
    inout wire DDR_UDQS_N,
    inout wire DDR_LDQS_P,
    inout wire DDR_LDQS_N,
    output wire DDR_CK_P,
    output wire DDR_CK_N,
    inout wire DDR_RZQ,
    inout wire DDR_ZIO,
    // EPD interface
    output wire EPD_GDOE,
    output wire EPD_GDCLK,
    output wire EPD_GDSP,
    output wire EPD_SDCLK,
    output wire EPD_SDLE,
    output wire EPD_SDOE,
    output wire [15:0] EPD_SD,
    output wire EPD_SDCE0,
    // CSR interface
    input wire SPI_CS,
    input wire SPI_SCK,
    input wire SPI_MOSI,
    output wire SPI_MISO,
    // Handshake interface.
    // PMIC_READY is gone: the XIAO firmware asserts it unconditionally at boot,
    // so it never carried any information. The high voltage rails are brought
    // up by hand and the drive gate is BTN0 instead. REFRESH_DONE is still
    // driven for whatever wants to watch the scan.
    output wire REFRESH_DONE,
    // Front panel: 5 buttons (active low) and 6 LEDs (active low)
    input wire [4:0] BTN_N,
    output wire [5:0] LED,
    // Debug console on the dock's onboard USB-UART (FT2232 channel B)
    output wire UART_TX
    );
    
    parameter COLORMODE = "MONO";
    
    parameter SIMULATION = "FALSE";
    parameter CALIB_SOFT_IP = "TRUE";
    parameter CLK_SOURCE = "DCM"; // Possible values: DDR, FPD, DCM
    // Remember to change clock multiplier in DDR3 unit
    // 2 for DCM, 8 for FPD, 20 for DDR

    // System clocking
    wire clk_sys;
    wire sys_rst;
    
    wire clk_ddr;
    wire mif_rst;
    
    wire clk_epdc;
    // For compatibility with r0.12 boards
    wire dcm_locked;
    sysclock sysclock(
        // Clock in ports
        .clk_in(CLK_IN),
        // Clock out ports
        .clk_ddr(clk_ddr),
        .clk_sys(clk_sys),
        // Status and control signals
        .reset(1'b0),
        .locked(dcm_locked)
    );
    
    // Reset sequencer: hold the whole design in reset until the PLL has been
    // locked for 256 clocks, then release synchronously.
    reg [7:0] rst_cnt = 8'd0;
    reg rst_int = 1'b1;
    always @(posedge clk_sys) begin
        if (!dcm_locked) begin
            rst_cnt <= 8'd0;
            rst_int <= 1'b1;
        end
        else if (rst_cnt != 8'hFF) begin
            rst_cnt <= rst_cnt + 1'b1;
            rst_int <= 1'b1;
        end
        else begin
            rst_int <= 1'b0;
        end
    end

    wire c3_sys_rst = rst_int;
    assign mif_rst = c3_sys_rst;

/*
    reg c3_sys_rst = 1'b1;
    always @(posedge clk_sys) begin
        c3_sys_rst <= 1'b0;
    end
    
    IBUFG clkin1_buf (
        .O (clk_sys),
        .I (CLK_IN)
    );
    assign clk_ddr = clk_sys;
    assign mif_rst = c3_sys_rst;
*/

    // Global frame trigger & control
    wire b_trigger;
    wire global_en;
    wire [23:0] frame_bytes_memif;

    // Video input
    wire vin_vsync;
    wire [31:0] vin_pixel;
    wire vin_valid;
    wire vin_ready;

    // Front panel. Owns the debounced button state and the LED readout; see
    // debug_ctrl.v for the button and LED map.
    wire dbg_drive_en;
    wire dbg_freerun;
    wire dbg_step;
    wire [1:0] dbg_pattern;
    wire [1:0] dbg_mode_sel;
    wire dbg_mode_toggle;
    wire selftest_led;
    wire [5:0] selftest_diag;

    debug_ctrl #(
        .CLK_HZ(40_500_000)
    ) debug_ctrl (
        .clk(clk_sys),
        .rst(sys_rst),
        .btn_n(BTN_N),
        .selftest_led(selftest_led),
        .selftest_diag(selftest_diag),
        .drive_en(dbg_drive_en),
        .freerun(dbg_freerun),
        .step_pulse(dbg_step),
        .pattern(dbg_pattern),
        .mode_sel(dbg_mode_sel),
        .mode_toggle(dbg_mode_toggle),
        .led(LED)
    );

    // Frame trigger. This build has no video receiver, so VSYNC is generated
    // locally and the internal test pattern is the only pixel source.
    //
    // With FREERUN on the period below applies. With it off nothing fires until
    // BTN1, which runs exactly one frame -- the mode to use with a scope or a
    // logic analyser, and the safe way to put the first frames on a panel.
    //
    // One panel frame is 344 x 1927 + VS_DELAY = 662,897 clocks. The period here
    // is a little longer so the scan always finishes and drops back to
    // SCAN_IDLE, which is what makes REFRESH_DONE pulse.
    //   675,000 clk @ 40.5 MHz = 60.00 Hz
    localparam VSYNC_PERIOD = 20'd674_999;
    localparam VSYNC_WIDTH  = 20'd512;

    reg [19:0] vsync_cnt = 20'd0;
    reg int_vsync = 1'b0;
    always @(posedge clk_sys) begin
        if (sys_rst) begin
            vsync_cnt <= 20'd0;
            int_vsync <= 1'b0;
        end else begin
            if (dbg_step || (dbg_freerun && vsync_cnt == VSYNC_PERIOD)) begin
                vsync_cnt <= 20'd0;
                int_vsync <= 1'b1;
            end else begin
                // Saturate rather than wrap. With FREERUN off the counter would
                // otherwise roll over and start emitting frames on its own.
                if (vsync_cnt != VSYNC_PERIOD)
                    vsync_cnt <= vsync_cnt + 1'b1;
                if (vsync_cnt > VSYNC_WIDTH)
                    int_vsync <= 1'b0;
            end
        end
    end

    assign clk_epdc = clk_sys;

    // Internal test pattern generator. Runs in the EPDC clock domain and is
    // pulled by vin_ready, so no input FIFO or clock crossing is needed.
    vin #(
        .COLORMODE(COLORMODE)
    ) vin(
        .clk(clk_sys),
        .rst(sys_rst),
        .vsync(int_vsync),
        .pattern(dbg_pattern),
        .v_vsync(vin_vsync),
        .v_pixel(vin_pixel),
        .v_valid(vin_valid),
        .v_ready(vin_ready)
    );


    // Hardware DDR controller
    wire clk_mif;
    wire ddr_calib_done;
    wire mig_cmd_en;
    wire [2:0] mig_cmd_instr;
    wire [5:0] mig_cmd_bl;
    wire [29:0] mig_cmd_byte_addr;
    wire mig_cmd_empty;
    wire mig_cmd_full;
    wire mig_wr_en;
    wire [15:0] mig_wr_mask;
    wire [127:0] mig_wr_data;
    wire mig_wr_empty;
    wire mig_wr_full;
    wire [6:0] mig_wr_count;
    wire mig_wr_underrun;
    wire mig_rd_en;
    wire [127:0] mig_rd_data;
    wire mig_rd_full;
    wire mig_rd_empty;
    wire mig_rd_overflow;
    wire [6:0] mig_rd_count;
    wire mig_error;

    mig_wrapper #(
        .SIMULATION(SIMULATION),
        .CALIB_SOFT_IP(CALIB_SOFT_IP)
    ) mig_wrapper(
        // Clock and reset
        .clk_sys(clk_ddr),
        .clk_mif(clk_mif),
        .rst_in(mif_rst),
        .sys_rst(sys_rst),
        // DDR ram interface
        .ddr_dq(DDR_DQ),
        .ddr_a(DDR_A),
        .ddr_ba(DDR_BA),
        .ddr_ras_n(DDR_RAS_N),
        .ddr_cas_n(DDR_CAS_N),
        .ddr_we_n(DDR_WE_N),
        .ddr_odt(DDR_ODT),
        .ddr_reset_n(DDR_RESET_N),
        .ddr_cke(DDR_CKE),
        .ddr_ldm(DDR_LDM),
        .ddr_udm(DDR_UDM),
        .ddr_udqs_p(DDR_UDQS_P),
        .ddr_udqs_n(DDR_UDQS_N),
        .ddr_ldqs_p(DDR_LDQS_P),
        .ddr_ldqs_n(DDR_LDQS_N),
        .ddr_ck_p(DDR_CK_P),
        .ddr_ck_n(DDR_CK_N),
        .ddr_rzq(DDR_RZQ),
        .ddr_zio(DDR_ZIO),
        // Control interface
        .ddr_calib_done(ddr_calib_done),
        // User interface
        .mig_cmd_en(mig_cmd_en),
        .mig_cmd_instr(mig_cmd_instr),
        .mig_cmd_bl(mig_cmd_bl),
        .mig_cmd_byte_addr(mig_cmd_byte_addr),
        .mig_cmd_empty(mig_cmd_empty),
        .mig_cmd_full(mig_cmd_full),
        .mig_wr_en(mig_wr_en),
        .mig_wr_mask(mig_wr_mask),
        .mig_wr_data(mig_wr_data),
        .mig_wr_empty(mig_wr_empty),
        .mig_wr_full(mig_wr_full),
        .mig_wr_count(mig_wr_count),
        .mig_wr_underrun(mig_wr_underrun),
        .mig_rd_en(mig_rd_en),
        .mig_rd_data(mig_rd_data),
        .mig_rd_full(mig_rd_full),
        .mig_rd_empty(mig_rd_empty),
        .mig_rd_overflow(mig_rd_overflow),
        .mig_rd_count(mig_rd_count),
        // Error
        .error(mig_error)
    );

    wire mig_error_epdc;
    mu_dsync mig_error_sync (
        .iclk(clk_mif),
        .in(mig_error),
        .oclk(clk_epdc),
        .out(mig_error_epdc)
    );

    // VRAM interface
    wire memif_enable;
    wire memif_trigger;
    wire pix_read_valid;
    wire pix_read_ready;
    wire [127:0] pix_read;
    wire pix_write_valid;
    wire pix_write_ready;
    wire [127:0] pix_write;
    
    wire memif_error;

    memif memif(
        // Clock and reset
        .clk(clk_mif),
        .rst(sys_rst),
        // Control
        .enable(memif_enable),
        .vsync(memif_trigger),
        .frame_bytes(frame_bytes_memif),
        // Pixel output interface
        .pix_read(pix_read),
        .pix_read_valid(pix_read_valid),
        .pix_read_ready(pix_read_ready),
        // Pixel input interface
        .pix_write(pix_write),
        .pix_write_valid(pix_write_valid),
        .pix_write_ready(pix_write_ready),
        // To MIG
        .mig_cmd_en(mig_cmd_en),
        .mig_cmd_instr(mig_cmd_instr),
        .mig_cmd_bl(mig_cmd_bl),
        .mig_cmd_byte_addr(mig_cmd_byte_addr),
        .mig_cmd_empty(mig_cmd_empty),
        .mig_cmd_full(mig_cmd_full),
        .mig_wr_en(mig_wr_en),
        .mig_wr_mask(mig_wr_mask),
        .mig_wr_data(mig_wr_data),
        .mig_wr_empty(mig_wr_empty),
        .mig_wr_full(mig_wr_full),
        .mig_wr_count(mig_wr_count),
        .mig_wr_underrun(mig_wr_underrun),
        .mig_rd_en(mig_rd_en),
        .mig_rd_data(mig_rd_data),
        .mig_rd_full(mig_rd_full),
        .mig_rd_empty(mig_rd_empty),
        .mig_rd_overflow(mig_rd_overflow),
        .mig_rd_count(mig_rd_count),
        // Error
        .error(memif_error)
    );

    mu_dsync memif_vs_sync (
        .iclk(clk_epdc),
        .in(b_trigger),
        .oclk(clk_mif),
        .out(memif_trigger)
    );

    wire [23:0] frame_bytes;
    mu_dbsync #(.W(24)) memif_fbytes_sync (
        .iclk(clk_epdc),
        .in(frame_bytes),
        .oclk(clk_mif),
        .out(frame_bytes_memif)
    );

    wire memif_error_epdc;
    mu_dsync memif_error_sync (
        .iclk(clk_mif),
        .in(memif_error),
        .oclk(clk_epdc),
        .out(memif_error_epdc)
    );

    wire ddr_calib_done_epdc;
    mu_dsync ddr_calib_done_sync (
        .iclk(clk_mif),
        .in(ddr_calib_done),
        .oclk(clk_epdc),
        .out(ddr_calib_done_epdc)
    );

    mu_dsync memif_en_sync (
        .iclk(clk_epdc),
        .in(ddr_calib_done_epdc && global_en),
        .oclk(clk_mif),
        .out(memif_enable)
    );

    // VRAM FIFOs
    // BI is from VRAM to EPDC
    wire bi_fifo_full;
    wire bi_fifo_empty;
    wire bi_fifo_overflow;
    wire [63:0] bi_pixel;
    wire bi_valid;
    wire bi_ready;
    bi_fifo bi_fifo(
        .rst(sys_rst), // input rst, reset at each frame
        // Write port
        .wr_clk(clk_mif),
        .din(pix_read),
        .wr_en(pix_read_valid),
        .full(bi_fifo_full),
        // Read port
        .rd_clk(clk_epdc),
        .rd_en(bi_ready),
        .dout(bi_pixel),
        .empty(bi_fifo_empty)
    );
    assign pix_read_ready = !bi_fifo_full;
    assign bi_valid = !bi_fifo_empty;

    // BO is from EPDC to VRAM
    wire bo_fifo_full;
    wire bo_fifo_empty;
    wire [63:0] bo_pixel;
    wire bo_valid;
    bo_fifo bo_fifo(
        .rst(sys_rst), // input rst, reset at each frame
        // Write port
        .wr_clk(clk_epdc),
        .din(bo_pixel),
        .wr_en(bo_valid),
        .full(bo_fifo_full),
        // Read port
        .rd_clk(clk_mif),
        .rd_en(pix_write_ready),
        .dout(pix_write),
        .empty(bo_fifo_empty)
    );
    assign pix_write_valid = !bo_fifo_empty;
    
    // Drive gate.
    //
    // The scan will not start, and GDOE/SDOE stay low, until this is high. The
    // PMIC handshake used to sit here; it was removed because the XIAO asserts
    // PMIC_READY unconditionally in setup(), so gating on it only looked safe.
    // The operator now owns the gate through BTN0, which starts OFF, so the EPD
    // bus is idle at power-up and the panel is only ever driven deliberately.
    //
    // ddr_calib_done_epdc is still in the term. It is tied high by the
    // mig_wrapper stub today and becomes real when the Gowin DDR3 IP lands.
    wire drive_en_epdc;
    mu_dsync drive_en_sync (
        .iclk(clk_sys),
        .in(dbg_drive_en),
        .oclk(clk_epdc),
        .out(drive_en_epdc)
    );
    wire sys_ready = drive_en_epdc && ddr_calib_done_epdc;

    
    wire [1:0] dbg_scan_state;
    wire [10:0] dbg_scan_h_cnt;
    wire [10:0] dbg_scan_v_cnt;
    wire dbg_spi_req_wen;
    wire [7:0] dbg_spi_req_addr;
    wire [7:0] dbg_spi_req_wdata;

    // Drive REFRESH_DONE (HIGH when idle, LOW when actively scanning)
    assign REFRESH_DONE = (dbg_scan_state == 2'b00);

    wire epdc_rst = rst_int;

    // CSR access. The external SPI pins are still wired up for an MCU, but the
    // mode button needs to issue a SETMODE op with no MCU present, so an
    // internal master drives the same three signals and takes priority while it
    // is busy. See csr_master.v.
    wire spi_ncs;
    wire ext_spi_sck;
    wire ext_spi_mosi;
    wire spi_miso;
    mu_dsync spi_cs_sync (
        .iclk(1'b0), // external
        .in(!SPI_CS),
        .oclk(clk_epdc),
        .out(spi_ncs)
    );
    wire ext_spi_cs = !spi_ncs;

    mu_dsync spi_sck_sync (
        .iclk(1'b0), // external
        .in(SPI_SCK),
        .oclk(clk_epdc),
        .out(ext_spi_sck)
    );

    mu_dsync spi_mosi_sync (
        .iclk(1'b0), // external
        .in(SPI_MOSI),
        .oclk(clk_epdc),
        .out(ext_spi_mosi)
    );

    // Mode index -> SETMODE parameter. Index 0 is fast mono bayer because that
    // is what OP_INIT already leaves every pixel in.
    wire [7:0] mode_param =
        (dbg_mode_sel == 2'd0) ? `SETMODE_FAST_MONO_BAYER :
        (dbg_mode_sel == 2'd1) ? `SETMODE_FAST_MONO_NO_DITHER :
        (dbg_mode_sel == 2'd2) ? `SETMODE_FAST_MONO_BLUE_NOISE :
                                 `SETMODE_FAST_GREY;

    // debug_ctrl hands over a toggle rather than a pulse, because a single cycle
    // pulse can be swallowed by a two flop level synchroniser. Both edges of the
    // synchronised toggle mean "the mode changed".
    wire mode_toggle_epdc;
    mu_dsync mode_toggle_sync (
        .iclk(clk_sys),
        .in(dbg_mode_toggle),
        .oclk(clk_epdc),
        .out(mode_toggle_epdc)
    );
    reg mode_toggle_d;
    always @(posedge clk_epdc)
        mode_toggle_d <= mode_toggle_epdc;
    wire mode_change_pulse = mode_toggle_epdc ^ mode_toggle_d;

    wire int_spi_busy;
    wire int_spi_cs;
    wire int_spi_sck;
    wire int_spi_mosi;
    csr_master csr_master (
        .clk(clk_epdc),
        .rst(epdc_rst),
        .start(mode_change_pulse),
        .mode_param(mode_param),
        .busy(int_spi_busy),
        .spi_cs(int_spi_cs),
        .spi_sck(int_spi_sck),
        .spi_mosi(int_spi_mosi)
    );

    // Force the external clock to the mode 3 idle level while its chip select is
    // deasserted. Without this the mux below produces a phantom rising edge the
    // moment the internal master takes over -- csr.v counts it as a bit and every
    // byte of the transfer lands one bit out of place.
    wire ext_spi_sck_idle = ext_spi_cs ? 1'b1 : ext_spi_sck;

    wire spi_cs   = int_spi_busy ? int_spi_cs   : ext_spi_cs;
    wire spi_sck  = int_spi_busy ? int_spi_sck  : ext_spi_sck_idle;
    wire spi_mosi = int_spi_busy ? int_spi_mosi : ext_spi_mosi;
    




    wire [15:0] epd_sd_caster;
    caster #(
        .SIMULATION(SIMULATION),
        .COLORMODE(COLORMODE)
    )
    caster(
        .clk(clk_epdc),
        .rst(epdc_rst),
        // Video input
        .vin_vsync(vin_vsync),
        .vin_pixel(vin_pixel),
        .vin_valid(vin_valid),
        .vin_ready(vin_ready),
        // Framebuffer input
        .bi_pixel(bi_pixel),
        .bi_valid(bi_valid),
        .bi_ready(bi_ready),
        // Framebuffer output
        .bo_pixel(bo_pixel),
        .bo_valid(bo_valid),
        // EPD signals
        .epd_gdoe(EPD_GDOE),
        .epd_gdclk(EPD_GDCLK),
        .epd_gdsp(EPD_GDSP),
        .epd_sdclk(EPD_SDCLK),
        .epd_sdle(EPD_SDLE),
        .epd_sdoe(EPD_SDOE),
        .epd_sd(epd_sd_caster),
        .epd_sdce0(EPD_SDCE0),
        // CSR interface
        .spi_cs(spi_cs),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),
        .spi_miso(SPI_MISO),
        // Control / status
        .b_trigger(b_trigger),
        .sys_ready(sys_ready),
        .mig_error(mig_error_epdc),
        .mif_error(memif_error_epdc),
        .frame_bytes(frame_bytes),
        .global_en(global_en),
        // Debugging
        .dbg_scan_state(dbg_scan_state),
        .dbg_scan_h_cnt(dbg_scan_h_cnt),
        .dbg_scan_v_cnt(dbg_scan_v_cnt),
        .dbg_spi_req_wen(dbg_spi_req_wen),
        .dbg_spi_req_addr(dbg_spi_req_addr),
        .dbg_spi_req_wdata(dbg_spi_req_wdata)
    );
    
    assign EPD_SD = epd_sd_caster;

    // Self-check on the EPD bus. Verifies GDCLK / SDLE / SDCE0 against the
    // configured timing every frame and reports on LED1, so the output can be
    // validated with no logic analyser and no panel attached.
    wire selftest_pass;
    wire [1:0] selftest_fail;
    wire selftest_frame_done;
    wire [11:0] selftest_last_gdclk;
    wire [11:0] selftest_last_sdle;
    wire [20:0] selftest_last_active;
    wire signed [21:0] selftest_err;
    epd_selftest #(
        .EXP_VTOTAL(`DEFAULT_VTOTAL),
        .EXP_ACTIVE(`DEFAULT_ACTIVE),
        .BLINK_DIV(25'd10_125_000)
    ) epd_selftest (
        .clk(clk_epdc),
        .rst(epdc_rst),
        .epd_gdsp(EPD_GDSP),
        .epd_gdclk(EPD_GDCLK),
        .epd_sdle(EPD_SDLE),
        .epd_sdce0(EPD_SDCE0),
        .pass(selftest_pass),
        .fail_code(selftest_fail),
        .diag(selftest_diag),
        .frame_done(selftest_frame_done),
        .last_gdclk_o(selftest_last_gdclk),
        .last_sdle_o(selftest_last_sdle),
        .last_active_o(selftest_last_active),
        .err_o(selftest_err),
        .led(selftest_led)
    );

    // Every frame's counters go out of the dock's USB serial port as text.
    // The LED blink code says only which count is wrong; this says by how
    // much, which is the number needed to tell a timing error from a wiring
    // error. Costs one pin that nothing else uses.
    debug_uart #(
        .DECIMATE(15)               // 4 lines/s at 60 Hz
    ) debug_uart (
        .clk(clk_epdc),
        .rst(epdc_rst),
        .frame_tick(selftest_frame_done),
        .gdclk_cnt(selftest_last_gdclk),
        .sdle_cnt(selftest_last_sdle),
        .active_cnt(selftest_last_active),
        .err(selftest_err),
        .pass(selftest_pass),
        .fail_code(selftest_fail),
        .tx(UART_TX)
    );

    // LED[5:0] is driven by debug_ctrl, already active low.

endmodule
`default_nettype wire
