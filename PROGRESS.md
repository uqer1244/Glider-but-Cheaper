# 진행상황 / 인수인계 — Glider_but_cheaper (Tang Primer 20K 포트)

> 최종 갱신 2026-08-24 (하드웨어 브링업 + UART 콘솔 + fail 코드 3 원인 규명)
> 상위 문서: `HANDOVER.md`(설계·안전사항 권위 문서) · `plan.md`(설계 계획서)
> 이 문서는 검증 결과·현재 상태·다음 작업만 다룬다.

---

## 0. 한 줄 요약

**plan.md 1단계 1-3 게이트 통과 — FPGA 내부 로직과 EPD 버스가 실물에서 검증됨.**
GDCLK 1927 / SDLE 1927 / SDCE0 614400, 오차 0, 25프레임 연속 동일.

**fail 코드 3은 스캔 결함이 아니라 파라미터 폭 절단 버그였다**(§1.2). EPD 스캔
타이밍은 처음부터 정상이었다. 진단 수단으로 **UART 디버그 콘솔**을 새로 붙였고,
그것이 원인을 즉시 드러냈다(§1.3).

**다음: 패널 없이 가능한 검증은 SD 버스 뿐 → 그 다음은 블로커 1 해제 후 패널.**

---

## 1. 하드웨어 브링업 결과 (2026-08-24)

### 1.1 확정 ✅

| 항목 | 결과 |
|---|---|
| JTAG / SRAM 로드 | `openFPGALoader --detect` 인식, `make program` 성공 |
| LED0 하트비트, BTN0→LED2, BTN4→LED3(FREERUN) | 전부 정상 |
| **SDCLK E15 = 1.65V** | 스캔 클럭 토글 중 |
| **GDCLK A15 = 3.05V** | 사양 일치 |
| **SDCE0 B13 = 0.296V** | 사양 일치 (91% Low) |
| GDCLK/SDLE 카운터 | fail 코드가 **3**이라는 것 = 두 카운터 모두 **정확히 1927** |
| **SDCE0 active_cnt** | 스캔 OFF로 얼린 값 **0x90000**(589,824) — 프레임 ~96% 지점. 카운팅 자체는 건강 |

> ⚠️ 첫날 B13=3.3V / A15=0V 측정치는 **프로브 착오**(재측정으로 반박됨).
> 인접 핀 GDOE/SDOE는 구동 중 상시 High(3.3V)가 정상. 헤더 프로빙 시 실크 재확인할 것.

### 1.2 해결 — fail 코드 3의 진짜 원인 (파라미터 폭 절단)

**스캔은 정상이었다. 기대값이 0이었다.**

```verilog
`define DEFAULT_HACT 12'd320
`define DEFAULT_VACT 12'd1920
.EXP_ACTIVE(`DEFAULT_HACT * `DEFAULT_VACT)   // top.v -- 12비트로 잘림
```

Verilog에서 곱셈 결과 폭은 피연산자 최대 폭이다. 둘 다 12비트라 결과도 12비트로
잘리는데, `320 * 1920 = 614400 = 4096 * 150`이라 **나머지가 정확히 0**이다.

| 툴 | 평가 결과 |
|---|---|
| iverilog | 32비트 정수 문맥으로 승격 → 614400 → **시뮬 통과** |
| yosys | 규칙대로 절단 → **0** → `active_cnt != 0` 항상 참 → **실물 fail 3** |

`EXP_VTOTAL`(1927)은 12비트에 들어가 안 잘렸다. **그래서 GDCLK/SDLE만 맞고
SDCE0만 틀리는** 정확히 그 증상이 나왔다.

UART 한 줄이 이걸 즉시 드러냈다 — `E=+096000`, 즉 오차가 기대값 전체와 같았다.

**수정**: `defines.vh`에 폭을 미리 넓힌 `DEFAULT_VTOTAL` / `DEFAULT_ACTIVE`를 두고
`top.v`·`tb_top.v`가 공유. 점에서 곱하지 말 것. yosys 재확인 `32'd614400`, 실물
재확인 `E=+000000 P=1 F=0`.

