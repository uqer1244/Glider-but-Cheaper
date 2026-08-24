`timescale 1ns / 1ps
`default_nettype none

module mig_wrapper(
    // Clock and reset
    input  wire         clk_sys,
    output wire         clk_mif,
    input  wire         rst_in,
    output wire         sys_rst,
    // DDR RAM interface
    inout  wire [15:0]  ddr_dq,
    output wire [12:0]  ddr_a,
    output wire [2:0]   ddr_ba,
    output wire         ddr_ras_n,
    output wire         ddr_cas_n,
    output wire         ddr_we_n,
    output wire         ddr_odt,
    output wire         ddr_reset_n,
    output wire         ddr_cke,
    output wire         ddr_ldm,
    output wire         ddr_udm,
    inout  wire         ddr_udqs_p,
    inout  wire         ddr_udqs_n,
    inout  wire         ddr_ldqs_p,
    inout  wire         ddr_ldqs_n,
    output wire         ddr_ck_p,
    output wire         ddr_ck_n,
    inout  wire         ddr_rzq,
    inout  wire         ddr_zio,
    // Control interface
    output wire         ddr_calib_done,
    // User interface
    input  wire         mig_cmd_en,
    input  wire [2:0]   mig_cmd_instr,
    input  wire [5:0]   mig_cmd_bl,
    input  wire [29:0]  mig_cmd_byte_addr,
    output wire         mig_cmd_empty,
    output wire         mig_cmd_full,
    input  wire         mig_wr_en,
    input  wire [15:0]  mig_wr_mask,
    input  wire [127:0] mig_wr_data,
    output wire         mig_wr_empty,
    output wire         mig_wr_full,
    output wire [6:0]   mig_wr_count,
    output wire         mig_wr_underrun,
    input  wire         mig_rd_en,
    output wire [127:0] mig_rd_data,
    output wire         mig_rd_full,
    output wire         mig_rd_empty,
    output wire         mig_rd_overflow,
    output wire [6:0]   mig_rd_count,
    // Error
    output wire         error
);

    parameter SIMULATION = "FALSE";
    parameter CALIB_SOFT_IP = "TRUE";

    // Loop clocks and resets
    assign clk_mif = clk_sys;
    assign sys_rst = rst_in;
    assign ddr_calib_done = 1'b1; // Calibration is mock-completed immediately

    assign error = 1'b0;

    // memif.v reads only three of the status signals; the rest are marked
    // unused there, so they are tied off.
    assign mig_cmd_empty   = 1'b1;
    assign mig_wr_empty    = 1'b1;
    assign mig_wr_count    = 7'b0;
    assign mig_wr_underrun = 1'b0;
    assign mig_rd_full     = 1'b0;
    assign mig_rd_overflow = 1'b0;
    assign mig_rd_count    = 7'd1;

`ifdef SIMULATION
    // ---- behavioural memory ----
    //
    // Caster keeps a 16-bit state per pixel in VRAM and decides what to drive
    // from it. With the old stub -- one 128-bit register, address ignored --
    // every pixel read the same word, so the whole field settled or refused to
    // settle as one. Everything downstream of the pipeline was therefore
    // unverifiable in simulation: greyscale, waveform progression, and whether
    // the picture is even the right picture.
    //
    // This is a real array instead. It cannot be synthesised -- 2.34 MB will
    // not fit in the GW2A-18's ~103 KB of BSRAM, which is why the hardware
    // needs the DDR3 IP (plan.md 2-2) -- but simulation has no such limit, and
    // the logic can be finished and verified before that IP exists.
    //
    // Protocol, from how memif.v drives it:
    //   mig_cmd_instr  3'b000 write, 3'b001 read
    //   mig_cmd_bl     burst length - 1 (memif uses 16 words)
    //   writes         data is pushed into the write FIFO first, then the
    //                  command is issued, so the words are already there
    //   reads          command first, then mig_rd_en pops words out
    //
    // A burst is serviced in one delta rather than one word per cycle. The
    // real MCB has latency and memif tolerates it (RD_WAIT1/RD_WAIT2), so
    // being early is safe; being wrong about the data would not be.
    localparam MEM_WORDS = 1 << 18;     // 4 MB at 16 B/word, ample for 2.34 MB

    reg [127:0] mem [0:MEM_WORDS-1];

    localparam FIFO_DEPTH = 256;
    reg [127:0] wrf [0:FIFO_DEPTH-1];
    reg [127:0] rdf [0:FIFO_DEPTH-1];
    integer wrf_wr, wrf_rd, rdf_wr, rdf_rd;
    integer i;

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = 128'd0;
        wrf_wr = 0; wrf_rd = 0; rdf_wr = 0; rdf_rd = 0;
    end

    wire [17:0] cmd_word_addr = mig_cmd_byte_addr[21:4];   // 16 B per word
    wire [6:0]  burst_words   = {1'b0, mig_cmd_bl} + 7'd1;

    always @(posedge clk_mif) begin
        if (rst_in) begin
            wrf_wr <= 0; wrf_rd <= 0; rdf_wr <= 0; rdf_rd <= 0;
        end
        else begin
            if (mig_wr_en) begin
                wrf[wrf_wr % FIFO_DEPTH] <= mig_wr_data;
                wrf_wr <= wrf_wr + 1;
            end

            if (mig_cmd_en) begin
                if (mig_cmd_instr[0] == 1'b0) begin
                    for (i = 0; i < burst_words; i = i + 1)
                        mem[(cmd_word_addr + i) % MEM_WORDS] =
                            wrf[(wrf_rd + i) % FIFO_DEPTH];
                    wrf_rd <= wrf_rd + burst_words;
                end
                else begin
                    for (i = 0; i < burst_words; i = i + 1)
                        rdf[(rdf_wr + i) % FIFO_DEPTH] =
                            mem[(cmd_word_addr + i) % MEM_WORDS];
                    rdf_wr <= rdf_wr + burst_words;
                end
            end

            // First-word fall-through: mig_rd_data already shows the head, so
            // mig_rd_en means "consume it", not "start a read".
            if (mig_rd_en && (rdf_rd != rdf_wr)) rdf_rd <= rdf_rd + 1;
        end
    end

    assign mig_rd_empty = (rdf_rd == rdf_wr);
    assign mig_rd_data  = rdf[rdf_rd % FIFO_DEPTH];
    assign mig_wr_full  = ((wrf_wr - wrf_rd) >= (FIFO_DEPTH - 32));
    assign mig_cmd_full = 1'b0;         // serviced immediately

`else
    // ---- synthesis stub ----
    // Still a single register: the real memory is the Gowin DDR3 IP and it is
    // not wired up yet (plan.md 2-2). Everything verified on hardware so far
    // is the scan and output layer, which does not depend on this.
    assign mig_cmd_full = 1'b0;
    assign mig_wr_full  = 1'b0;
    assign mig_rd_empty = 1'b0;         // always claims data is available

    reg [127:0] data_reg;
    initial begin
        data_reg = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    end
    always @(posedge clk_mif) begin
        if (mig_wr_en) begin
            data_reg <= mig_wr_data;
        end
    end
    assign mig_rd_data = data_reg;
`endif

endmodule
`default_nettype wire
