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
[ HDMI Source ] ──(HDMI/DVI)──> [ Tang Primer 20K Dock ] ──> [ E-ink Screen (Parallel I/F) ]
                                    │             │
                                    └───(DDR3)────┘
                                   (Framebuffer)
                                          ▲
                                          │ Handshake (PMIC_READY / REFRESH_DONE)
                                          ▼
                             [ XIAO PMIC Controller ] (TPS65185 / EE03 Board)
```

> **Note on PMIC**: For E-ink high voltage rails (+/-15V, VGH/VGL, VCOM), you can salvage the PMIC portion of the Seeed Studio *XIAO ePaper Display Board EE03* by bypassing its onboard IT8951 TCON chip and using only its TPS65185 PMIC circuitry controlled via I2C.

### Key Features
- **Ultra-Low Latency**: Frame processing delay < 20 µs.
- **Direct DVI/HDMI Input**: HDMI video input processed directly via onboard microHDMI port.
- **128MB DDR3 Framebuffer**: Utilizes on-module DDR3 SDRAM for high-frame-rate rendering.
- **Flexible Toolchain Support**: Works with official Gowin EDA as well as open-source toolchains (Yosys, nextpnr-himbaechel-gowin, Apicula).
- **Verilator Simulation**: Includes a full visualizer-based simulation workspace using C++ and SDL2.
- **PMIC Handshake**: Hardware handshake interface between FPGA and external PMIC controller for safe power-sequencing.

---

### Repository Structure
```
Glider_but_cheaper/
├── bin/                        # Precompiled bitstream binaries (glider_tang.fs)
├── constraints/                # Gowin CST pin constraint files
├── rtl/                        # FPGA Verilog HDL source files
│   └── mulib/                  # Memory & sync utility primitives
├── sim/                        # Verilator + SDL2 visual simulation workspace
├── xiao_pmic_controller/       # Arduino source code for XIAO PMIC controller
├── Makefile                    # Main Makefile for building & flashing
├── glider_tang.gprj            # Gowin EDA Project file
├── LICENSE                     # CERN-OHL-P v2 License
└── README.md                   # Project documentation
```

---

### Hardware Requirements
1. **Sipeed Tang Primer 20K Core Board & Dock Baseboard**
2. **E-ink Screen**: Parallel interface E-ink panel (e.g., ED133UT2, ED060XH2, etc.)
3. **PMIC Power Supply**: TPS65185 PMIC module producing E-ink high voltages (+15V, -15V, VGH, VGL, VCOM). *(e.g., Seeed Studio XIAO ePaper EE03 board with TCON bypassed)*
4. **PMIC Controller Board**: Seeed XIAO (e.g., ESP32S3 or SAMD21) for PMIC initialization and handshake management.

---

### Pin Mapping Guide (Dock Board PMOD Connectors)

#### 1. EPD Parallel Control Interface (PMOD2)
| Signal Name | FPGA Pin | Description |
| :--- | :--- | :--- |
| **EPD_GDOE** | `B14` | Gate Driver Output Enable (PMOD2 Pin 3) |
| **EPD_GDCLK**| `A15` | Gate Driver Clock (PMOD2 Pin 4) |
| **EPD_GDSP** | `D14` | Gate Driver Start Pulse (PMOD2 Pin 1) |
| **EPD_SDCLK**| `E15` | Source Driver Clock (PMOD2 Pin 2) |
| **EPD_SDLE** | `B12` | Source Driver Latch Enable (PMOD2 Pin 9) |
| **EPD_SDOE** | `C12` | Source Driver Output Enable (PMOD2 Pin 10) |
| **EPD_SDCE0**| `B13` | Source Driver Chip Enable 0 (PMOD2 Pin 7) |

#### 2. EPD Parallel Data Interface (PMOD0 & PMOD1)
| Signal Name | FPGA Pin | Description |
| :--- | :--- | :--- |
| **EPD_SD[0]**| `T12` | Source Data Bit 0 (PMOD1 Pin 3) |
| **EPD_SD[1]**| `T11` | Source Data Bit 1 (PMOD1 Pin 1) |
| **EPD_SD[2]**| `P11` | Source Data Bit 2 (PMOD1 Pin 2) |
| **EPD_SD[3]**| `R11` | Source Data Bit 3 (PMOD1 Pin 4) |
| **EPD_SD[4]**| `M15` | Source Data Bit 4 (PMOD1 Pin 8) |
| **EPD_SD[5]**| `M14` | Source Data Bit 5 (PMOD1 Pin 7) |
| **EPD_SD[6]**| `J16` | Source Data Bit 6 (PMOD1 Pin 10) |
| **EPD_SD[7]**| `J14` | Source Data Bit 7 (PMOD1 Pin 9) |
| **EPD_SD[8]**| `R8`  | Source Data Bit 8 (PMOD0 Pin 3) |
| **EPD_SD[9]**| `T6`  | Source Data Bit 9 (PMOD0 Pin 1) |
| **EPD_SD[10]**| `P6` | Source Data Bit 10 (PMOD0 Pin 2) |
| **EPD_SD[11]**| `T7` | Source Data Bit 11 (PMOD0 Pin 4) |
| **EPD_SD[12]**| `P8` | Source Data Bit 12 (PMOD0 Pin 8) |
| **EPD_SD[13]**| `T8` | Source Data Bit 13 (PMOD0 Pin 7) |
| **EPD_SD[14]**| `T9` | Source Data Bit 14 (PMOD0 Pin 10) |
| **EPD_SD[15]**| `P9` | Source Data Bit 15 (PMOD0 Pin 9) |

#### 3. FPGA-to-PMIC Handshake Interface (PMOD3 Pins 7, 8)
| Signal Name | FPGA Pin | Direction | Description |
| :--- | :--- | :--- | :--- |
| **PMIC_READY** | `N7`  | Input | High indicates PMIC high voltage rails (+/-15V) are stable |
| **REFRESH_DONE**| `N9` | Output | High indicates FPGA EPD scan is idle (refresh complete) |

#### 4. CSR SPI Host Interface (PMOD3 Pins 1, 2, 3, 4)
| Signal Name | FPGA Pin | Description |
| :--- | :--- | :--- |
| **SPI_CS**   | `N6`  | Chip Select (PMOD3 Pin 3) |
| **SPI_SCK**  | `D11` | SPI Clock (PMOD3 Pin 4) |
| **SPI_MOSI** | `A11` | Master Out Slave In (PMOD3 Pin 1) |
| **SPI_MISO** | `B11` | Master In Slave Out (PMOD3 Pin 2) |

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
[ HDMI 영상 입력 ] ──(HDMI/DVI)──> [ Tang Primer 20K Dock ] ──> [ E-ink 화면 (병렬 I/F) ]
                                         │             │
                                         └───(DDR3)────┘
                                        (프레임버퍼)
                                               ▲
                                               │ 핸드셰이크 (PMIC_READY / REFRESH_DONE)
                                               ▼
                                 [ XIAO PMIC 컨트롤러 ] (TPS65185 / EE03 보드)
```

