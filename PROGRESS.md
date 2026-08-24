# 진행상황 — Glider_but_cheaper (Tang Primer 20K 포트)

> 작성일 2026-08-24 · 세션 종료 시점 스냅샷
> 상위 문서: `HANDOVER.md`(2026-08-22 인수인계서) · `plan.md`(설계 계획서)
> 이 문서는 HANDOVER 이후의 **검증 결과와 남은 작업**만 다룬다.

---

## 0. 한 줄 요약

**RTL 레벨 검증 완료 + P&R 타이밍 클로징 통과(78.27 MHz ≥ 40.5 MHz) +
최신 비트스트림 확보.** 하드웨어에서는 아직 아무것도 확인 안 됨.
**다음 단계: 보드 단독 확인(LED 하트비트 → BTN0 → 버튼 매핑).**

---

## 1. ✅ 검증된 것

### 시뮬레이션 (`make simulation` 4단계 전부 통과)

| # | 검증 내용 | 근거 |
|---|---|---|
| A | 전원 인가 직후 EPD 버스 조용함 — GDOE/SDOE 낮음, GDCLK 무토글 | 안전 게이트(BTN0 OFF 기본) 동작 |
| B | BTN0 → 게이트 열림, 2프레임 연속 `GDCLK=1927`, `SDLE=1927`, `SDCE0 active=614400` | 스캔 타이밍 규격 일치 (344×1927) |
| C | BTN3 → `csr_master` SETMODE → caster가 `op_cmd=1 op_param=2 region=0,0..1280,960` 래치 | MCU 없는 모드 전환 경로 |
| D | BTN4 FREERUN 해제 → BTN1로 정확히 한 프레임만 실행 | 수동 스텝 |

### 합성 · P&R (2026-08-23 빌드)

| 항목 | 결과 |
|---|---|
| 전체 빌드 체인 | yosys → nextpnr-himbaechel → gowin_pack 전부 EXIT=0 |
| BSRAM / rPLL / ODDR | 27/46 · 1 · 1 (프론트 패널 추가 전과 동일) |
| 증가분 | LUT +101, MUX +119, DFF +179 (디바운스 5개 + LED 분주기 + SPI 마스터) |
| **최종 Fmax (라우팅 후)** | **78.27 MHz** @ `clk_ddr` 도메인 — 제약 12 MHz PASS |
| 배치 단계 추정치 | 52.61 MHz (참고용, 라우팅 후 상승) |
| **40.5 MHz 목표** | **약 1.9배 여유로 클리어** |
| 크리티컬 패스 | `rst_int` → `trigger` → `caster.scan_h_cnt` CLEAR / `scale_ptr` → `line_reverse.wrptr` 카운터 체인. 픽셀 데이터패스가 아니므로 추가 최적화가 필요하면 카운터/리셋 로직부터 |

### 산출물

| 파일 | 상태 |
|---|---|
| `glider_tang.fs` (7,261,470 bytes, 2026-08-23 생성) | ✅ **최신** — 프론트 패널 + BTN0 게이트 + 16비트 버스 반영 |
| `glider_tang.pnr.json` (19MB) | ✅ P&R 결과 (재패킹용) |
| `bin/glider_tang.fs` | ✅ **최신** — 루트 `.fs`와 동일 내용으로 갱신 (2026-08-23 빌드) |

### 정리 작업 (이전 세션)

`top.v` 711→630줄. 죽은 코드 제거: `timing_generator.v`(빈 파일), chipscope/ILA,
`PMIC_READY`, `BRINGUP_NO_PMIC`, `CSR_SELFBOOT`, `dvi_rx.v`.

---

## 2. ❌ 미검증 / 미완료

### 하드웨어 — 전부 미확인
- 보드 투입 안 함 → LED0 하트비트, BTN0 게이트, **버튼 물리 매핑**(실큐 vs T10 등) 미확인
- 패널 반응 당연히 미확인

### 시뮬레이션이 안 본 것
- `EPD_SD[15:0]` **데이터 내용** — 제어신호만 셈. 체커보드 픽셀이 올바르게 나가는지 미확인
- 패턴 1·2·3 (램프/줄무늬/백색) 미실행 — 패턴 0만 돌음
- 모드 2·3 (블루노이즈/FAST_GREY) 미실행 — 모드 1만 확인
- `make demo`(`PANEL_TEST`) — 합성만 통과, 시뮬 안 돌림
- 웨이브폼 LUT / 그레이스케일 정확도
- DDR3 — `mig_wrapper.v` 여전히 128비트 루프백 스텁
- HDMI 입력 — 의도적 제거 (2단계)

### 손 안 댄 기존 문제 (HANDOVER.md §2 참조)
- **XIAO 펌웨어 PMIC 레지스터 버그**: `REG_VCOM=0x00`은 실제 TMST_VALUE(읽기전용),
  `REG_UP_SEQ=0x02`는 실제 VADJ → VCOM 설정된 적 없음, VPOS/VNEG 오염 가능. 전압 실측 필요
- **블로커 1 유효**: IT8951 TCON 살아있음 — 패널 FPC를 EE03 커넥터에 직접 꽂으면 버스 충돌.
  plan.md A안(별도 브레이크아웃, EE03에서 전원 7선만) 사용

---

## 3. 남은 단계 (순서 고정)

1. ~~P&R 타이밍 클로징~~ → ✅ **2026-08-23 완료 (78.27 MHz)**
2. **보드 단독 확인** ← 지금 여기
   - `make program` (openFPGALoader SRAM 로드)
   - LED0 하트비트(~1 Hz) 확인
   - BTN0 → LED1 셀프테스트 → LED2(DRIVE) 점등 확인
   - 실큐 대조표(HANDOVER.md §2.5)로 버튼 물리 매핑 확정
3. **패널 연결** (블로커 1 해결 후)
   - BTN4로 FREERUN 끄고 BTN1 한 프레임씩
   - 첫 성공 기준: 체커보드(패턴 0)가 화면에 찍힘
4. 그 다음: 나머지 패턴/모드 시뮬, SD 데이터 무결성 검사 추가,
   PMIC 펌웨어 수정 + 전압 실측, (2단계) HDMI 복원, DDR3 실장

---

## 4. 재현 커맨드

```bash
cd Glider_but_cheaper
make simulation   # Verilator 4단계 (A~D)
make              # 합성 + P&R + 비트스트림 → glider_tang.fs
make program      # openFPGALoader SRAM 로드 (전원 끄면 사라짐)
```

> P&R 로그 전문: `/tmp/glider_pnr.log` (세션 종료 시 사라질 수 있음.
> Fmax 요약은 `grep "Max frequency" /tmp/glider_pnr.log`)
