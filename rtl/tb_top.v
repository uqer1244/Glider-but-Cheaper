`timescale 1ns / 1ps
//
// tb_top.v
// Bring-up testbench for the front panel and the EPD output bus.
//
// There is no video input in this build: top.v generates VSYNC locally, vin.v
// generates the test pattern, and csr.v comes out of reset already enabled with
// the timing from defines.vh. The testbench supplies the clock and drives the
// five buttons, which is the whole user interface.
//
// Four phases, in the order an operator would use them:
//
//   A  drive gate closed  GDOE/SDOE low and no gate clocks before BTN0
//   B  free running       BTN0 opens the gate, two frames are checked against
//                           GDCLK == vtotal, SDLE == vtotal, SDCE0 == hact*vact
//   C  mode switch        BTN3 makes csr_master issue a full-screen SETMODE and
//                           caster latches op_cmd / op_param / region
//   D  single step        BTN4 stops the scan, BTN1 runs exactly one frame
//
// Frame boundaries are taken from GDSP, which goes low for exactly the vsync
// lines once per frame.
//
// Run with:  make simulation
// Set SIM_DEFS="-DFULL_DUMP" for a full-hierarchy VCD; by default only the
// testbench level is dumped, because a whole-design trace over a 663k-clock
// frame is several GB.

`include "defines.vh"