> **PMIC 전원부 참고**: E-ink 구동용 고전압(+/-15V, VGH/VGL, VCOM)은 Seeed Studio의 *XIAO ePaper Display Board EE03* 모듈 내장 IT8951 TCON 칩을 우회(Bypass)하고, TPS65185 PMIC 회로 부분만 I2C 제어를 통해 활용할 수 있습니다.

### 주요 특징
- **초저지연 디스플레이**: 20 µs 미만의 신호 처리 지연시간 구현.
- **직접 DVI/HDMI 입력**: Tang Primer 20K Dock 보드의 내장 microHDMI 커넥터 지원.
- **128MB DDR3 프레임버퍼**: Core 보드 탑재 128MB DDR3 SDRAM을 활용한 고속 프레임 버퍼링.
- **다양한 툴체인 지원**: 공식 Gowin EDA IDE 및 오픈소스 툴체인(Yosys, nextpnr-himbaechel-gowin, Apicula) 호환.
- **Verilator 시뮬레이터 동봉**: C++ 및 SDL2 기반 화면 갱신 시각화 시뮬레이션 환경 제공.
- **하드웨어 핸드셰이크**: PMIC 제어기와 FPGA 간의 전원 상태 동기화 (PMIC_READY / REFRESH_DONE).

---

### 디렉토리 구조
```
Glider_but_cheaper/
├── bin/                        # 미리 컴파일된 비트스트림 바이너리 (glider_tang.fs)
├── constraints/                # Gowin CST 핀 맵핑 핀제약 파일
├── rtl/                        # FPGA Verilog HDL 하드웨어 소스코드
│   └── mulib/                  # 메모리 및 동기화 유틸리티 모듈
├── sim/                        # Verilator + SDL2 시각 시뮬레이션 워크스페이스
├── xiao_pmic_controller/       # Arduino 기반 XIAO PMIC 전원 제어기 소스코드
├── Makefile                    # 전체 프로젝트 빌드 및 업로드 메인 Makefile
├── glider_tang.gprj            # Gowin EDA 프로젝트 파일
├── LICENSE                     # CERN-OHL-P v2 라이선스
└── README.md                   # 프로젝트 문서
```

---