> ⚠️ 파라미터 오버라이드에는 정수 문맥이 생기지 않아 `localparam integer` 트릭이
> 안 먹힌다. `tb_top.v`에는 이 함정을 경고하는 주석이 이미 있었는데 `top.v`에는
> 적용돼 있지 않았다. 앞으로 사이즈드 리터럴끼리 곱하는 자리는 전부 의심할 것.

> ⚠️ 이전 세션의 `active_cnt = 0x90000` 판독은 **성립하지 않는다**. 당시
> `nib_idx`가 2비트라 21비트 카운터의 하위 16비트만 보였고(0x96000의 상위 니블
> `9`는 표시 불가), LED 극성도 뒤집혀 읽혔다. 정상값 (idx3, 니블 6)이
> (idx0, 9)로 보이는 조합이었다.

### 1.3 UART 디버그 콘솔 (신규 — 주력 진단 수단)

Tang Primer 20K **Dock**의 FT2232는 2채널이고, 채널 B가 FPGA **M11**에 이미
배선돼 있다. **추가 배선 없이** 기존 USB 케이블 그대로 쓴다.

| 포트 | 용도 |
|---|---|
| `/dev/cu.usbserial-1100` | JTAG (openFPGALoader) |
| `/dev/cu.usbserial-1101` | **UART 콘솔** |

프레임마다(기본 15프레임에 1회 = 초당 4줄) 한 줄이 나온다:

```
G=787 S=787 A=096000 E=+000000 P=1 F=0
│     │     │        │         │   └ fail_code
│     │     │        │         └───── pass
│     │     │        └─────────────── active_cnt - 기대값, 부호+절대값
│     │     └──────────────────────── SDCE0 액티브 사이클
│     └────────────────────────────── SDLE 상승 에지
└──────────────────────────────────── GDCLK 상승 에지
```

전부 16진. 정상 = `G=787 S=787 A=096000 E=+000000 P=1 F=0`.
값이 16비트를 넘으면 포화(`7fffff`/`800000`)시켜, 랩어라운드된 값이 작은 오차처럼
보이는 일이 없게 했다.

읽는 법:
- `E=+000000` → 카운트 정확
- 320의 배수(`±000140` 등) → **라인 단위** 누락/초과 (320 = HACT)
- 320의 배수가 아님 → 라인 내부에서 어긋남 (클럭 인에이블/CDC 의심)
- 줄마다 값이 흔들림 → 과도기가 아니라 불안정 (신호 무결성)

**BTN0을 눌러 스캔이 돌아야 줄이 나온다.** 스캔이 멈춰 있으면 GDSP가 토글하지
않아 프레임 펄스가 없다. 한 줄도 안 나오는 것 자체가 정보다.

관련 RTL: `rtl/uart_tx.v`(8N1 송신기), `rtl/debug_uart.v`(포매터),
`epd_selftest.v`의 `frame_done` + 래치 출력 포트.

### 1.4 UART 받는 법 (중요)

보드를 다시 꽂을 때마다 `/dev/cu.usbserial-1101`의 termios가 **9600으로
리셋**된다. `stty`로 잡아도 포트를 닫는 순간 날아가므로 소용없다.
**포트를 연 채로 보율을 설정해야 한다.**

```bash
python3 - <<'EOF'
import serial, time
s = serial.Serial('/dev/cu.usbserial-1101', 115200, timeout=0.2)
s.reset_input_buffer()
end = time.time() + 10
while time.time() < end:
    d = s.read(4096)
    if d: print(d.decode('ascii','replace'), end='')
EOF
```

`cat /dev/cu.usbserial-1101` 로 받으면 글자가 깨진다 — 이 함정에 한 번 빠졌다.

### 1.5 BTN2 니블 리드아웃 (보조 — 이제 거의 쓸 일 없음)

