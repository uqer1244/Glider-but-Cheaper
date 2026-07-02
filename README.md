# Glider but Cheaper

Low-latency E-ink Monitor Controller ported to **Sipeed Tang Primer 20K** (Gowin GW2A-LV18).

[한국어 설명은 아래로 스크롤하세요. (Scroll down for Korean description.)]

---

## English

This project is a cost-optimized, self-contained port of the **Glider** open-source E-ink monitor controller to the **Sipeed Tang Primer 20K** FPGA module.

The original Glider board uses a Xilinx Spartan-6 LX16 FPGA, DDR3 framebuffer, and an STM32H750 MCU. This port targets the much cheaper and widely available Tang Primer 20K board (featuring the Gowin GW2A-LV18PG256C8/I7 FPGA and 128MB on-module DDR3), enabling you to build a low-latency paper-like display monitor at a fraction of the cost.

### System Architecture
```
[ HDMI Source ] ──(HDMI/DVI)──> [ Tang Primer 20K Dock ] ──> [ E-ink Screen (Parallel I/F) ]
                                    │             │
                                    └───(DDR3)────┘
                                   (Framebuffer)
```
*Note: For the E-ink PMIC, you can salvage/isolate the PMIC portion of the Seeed Studio "XIAO ePaper Display Board EE03" by bypassing its onboard IT8951 TCON chip and using only its TPS65185 PMIC circuitry.*

### Key Features
- **Ultra-low latency**: Processing delay of <20 us.
- **DVI/HDMI Input**: Direct digital video input via the onboard microHDMI port.
- **DDR3 Framebuffer**: Uses the 128MB DDR3 memory on the Tang Primer 20K core board.
- **Open-source Toolchain Ready**: Compiles with Yosys, nextpnr-himbaechel, and Apicula.
- **Verilator Simulation**: Includes a full visualizer-based simulation workspace.

---

### Hardware Requirements
1. **Sipeed Tang Primer 20K Core Board & Dock Baseboard**
2. **E-ink Screen**: E-ink panels with parallel interface (e.g., ED133UT2, ED060XH2, etc.).
3. **PMIC Board**: TPS65185 PMIC for generating E-ink high voltages (+/-15V, VGH/VGL). *(Note: Can be salvaged from the Seeed Studio XIAO ePaper EE03 board by utilizing only its PMIC section and bypassing the onboard TCON).*

---

### Pin Mapping Guide (Dock Board PMOD Connectors)
Signals are mapped to PMOD headers on the Tang Primer 20K Dock board for easy wiring:

#### 1. EPD Parallel Control Interface (PMOD1, PMOD2, PMOD3)
| Signal Name | FPGA Pin | Description |
| :--- | :--- | :--- |
| **EPD_GDOE** | `B14` | Gate Driver Output Enable |
| **EPD_GDCLK**| `A15` | Gate Driver Clock |
| **EPD_GDSP** | `D14` | Gate Driver Start Pulse |
| **EPD_SDCLK**| `E15` | Source Driver Clock |
| **EPD_SDLE** | `L9`  | Source Driver Latch Enable |
| **EPD_SDOE** | `N8`  | Source Driver Output Enable |
| **EPD_SDCE0**| `N9`  | Source Driver Chip Enable 0 |
| **EPD_SD[0]**| `T12` | Source Data Bit 0 |
| **EPD_SD[1]**| `T11` | Source Data Bit 1 |
| **EPD_SD[2]**| `P11` | Source Data Bit 2 |
| **EPD_SD[3]**| `R11` | Source Data Bit 3 |
| **EPD_SD[4]**| `M15` | Source Data Bit 4 |
| **EPD_SD[5]**| `M14` | Source Data Bit 5 |
| **EPD_SD[6]**| `J16` | Source Data Bit 6 |
| **EPD_SD[7]**| `J14` | Source Data Bit 7 |
| **EPD_SD[8]**| `F14` | Source Data Bit 8 |
| **EPD_SD[9]**| `F16` | Source Data Bit 9 |
| **EPD_SD[10]**| `G15`| Source Data Bit 10 |
| **EPD_SD[11]**| `G14`| Source Data Bit 11 |
| **EPD_SD[12]**| `F13`| Source Data Bit 12 |
| **EPD_SD[13]**| `G12`| Source Data Bit 13 |
| **EPD_SD[14]**| `L13`| Source Data Bit 14 |
| **EPD_SD[15]**| `C10`| Source Data Bit 15 |

#### 2. PMIC & Configuration Interface (PMOD2 Row 3/4)
| Signal Name | FPGA Pin | Description |
| :--- | :--- | :--- |
| **PMIC_SCL** | `D10` | I2C Clock (with internal Pull-up) |
| **PMIC_SDA** | `B12` | I2C Data (with internal Pull-up) |
| **PMIC_WAKEUP**| `A14`| PMIC Wakeup pin |
| **PMIC_PWRUP** | `B13`| PMIC Power-up pin |