### 하드웨어 준비물
1. **Sipeed Tang Primer 20K Core Board & Dock Baseboard**
2. **E-ink 스크린**: 병렬 인터페이스 지원 EPD 패널 (예: ED133UT2, ED060XH2 등)
3. **PMIC 전원 모듈**: TPS65185 기반 E-ink 고전압(+15V, -15V, VGH, VGL) 생성 모듈 *(예: Seeed Studio XIAO ePaper EE03 보드 TCON 우회)*
4. **PMIC 제어용 MCU**: PMIC 전원 켜기/끄기 및 핸드셰이크를 제어할 모듈 (Seeed XIAO ESP32S3 등)

---

### 핀 맵핑 가이드 (Dock 보드 PMOD 커넥터 연결)

#### 1. EPD 병렬 제어 인터페이스 (PMOD2)
| 신호 이름 | FPGA 핀번호 | 설명 |
| :--- | :--- | :--- |
| **EPD_GDOE** | `B14` | Gate Driver Output Enable (PMOD2 Pin 3) |
| **EPD_GDCLK**| `A15` | Gate Driver Clock (PMOD2 Pin 4) |
| **EPD_GDSP** | `D14` | Gate Driver Start Pulse (PMOD2 Pin 1) |
| **EPD_SDCLK**| `E15` | Source Driver Clock (PMOD2 Pin 2) |
| **EPD_SDLE** | `B12` | Source Driver Latch Enable (PMOD2 Pin 9) |
| **EPD_SDOE** | `C12` | Source Driver Output Enable (PMOD2 Pin 10) |
| **EPD_SDCE0**| `B13` | Source Driver Chip Enable 0 (PMOD2 Pin 7) |

#### 2. EPD 병렬 데이터 인터페이스 (PMOD0 & PMOD1)
| 신호 이름 | FPGA 핀번호 | 설명 |
| :--- | :--- | :--- |
| **EPD_SD[0]**| `T12` | Source Data Bit 0 (PMOD1 Pin 3) |
| **EPD_SD[1]**| `T11` | Source Data Bit 1 (PMOD1 Pin 1) |
| **EPD_SD[2]**| `P11` | Source Data Bit 2 (PMOD1 Pin 2) |
| **EPD_SD[3]**| `R11` | Source Data Bit 4 (PMOD1 Pin 4) |
| **EPD_SD[4]**| `M15` | Source Data Bit 4 (PMOD1 Pin 8) |
| **EPD_SD[5]**| `M14` | Source Data Bit 5 (PMOD1 Pin 7) |
| **EPD_SD[6]**| `J16` | Source Data Bit 6 (PMOD1 Pin 10) |
| **EPD_SD[7]**| `J14` | Source Data Bit 7 (PMOD1 Pin 9) |
| **EPD_SD[8]**| `R8`  | Source Data Bit 8 (PMOD0 Pin 3) |
| **EPD_SD[9]**| `T6`  | Source Data Bit 9 (PMOD0 Pin 1) |
| **EPD_SD[10]**| `P6` | Source Data Bit 10 (PMOD0 Pin 2) |
| **EPD_SD[11]**| `T7` | Source Data Bit 11 (PMOD0 Pin 4) |
| **EPD_SD[12]**| `P8` | Source Data Bit 12 (PMOD0 Pin 8) |
| **EPD_SD[13]**| `T8` | Source Data Bit 13 (PMOD0 Pin 7) |
| **EPD_SD[14]**| `T9` | Source Data Bit 14 (PMOD0 Pin 10) |
| **EPD_SD[15]**| `P9` | Source Data Bit 15 (PMOD0 Pin 9) |

#### 3. FPGA-PMIC 핸드셰이크 인터페이스 (PMOD3 Pins 7, 8)
| 신호 이름 | FPGA 핀번호 | 방향 | 설명 |
| :--- | :--- | :--- | :--- |
| **PMIC_READY** | `N7`  | 입력 | High일 때 PMIC의 고전압 출력이 안정되었음을 의미 |
| **REFRESH_DONE**| `N9` | 출력 | High일 때 FPGA의 EPD 스캔이 완료되어 유휴 상태임을 의미 |

#### 4. CSR SPI 통신 인터페이스 (PMOD3 Pins 1, 2, 3, 4)
| 신호 이름 | FPGA 핀번호 | 설명 |
| :--- | :--- | :--- |
| **SPI_CS**   | `N6`  | Chip Select (PMOD3 Pin 3) |
| **SPI_SCK**  | `D11` | SPI Clock (PMOD3 Pin 4) |
| **SPI_MOSI** | `A11` | Master Out Slave In (PMOD3 Pin 1) |
| **SPI_MISO** | `B11` | Master In Slave Out (PMOD3 Pin 2) |

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
