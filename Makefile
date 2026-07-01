# Glider but Cheaper - Gowin FPGA Project Makefile
# Targets Sipeed Tang Primer 20K (GW2A-LV18PG256C8/I7)

TARGET      = glider_tang
TOP_MODULE  = top
RTL_DIR     = rtl

SRCS        = $(RTL_DIR)/top.v \
              $(RTL_DIR)/dvi_rx.v \
              $(RTL_DIR)/caster.v \
              $(RTL_DIR)/pixel_processing.v \
              $(RTL_DIR)/wvfmlut.v \
              $(RTL_DIR)/csr.v \
              $(RTL_DIR)/degamma.v \
              $(RTL_DIR)/bayer_dithering.v \
              $(RTL_DIR)/blue_noise_dithering.v \
              $(RTL_DIR)/line_reverse.v \
              $(RTL_DIR)/adder_sat.v \
              $(RTL_DIR)/adder_sat_8.v \
              $(RTL_DIR)/mulib/rtl/baseip/mu_ram_2rw.v \
              $(RTL_DIR)/mulib/rtl/baseip/generic/mu_dsync.v \
              $(RTL_DIR)/mulib/rtl/baseip/generic/mu_dbsync.v \
              $(RTL_DIR)/memif.v \
              $(RTL_DIR)/timing_generator.v \
              $(RTL_DIR)/sysclock.v \
              $(RTL_DIR)/vin.v \
              $(RTL_DIR)/mig_wrapper.v \
              $(RTL_DIR)/bi_fifo.v \
              $(RTL_DIR)/bo_fifo.v \
              $(RTL_DIR)/tps65185_ctrl.v

CST_FILE    = constraints/gowin_constraints.cst
DEVICE      = GW2A-LV18PG256C8/I7
FAMILY      = GW2A-18

SIM_TARGET  = sim_elf
TB_SRC      = $(RTL_DIR)/tb_top.v
WAVE_FILE   = waveform.vcd

all: $(TARGET).fs

# 1. Synthesis via Yosys (Gowin target)
$(TARGET).json: $(SRCS)
	yosys -p "read_verilog -I$(RTL_DIR) -I$(RTL_DIR)/mulib/rtl $(SRCS); synth_gowin -json $(TARGET).json -top $(TOP_MODULE)"

# 2. Place & Route via nextpnr-himbaechel
$(TARGET).pnr.json: $(TARGET).json $(CST_FILE)
	python3 -c "import sys, yowasp_nextpnr_himbaechel_gowin; sys.exit(yowasp_nextpnr_himbaechel_gowin.run_nextpnr_himbaechel_gowin(sys.argv[1:]))" --json $(TARGET).json --write $(TARGET).pnr.json --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CST_FILE)

# 3. Bitstream generation via Apicula (gowin_pack)
$(TARGET).fs: $(TARGET).pnr.json
	gowin_pack -d $(FAMILY) -o $(TARGET).fs $(TARGET).pnr.json

# 4. Flash to SRAM (temporary load)
program: $(TARGET).fs
	openFPGALoader -b tangprimer20k $(TARGET).fs

# 5. Flash to board internal Flash (permanent boot)
flash: $(TARGET).fs
	openFPGALoader -b tangprimer20k -f $(TARGET).fs

# 6. Deploy precompiled release binary to SRAM
program_bin: bin/glider_tang.fs
	openFPGALoader -b tangprimer20k bin/glider_tang.fs

# 7. Deploy precompiled release binary to internal Flash
flash_bin: bin/glider_tang.fs
	openFPGALoader -b tangprimer20k -f bin/glider_tang.fs

# 8. Compile and run simulation
simulation: $(SRCS) $(TB_SRC)
	iverilog -DSIMULATION -I$(RTL_DIR) -I$(RTL_DIR)/mulib/rtl -o $(SIM_TARGET) $(TB_SRC) $(SRCS)
	./$(SIM_TARGET)
	@echo "Simulation complete. $(WAVE_FILE) is ready."

clean:
	rm -f *.json *.fs $(SIM_TARGET) $(WAVE_FILE)

.PHONY: all program flash program_bin flash_bin clean simulation