#### 3. CSR SPI Host Interface (PMOD4)
| Signal Name | FPGA Pin | Description |
| :--- | :--- | :--- |
| **SPI_CS**   | `N6`  | Chip Select |
| **SPI_SCK**  | `D11` | SPI Clock |
| **SPI_MOSI** | `A11` | Master Out Slave In |
| **SPI_MISO** | `B11` | Master In Slave Out |

---

### How to Use

#### Method A: Quick Start (Flash Precompiled Binary)
You can directly flash the precompiled bitstream without setting up synthesis toolchains.
Ensure `openFPGALoader` is installed, then run:

*   **Load to RAM (Temporary)**:
    ```bash
    make program_bin
    ```
*   **Flash to Board (Permanent)**:
    ```bash
    make flash_bin
    ```

#### Method B: Build from Source (Open-Source Toolchain)
1. Install the open-source Gowin FPGA toolchain:
   - **Synthesis**: [Yosys](https://github.com/YosysHQ/yosys)
   - **Place & Route**: [nextpnr-himbaechel-gowin](https://github.com/YosysHQ/nextpnr)
   - **Bitstream pack**: [Apicula (gowin_pack)](https://github.com/YosysHQ/apicula)
   - **Programmer**: [openFPGALoader](https://github.com/trabucayrog/openFPGALoader)
2. Build the project:
   ```bash
   make
   ```
3. Load or flash your custom built design:
   ```bash
   make program   # load to RAM
   make flash     # write to flash
   ```

#### Method C: Run Verilator Simulation
A complete simulation model is provided using Verilator and SDL2 to visualize E-ink screen refreshing.
1. Install **Verilator** and **SDL2**.
2. Run simulation from the root directory:
   ```bash
   make simulation
   ```
   Or navigate to `sim/` and use:
   ```bash
   cd sim
   make
   ./sim
   ```

---

## 한국어 (Korean)

이 프로젝트는 오픈소스 E-ink 모니터 컨트롤러인 **Glider**를 **Sipeed Tang Primer 20K** FPGA 모듈로 이식하여 비용을 최적화하고 단독 실행이 가능하도록 정리한 버전입니다.

기존 오리지널 Glider 보드는 Xilinx Spartan-6 LX16 FPGA, DDR3 프레임버퍼, STM32H750 MCU를 사용하여 상대적으로 비용이 높고 칩 구하기가 어렵습니다. 이 포트는 훨씬 저렴하고 구하기 쉬운 Tang Primer 20K(Gowin GW2A-LV18PG256C8/I7 FPGA 및 128MB DDR3 포함)를 타겟으로 하여 저렴하게 초저지연 E-ink 모니터를 자작할 수 있도록 돕습니다.

### 시스템 구성
```
[ HDMI 영상 입력 ] ──(HDMI/DVI)──> [ Tang Primer 20K Dock ] ──> [ E-ink 화면 (병렬 I/F) ]
                                        │             │
                                        └───(DDR3)────┘
                                       (프레임버퍼)
```
*참고: E-ink PMIC 전원부의 경우, Seeed Studio "XIAO ePaper Display Board EE03" 모듈의 내장 IT8951 TCON 칩을 우회(Bypass)하고 온보드 TPS65185 PMIC 회로 부분만 활용하여 전원 공급용으로 사용할 수 있습니다.*

### 주요 기능 및 특징
- **초저지연**: 20 us 미만의 극도로 짧은 프로세싱 지연시간.
- **DVI/HDMI 입력 지원**: Dock 보드에 내장된 microHDMI 커넥터를 통한 직접 디지털 영상 입력.
- **DDR3 프레임버퍼 사용**: Tang Primer 20K 코어 보드 내장 128MB DDR3 메모리를 활용한 프레임 스토리지 구현.
- **오픈소스 툴체인 지원**: Yosys, nextpnr-himbaechel, Apicula 툴체인을 사용하여 무료로 컴파일 가능.
- **Verilator 시뮬레이션 지원**: 화면이 갱신되는 동작을 시각적으로 확인할 수 있는 C++ 기반 시뮬레이터 제공.

---

### 하드웨어 준비물
1. **Sipeed Tang Primer 20K Core Board & Dock Baseboard**
2. **E-ink 스크린**: 병렬 인터페이스 지원 EPD 패널 (예: ED133UT2, ED060XH2 등)
3. **PMIC 보드**: E-ink 구동을 위한 고전압(+/-15V, VGH/VGL) 생성용 TPS65185 모듈 *(참고: Seeed Studio XIAO ePaper EE03 보드에서 TCON부를 우회하고 PMIC부 회로만 활용하여 자작 가능)*

---

### 핀 맵핑 가이드 (Dock 보드 PMOD 커넥터 연결)
Tang Primer 20K Dock 보드의 PMOD 포트에 맞춘 연결 핀 맵핑 테이블입니다:

#### 1. EPD 병렬 제어 인터페이스 (PMOD1, PMOD2, PMOD3)
| 신호 이름 | FPGA 핀번호 | 설명 |
| :--- | :--- | :--- |
| **EPD_GDOE** | `B14` | Gate Driver Output Enable |
| **EPD_GDCLK**| `A15` | Gate Driver Clock |
| **EPD_GDSP** | `D14` | Gate Driver Start Pulse |
| **EPD_SDCLK**| `E15` | Source Driver Clock |
| **EPD_SDLE** | `L9`  | Source Driver Latch Enable |
| **EPD_SDOE** | `N8`  | Source Driver Output Enable |
| **EPD_SDCE0**| `N9`  | Source Driver Chip Enable 0 |
| **EPD_SD[0]**| `T12` | Source Data Bit 0 |
| **EPD_SD[1]**| `T11` | Source Data Bit 1 |
| **EPD_SD[2]**| `P11` | Source Data Bit 2 |
| **EPD_SD[3]**| `R11` | Source Data Bit 3 |
| **EPD_SD[4]**| `M15` | Source Data Bit 4 |
| **EPD_SD[5]**| `M14` | Source Data Bit 5 |
| **EPD_SD[6]**| `J16` | Source Data Bit 6 |
| **EPD_SD[7]**| `J14` | Source Data Bit 7 |
| **EPD_SD[8]**| `F14` | Source Data Bit 8 |
| **EPD_SD[9]**| `F16` | Source Data Bit 9 |
| **EPD_SD[10]**| `G15`| Source Data Bit 10 |
| **EPD_SD[11]**| `G14`| Source Data Bit 11 |
| **EPD_SD[12]**| `F13`| Source Data Bit 12 |
| **EPD_SD[13]**| `G12`| Source Data Bit 13 |
| **EPD_SD[14]**| `L13`| Source Data Bit 14 |
| **EPD_SD[15]**| `C10`| Source Data Bit 15 |

#### 2. PMIC 전원 제어 인터페이스 (PMOD2 Row 3/4)
| 신호 이름 | FPGA 핀번호 | 설명 |
| :--- | :--- | :--- |
| **PMIC_SCL** | `D10` | I2C Clock (내부 풀업 활성화됨) |
| **PMIC_SDA** | `B12` | I2C Data (내부 풀업 활성화됨) |
| **PMIC_WAKEUP**| `A14`| PMIC Wakeup 핀 |
| **PMIC_PWRUP** | `B13`| PMIC Power-up 핀 |

#### 3. CSR SPI 통신 인터페이스 (PMOD4)
| 신호 이름 | FPGA 핀번호 | 설명 |
| :--- | :--- | :--- |
| **SPI_CS**   | `N6`  | Chip Select |
| **SPI_SCK**  | `D11` | SPI Clock |
| **SPI_MOSI** | `A11` | Master Out Slave In |
| **SPI_MISO** | `B11` | Master In Slave Out |

---

### 사용 방법

#### 방법 A: 빠른 시작 (미리 빌드된 파일 업로드)
도구를 직접 설치하여 컴파일할 필요 없이 미리 컴파일된 바이너리 파일을 바로 보드에 업로드할 수 있습니다.
컴퓨터에 `openFPGALoader`가 설치되어 있는지 확인하고 다음 명령을 실행합니다:

*   **RAM에 임시 다운로드**:
    ```bash
    make program_bin
    ```
*   **보드 내장 플래시 메모리에 영구 업로드**:
    ```bash
    make flash_bin
    ```

#### 방법 B: 소스코드 직접 컴파일 및 업로드
1. 아래 오픈소스 Gowin 툴체인을 컴퓨터에 설치합니다:
   - **논리 합성**: [Yosys](https://github.com/YosysHQ/yosys)
   - **배치배선 (P&R)**: [nextpnr-himbaechel-gowin](https://github.com/YosysHQ/nextpnr)
   - **비트스트림 패키징**: [Apicula (gowin_pack)](https://github.com/YosysHQ/apicula)
   - **업로더**: [openFPGALoader](https://github.com/trabucayrog/openFPGALoader)
2. 아래 명령어로 소스코드를 빌드합니다:
   ```bash
   make
   ```
3. 생성된 바이너리를 보드에 로드합니다:
   ```bash
   make program   # RAM 임시 쓰기
   make flash     # 플래시 영구 쓰기
   ```

#### 방법 C: Verilator 시뮬레이션 실행하기
이 레포지토리에는 Verilator 및 SDL2를 활용해 화면 갱신 과정을 시각적으로 확인하는 시뮬레이터가 동봉되어 있습니다.
1. 컴퓨터에 **Verilator**와 **SDL2** 라이브러리를 설치합니다.
2. 메인 디렉토리에서 아래 명령을 실행합니다:
   ```bash
   make simulation
   ```
   또는 `sim` 폴더로 직접 이동하여 컴파일할 수 있습니다:
   ```bash
   cd sim
   make
   ./sim
   ```

---

## References & License
- Original Glider design by Wenting Zhang: [Glider Github](https://github.com/zephray/Glider)
- Caster EPDC Core: [Caster Gitlab](https://gitlab.com/zephray/Caster/)
- License: CERN-OHL-P v2 (Open-source Hardware License)
