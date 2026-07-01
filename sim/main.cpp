//
// Caster simulator
// Copyright 2021 Wenting Zhang
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
#include <stdio.h>
#include <stdint.h>
#include <assert.h>

#include <SDL.h>

#include "verilated.h"
#include "verilated_vcd_c.h"
#include "Vcaster.h"

#include "dispsim.h"
#include "srcsim.h"
#include "vramsim.h"
#include "spisim.h"
#include "intapi.h"

#define SIM_STEP 100000
//#define MAX_CYCLES 500000
#define TRACE

constexpr int DISP_FACTOR = 2;

// Headless screen buffer
uint32_t screen_pixels[DISP_WIDTH * DISP_HEIGHT];

// Verilator related
Vcaster *core;
VerilatedVcdC *trace;
uint64_t tickcount;

// Legacy function required by some platforms/ versions of Verilator
double sc_time_stamp() { return 0; }

void testmain(void) {
    static int step = 0;
    // This function is called every tick
    switch (step) {
    case 0:
        spi_write_reg8(CSR_CFG_V_FP, 3);
        spi_write_reg8(CSR_CFG_V_SYNC, 1);
        spi_write_reg8(CSR_CFG_V_BP, 2);
        spi_write_reg16(CSR_CFG_V_ACT, 240);
        spi_write_reg8(CSR_CFG_H_FP, 3);
        spi_write_reg8(CSR_CFG_H_SYNC, 1);
        spi_write_reg8(CSR_CFG_H_BP, 2);
        spi_write_reg16(CSR_CFG_H_ACT, 80);
        spi_write_reg8(CSR_CFG_MINDRV, 1);

        // Enable OSD
        spi_write_reg16(CSR_OSD_LEFT, 0);
        spi_write_reg16(CSR_OSD_RIGHT, 256/4);
        spi_write_reg16(CSR_OSD_TOP, 0);
        spi_write_reg16(CSR_OSD_BOTTOM, 128);
        spi_write_reg16(CSR_OSD_ADDR, 0);
        /*for (int i = 0; i < 4096; i++) {
            spi_write_reg8(CSR_OSD_WR, 0x55);
        }*/
        spi_write_reg8(CSR_OSD_EN, 1);
        spi_write_reg8(CSR_CFG_MIRROR, 1);

        spi_write_reg8(CSR_ENABLE, 1); // Enable refresh
        // Read back status
        spi_write_reg8(CSR_STATUS, 0);
        step = 1;
        break;
    case 1:
        if (!spi_is_busy()) {
            printf("Initialization over SPI done.\n");
            step = 2;
        }
        break;
    case 2:
        /*if (tickcount > 200*1000) {
            printf("Testing clearing\n");
            intapi_redraw(40, 30, 120, 90);
            step = 3;
        }*/
        break;
    // Do more test here
    }
}

void tick(void) {
    // Create local copy of input signals
    uint8_t vin_vsync;
    uint32_t vin_pixel;
    uint8_t vin_valid;
    uint64_t bi_pixel;
    uint8_t bi_valid;
    uint8_t spi_cs;
    uint8_t spi_sck;
    uint8_t spi_mosi;

    // Call simulated modules
    dispsim_apply(
        screen_pixels,
        core->epd_gdoe,
        core->epd_gdclk,
        core->epd_gdsp,
        core->epd_sdle,
        core->epd_sdoe,
        core->epd_sd,
        core->epd_sdce0,
        core->dbg_wvfm_tgt
    );
    srcsim_apply(
        vin_vsync,
        vin_pixel,
        vin_valid,
        core->vin_ready
    );
    vramsim_apply(
        core->b_trigger,
        bi_pixel,
        bi_valid,
        core->bi_ready,
        core->bo_pixel,
        core->bo_valid
    );
    spisim_apply(
        spi_cs,
        spi_sck,
        spi_mosi,
        core->spi_miso
    );

    // Posedge
    core->clk = 1;
    core->eval();

    // Apply changed input signals after clock edge
    core->vin_vsync = vin_vsync;
    core->vin_pixel = vin_pixel;
    core->vin_valid = vin_valid;
    core->bi_pixel = bi_pixel;
    core->bi_valid = bi_valid;
    core->spi_cs = spi_cs;
    core->spi_sck = spi_sck;
    core->spi_mosi = spi_mosi;

    // Let combinational changes propagate
    core->eval();
#ifdef TRACE
    trace->dump(tickcount * 10);
#endif

    // Negedge
    core->clk = 0;
    core->eval();
#ifdef TRACE
    trace->dump(tickcount * 10 + 5);
#endif
    tickcount++;

    testmain();
}

void reset(void) {
    core->rst = 1;
    tick();
    tick();
    core->rst = 0;
    dispsim_reset();
    srcsim_reset();
    vramsim_reset();
    spisim_reset();
    core->sys_ready = 1;
}

void save_bmp(const char *filename, uint32_t *pixels, int width, int height) {
    FILE *f = fopen(filename, "wb");
    if (!f) return;

    unsigned char bmpFileHeader[14] = {'B','M', 0,0,0,0, 0,0, 0,0, 54,0,0,0};
    unsigned char bmpInfoHeader[40] = {40,0,0,0, 0,0,0,0, 0,0,0,0, 1,0, 32,0};

    int fileSize = 54 + width * height * 4;
    bmpFileHeader[2] = (unsigned char)(fileSize      );
    bmpFileHeader[3] = (unsigned char)(fileSize >>  8);
    bmpFileHeader[4] = (unsigned char)(fileSize >> 16);
    bmpFileHeader[5] = (unsigned char)(fileSize >> 24);

    bmpInfoHeader[4] = (unsigned char)(width      );
    bmpInfoHeader[5] = (unsigned char)(width  >>  8);
    bmpInfoHeader[6] = (unsigned char)(width  >> 16);
    bmpInfoHeader[7] = (unsigned char)(width  >> 24);

    int negHeight = -height;
    bmpInfoHeader[8] = (unsigned char)(negHeight      );
    bmpInfoHeader[9] = (unsigned char)(negHeight >>  8);
    bmpInfoHeader[10] = (unsigned char)(negHeight >> 16);
    bmpInfoHeader[11] = (unsigned char)(negHeight >> 24);

    fwrite(bmpFileHeader, 1, 14, f);
    fwrite(bmpInfoHeader, 1, 40, f);
    fwrite(pixels, 4, width * height, f);
    fclose(f);
}

void render_copy(void) {
    static int frame_num = 0;
    char fname[64];
    sprintf(fname, "frame_%04d.bmp", frame_num++);
    save_bmp(fname, screen_pixels, DISP_WIDTH, DISP_HEIGHT);
    printf("Saved frame: %s\n", fname);
}

int main(int argc, char *argv[]) {
    // Initialize testbench
    Verilated::commandArgs(argc, argv);

    core = new Vcaster;
    Verilated::traceEverOn(true);

#ifdef TRACE
    trace = new VerilatedVcdC;
    core->trace(trace, 99);
    trace->open("trace.vcd");
#endif

    // Start simulation
    printf("Simulation start (headless).\n");

    reset();

    // Run for 1,000,000 cycles to capture waveforms
    for (int i = 0; i < 1000000; i++) {
        tick();
    }

    printf("Stop.\n");

#ifdef TRACE
    trace->close();
#endif

    return 0;
}