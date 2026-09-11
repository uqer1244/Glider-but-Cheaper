# Glider but Cheaper

> **Low-latency E-ink Monitor Controller ported to Sipeed Tang Primer 20K (Gowin GW2A-LV18)**

[![License: CERN-OHL-P v2](https://img.shields.io/badge/License-CERN--OHL--P--v2-blue.svg)](LICENSE)
[![FPGA](https://img.shields.io/badge/FPGA-Gowin%20GW2A--LV18-orange.svg)](https://wiki.sipeed.com/hardware/en/tang/Tang-Primer-20K/Primer-20K.html)
[![Toolchain](https://img.shields.io/badge/Toolchain-Yosys%20%7C%20nextpnr%20%7C%20Gowin-green.svg)](https://github.com/YosysHQ/yosys)

[한국어 설명은 아래로 스크롤하세요. (Scroll down for Korean description.)](#한국어-korean)

---

## English

### Overview
**Glider but Cheaper** is a cost-optimized, self-contained port of the **Glider** open-source E-ink monitor controller to the **Sipeed Tang Primer 20K** FPGA module.

The original Glider board relies on a Xilinx Spartan-6 LX16 FPGA, external DDR3 framebuffer, and an STM32H750 MCU. This port targets the widely available and budget-friendly **Tang Primer 20K** (featuring the Gowin GW2A-LV18PG256C8/I7 FPGA and 128MB on-module DDR3), enabling makers to build an ultra-low-latency paper-like display monitor at a fraction of the original hardware cost.

### System Architecture
```
[ vin.v test pattern ] ──> [ Caster EPDC core (rtl/) ] ──> [ E-ink Screen (Parallel I/F) ]
   (HDMI/DVI removed,            │
    phase 2 not started)         └── UART debug console (M11, 115200 8N1)
                                         GDCLK/SDLE/SDCE0, 16-bit bus, 2x upscale,
                                         all checked against spec every frame

[ XIAO PMIC Controller ] (TPS651851 / EE03 Board) ── independent of the FPGA;
   brings up the E-ink high-voltage rails (+/-15V, VGH/VGL, VCOM) on its own
```

> **Note on PMIC**: The E-ink high voltage rails (+/-15V, VGH/VGL, VCOM) come from
> the TPS651851 PMIC on a Seeed Studio *XIAO ePaper Display Board EE03*. Its I2C
> bus is **not** exposed on the XIAO's own I2C pins — schematic-confirmed, the
> PMIC's `SCL`/`SDA` sit on a separate bus that only the onboard IT8951 TCON
> masters. Driving the PMIC therefore means going through the TCON
> (see `xiao_pmic/`) — there is no way around it without soldering to test
> points. An earlier revision of this README reported that TCON as dead.
> **It was not.** The chip had been answering all along; the transport was
> skipping the HRDY wait the IT8951 requires after the read preamble, and an
> ungated read returns plausible garbage rather than zeros
> (`docs/PROGRESS.md` §1.19). With the wait in place the board sets VCOM,
> raises the rails and holds them — which is all the FPGA needs from it.
> Panel rendering through the TCON is confirmed on real hardware.
>
> The fallback, never used and no longer needed, is an external MCU wired to
> three PMIC test points (`ITE_I2C_SCL`/`SDA` at `TP42`/`TP43`, `WAKEUP`) plus
> a fourth pad (`VCOM_CTRL`) — no `PWRUP` wire, since the PMIC's `ENABLE`
> register has an `ACTIVE` bit that does the same job over I2C.

### Key Features
- **Ultra-Low Latency**: Frame processing delay < 20 µs (once DDR3 is wired up; see Verification Status).
- **Direct DVI/HDMI Input** *(phase 2, not started)*: the receiver has been taken out of the tree so the EPD output can be verified on its own. Pixels come from an internal test pattern (`rtl/vin.v`) until it is restored.
- **128MB DDR3 Framebuffer**: on-module DDR3 SDRAM; synthesis path is still a loopback stub, but the simulation path has a real behavioural memory model so pipeline logic (waveform LUT, dithering, greyscale) can be verified before the Gowin DDR3 IP is wired in.
- **Flexible Toolchain Support**: Works with official Gowin EDA as well as open-source toolchains (Yosys, nextpnr-himbaechel-gowin, Apicula).
- **Verilator Simulation**: Includes a full visualizer-based simulation workspace using C++ and SDL2.
- **UART Debug Console**: the Dock's onboard USB-UART (FT2232 channel B, `M11`, no extra wiring) streams one line per frame — control timing, 16-bit bus health, Hi-Z count, 2x upscale integrity (horizontal and vertical), frame rate — enough to bring up the board with nothing but a serial terminal.
- **Front Panel Safety Gate**: EPD bus stays silent at power-up; `BTN0` is a manual drive-enable gate, `BTN1`-`BTN4` step through patterns/modes/manual framing. `PMIC_READY` handshake was removed after it turned out to always read HIGH regardless of PMIC state — the front panel button replaced it as the actual safety check.

---

### Repository Structure
```
Glider_but_cheaper/
├── bin/                        # Precompiled bitstream binaries (glider_tang.fs)
├── constraints/                # Gowin CST pin constraint files
├── rtl/                        # FPGA Verilog HDL source files
│   ├── caster.v                 # Ported EPDC core (scan, pipeline, 2x upscale)
│   ├── top.v                    # Top level: resets, front panel, debug wiring
│   ├── vin.v                    # Internal test pattern generator (checker/ramp/stripe/white)
│   ├── epd_selftest.v           # Control-timing self-check (GDCLK/SDLE/SDCE0 vs spec)
│   ├── epd_sd_check.v           # SD data bus check (16-bit live, Hi-Z, 2x horizontal wiring)
│   ├── epd_line_dup.v           # Vertical 2x upscale check (CRC over line pairs)
│   ├── epd_verdict.v            # Folds the three checks above into one LED code
│   ├── debug_ctrl.v              # Front-panel buttons/LEDs, BTN0 drive-enable gate
│   ├── debug_uart.v / uart_tx.v # UART debug console (M11, one line/frame)
│   ├── mig_wrapper.v            # DDR3: synthesis stub / real memory model under SIMULATION
│   └── mulib/                   # Memory & sync utility primitives
├── sim/                         # Verilator + SDL2 visual simulation workspace
├── xiao_pmic/                   # Arduino sketch: EE03 as the PMIC (rails for the FPGA)
├── ee03_probe/                  # Arduino sketch: read-only survey of an EE03 board
├── docs/
│   ├── plan.md                  # Design plan: architecture, risks, milestones
│   ├── PROGRESS.md              # Session-by-session bring-up log and current status
│   ├── HANDOVER.md              # Session handover snapshot
│   ├── WIRING.md                # EE03 power harness, grounding, operating order
│   └── BREAKOUT_40P.md          # Panel pin 1..40 wiring sheet (EE03 vs FPGA)
├── Makefile                     # Main Makefile for building & flashing
├── glider_tang.gprj             # Gowin EDA Project file
├── LICENSE                      # CERN-OHL-P v2 License
└── README.md                    # Project documentation
```

> **Start here for current status**: `docs/PROGRESS.md` is the up-to-date record of what has been verified on real hardware and what hasn't. This README describes the design; `docs/PROGRESS.md` describes where the bring-up actually stands.

---

### Hardware Requirements
1. **Sipeed Tang Primer 20K Core Board & Dock Baseboard**
2. **E-ink Screen**: Parallel interface E-ink panel (project targets ED115OC1, 2760x2070, driven at 2x horizontal/vertical upscale — see `docs/plan.md` for why)
3. **PMIC Power Supply**: TPS651851 PMIC producing E-ink high voltages (+15V, -15V, VGH, VGL, VCOM). *(e.g., Seeed Studio XIAO ePaper EE03 board — its IT8951 TCON is the only verified path to the PMIC's I2C bus; see the PMIC note above)*
4. **PMIC Controller Board**: A Seeed XIAO (ESP32S3) on the EE03 board runs `xiao_pmic/`, which raises the rails and holds them. Should that TCON ever fail, an external 3.3V MCU wired to the PMIC's test points is the fallback (see PMIC note above) — untried, and not currently needed.

---

### Pin Mapping Guide (Dock Board PMOD Connectors)

> **Wire by ball name, not by pin number.** The dock's back-side silk prints a
> legend for every PMOD with the ball name next to each pad — four signal rows,
> then GND, then 3V3. Positions below are given as that legend reads
> (row 1–4, left/right column). Every assignment here was checked pad-by-pad
> against `constraints/gowin_constraints.cst` and a photo of the board on
> 2026-09-09: all 88 non-DDR pins match. An earlier revision quoted
> "PMODn pin k" numbers that do **not** line up with the legend — counting pins
> from those would have mis-wired the bus.
>
> ```
> PMOD0  T6|P6   R8|T7   T8|P8   P9|T9   GND|GND  3V3|3V3
> PMOD1  T11|P11 T12|R11 M14|M15 J14|J16 GND|GND  3V3|3V3
> PMOD2  D14|E15 B14|A15 B13|A14 B12|C12 GND|GND  3V3|3V3
> PMOD3  A11|B11 N6|D11  N9|N7   L9|N8   GND|GND  3V3|3V3
> ```

#### 1. EPD Parallel Control Interface (PMOD2)
| Signal Name | FPGA Pin | Description |
| :--- | :--- | :--- |
| **EPD_GDOE** | `B14` | Gate Driver Output Enable (PMOD2 row 2 left) |
| **EPD_GDCLK**| `A15` | Gate Driver Clock (PMOD2 row 2 right) |
| **EPD_GDSP** | `D14` | Gate Driver Start Pulse (PMOD2 row 1 left) |
| **EPD_SDCLK**| `E15` | Source Driver Clock (PMOD2 row 1 right) |
| **EPD_SDLE** | `B12` | Source Driver Latch Enable (PMOD2 row 4 left) |
| **EPD_SDOE** | `C12` | Source Driver Output Enable (PMOD2 row 4 right) |
| **EPD_SDCE0**| `B13` | Source Driver Chip Enable 0 (PMOD2 row 3 left) |

#### 2. EPD Parallel Data Interface (PMOD0 & PMOD1)
| Signal Name | FPGA Pin | Description |
| :--- | :--- | :--- |
| **EPD_SD[0]**| `T12` | Source Data Bit 0 (PMOD1 row 2 left) |
| **EPD_SD[1]**| `T11` | Source Data Bit 1 (PMOD1 row 1 left) |
| **EPD_SD[2]**| `P11` | Source Data Bit 2 (PMOD1 row 1 right) |
| **EPD_SD[3]**| `R11` | Source Data Bit 3 (PMOD1 row 2 right) |
| **EPD_SD[4]**| `M15` | Source Data Bit 4 (PMOD1 row 3 right) |
| **EPD_SD[5]**| `M14` | Source Data Bit 5 (PMOD1 row 3 left) |
| **EPD_SD[6]**| `J16` | Source Data Bit 6 (PMOD1 row 4 right) |
| **EPD_SD[7]**| `J14` | Source Data Bit 7 (PMOD1 row 4 left) |
| **EPD_SD[8]**| `R8`  | Source Data Bit 8 (PMOD0 row 2 left) |
| **EPD_SD[9]**| `T6`  | Source Data Bit 9 (PMOD0 row 1 left) |
| **EPD_SD[10]**| `P6` | Source Data Bit 10 (PMOD0 row 1 right) |
| **EPD_SD[11]**| `T7` | Source Data Bit 11 (PMOD0 row 2 right) |
| **EPD_SD[12]**| `P8` | Source Data Bit 12 (PMOD0 row 3 right) |
| **EPD_SD[13]**| `T8` | Source Data Bit 13 (PMOD0 row 3 left) |
| **EPD_SD[14]**| `T9` | Source Data Bit 14 (PMOD0 row 4 right) |
| **EPD_SD[15]**| `P9` | Source Data Bit 15 (PMOD0 row 4 left) |

#### 3. Status Output
| Signal Name | FPGA Pin | Direction | Description |
| :--- | :--- | :--- | :--- |
| **REFRESH_DONE**| `N9` | Output | High when the FPGA EPD scan is idle (refresh complete) |
| **UART_TX** | `M11` | Output | Debug console, 115200 8N1, one line/frame. Dock's onboard USB-UART, channel B — no extra wiring, shows up as a second serial port alongside the JTAG one. |

> `PMIC_READY` (previously `N7`) is gone. It was asserted unconditionally by the XIAO firmware at boot regardless of actual PMIC state, so the FPGA had no way to trust it. The front-panel `BTN0` safety gate replaced it: the EPD bus stays silent at power-up and only starts driving when a human presses the button, after checking rail voltages by hand.

#### 4. Front Panel (5 buttons, 6 LEDs, active low)
| Signal Name | FPGA Pin(s) | Description |
| :--- | :--- | :--- |
| **BTN_N[0..4]** | `T10` `T3` `T2` `D7` `C7` | BTN0 = drive-enable gate. BTN1 = manual frame step. BTN2 = pattern select. BTN3 (held) = mode select. BTN4 = FREERUN toggle. |
| **LED[0..5]** | `C13` `A13` `N16` `N14` `L14` `L16` | LED0 heartbeat, LED1 self-test verdict (see `epd_verdict.v`), LED2 drive-enable, LED3 FREERUN, LED5:4 pattern/mode index. |

#### 5. CSR SPI Host Interface (PMOD3, top two rows)
| Signal Name | FPGA Pin | Description |
| :--- | :--- | :--- |
| **SPI_CS**   | `N6`  | Chip Select (PMOD3 row 2 left) |
| **SPI_SCK**  | `D11` | SPI Clock (PMOD3 row 2 right) |
| **SPI_MOSI** | `A11` | Master Out Slave In (PMOD3 row 1 left) |
| **SPI_MISO** | `B11` | Master In Slave Out (PMOD3 row 1 right) |

#### 6. Panel Connector (40P-A) Wiring — FPGA signals + EE03 power rails

The panel side of the breakout follows the **Glider 40P-A pinout** (verified against
the J1 pad-net list of `pcb/40p-adapter-ab/adapter.kicad_pcb`; ED115OC1 is a 40P-A
panel). Power comes from the EE03 board's own 40-pin connector, and the two
power maps do line up: +15V is on **pin 36** on both, 37 is a no-connect on
both, and EE03's pin 40 reaches VCOM through `R60`. An earlier revision of this
README had 36 and 37 swapped — corrected against the PCB netlist
(`docs/PROGRESS.md` §1.18). The one difference is pin 34: NC on the panel, but
EE03 drives +3V3 there. Do not use it as a ground return.

| Panel pin | Signal | Source |
|--:| :--- | :--- |
| 1 | VGL (−20V) | EE03 pin 1 |
| 2 / 4 / 35 / 37 / 39 | NC | — (EE03 pin 37 is a no-connect too) |
| 34 | NC on the panel | ⚠️ EE03 drives **+3V3** here through `R121`. Not a ground return. |
| 3 | VGH (+22V) | EE03 pin 3 |
| 5 / 11 | +3V3 (source driver logic) | EE03 pins 5, 11 |
| 6 | GDOE (= panel MODE) | PMOD2 row 2 left (`B14`) |
| 7 | GDCLK (= CKV) | PMOD2 row 2 right (`A15`) |
| 8 | GDSP (= SPV) | PMOD2 row 1 left (`D14`) |
| 9 / 12 / 22 | GND | EE03 pins 9, 12, 22 — **common with FPGA GND**, several strands |
| 10 | VCOM | EE03 pin 10 |
| 13 | SDCLK (= XCL) | PMOD2 row 1 right (`E15`) |
| 14–21 | ED0–ED7 | PMOD1: EPD_SD[0..7] (`T12 T11 P11 R11 M15 M14 J16 J14`) |
| 23–30 | ED8–ED15 | PMOD0: EPD_SD[8..15] (`R8 T6 P6 T7 P8 T8 T9 P9`) |
| 31 | SDCE0 (= XSTL) | PMOD2 row 3 left (`B13`) |
| 32 | SDLE (= XLE) | PMOD2 row 4 left (`B12`) |
| 33 | SDOE (= XOE) | PMOD2 row 4 right (`C12`) |
| 36 | +VP (+15V) | EE03 pin 36 (`VDPS_OUT`, PCB netlist verified) |
| 38 | −VN (−15V) | EE03 pin 38 |
| 40 | tied to VCOM | EE03 pin 40 reaches VCOM through `R60` (0R, fitted) — same net |

> The panel FPC must never be plugged into the EE03 board itself **while the
> FPGA is connected** — its IT8951 drives the same bus. With the FPGA absent it
> is exactly how the panel was first lit, which is worth doing: it gives you a
> known-good rendering of your own panel to compare the FPGA's output against.
> Pin-by-pin sheet: **`docs/BREAKOUT_40P.md`**. Harness, grounding, operating
> order and protection notes: **`docs/WIRING.md`**.
> Firmware for the EE03 side: **`xiao_pmic/`**.

---

### Verification Status (see `docs/PROGRESS.md` for the full log)

Everything below has been checked against real hardware, not just simulation:

| Checked | Evidence |
| :--- | :--- |
| Control timing (GDCLK/SDLE/SDCE0) matches spec, frame after frame | UART: `G=787 S=787 A=096000 E=+000000`, 1200 consecutive frames identical |
| 16-bit source bus actually active (not stuck in 8-bit mode) | UART `U=ff`, both polarities driven |
| 2x horizontal upscale wiring intact, every active cycle | UART `D=0000` over 614,400 cycles/frame |
| 2x vertical upscale (line-buffer based) intact | UART `V=0000 L=03c0` — 960 line pairs, CRC-matched |
| No Hi-Z (`2'b11`) ever driven onto the source bus | UART `Z=0000` |
| Clock is actually 40.5 MHz, not just self-consistent counts | Frame-rate measured at 59.96 fps over 20s → 40.472 MHz implied, -0.07% |
| Pattern/mode switching reaches the output stage | `FAST_GREY` mode produces a distinct `U=55` bus signature vs. `U=ff`/`00` for other modes |
| `make demo` (PANEL_TEST, DDR3-free bring-up path) | Passes the same checks: `U=ff Z=0 D=0 V=0 L=960` |
| Bitstream built from source in this repo runs on real hardware | P&R + `openFPGALoader`, self-test clean across 1203 consecutive frames |
| Frame rate is 60.00 fps | One UART line per frame (`DECIMATE=1`), 1203 lines in 20.05 s |
| IT8951 TCON alive and addressable | HRDY releases 1605 ms after reset, `GET_DEV_INFO` returns 1872x1404, FW `Seeed_v.0.1`, LUT `3M29T` |
| PMIC rails come up, and stay up | Measured at the test points. They persist for as long as the TCON is left in SYS_RUN, so the board can hold power for the FPGA |
| Rail values are inside the panel's operating range | The ED115OC1 renders when driven by the EE03's own TCON — see `xiao_pmic/` |
| VCOM is volatile and must be rewritten every power-up | Reads back 2500 mV after every reset; written to 1310 mV and verified before anything drives the glass |

**Not yet verified**: actual pixel content on the SD bus (checks above are structural, not content), panel SDCLK ceiling (no public datasheet for the target panel — see `docs/plan.md`), the FPGA driving the panel at all (the harness in `docs/WIRING.md` is not built yet), and anything past the FPGA — DDR3 hardware path and HDMI input are both phase 2, not started.

---

### How to Use

#### Method A: Quick Start (Flash Precompiled Binary)
Flash the included precompiled bitstream (`bin/glider_tang.fs`) using `openFPGALoader`:

- **Load to SRAM (Temporary)**:
  ```bash
  make program_bin
  ```
- **Flash to Board (Permanent Boot)**:
  ```bash
  make flash_bin
  ```

#### Method B: Build from Source (Open-Source Toolchain)
1. Install toolchain:
   - **Synthesis**: [Yosys](https://github.com/YosysHQ/yosys)
   - **Place & Route**: [nextpnr-himbaechel-gowin](https://github.com/YosysHQ/nextpnr)
   - **Bitstream Pack**: [Apicula (gowin_pack)](https://github.com/YosysHQ/apicula)
   - **Flashing**: [openFPGALoader](https://github.com/trabucayrog/openFPGALoader)
2. Build bitstream:
   ```bash
   make
   ```
3. Load or flash design:
   ```bash
   make program   # load to SRAM
   make flash     # write to internal flash
   ```

#### Method C: Gowin EDA IDE
1. Open Gowin EDA.
2. Load project file `glider_tang.gprj`.
3. Run Synthesis and Place & Route.
4. Program device using Gowin Programmer.

#### Method D: Verilator Simulation
1. Install **Verilator** and **SDL2**.
2. Run simulation from root directory:
   ```bash
   make simulation
   ```
   Or build & execute inside `sim/`:
   ```bash
   cd sim
   make
   ./sim
   ```

---

## 한국어 (Korean)

### 개요
**Glider but Cheaper**는 오픈소스 초저지연 E-ink 모니터 컨트롤러 **Glider**를 **Sipeed Tang Primer 20K** FPGA 보드로 이식하여 제작 비용을 획기적으로 낮춘 프로젝트입니다.

오리지널 Glider 보드는 Xilinx Spartan-6 LX16 FPGA, 외부 DDR3 메모리, STM32H750 MCU를 사용하여 상대적으로 부품 구하기가 어렵고 자작 비용이 높았습니다. 이 프로젝트는 시중에서 쉽게 구할 수 있고 저렴한 **Tang Primer 20K** (Gowin GW2A-LV18PG256C8/I7 FPGA + 온모듈 128MB DDR3 포함)를 활용하여 초저지연 E-ink 디스플레이 컨트롤러를 경제적으로 자작할 수 있도록 돕습니다.

### 시스템 구성도
```
[ vin.v 내부 테스트 패턴 ] ──> [ Caster EPDC 코어 (rtl/) ] ──> [ E-ink 화면 (병렬 I/F) ]
   (HDMI/DVI 제거됨,                 │
    2단계 미착수)                    └── UART 디버그 콘솔 (M11, 115200 8N1)
                                         GDCLK/SDLE/SDCE0, 16비트 버스, 2배 확대를
                                         매 프레임 사양과 대조해 실물 검증됨

[ XIAO PMIC 컨트롤러 ] (TPS651851 / EE03 보드) ── FPGA와 독립적으로 동작하며
   E-ink 구동용 고전압(+/-15V, VGH/VGL, VCOM)을 자체적으로 기동한다
```

> **PMIC 전원부 참고**: E-ink 구동용 고전압(+/-15V, VGH/VGL, VCOM)은 Seeed Studio
> *XIAO ePaper Display Board EE03*의 TPS651851 PMIC에서 나온다. 회로도로 확인한
> 결과 **PMIC의 I2C 버스는 XIAO 자신의 I2C 핀에 노출되어 있지 않다** — PMIC의
> SCL/SDA는 온보드 IT8951 TCON이 마스터인 별도 버스에 있다. 따라서 PMIC를
> 제어하려면 TCON을 거쳐야 하고(`xiao_pmic/`),
> 테스트포인트에 직접 납땜하지 않는 이상 다른 경로가 없다. 이 README의 이전
> 판본은 그 TCON이 죽었다고 적었다. **아니었다.** 칩은 계속 응답하고 있었고,
> 원인은 IT8951이 read preamble 뒤에 요구하는 HRDY 대기를 전송 코드가 건너뛴
> 것이었다. 게이팅 없는 읽기는 0이 아니라 **그럴듯한 쓰레기**를 준다
> (`docs/PROGRESS.md` §1.19). 대기를 넣자 VCOM 설정도, 레일 기동·유지도 된다 —
> FPGA가 이 보드에 원하는 건 그게 전부다.
>
> 아직 쓰지 않았고 이제 필요도 없어진 대안은, 외부 MCU를 PMIC 테스트포인트
> 3개(`ITE_I2C_SCL`/`SDA` = `TP42`/`TP43`, `WAKEUP`)와 저항 패드 1개
> (`VCOM_CTRL`)에 직결하는 것이다. `PWRUP` 배선은 필요 없다 — PMIC의 `ENABLE`
> 레지스터에 `ACTIVE` 비트가 있어서 I2C로 같은 일을 할 수 있다.

### 주요 특징
- **초저지연 디스플레이**: 20 µs 미만의 신호 처리 지연시간 구현 (DDR3 연결 후 — 검증 현황 참고).
- **직접 DVI/HDMI 입력** *(2단계, 미착수)*: EPD 출력 검증에 집중하기 위해 수신부를 트리에서 제거했다. 복원 전까지 픽셀은 내부 테스트 패턴(`rtl/vin.v`)에서 나온다.
- **128MB DDR3 프레임버퍼**: 온모듈 DDR3 SDRAM. 합성 경로는 아직 루프백 스텁이지만, 시뮬레이션 경로는 실제 메모리 모델을 갖고 있어 Gowin DDR3 IP를 붙이기 전에도 파이프라인 로직(웨이브폼 LUT, 디더링, 그레이스케일)을 검증할 수 있다.
- **다양한 툴체인 지원**: 공식 Gowin EDA IDE 및 오픈소스 툴체인(Yosys, nextpnr-himbaechel-gowin, Apicula) 호환.
- **Verilator 시뮬레이터 동봉**: C++ 및 SDL2 기반 화면 갱신 시각화 시뮬레이션 환경 제공.
- **UART 디버그 콘솔**: Dock 보드의 온보드 USB-UART(FT2232 채널 B, `M11`, 추가 배선 불필요)로 프레임마다 한 줄씩 — 제어 타이밍, 16비트 버스 상태, Hi-Z 카운트, 2배 확대 무결성(가로·세로), 프레임레이트까지 시리얼 터미널 하나로 브링업이 가능하다.
- **프론트 패널 안전 게이트**: 전원 인가 직후 EPD 버스는 조용하고, `BTN0`이 수동 구동 게이트다. `BTN1`~`BTN4`로 패턴/모드/수동 프레임 전환. `PMIC_READY` 핸드셰이크는 PMIC 상태와 무관하게 항상 HIGH로 뜨는 거짓 신호였다는 게 드러나 제거했고, 사람이 전압을 확인하고 누르는 프론트 패널 버튼이 실질적인 안전장치를 대신한다.

---

### 디렉토리 구조
```
Glider_but_cheaper/
├── bin/                         # 미리 컴파일된 비트스트림 바이너리 (glider_tang.fs)
├── constraints/                 # Gowin CST 핀 맵핑 핀제약 파일
├── rtl/                         # FPGA Verilog HDL 하드웨어 소스코드
│   ├── caster.v                  # 이식된 EPDC 코어 (스캔·파이프라인·2배 확대)
│   ├── top.v                     # 최상위: 리셋 시퀀서, 프론트 패널, 디버그 배선
│   ├── vin.v                     # 내부 테스트 패턴 생성기 (체커보드/램프/줄무늬/백색)
│   ├── epd_selftest.v            # 제어 타이밍 자체 검증 (GDCLK/SDLE/SDCE0 vs 사양)
│   ├── epd_sd_check.v            # SD 데이터 버스 검증 (16비트 실효·Hi-Z·가로 2배 배선)
│   ├── epd_line_dup.v            # 세로 2배 확대 검증 (라인 쌍 CRC 서명 비교)
│   ├── epd_verdict.v             # 위 세 검사를 LED 코드 하나로 통합
│   ├── debug_ctrl.v               # 프론트 패널 버튼/LED, BTN0 구동 게이트
│   ├── debug_uart.v / uart_tx.v  # UART 디버그 콘솔 (M11, 프레임당 한 줄)
│   ├── mig_wrapper.v             # DDR3: 합성용 스텁 / SIMULATION 시 실제 메모리 모델
│   └── mulib/                    # 메모리 및 동기화 유틸리티 모듈
├── sim/                          # Verilator + SDL2 시각 시뮬레이션 워크스페이스
├── xiao_pmic/                    # EE03를 PMIC로 쓰는 아두이노 스케치 (FPGA용 레일 유지)
├── ee03_probe/                   # EE03 보드를 읽기 전용으로 진단하는 아두이노 스케치
├── docs/
│   ├── plan.md                   # 설계 계획서: 아키텍처, 리스크, 마일스톤
│   ├── PROGRESS.md               # 세션별 브링업 기록과 현재 상태
│   ├── HANDOVER.md               # 세션 인수인계 스냅샷
│   ├── WIRING.md                 # EE03 전원 하니스 · 접지 · 운용 순서
│   └── BREAKOUT_40P.md           # 패널 1~40번 핀 배선 시트 (EE03 / FPGA 구분)
├── Makefile                      # 전체 프로젝트 빌드 및 업로드 메인 Makefile
├── glider_tang.gprj              # Gowin EDA 프로젝트 파일
├── LICENSE                       # CERN-OHL-P v2 라이선스
└── README.md                     # 프로젝트 문서
```

> **현재 상태는 `docs/PROGRESS.md`부터 보세요**: 실물 하드웨어로 검증된 것과 아직 안 된
> 것이 최신 상태로 기록돼 있습니다. 이 README는 설계를 설명하고,
> `docs/PROGRESS.md`는 브링업이 실제로 어디까지 왔는지 설명합니다.

---

### 하드웨어 준비물
1. **Sipeed Tang Primer 20K Core Board & Dock Baseboard**
2. **E-ink 스크린**: 병렬 인터페이스 지원 EPD 패널 (프로젝트 목표는 ED115OC1, 2760x2070, 가로·세로 2배 확대 구동 — 이유는 `docs/plan.md` 참고)
3. **PMIC 전원 모듈**: TPS651851 기반 E-ink 고전압(+15V, -15V, VGH, VGL, VCOM) 생성 모듈 *(예: Seeed Studio XIAO ePaper EE03 보드 — 그 보드의 IT8951 TCON이 PMIC의 I2C 버스에 접근하는 유일한 검증된 경로다. 위 PMIC 참고 항목 확인)*
4. **PMIC 제어용 MCU**: EE03 위의 Seeed XIAO(ESP32S3)가 `xiao_pmic/`를 실행해 레일을 올리고 유지한다. 혹시 그 TCON이 고장 나면 PMIC 테스트포인트에 직결한 별도 3.3V MCU가 대안이다(위 PMIC 참고 항목) — 아직 써본 적 없고, 지금은 필요도 없다.

---

### 핀 맵핑 가이드 (Dock 보드 PMOD 커넥터 연결)

> **핀 번호가 아니라 볼 이름으로 배선할 것.** 도크 뒷면 실크에 PMOD별 legend가
> 인쇄돼 있고 패드마다 볼 이름이 적혀 있다 — 신호 4행, 그 다음 GND, 3V3 순이다.
> 아래 위치는 그 legend 기준(1~4행, 좌/우 열)이다. 2026-09-09에 보드 실물 사진과
> `constraints/gowin_constraints.cst`를 패드 단위로 전수 대조했고, **비-DDR 88핀
> 전부 일치**한다. 이전 판본이 적어둔 "PMODn pin k" 번호는 legend와 **맞지 않는다** —
> 그 번호를 세서 배선했다면 버스를 잘못 꽂았을 것이다.
>
> ```
> PMOD0  T6|P6   R8|T7   T8|P8   P9|T9   GND|GND  3V3|3V3
> PMOD1  T11|P11 T12|R11 M14|M15 J14|J16 GND|GND  3V3|3V3
> PMOD2  D14|E15 B14|A15 B13|A14 B12|C12 GND|GND  3V3|3V3
> PMOD3  A11|B11 N6|D11  N9|N7   L9|N8   GND|GND  3V3|3V3
> ```

#### 1. EPD 병렬 제어 인터페이스 (PMOD2)
| 신호 이름 | FPGA 핀번호 | 설명 |
| :--- | :--- | :--- |
| **EPD_GDOE** | `B14` | Gate Driver Output Enable (PMOD2 row 2 left) |
| **EPD_GDCLK**| `A15` | Gate Driver Clock (PMOD2 row 2 right) |
| **EPD_GDSP** | `D14` | Gate Driver Start Pulse (PMOD2 row 1 left) |
| **EPD_SDCLK**| `E15` | Source Driver Clock (PMOD2 row 1 right) |
| **EPD_SDLE** | `B12` | Source Driver Latch Enable (PMOD2 row 4 left) |
| **EPD_SDOE** | `C12` | Source Driver Output Enable (PMOD2 row 4 right) |
| **EPD_SDCE0**| `B13` | Source Driver Chip Enable 0 (PMOD2 row 3 left) |

#### 2. EPD 병렬 데이터 인터페이스 (PMOD0 & PMOD1)
| 신호 이름 | FPGA 핀번호 | 설명 |
| :--- | :--- | :--- |
| **EPD_SD[0]**| `T12` | Source Data Bit 0 (PMOD1 row 2 left) |
| **EPD_SD[1]**| `T11` | Source Data Bit 1 (PMOD1 row 1 left) |
| **EPD_SD[2]**| `P11` | Source Data Bit 2 (PMOD1 row 1 right) |
| **EPD_SD[3]**| `R11` | Source Data Bit 3 (PMOD1 row 2 right) |
| **EPD_SD[4]**| `M15` | Source Data Bit 4 (PMOD1 row 3 right) |
| **EPD_SD[5]**| `M14` | Source Data Bit 5 (PMOD1 row 3 left) |
| **EPD_SD[6]**| `J16` | Source Data Bit 6 (PMOD1 row 4 right) |
| **EPD_SD[7]**| `J14` | Source Data Bit 7 (PMOD1 row 4 left) |
| **EPD_SD[8]**| `R8`  | Source Data Bit 8 (PMOD0 row 2 left) |
| **EPD_SD[9]**| `T6`  | Source Data Bit 9 (PMOD0 row 1 left) |
| **EPD_SD[10]**| `P6` | Source Data Bit 10 (PMOD0 row 1 right) |
| **EPD_SD[11]**| `T7` | Source Data Bit 11 (PMOD0 row 2 right) |
| **EPD_SD[12]**| `P8` | Source Data Bit 12 (PMOD0 row 3 right) |
| **EPD_SD[13]**| `T8` | Source Data Bit 13 (PMOD0 row 3 left) |
| **EPD_SD[14]**| `T9` | Source Data Bit 14 (PMOD0 row 4 right) |
| **EPD_SD[15]**| `P9` | Source Data Bit 15 (PMOD0 row 4 left) |

#### 3. 상태 출력
| 신호 이름 | FPGA 핀번호 | 방향 | 설명 |
| :--- | :--- | :--- | :--- |
| **REFRESH_DONE**| `N9` | 출력 | High일 때 FPGA의 EPD 스캔이 완료되어 유휴 상태임을 의미 |
| **UART_TX** | `M11` | 출력 | 디버그 콘솔, 115200 8N1, 프레임당 한 줄. Dock의 온보드 USB-UART 채널 B — 추가 배선 없이 JTAG용 포트 옆에 두 번째 시리얼 포트로 나타난다. |

> `PMIC_READY`(기존 `N7`)는 제거됐다. XIAO 펌웨어가 실제 PMIC 상태와 무관하게
> 부팅 시 무조건 HIGH로 올렸기 때문에 FPGA가 이 신호를 신뢰할 방법이 없었다.
> 프론트 패널의 `BTN0` 안전 게이트가 그 자리를 대신한다 — 전원 인가 직후
> EPD 버스는 조용하고, 사람이 전압을 손으로 확인한 뒤 버튼을 눌러야 구동이
> 시작된다.

#### 4. 프론트 패널 (버튼 5개, LED 6개, 액티브 로우)
| 신호 이름 | FPGA 핀번호 | 설명 |
| :--- | :--- | :--- |
| **BTN_N[0..4]** | `T10` `T3` `T2` `D7` `C7` | BTN0=구동 게이트, BTN1=수동 프레임 스텝, BTN2=패턴 선택, BTN3(홀드)=모드 선택, BTN4=FREERUN 토글 |
| **LED[0..5]** | `C13` `A13` `N16` `N14` `L14` `L16` | LED0 하트비트, LED1 셀프테스트 판정(`epd_verdict.v` 참고), LED2 구동 게이트, LED3 FREERUN, LED5:4 패턴/모드 인덱스 |

#### 5. CSR SPI 통신 인터페이스 (PMOD3 상단 두 행)
| 신호 이름 | FPGA 핀번호 | 설명 |
| :--- | :--- | :--- |
| **SPI_CS**   | `N6`  | Chip Select (PMOD3 row 2 left) |
| **SPI_SCK**  | `D11` | SPI Clock (PMOD3 row 2 right) |
| **SPI_MOSI** | `A11` | Master Out Slave In (PMOD3 row 1 left) |
| **SPI_MISO** | `B11` | Master In Slave Out (PMOD3 row 1 right) |

#### 6. 패널 커넥터(40P-A) 배선 — FPGA 신호 + EE03 전원

브레이크아웃의 패널 측은 **Glider 40P-A 핀맵**을 따른다
(`pcb/40p-adapter-ab/adapter.kicad_pcb` J1 패드-넷 리스트로 검증. ED115OC1은 40P-A).
전원은 EE03 보드의 40핀 커넥터에서 가져오고, **전원 핀맵은 서로 일치한다** —
+15V는 양쪽 다 **36번**, 37번은 양쪽 다 NC, EE03의 40번도 `R60`(0R) 경유로 VCOM에
닿는다. 이 README의 이전 판본은 36과 37을 뒤바꿔 적었다 — PCB 넷리스트로 정정했다
(`docs/PROGRESS.md` §1.18). 유일한 차이는 34번이다: 패널은 NC인데 EE03는 여기에
+3V3을 준다. **접지 리턴으로 쓰지 말 것.**

| 패널 핀 | 신호 | 연결처 |
|--:| :--- | :--- |
| 1 | VGL (−20V) | EE03 핀 1 |
| 2 / 4 / 35 / 37 / 39 | NC | — (EE03도 37번은 NC) |
| 34 | 패널쪽 NC | ⚠️ EE03는 `R121` 경유로 여기에 **+3V3**을 준다. 접지 리턴 금지 |
| 3 | VGH (+22V) | EE03 핀 3 |
| 5 / 11 | +3V3 (소스드라이버 로직) | EE03 핀 5, 11 |
| 6 | GDOE (=패널 MODE) | PMOD2 2행 좌 (`B14`) |
| 7 | GDCLK (=CKV) | PMOD2 2행 우 (`A15`) |
| 8 | GDSP (=SPV) | PMOD2 1행 좌 (`D14`) |
| 9 / 12 / 22 | GND | EE03 핀 9, 12, 22 — **FPGA GND와 공통 필수**, 여러 가닥으로 |
| 10 | VCOM | EE03 핀 10 |
| 13 | SDCLK (=XCL) | PMOD2 1행 우 (`E15`) |
| 14–21 | ED0–ED7 | PMOD1: EPD_SD[0..7] (`T12 T11 P11 R11 M15 M14 J16 J14`) |
| 23–30 | ED8–ED15 | PMOD0: EPD_SD[8..15] (`R8 T6 P6 T7 P8 T8 T9 P9`) |
| 31 | SDCE0 (=XSTL) | PMOD2 3행 좌 (`B13`) |
| 32 | SDLE (=XLE) | PMOD2 4행 좌 (`B12`) |
| 33 | SDOE (=XOE) | PMOD2 4행 우 (`C12`) |
| 36 | +VP (+15V) | EE03 핀 36 (`VDPS_OUT`, PCB 넷리스트 검증) |
| 38 | −VN (−15V) | EE03 핀 38 |
| 40 | VCOM에 결선 | EE03 핀 40도 `R60`(0R, 실장) 경유 VCOM — 같은 넷 |

> **FPGA가 연결된 상태에서는** 패널 FPC를 EE03 보드에 직접 꽂지 말 것 — 보드의
> IT8951이 같은 버스를 구동한다. FPGA가 없을 때는 오히려 그렇게 첫 점등을 했고,
> 해볼 가치가 있다: 내 패널의 정상 렌더링을 확보해 두면 나중에 FPGA 출력과
> 비교할 기준이 된다. 핀별 배선 시트는 **`docs/BREAKOUT_40P.md`**,
> 하니스·접지·운용 순서·보호 회로는 **`docs/WIRING.md`**,
> EE03 쪽 펌웨어는 **`xiao_pmic/`**.

---

### 검증 현황 (전체 기록은 `docs/PROGRESS.md` 참고)

아래는 시뮬레이션이 아니라 **실물 하드웨어로 확인된 것들**이다:

| 확인됨 | 근거 |
| :--- | :--- |
| 제어 타이밍(GDCLK/SDLE/SDCE0)이 매 프레임 사양과 일치 | UART: `G=787 S=787 A=096000 E=+000000`, 1200프레임 연속 동일 |
| 16비트 소스 버스가 실제로 살아있음 (8비트로 굳지 않음) | UART `U=ff`, 양쪽 극성 다 구동됨 |
| 가로 2배 확대 배선이 매 액티브 사이클마다 무결 | UART `D=0000`, 프레임당 614,400 사이클 |
| 세로 2배 확대(라인버퍼 방식)가 무결 | UART `V=0000 L=03c0` — 960 라인 쌍, CRC 일치 |
| Hi-Z(`2'b11`)가 소스 버스에 한 번도 안 실림 | UART `Z=0000` |
| 클럭이 카운트 상대값이 아니라 실제로 40.5 MHz | 20초간 프레임레이트 실측 59.96 fps → 역산 40.472 MHz, 편차 −0.07% |
| 패턴/모드 전환이 출력단까지 도달함 | `FAST_GREY` 모드에서 `U=55`라는 고유 서명, 다른 모드의 `U=ff`/`00`와 구분됨 |
| `make demo`(PANEL_TEST, DDR3 없이 가는 브링업 경로) | 위와 동일 검사 통과: `U=ff Z=0 D=0 V=0 L=960` |

| 이 저장소에서 소스로 빌드한 비트스트림이 실물에서 동작 | P&R + `openFPGALoader`, 1203프레임 연속 셀프테스트 무결 |
| 프레임레이트 60.00 fps | 프레임마다 UART 한 줄(`DECIMATE=1`), 20.05초에 1203줄 |
| IT8951 TCON이 살아 있고 응답함 | 리셋 후 1605 ms에 HRDY 해제, `GET_DEV_INFO`가 1872×1404 / FW `Seeed_v.0.1` / LUT `3M29T` 반환 |
| PMIC 레일이 올라오고, **유지된다** | 테스트포인트 실측. TCON을 SYS_RUN에 두는 한 계속 살아 있어서 FPGA용 전원으로 붙들어 둘 수 있다 |
| 레일 값이 패널 동작 범위 안 | EE03 자체 TCON으로 구동했을 때 ED115OC1이 실제로 그려진다 — `xiao_pmic/` 참고 |
| VCOM은 휘발성이라 매 파워업마다 다시 써야 함 | 리셋할 때마다 2500 mV로 돌아옴. 1310 mV로 쓰고 검증한 뒤에만 유리에 전압을 건다 |

**아직 검증 안 된 것**: SD 버스에 실린 실제 픽셀 값(위 검사들은 전부 구조적 성질만 봄, 내용은 안 봄), 패널 SDCLK 상한(대상 패널 데이터시트 공개본 없음 — `docs/plan.md` 참고), **FPGA가 패널을 실제로 구동하는 것**(`docs/WIRING.md`의 하니스가 아직 안 만들어졌다), FPGA 이후 전부 — DDR3 하드웨어 경로와 HDMI 입력은 둘 다 2단계, 아직 착수 전.

---

### 사용 방법

#### 방법 A: 빠른 시작 (미리 빌드된 파일 업로드)
`openFPGALoader`를 설치 후 미리 컴파일된 비트스트림(`bin/glider_tang.fs`)을 보드에 주입합니다:

- **RAM에 임시 다운로드**:
  ```bash
  make program_bin
  ```
- **내장 플래시 메모리에 영구 업로드**:
  ```bash
  make flash_bin
  ```

#### 방법 B: 오픈소스 툴체인 소스 컴파일
1. 오픈소스 Gowin 툴체인 설치:
   - **합성**: [Yosys](https://github.com/YosysHQ/yosys)
   - **배치배선**: [nextpnr-himbaechel-gowin](https://github.com/YosysHQ/nextpnr)
   - **비트스트림 패키징**: [Apicula (gowin_pack)](https://github.com/YosysHQ/apicula)
   - **다운로더**: [openFPGALoader](https://github.com/trabucayrog/openFPGALoader)
2. 소스코드 빌드:
   ```bash
   make
   ```
3. 보드에 업로드:
   ```bash
   make program   # RAM 쓰기
   make flash     # 플래시 영구 쓰기
   ```

#### 방법 C: Gowin EDA IDE 이용
1. Gowin EDA 실행 후 `glider_tang.gprj` 프로젝트 열기.
2. Synthesis 및 Place & Route 실행.
3. Gowin Programmer를 통해 보드에 비트스트림 다운로드.

#### 방법 D: Verilator 시뮬레이션 실행
1. **Verilator** 및 **SDL2** 라이브러리 설치.
2. 루트 디렉토리에서 시뮬레이션 실행:
   ```bash
   make simulation
   ```
   또는 `sim/` 디렉토리로 이동하여 실행:
   ```bash
   cd sim
   make
   ./sim
   ```

---

## References & License
- **Original Glider Design** by Wenting Zhang: [Glider GitHub](https://github.com/zephray/Glider)
- **Caster EPDC Core**: [Caster GitLab](https://gitlab.com/zephray/Caster/)
- **License**: CERN-OHL-P v2 (Open-Source Hardware License)