BTN2 홀드 중 LED 6개가 `E` 필드(오차)를 16진 니블로 순환 표시한다.
인덱스 2비트 + 값 4비트 = LED 6개를 전부 쓴다. **점등 = 논리 1**
(`debug_ctrl`이 `~diag`로 반전해 active-low LED를 직접 구동).
정상이면 네 니블 모두 0. UART가 있으면 UART를 쓸 것.

---

## 2. 다음 작업 (순서 고정)

1. **`make simulation` 4단계 재검증** — 오늘 RTL을 크게 바꿨는데 아직 안 돌렸다
2. **SD 버스 검증** ← 패널 없이 가능한 마지막 항목.
   plan.md §7.4가 **"SD[15:8]이 0 V가 아닌 것이 16비트 전환의 증거"**라 했는데
   아직 아무도 확인 안 했다. 멀티미터 대신 fabric에서 세어 UART로 뽑는 쪽이 낫다:
   - `EPD_SD[15:8]` 토글 여부 (8비트 모드면 상수 0이었다)
   - `2'b11`(Hi-Z) 출력 0건 — plan.md 기대값 표에 있으나 미검사
3. **1-1 SDCLK 클럭 사다리 실측** — plan.md 리스크 표의 유일한 "높음 + 우회 불가".
   40.5 MHz는 여전히 **정황 근거만 있는 미검증 가정**이다. 패널 필요
4. **1-2 PMIC 전압 실측** (VCOM/VPOS/VNEG) + 레지스터 버그 수정
5. **블로커 1 해제** — EE03 IT8951 TCON 살아있음. plan.md A안 브레이크아웃
6. 1-4 패널 데모 점등 (`make demo`)
7. 이후: 패턴/모드 시뮬 보강, (2단계) HDMI 복원, DDR3 실장

---

## 3. 미완료 목록 (이전 세션에서 이어짐)

- 시뮬 미검증: `EPD_SD[15:0]` 데이터 내용, `2'b11` 0건, 패턴 1·2·3, 모드 2·3,
  `make demo`(PANEL_TEST), 웨이브폼 LUT/그레이스케일
- plan.md가 코드와 어긋남: `make bringup` 타깃 없음(제거됨), `PMIC_READY` 신호
  자체가 없음(`top.v:55`), §7.4 Fmax 62 MHz는 옛날 값
- DDR3: `mig_wrapper.v` 여전히 128비트 루프백 스텁
- HDMI: 의도적 제거 (2단계 복원)
- XIAO 펌웨어 PMIC 레지스터 버그 (`REG_VCOM=0x00`=TMST_VALUE 읽기전용,
  `REG_UP_SEQ=0x02`=VADJ) — VCOM 설정된 적 없음, 전압 실측 필요
- **블로커 1 유효**: EE03 IT8951 TCON 살아있음 — 패널 FPC 직결 금지,
  plan.md A안 브레이크아웃 필요
- 버튼 물리 매핑: 실큐 예상표(T10/T3/T2/D7/C7) 있으나 실물 대조 미확정

## 4. 재현 커맨드 & 참고

```bash
cd Glider_but_cheaper
make simulation   # iverilog top 레벨 (몇 분 — 백그라운드 권장)
make              # yosys → nextpnr → gowin_pack → glider_tang.fs
make program      # openFPGALoader SRAM 로드
```

- P&R 기준: Fmax 79.30~92.15 MHz @ clk_ddr (목표 40.5MHz, 여유 충분).
  크리티컬 패스는 스캔 카운터 체인 (픽셀 패스 아님)
- 시뮬 하네스 2종 존재: `sim/main.cpp`(Verilator, caster 단독 — selftest 미포함),
  `rtl/tb_top.v`(iverilog, top 전체 — `make simulation`)
- 셀프테스트 LED 극성: 보드 LED는 active-low, `debug_ctrl.v`에서 `~` 반전 후 출력.
  **"켜짐 = 논리 0"** — 판독 시 항상 유의