module tb_top;

    // `integer` matters: the defines are sized literals, so an unsized localparam
    // inherits their 12-bit width and HTOTAL * VTOTAL silently wraps.
    //
    // The same hazard bit top.v, where a module parameter override has no
    // integer context to widen it: `DEFAULT_HACT * `DEFAULT_VACT truncated to
    // 0 under yosys while iverilog computed 614400, so the self-test compared
    // against zero on hardware and passed in simulation. VTOTAL and ACTIVE now
    // come from defines.vh, pre-widened, so both files cannot disagree again.
    localparam integer VTOTAL = `DEFAULT_VTOTAL;
    localparam integer HTOTAL = `DEFAULT_HFP + `DEFAULT_HSYNC + `DEFAULT_HBP + `DEFAULT_HACT;
    localparam integer ACTIVE = `DEFAULT_ACTIVE;

    // 40.5 MHz. sysclock.v bypasses the rPLL under SIMULATION and feeds CLK_IN
    // straight through, so this is the actual core clock in simulation.
    localparam real CLK_HALF = 12.346;

    // One frame at 40.5 MHz, in ns. Used to size the waits.
    localparam real FRAME_NS = 675000 * 2 * CLK_HALF;

    // debug_ctrl debounces for 10 ms, so a press has to be held longer.
    localparam real PRESS_NS = 15_000_000;

    reg CLK_IN = 1'b0;
    // Buttons are active low and released at power-up.
    //   0 DRIVE   1 STEP   2 PATTERN   3 MODE   4 FREERUN
    reg [4:0] BTN_N = 5'b11111;
    reg SPI_CS = 1'b1;
    reg SPI_SCK = 1'b0;
    reg SPI_MOSI = 1'b0;

    wire [12:0] DDR_A;
    wire [2:0]  DDR_BA;
    wire DDR_RAS_N, DDR_CAS_N, DDR_WE_N, DDR_ODT;
    wire DDR_RESET_N, DDR_CKE, DDR_LDM, DDR_UDM;
    wire DDR_CK_P, DDR_CK_N;
    wire EPD_GDOE, EPD_GDCLK, EPD_GDSP;
    wire EPD_SDCLK, EPD_SDLE, EPD_SDOE;
    wire [15:0] EPD_SD;
    wire EPD_SDCE0;
    wire SPI_MISO;
    wire REFRESH_DONE;
    wire [5:0] LED;
    wire UART_TX;

    wire [15:0] DDR_DQ;
    wire DDR_UDQS_P, DDR_UDQS_N, DDR_LDQS_P, DDR_LDQS_N;
    wire DDR_RZQ, DDR_ZIO;

    top #(
        .COLORMODE("MONO"),
        .SIMULATION("TRUE")
    ) uut (
        .CLK_IN(CLK_IN),
        .DDR_DQ(DDR_DQ),
        .DDR_A(DDR_A),
        .DDR_BA(DDR_BA),
        .DDR_RAS_N(DDR_RAS_N),
        .DDR_CAS_N(DDR_CAS_N),
        .DDR_WE_N(DDR_WE_N),
        .DDR_ODT(DDR_ODT),
        .DDR_RESET_N(DDR_RESET_N),
        .DDR_CKE(DDR_CKE),
        .DDR_LDM(DDR_LDM),
        .DDR_UDM(DDR_UDM),
        .DDR_UDQS_P(DDR_UDQS_P),
        .DDR_UDQS_N(DDR_UDQS_N),
        .DDR_LDQS_P(DDR_LDQS_P),
        .DDR_LDQS_N(DDR_LDQS_N),
        .DDR_CK_P(DDR_CK_P),
        .DDR_CK_N(DDR_CK_N),
        .DDR_RZQ(DDR_RZQ),
        .DDR_ZIO(DDR_ZIO),
        .EPD_GDOE(EPD_GDOE),
        .EPD_GDCLK(EPD_GDCLK),
        .EPD_GDSP(EPD_GDSP),
        .EPD_SDCLK(EPD_SDCLK),
        .EPD_SDLE(EPD_SDLE),
        .EPD_SDOE(EPD_SDOE),
        .EPD_SD(EPD_SD),
        .EPD_SDCE0(EPD_SDCE0),
        .SPI_CS(SPI_CS),
        .SPI_SCK(SPI_SCK),
        .SPI_MOSI(SPI_MOSI),
        .SPI_MISO(SPI_MISO),
        .REFRESH_DONE(REFRESH_DONE),
        .BTN_N(BTN_N),
        .LED(LED),
        .UART_TX(UART_TX)
    );

    always #CLK_HALF CLK_IN = ~CLK_IN;

    wire clk = uut.clk_sys;

    integer errors = 0;

    task fail(input [8*64-1:0] msg);
        begin
            $display("[TB]   FAIL %0s", msg);
            errors = errors + 1;
        end
    endtask

    task press(input integer idx);
        begin
            BTN_N[idx] = 1'b0;
            #PRESS_NS;
            BTN_N[idx] = 1'b1;
            #PRESS_NS;      // let the release debounce too
        end
    endtask

    // ---- EPD bus counters ---------------------------------------------------
    // Same three quantities epd_selftest.v checks in fabric.

    reg gdsp_d  = 1'b1;
    reg gdclk_d = 1'b0;
    reg sdle_d  = 1'b0;

    integer gdclk_cnt  = 0;
    integer sdle_cnt   = 0;
    integer active_cnt = 0;

    // Snapshot of the frame that just ended, plus a boundary counter the
    // sequencer polls.
    integer f_gdclk = 0;
    integer f_sdle  = 0;
    integer f_activ = 0;
    integer frames  = 0;

    always @(posedge clk) begin
        gdsp_d  <= EPD_GDSP;
        gdclk_d <= EPD_GDCLK;
        sdle_d  <= EPD_SDLE;

        if (EPD_GDSP && !gdsp_d) begin
            f_gdclk = gdclk_cnt;
            f_sdle  = sdle_cnt;
            f_activ = active_cnt;
            frames  = frames + 1;

            // The edge landing on this cycle belongs to the new frame.
            gdclk_cnt  = (EPD_GDCLK && !gdclk_d) ? 1 : 0;
            sdle_cnt   = (EPD_SDLE  && !sdle_d)  ? 1 : 0;
            active_cnt = (!EPD_SDCE0)            ? 1 : 0;
        end
        else begin
            if (EPD_GDCLK && !gdclk_d) gdclk_cnt  = gdclk_cnt + 1;
            if (EPD_SDLE  && !sdle_d)  sdle_cnt   = sdle_cnt + 1;
            if (!EPD_SDCE0)            active_cnt = active_cnt + 1;
        end
    end

    task check_last_frame;
        begin
            $display("[TB]   gdclk=%0d (exp %0d)  sdle=%0d (exp %0d)  active=%0d (exp %0d)",
                     f_gdclk, VTOTAL, f_sdle, VTOTAL, f_activ, ACTIVE);
            if (f_gdclk != VTOTAL) fail("GDCLK count");
            if (f_sdle  != VTOTAL) fail("SDLE count");
            if (f_activ != ACTIVE) fail("SDCE0 active window");

            // The tb counted these itself above. epd_selftest.v counts the same
            // three in fabric and is what LED1 actually reports, so check its
            // verdict too -- otherwise the module driving the bring-up LED is
            // the one thing the simulation never tests.
            $display("[TB]   selftest: pass=%0d fail_code=%0d (gdclk=%0d sdle=%0d active=%0d)",
                     uut.epd_selftest.pass, uut.epd_selftest.fail_code,
                     uut.epd_selftest.gdclk_cnt, uut.epd_selftest.sdle_cnt,
                     uut.epd_selftest.active_cnt);
            $display("[TB]   selftest latched: gdclk=%0d sdle=%0d active=%0d  err=%0d",
                     uut.epd_selftest.last_gdclk, uut.epd_selftest.last_sdle,
                     uut.epd_selftest.last_active,
                     $signed(uut.epd_selftest.err_full));
            $display("[TB]   diag=%06b (nib_idx=%0d nib_val=0x%0X)  err16=0x%04X",
                     uut.epd_selftest.diag, uut.epd_selftest.diag[5:4],
                     uut.epd_selftest.diag[3:0], uut.epd_selftest.err16);
            if (uut.epd_selftest.err_full !== 0)
                fail("selftest latched active window error is non-zero");
            if (!uut.epd_selftest.pass) fail("epd_selftest did not pass");

            // epd_sd_check watches the data bus, which nothing else here looks
            // at. Hardware reports U=ff Z=0000 D=0000; assert the same in
            // simulation so a regression in the output stage is caught before
            // it reaches a board.
            $display("[TB]   sd_check: U=%02x Z=%0d D=%0d",
                     uut.epd_sd_check.sd_or_o, uut.epd_sd_check.hiz_cnt_o,
                     uut.epd_sd_check.dup_cnt_o);
            if (uut.epd_sd_check.sd_or_o == 8'd0)
                fail("SD[15:8] never asserted -- OUTPUT_16B not in effect");
            if (uut.epd_sd_check.hiz_cnt_o != 0)
                fail("SD bus drove 2'b11 (Hi-Z) during the active window");
            if (uut.epd_sd_check.dup_cnt_o != 0)
                fail("2x upscale duplication broken on the SD bus");
        end
    endtask

    // Wait for `n` more frame boundaries, or give up after `limit` frame times.
    task wait_frames(input integer n, input integer limit);
        integer target;
        integer spins;
        begin
            target = frames + n;
            spins  = 0;
            while ((frames < target) && (spins < limit)) begin
                #FRAME_NS;
                spins = spins + 1;
            end
            if (frames < target)
                fail("timed out waiting for a frame");
        end
    endtask

    // ---- Sequence -----------------------------------------------------------

    integer mark;

    initial begin
        $dumpfile("waveform.vcd");
`ifdef FULL_DUMP
        $dumpvars(0, tb_top);
`else
        $dumpvars(1, tb_top);
`endif

        $display("[TB] htotal=%0d vtotal=%0d active=%0d (%0d clk/frame)",
                 HTOTAL, VTOTAL, ACTIVE, HTOTAL * VTOTAL);

        // ---- A: drive gate closed at power-up ----
        #(2 * FRAME_NS);
        $display("[TB] A: drive gate closed at power-up");
        if (EPD_GDOE) fail("GDOE high before BTN0");
        if (EPD_SDOE) fail("SDOE high before BTN0");
        if (frames != 0) fail("frames ran before BTN0");
        if (gdclk_cnt != 0) fail("GDCLK toggled before BTN0");

        // ---- B: BTN0 opens the gate, check two frames ----
        $display("[TB] B: BTN0 -> drive enabled, free running");
        press(0);
        if (!EPD_GDOE) fail("GDOE still low after BTN0");
        if (!EPD_SDOE) fail("SDOE still low after BTN0");
        wait_frames(2, 6);
        check_last_frame;
        wait_frames(1, 6);
        check_last_frame;

        // ---- C: BTN3 issues a SETMODE over the internal CSR master ----
        $display("[TB] C: BTN3 -> SETMODE via csr_master");
        press(3);
        // The op is latched into caster at the next vsync trigger.
        wait_frames(2, 6);
        $display("[TB]   mode_sel=%0d op_cmd=%0d op_param=%0d region=%0d,%0d..%0d,%0d",
                 uut.dbg_mode_sel, uut.caster.op_cmd, uut.caster.op_param,
                 uut.caster.op_left, uut.caster.op_top,
                 uut.caster.op_right, uut.caster.op_bottom);
        if (uut.dbg_mode_sel !== 2'd1)                        fail("mode_sel did not advance");
        if (uut.caster.op_cmd !== `OP_EXT_SETMODE)            fail("op_cmd is not SETMODE");
        if (uut.caster.op_param !== `SETMODE_FAST_MONO_NO_DITHER) fail("op_param wrong for mode 1");
        if (uut.caster.op_left !== 12'd0)                     fail("op_left not 0");
        if (uut.caster.op_top !== 12'd0)                      fail("op_top not 0");
        if (uut.caster.op_right !== `INPUT_HACT * 4)          fail("op_right not full width");
        if (uut.caster.op_bottom !== `INPUT_VACT)             fail("op_bottom not full height");

        // ---- D: BTN4 stops free running, BTN1 steps one frame ----
        $display("[TB] D: BTN4 -> manual, BTN1 -> one frame");
        press(4);
        if (uut.dbg_freerun !== 1'b0) fail("freerun did not clear");
        // Let any frame already in flight finish, then confirm the scan stops.
        #(2 * FRAME_NS);
        mark = frames;
        #(3 * FRAME_NS);
        if (frames != mark) fail("scan kept running with FREERUN off");

        press(1);
        #(2 * FRAME_NS);
        if (frames != mark + 1)
            $display("[TB]   FAIL STEP ran %0d frames, expected 1", frames - mark);
        if (frames != mark + 1) errors = errors + 1;
        else begin
            $display("[TB]   one frame stepped");
            check_last_frame;
        end

        // ---- verdict ----
        if (errors == 0)
            $display("[TB] PASS - front panel and EPD bus behave as specified");
        else
            $display("[TB] FAIL - %0d problem(s)", errors);
        $finish;
    end

    // Backstop in case a wait never completes.
    initial begin
        #(60 * FRAME_NS);
        $display("[TB] FAIL - global timeout at frame %0d", frames);
        $finish;
    end

endmodule
