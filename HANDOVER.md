# 인수인계서 — Glider_but_cheaper (Tang Primer 20K 포트)

> 작성일 2026-08-22 · 세션 종료 시점 스냅샷
> 대상 문서: `plan.md` · 상위 `../README.md` (Caster 원본 아키텍처 문서)

---

## 0. 한 줄 요약

**목표는 자일링스 Caster의 e-ink 드라이버가 Gowin에서 재현되는지 확인하는 것.**
HDMI 입력은 제거했고, 화면은 FPGA 내부 테스트 패턴으로 만든다.
**조작은 온보드 버튼 5개, 상태 확인은 LED 6개로 전부 가능하다([2.5](#25-프론트-패널--버튼-5개--led-6개)).**

**RTL 합성 통과 · 시뮬레이션 통과. 다음은 P&R로 40.5 MHz 타이밍 클로징 확인.**
패널 데이터시트는 존재하지 않는다 — SDCLK 상한은 실측해야 한다([7.5](#75--미검증-가정-패널-sdclk-최대-주파수)).

---

## 1. 프로젝트 정체

Modos/zephray의 **Caster EPDC**(e-paper display controller)를 Xilinx Spartan-6 →
**Gowin GW2A-LV18 (Tang Primer 20K)** 로 포팅.
최종 목표는 **11.5″ 2760×2070 ED115OC1** e-ink 패널 구동.

### 현재 구성 (1단계)
- VRAM 그리드 **1280×960** → 2× 최근접이웃 업스케일 → 패널 스캔영역 **2560×1920** (패널의 86%)
- **16비트 병렬 ED 버스, 2bpp** — SDCLK 1클럭 = 패널 8픽셀 = 코어 4픽셀 = 코어 1워드
- DDR3는 **미사용** (`mig_wrapper.v`가 128비트 레지스터 루프백 스텁)
- HDMI 입력 **제거됨** — `rtl/dvi_rx.v` 삭제, `top.v`의 DPI 스텁 배선 삭제,
  Makefile SRCS·CST HDMI 핀 정리. 픽셀 소스는 `vin.v` 테스트 패턴 단독
  (2단계에서 되살릴 때는 `git checkout <이전커밋> -- rtl/dvi_rx.v`)
- **PMIC 핸드셰이크 제거됨** — `PMIC_READY` 포트와 CST 항목 삭제.
  드라이브 게이트는 이제 **BTN0**이다([2.5](#25-프론트-패널--버튼-5개--led-6개))
- **프론트 패널 추가** — `rtl/debug_ctrl.v`(버튼/LED), `rtl/csr_master.v`(내부 SPI 마스터)

---

## 2. ⚠️ 하드웨어 안전 사항 (제일 중요)

### 지금 패널 연결하면 안 되는 이유 — 블로커 3개

| # | 문제 | 근거 | 결과 |
|---|------|------|------|
| 1 | **IT8951 TCON이 살아있다** | `xiao_pmic_controller.ino:53` `digitalWrite(PIN_TFT_RST, HIGH)` | EE03 커넥터에 패널 FPC 꽂으면 **ED0-15/SDCLK/SDLE/SDOE/GDCLK에서 FPGA와 버스 충돌** |
| 2 | ~~PMIC_READY가 가짜 핸드셰이크~~ **해소** | `.ino:48` `setup()`에서 무조건 HIGH | 신호가 정보를 담지 않으므로 **포트를 제거하고 BTN0 수동 게이트로 대체**. 이제 전원이 들어와도 EPD 버스는 조용하고, 사람이 버튼을 눌러야 구동이 시작된다 |
| 3 | **PMIC 레지스터 주소가 틀림** | 아래 표 참조 | 코드에 적힌 전압과 **실제 나오는 전압이 다름** |

#### PMIC 레지스터 오류 상세 (`xiao_pmic_controller.ino`)
```c
#define REG_VCOM    0x00  // ❌ 실제로는 TMST_VALUE (읽기전용) → VCOM 쓰기가 전부 무시됨
#define REG_ENABLE  0x01  // ✅ 맞음
#define REG_UP_SEQ  0x02  // ❌ 실제로는 VADJ → VPOS/VNEG 설정값을 오염시킴
```
> 사용자는 "XIAO에서 전압 잘 나온다(확인함)"고 했으나, **VCOM은 설정된 적이 없고
> VPOS/VNEG는 의도한 값이 아닐 가능성이 높다.** TPS65185 데이터시트로 재확인 필요.

### 반드시 지킬 것
- 패널 FPC를 **EE03 커넥터에 직접 꽂지 말 것**. plan.md의 **A안**(별도 브레이크아웃,
  EE03에서는 전원 7선만 가져오기)을 쓸 것. 블로커 1(IT8951 버스 충돌)은 **아직 유효하다.**
- 첫 통전은 반드시 **BTN4로 FREERUN을 끄고, BTN1로 한 프레임씩** 진행할 것.
  60 Hz 자유 주행은 파형이 확인된 뒤에 켠다.
- `make demo`(`PANEL_TEST`) 빌드는 파이프라인을 우회해 **전 픽셀을 무조건 구동**한다.
  BTN0 게이트는 여전히 적용되지만, 화면 내용을 신뢰하지 말 것.

---

## 2.5 프론트 패널 — 버튼 5개 / LED 6개

MCU가 없으므로 온보드 버튼과 LED가 유일한 인터페이스다.
구현은 `rtl/debug_ctrl.v`, 핀은 Sipeed 레퍼런스(`constraints/sipeed_tang_primer_20k.cst`
의 `btn_n0..btn_n4`)에서 가져왔다. 전부 **액티브 로우**, 10 ms 디바운스.

| 버튼 | 핀 | IO_TYPE | 기능 |
|---|---|---|---|
| **BTN0** | T10 | LVCMOS33 | **DRIVE** 게이트 토글. **전원 인가 시 OFF** — GDOE/SDOE 낮음, 스캔 정지 |
| **BTN1** | T3 | LVCMOS15 | **STEP** — 정확히 한 프레임 실행 (FREERUN이 꺼져 있을 때만 의미 있음) |
| **BTN2** | T2 | LVCMOS15 | **PATTERN** 순환 (4종) |
| **BTN3** | D7 | LVCMOS15 | **MODE** 순환 (4종) + SETMODE 발행. **누르고 있으면** LED5:4가 모드를 표시 |
| **BTN4** | C7 | LVCMOS15 | **FREERUN** 토글 (60 Hz 자유 주행 ↔ 수동 스텝) |

| LED | 실크 | 의미 |
|---|---|---|
| LED0 | D1 | **하트비트 ~1 Hz.** 안 깜빡이면 rPLL 미락 또는 리셋 미해제 |
| LED1 | D2 | **EPD 버스 셀프테스트** — 점등=통과 / 1회 점멸=GDCLK / 2회=SDLE / 3회=SDCE0 |
| LED2 | D3 | **DRIVE 활성** (GDOE/SDOE 살아있음) |
| LED3 | D4 | **FREERUN 켜짐** |
| LED5:4 | D6,D5 | **패턴 인덱스**. BTN3을 누르고 있는 동안은 **모드 인덱스** |

### 패턴 (BTN2) — `rtl/vin.v`
| # | 내용 | 목적 |
|---|---|---|
| 0 | 체커보드 + 프레임마다 내려가는 회색 밴드 | 기하 + 생존 확인 |
| 1 | 좌→우 그레이 램프 | 디더링 / 그레이스케일 모드 |
| 2 | 1워드 폭 세로 줄무늬 (패널상 8픽셀 주기) | 소스 버스 최대 토글, 신호 무결성 |
| 3 | 전체 백색 | 화면 클리어 |

### 모드 (BTN3) — `rtl/csr_master.v`가 SETMODE 발행
| # | 모드 |
|---|---|
| 0 | `FAST_MONO_BAYER` — OP_INIT 직후 상태와 동일하므로 부팅 시 LED5:4=00이 진실 |
| 1 | `FAST_MONO_NO_DITHER` |
| 2 | `FAST_MONO_BLUE_NOISE` |
| 3 | `FAST_GREY` |

MCU 없이 SETMODE를 넣기 위해 **내부 SPI 마스터**를 붙였다. `caster.v`/`csr.v`는
전혀 건드리지 않았다 — 기존 CSR SPI 슬레이브에 그대로 물린다.
csr.v의 주소 자동증가를 이용해 **CS 한 번에 주소 1바이트(OP_LEFT_HI) + 데이터 11바이트**로
전체 화면 영역과 모드, `OP_EXT_SETMODE`까지 한 번에 쓴다.
외부 SPI 핀은 살아 있고, 내부 마스터가 busy인 동안만 우선권을 갖는다.

---

## 3. 빌드 상태 — 합성 검증 완료 ✅

### 실행한 것 (비파괴, 스크래치패드 출력)
```bash
yosys -p "read_verilog -Irtl -Irtl/mulib/rtl $SRCS; \
          synth_gowin -json $SP/check.json -top top"
```
**결과: `make` / `make demo` 두 빌드 모두 EXIT=0, Yosys 0.66 — 통과.**

> ⚠️ 산출물은 스크래치패드에 있고 세션 tmp 정리로 사라진다. 필요하면 재실행.
>
> ⚠️ yosys 로그는 통계 블록을 **두 번** 찍는다. 스크립트로 집계하면 값이 2배가 된다.
> 아래는 실제 값이다.

### 리소스 집계 (프론트 패널 추가 후)
| 항목 | 이전 | 현재 | 증감 |
|---|---:|---:|---:|
| LUT1~4 | 4,620 | 4,721 | +101 |
| MUX2_LUT5~8 | 834 | 953 | +119 |
| DFF 계열 | 1,747 | 1,926 | +179 |
| **BSRAM** (DPB 10 + DPX9B 5 + SDPX9B 4 + SPX9 8) | 27 | **27** / 46 | — |
| RAM16SDP4 (분산 RAM) | 512 | 512 | — |
| **rPLL** | 1 | **1** ✅ | — |
| **ODDR** | 1 | **1** ✅ | — |
| IBUF / OBUF | 28 / 57 | 31 / 57 | +3 / — |

증가분은 `debug_ctrl`(디바운스 카운터 5개 + LED 분주기)과 `csr_master`다.
`make demo`(`PANEL_TEST`)는 파이프라인을 통째로 우회하므로 BSRAM 0, LUT도 1/4 수준이다.

**핵심 확인 2가지:**
- `rPLL` 1개 생존 → `sysclock.v`가 최적화로 삭제되지 않음. **40.5 MHz가 실제로 생성된다.**
- `ODDR` 1개 → `epd_sdclk`가 IO 프리미티브로 출력. plan §5.3 요구사항 반영 완료.
- BSRAM 27개는 plan.md의 `make` 빌드 수치(27/46)와 **정확히 일치**.

### 경고 89건 (65 unique) — 전부 예상된 것
- 거의 전부 `DDR_* is used but has no driver`
  (DDR_A[0..12], DDR_BA[0..2], DDR_RAS_N/CAS_N/WE_N, DDR_ODT, DDR_RESET_N,
   DDR_CKE, DDR_LDM/UDM, DDR_CK_P/N) — top과 mig_wrapper 양쪽에서 보고.
  **plan §6.1의 DDR3 스텁 설명 그대로. 1단계에선 무해.**
- 비-DDR 경고는 이제 없음 (`dvi_rx.v` 삭제로 `align_counter` 경고도 사라짐).

### 아직 검증 안 된 것
**P&R을 안 돌려서 40.5 MHz 타이밍 클로징이 미확인이다.**
plan §7.3은 `make` 빌드 기준 48% LUT4 / 27-of-46 BSRAM / **62 MHz**라고 적고 있으나
실측값인지 불명. 합성 통과 ≠ 타이밍 통과.

---

## 3.5 시뮬레이션 — `make simulation`

`rtl/tb_top.v`를 다시 썼다. 이전 것은 `top`에 존재하지 않는 `DPI_*`/`LVDS_*` 포트를
물고 있어서 **애초에 컴파일이 안 됐다.**

지금은 오퍼레이터가 실제로 쓸 순서 그대로 4단계를 검증한다:

| 단계 | 검증 내용 |
|---|---|
| **A** | 전원 인가 직후 **드라이브 게이트가 닫혀 있음** — GDOE/SDOE 낮음, GDCLK 무토글, 프레임 0 |
| **B** | BTN0으로 게이트 열림 → 2프레임에 대해 GDCLK==vtotal, SDLE==vtotal, SDCE0==hact×vact |
| **C** | BTN3 → `csr_master`가 SETMODE 발행 → caster가 `op_cmd`/`op_param`/영역을 래치 |
| **D** | BTN4로 스캔 정지 확인 → BTN1로 **정확히 한 프레임**만 실행 |

fabric의 `epd_selftest.v`와 같은 3가지를 세지만, 점멸 코드 대신 숫자로 출력한다.

VCD는 기본적으로 TB 레벨만 덤프한다. 663k 클럭 프레임을 전체 계층으로 덤프하면
수 GB가 된다. 필요하면:
```bash
make simulation SIM_DEFS=-DFULL_DUMP
```

> 한 프레임이 662,888 클럭이라 **실행에 수 분 걸린다.** 정상이다.

### 알려진 무해한 출력
- `Scan FSM in invalid state` 1회 — `caster.v`의 default 분기. 리셋 전 `scan_state`가
  X라서 나온다. 실기에는 리셋 시퀀서가 있어 발생하지 않는다.
- `blue_noise_dithering.v:78: @* found no sensitivities` ×2 — 기존 경고.

---

## 3.7 🔴 이번 세션에서 실제로 밟은 버그 2개

둘 다 "모드 버튼을 눌러도 SETMODE가 발행되지 않는다"로 나타났다.
시뮬 C단계에서 `caster`의 `op_cmd`/`op_param`이 전부 X로 남는 증상이었다.

### (1) 진짜 원인 — SPI 먹스가 가짜 클럭 에지를 만든다

내부 CSR 마스터와 외부 SPI 핀을 `int_spi_busy`로 먹싱했는데:

```verilog
wire spi_sck = int_spi_busy ? int_spi_sck : ext_spi_sck;
```

- `int_spi_sck`는 SPI 모드 3이라 **idle이 1**
- `ext_spi_sck`는 아무것도 안 물렸을 때 **0**

`int_spi_busy`가 0→1 하는 순간 `spi_sck`가 0에서 1로 점프한다.
**csr.v는 이걸 상승 에지로 세고, 전송 전체가 1비트씩 밀린다.**

증상이 아주 특징적이었다 — 보낸 값과 받은 값이 정확히 1비트 시프트:
```
보냄:  04 00 00 05 00 00 00 03 C0 02 10 01
받음:  02 | 00 00 02 80 00 00 01 E0 01 08 00     ← 전부 >>1
```
주소가 4가 아니라 2로 들어가고, 그 뒤로는 주소 3(`CSR_LUT_WR`, 자동증가 안 됨)에
데이터가 계속 꽂혔다.

**해결:** 외부 SCK를 자기 CS로 게이팅해 idle 레벨을 맞춘다.
```verilog
wire ext_spi_sck_idle = ext_spi_cs ? 1'b1 : ext_spi_sck;
```
> 외부 MCU가 제대로 된 모드 3 마스터라면 어차피 SCK를 high로 두므로 동작이 안 바뀐다.
> 반대로 SCK를 low로 두는 마스터를 물려도 이제 CS 어서트 시점의 오카운트가 안 생긴다.

### (2) 잠재 버그 — `mu_dsync`에 펄스를 통과시키지 말 것

(1)을 찾는 과정에서 같이 발견했다. 이것만으로는 증상이 안 났지만 명백한 오류다.

`mu_dsync`는 평범한 2FF 동기화기처럼 보이지만, **`SIMULATION`으로 빌드하면
매 사이클 출력 탭을 `shiftreg[1]`과 `shiftreg[2]` 사이에서 무작위로 고른다**
(`mu_dsync.v:52`). 메타스터빌리티를 일부러 모사하는 장치다.

레벨 신호에는 무해하다(1클럭 늦거나 말거나 결국 안정된다).
그러나 **1클럭 펄스는 통째로 사라질 수 있다.**

**해결:** 소스 도메인에서 **토글**(레벨)을 만들고, 목적지에서 양 에지를 검출한다.
```verilog
// debug_ctrl.v (clk_sys)
if (btn_press[3]) mode_toggle <= ~mode_toggle;

// top.v (clk_epdc)
mu_dsync mode_toggle_sync (... .out(mode_toggle_epdc));
reg mode_toggle_d;
always @(posedge clk_epdc) mode_toggle_d <= mode_toggle_epdc;
wire mode_change_pulse = mode_toggle_epdc ^ mode_toggle_d;
```

> 지금은 `assign clk_epdc = clk_sys;`라 사실 CDC가 필요 없다.
> 그래도 제대로 해두는 편이 낫다 — 2단계에서 DDR3 IP가 들어오면
> 클럭 도메인이 실제로 갈라진다.

### 디버깅 방법 메모
전체 시뮬은 한 프레임이 662,888클럭이라 **6분 이상 걸린다.**
모드 경로는 프레임이 필요 없으므로(`csr_op_en`은 스캔과 무관하게 뜬다)
**BTN3만 누르고 `csr.spi_req_addr`/`spi_req_wdata`를 찍는 20 ms짜리 TB**를
따로 만들어 몇 초 만에 좁혔다. 다음에도 이 방법을 쓸 것.

---

## 3.6 이번 세션에서 걷어낸 것

| 대상 | 사유 |
|---|---|
| `rtl/dvi_rx.v` | HDMI 입력 2단계로 연기. git에 있으므로 복구 가능 |
| `rtl/timing_generator.v` | **0바이트 빈 파일**인데 SRCS와 `.gprj`에 등록돼 있었음 |
| `top.v`의 chipscope/ILA 블록 | 자일링스 IP. 약 3.7 KB의 주석 처리된 죽은 코드 |
| `PMIC_READY` 포트 + CST | 신호가 정보를 담지 않음. BTN0으로 대체 |
| `BRINGUP_NO_PMIC` + `make bringup` | BTN0이 런타임에 같은 일을 함 |
| `` `define CSR_SELFBOOT `` + `-DCSR_SELFBOOT=1` | 어떤 RTL도 참조하지 않는 죽은 정의 |
| `vin.v`의 DPI/FPD-Link 포트 11개 | 전부 상수로 묶여 있던 죽은 배선 |

`.gprj`의 FileList도 실제 SRCS와 맞췄다(`timing_generator` 제거, `debug_ctrl`·`csr_master` 추가).

---

## 4. 즉시 다음 할 일

### (1) P&R 실행 — 비파괴로
```bash
SP=<scratchpad>
nextpnr-himbaechel --json $SP/check_bringup.json \
  --write $SP/check_bringup.pnr.json \
  --device GW2A-LV18PG256C8/I7 \
  --vopt family=GW2A-18C --vopt cst=constraints/gowin_constraints.cst
```
→ 로그에서 **Fmax**를 확인. **40.5 MHz 이상이어야 한다.**

### (2) 통과하면 실제 비트스트림
```bash
make             # 기본 빌드
```
> **경고: `make demo`는 내부에서 `make clean`을 돌려 `rm -f *.json *.fs`를 한다.**
> 루트의 기존 `glider_tang.json`(10.6 MB)이 지워진다.
> 사용자는 이전에 이것 때문에 빌드 호출을 한 번 거부했다.
> **파괴적 단계는 실행 전에 반드시 먼저 알릴 것.**

### (3) 플래싱
사용자는 **Gowin EDA 프로그래머**를 선호한다(편해서). RTL 빌드는 yosys로 하고,
나온 `.fs`만 Gowin Programmer로 굽는 방식을 권장했다.
- 모드: **SRAM Program**, 디바이스 **GW2A-18C**

### (4) 보드 단독 확인 — 패널 없이, PMIC 없이
비트스트림을 굽고 **아무것도 연결하지 않은 상태**에서:

1. **LED0이 1 Hz로 깜빡이는가** → rPLL 락 + 리셋 해제 확인
2. LED2 꺼짐, LED3 켜짐(FREERUN 기본 ON) 확인
3. **BTN0** → LED2 점등. 이때부터 EPD 버스가 살아난다
4. 몇 초 뒤 **LED1 점등** → GDCLK/SDLE/SDCE0 개수가 타이밍과 일치.
   점멸하면 횟수를 셀 것: 1=GDCLK, 2=SDLE, 3=SDCE0
5. **BTN2**를 눌러가며 LED5:4가 00→01→10→11로 도는지 확인 (버튼 매핑 검증)
6. **BTN3**을 누른 채로 LED5:4가 모드 인덱스로 바뀌는지 확인

> 여기까지 통과하면 **FPGA 쪽은 끝**이다. 버튼 물리 배치(어느 버튼이 T10인지)는
> 보드 실크와 다를 수 있으니 5번에서 확인하고, 다르면 CST의 핀 순서만 바꾸면 된다.

### (5) 패널 연결 후 첫 구동
1. **BTN4로 FREERUN을 끈다** (LED3 소등). 이 상태에서는 아무 프레임도 안 나간다
2. 패널 + PMIC 연결. **블로커 1(IT8951 버스 충돌)을 먼저 해결할 것** — [2장](#2--하드웨어-안전-사항-제일-중요)
3. PMIC 레일 인가
4. **BTN0** → 드라이브 게이트 열기 (아직 프레임은 안 나감)
5. **BTN1을 한 번** → 딱 한 프레임. 스코프로 SDCLK/SDLE/GDCLK 확인
6. 파형이 맞으면 BTN1을 반복해 이미지가 쌓이는지 관찰
7. 확신이 서면 **BTN4로 FREERUN 켜기**
8. **BTN2**로 패턴 3(전체 백색)을 넣어 화면 클리어가 되는지 확인 —
   이게 되면 구동 경로 전체가 살아있다는 뜻

---

## 5. ⚠️ 함정: Gowin EDA로 직접 빌드하면 조용히 실패한다

`glider_tang.gprj`의 OptionList에 **Verilog define이 하나도 없다**:
```xml
<Option type="top_module" value="top"/>
<Option type="use_sspi_as_regular_io" value="1"/>
<Option type="use_mspi_as_regular_io" value="1"/>
```
→ 디폴트 빌드 → `PMIC_READY`(CST에서 `PULL_MODE=DOWN`, 미연결) → `sys_ready` 0 고정
→ **출력 전무, LED 무반응, EPD 무동작.** 에러는 안 난다.

**결론: 빌드는 Makefile로, 플래싱만 Gowin으로.**

---

## 6. 빌드 변형 (Makefile)

```make
make                # 기본. 전체 파이프라인 + vin.v 테스트 패턴
make demo           # -DPANEL_TEST=1 : 파이프라인/VRAM 우회, 움직이는 상자
make simulation     # 아이카루스. 프론트 패널 + EPD 버스 4단계 검증
make program        # SRAM 로드
make flash          # 내장 플래시
```
> `bringup` 타깃은 **삭제**했다. BTN0이 런타임에 같은 일(드라이브 게이트)을 하고,
> 그쪽이 더 안전하다 — 비트스트림을 바꿔 끼울 필요가 없다.
>
> `CSR_SELFBOOT` 정의도 **삭제**했다. 어떤 RTL도 참조하지 않는 죽은 정의였다
> (`csr.v`는 리셋에서 조건 없이 `csr_en <= 1'b1`을 한다).

**툴체인:** yosys 0.66 + nextpnr-himbaechel (yowasp) + apicula gowin_pack + openFPGALoader.
Gowin EDA는 **2단계 DDR3 IP에만** 필요.

---

## 7. 타이밍 — 확정된 수치 (plan.md §3 / 부록 B에 반영 완료)

```
htotal  =  344   (HACT 320 + HFP 20 + HSYNC 2 + HBP 2)
vtotal  = 1927   (VACT 1920 + VFP 4 + VSYNC 1 + VBP 2)
프레임당 스캔 클럭 = 344 × 1927 = 662,888
60 Hz 필요 최소 SDCLK = 662,888 × 60 = 39.8 MHz
실제 코어 클럭 = SDCLK = 40.5 MHz  (rPLL 27 × 3/2, 여유 1.8%)
vsync 주기 = 675,000 clk  (top.v:162 → localparam VSYNC_PERIOD = 20'd674_999)
```

### 675,000 vs 662,888 — 12,112 clk 차이는 **버그가 아니다**
`../README.md:845`가 EPDC 타이밍은 입력 비디오 타이밍의
**"slightly delayed version"** 이어야 한다고 규정한다.
README의 TCON 유도식을 적용하면 정확히 이 형태가 나온다
(수평 차이 0, 수직 차이 = vfp). 나머지 12,112 clk는 **vsync 대기**로 흡수된다.

### HFP=20의 이유
미최적화 블랭킹이 아니라 **GDCLK low 펄스 494 ns 확보용 의도된 값**.
`defines.vh:131`에 주석과 함께 있음 (추정치, 실측 후 조정 필요).

### 🔴 2단계에서 반드시 지킬 제약 (내가 유도해서 plan에 추가함)
2× 수직 스케일링 때문에 README 규칙이 이렇게 일반화된다:

```
입력 (1280x960 CVT-RB, 85.2 MHz, htotal 1440) = 59.17 kHz/line
        × 2                                   = 118.3 kHz
EPDC (40.5 MHz, htotal 344)                   = 117.7 kHz/line  → 0.5% 느림 ✅
```
**EPDC 라인레이트 = 입력 라인레이트 × 2 이되, 반드시 "약간 느린" 쪽.**
빠르면 입력 FIFO 언더런 → 프레임 kill. 현재 값은 안전한 쪽에 있다.
`vi_fifo`는 최소 1라인(320워드) 버퍼링 필요
(EPDC는 7.9 µs에 소비, 입력은 15.0 µs에 걸쳐 공급).

---

## 7.5 🔴 미검증 가정: 패널 SDCLK 최대 주파수

**데이터시트는 공개된 것이 없다** (2026-08-22 웹 조사 완료 — 재조사 불필요).

| 소스 | 결과 |
|---|---|
| PanelLook | 캡차 차단, PDF 없음 |
| Andesource(유통사) | **"Data sheet: Work in progress"** — 유통사조차 미보유 |
| DatasheetArchive / GoodDisplay / Waveshare | ED115 계열 없음 |
| eBay / AliExpress / Amazon | 판매만 |

확보 가능한 최대 정보는 루트 `README.md:1349` 한 줄:
```
ED115OC1 | E4R | V220 | 2760x2070 | Pearl | 35% | 12:1 | 2012 | TTL | 40핀 | 40P-A | Tested: Yes
```

### epdiy 저자의 "max 10 MHz" 주장 — 반박됨(정황), 반증은 아님

epdiy 저자 martinberlin이 Tindie에 *"avoid ... ED115OC1 (nice resolution but super huge
buffer with **max 10 MHz clock**)"* 라고 적어둠. 사실이면 40.5 MHz는 4배 초과.

**패널 규격이 아니라 ESP32 플랫폼 한계로 판단한다:**
1. epdiy `bus_speed`는 **바이트레이트가 20~22 MB/s로 고정** — 8비트 22 MHz / 16비트 11 MHz.
   16비트가 정확히 절반인 건 ESP32 LCD 주변장치 처리량 한계이지 패널 특성이 아니다.
2. 저자 본인이 Discussion #390에서 *"tested ... and **works**"* 라고 말함.
   실제 미지원 사유는 width>2000 드라이버 행 + PSRAM 2 MB 한계 — **둘 다 ESP32 문제**.
3. epdiy는 ESP32 저주사율 부분갱신, Caster는 FPGA 고주사율 연속스캔. **플랫폼이 다르다.**
   드라이버 병목을 패널 제약으로 오귀속한 것으로 보인다. README의 Tested: Yes도 이를 지지.

> ⚠️ 정황 근거일 뿐이다. **실측 전까지 40.5 MHz는 미검증 가정으로 남는다.**

### 실측 사다리 (plan.md 10장 1-1에 반영됨)

`sysclock.v` rPLL 분주비만 바꿔 비트스트림을 여러 개 굽고, 낮은 쪽부터 올려가며
화면이 깨지는 지점을 찾는다.

| 목표 SDCLK | rPLL (27 MHz 입력) | 프레임레이트 |
|---|---|---|
| 13.5 MHz | ×1/2 | 20.4 Hz |
| 20.25 MHz | ×3/4 | 30.5 Hz |
| 27 MHz | ×1 | 40.7 Hz |
| 33.75 MHz | ×5/4 | 50.9 Hz |
| **40.5 MHz** | **×3/2 (현재)** | **61.1 Hz** |

필요 SDCLK = 662,888 × 목표 FR. **40.5 MHz가 불가해도 프레임레이트를 낮춰 타협 가능하므로
프로젝트가 무산되는 시나리오는 아니다.**

### 아직 안 해본 입수 경로
1. **zephray(Modos)에게 직접 문의** — README에 Tested: Yes를 적은 당사자. **승산 최고.**
2. 패널 원출처 기기 역추적 (2012년 11.5″ 300 ppi). 미특정.
3. AliExpress/eBay 셀러에게 스펙 시트 요청.
4. Andesource RFQ (`andehk@andesource.com`).

---

## 8. 파일별 핵심 위치

| 파일 | 라인 | 내용 |
|---|---|---|
| `rtl/top.v` | — | `localparam VSYNC_PERIOD = 20'd674_999` (60 Hz), FREERUN/STEP로 게이트 |
| | — | `debug_ctrl` 인스턴스 — 버튼/LED 전부 여기서 나옴 |
| | — | `wire sys_ready = drive_en_epdc && ddr_calib_done_epdc;` (PMIC 항 없음) |
| | — | `csr_master` 인스턴스 + 외부 SPI 핀과의 먹스 |
| | — | `assign REFRESH_DONE = (dbg_scan_state == 2'b00);` |
| | — | `epd_selftest` 인스턴스 (LED1 구동) |
| `rtl/debug_ctrl.v` | — | 버튼 디바운스 / 상태 / LED. 파라미터 `CLK_HZ`, `DEBOUNCE` |
| `rtl/csr_master.v` | — | SETMODE 발행용 내부 SPI 마스터. SPI 모드 3, clk/8 |
| `rtl/defines.vh` | 75 | `` `define OUTPUT_16B `` |
| | 124~ | INPUT_HACT 320 / INPUT_VACT 960 |
| | 131 | `` `define DEFAULT_HFP 8'd20 `` |
| | 183 | `` `define DEFAULT_FBYTES `INPUT_HACT * 4 * `INPUT_VACT * 2 `` |
| `rtl/sysclock.v` | — | rPLL: IDIV_SEL(1) FBDIV_SEL(2) ODIV_SEL(16) → 27×3/2 = 40.5 MHz |
| `constraints/gowin_constraints.cst` | — | EPD_GDOE B14, GDCLK A15, GDSP D14, SDCLK E15, SDLE B12, SDOE C12, SDCE0 B13, SD[0..15] / REFRESH_DONE N9 / BTN_N[0..4] T10,T3,T2,D7,C7 / LED[0..5] L16,L14,N14,N16,A13,C13 |
| | — | **N7(구 PMIC_READY)은 이제 미할당.** 되살리려면 포트·CST·`sys_ready` 항을 함께 복원 |

### 🔴 `bin/glider_tang.fs`는 **stale** (7/2자)
16비트 버스 / rPLL / GDCLK RTL 작업 **이전** 산출물이다.
**`make program_bin` 쓰지 말 것.**

---

## 9. plan.md에 남은 정리 작업 (사용자 승인 대기)

이전 세션에서 발견해 보고했으나 **범위 밖이라 일부러 안 고친 것들**:

1. **§9이 stale** — 이미 완료된 작업을 TODO로 나열 중.
   실제 남은 것만 남겨야 함: `mig_wrapper.v`, XIAO 펌웨어, 웨이브폼.
   (`dvi_rx` 배선과 CST HDMI 핀은 삭제됐으므로 2단계 항목으로 이동)
2. **1001줄 문장 중복** — `**VCOM 계산식도 다르다.****VCOM 계산식도 다르다.**`
3. **§7.4 GDCLK 듀티 오류** — HFP=20 기준으로 92.5% → **약 94.2%** (3.05 V → 3.11 V)
4. 519 / 966 / 1304줄의 37.9 MHz는 **의도적으로 남긴 것**
   ("HFP를 4로 줄이면" 대안 시나리오). 지우지 말 것.

---

## 9.5 다음 세션이 이어받을 것 — 우선순위

1. **P&R 타이밍 클로징** ([4장 (1)](#4-즉시-다음-할-일)). 40.5 MHz가 안 나오면
   `debug_ctrl`의 디바운스 카운터 폭이나 `csr_master`가 크리티컬 패스일 가능성은
   낮다 — 기존 픽셀 파이프라인이 먼저다.
2. **보드 단독 확인** ([4장 (4)](#4-즉시-다음-할-일)). 버튼 물리 매핑을 여기서 확정.
3. **블로커 1(IT8951 버스 충돌) 해결** — 이게 패널 연결의 유일한 남은 관문이다.
   plan.md A안(별도 브레이크아웃).
4. **패널 첫 구동** ([4장 (5)](#4-즉시-다음-할-일)). 반드시 수동 스텝부터.
5. 여기까지 되면 **1단계 목표 달성** = 자일링스 Caster 드라이버가 Gowin에서 재현됨.
6. 그 다음이 2단계: `mig_wrapper.v` 실구현(Gowin DDR3 IP) → `dvi_rx.v` 복원 → HDMI 입력.

### 손대지 않은 채로 남은 것
- **XIAO 펌웨어의 PMIC 레지스터 주소 오류** ([2장](#2--하드웨어-안전-사항-제일-중요)).
  FPGA 쪽에서 핸드셰이크를 걷어냈을 뿐, **펌웨어 버그는 그대로다.**
  VCOM은 여전히 설정된 적이 없다. 전압을 실측해서 확인할 것.
- `bin/glider_tang.fs`는 여전히 stale.
- `sim/` (Verilator + SDL2 비주얼 시뮬)은 이번 세션에서 건드리지 않았다.
  **확인 결과 멀쩡하다** — 이쪽은 `top`이 아니라 `caster`를 직접 감싸고
  `vin_*`를 C++에서 먹여주므로, `top.v`/`vin.v` 포트 변경의 영향을 받지 않는다.
  단 `sim/obj`에 stale 오브젝트가 남아 있으면 `dispsim_apply` 링크 에러가 난다.
  `cd sim && make clean && make`로 해결된다.

---

## 10. 작업 방식 메모 (사용자 선호)

- **파괴적 명령은 실행 전에 먼저 알릴 것.** 이전에 `make bringup`이
  `make clean`을 품고 있다는 걸 안 알리고 호출했다가 거부당했다.
  비파괴 검증(스크래치패드 출력)을 우선할 것.
- 사용자는 **점진적 검증**을 선호한다("합성체크부터 해보자" — '부터'에 주목).
  한 번에 다 하지 말고 단계별로 확인받을 것.
- 응답은 **한국어**.
