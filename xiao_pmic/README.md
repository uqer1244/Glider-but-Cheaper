# xiao_pmic — EE03를 Glider의 PMIC로

Seeed **XIAO ePaper Display Board EE03**(XIAO ESP32-S3 + IT8951 TCON +
TPS651851 PMIC) 위에서 도는 펌웨어. 역할은 둘이다.

1. **PMIC 운용** — e-ink 고전압 레일(VPOS/VNEG/VGH/VGL/VCOM)을 만들어 **유지**한다.
   FPGA가 EPD 제어신호를 쏘는 동안 전원 공급기 노릇을 한다. 조작은 보드의 물리 버튼 3개.
2. **패널 자가진단** — 패널 FPC를 EE03의 J1에 직접 꽂으면 IT8951로 테스트 패턴을
   그린다. FPGA가 만든 화면과 비교할 **골든 레퍼런스**를 얻는 용도.

Seeed_GFX에 의존하지 않는다. IT8951 전송 규약은 직접 구현했다.

---

## 버튼 — 전부 짧게 누르기

| 버튼 | GPIO | 기능 |
|---|---|---|
| **BUTTON1** | 2 | **레일 ON.** PWR_EN → TCON 리셋 → VCOM 검증 → 레일 올리고 유지 |
| **BUTTON2** | 3 | **레일 OFF.** IT8951 `SLEEP` → PMIC가 자기 다운시퀀스대로 순서 있게 내림 |
| **BUTTON3** | 5 | **비상 차단.** `PWR_EN` 즉시 LOW |

BUTTON2와 3은 달라 보이지 않지만 다르다. `SLEEP`은 TPS65185의 다운시퀀서에 일을
넘겨 레일이 패널이 기대하는 순서로 떨어진다. `PWR_EN` 차단은 PMIC 입력을 뽑아버려
모든 레일이 각자 RC대로 무너진다. **평소엔 2번, 뭔가 잘못됐을 땐 3번.**

3번은 **SPI를 한 줄도 쓰지 않고**, HRDY 대기·리프레시 대기 루프 **안에서도** 폴링된다.
펌웨어가 한가할 때만 먹히는 비상정지는 비상정지가 아니라서다.

## 안전 인터록

- **VCOM.** 이 보드는 매 파워업마다 VCOM이 −2.50 V로 돌아온다(휘발성). 패널 라벨은
  −1.31 V다. 레일을 올리기 **전에** 1310 mV를 쓰고 3회 연속 같은 값으로 되읽지 못하면
  레일을 올리지 않는다. 그리고 **레일이 올라온 뒤 한 번 더** 확인한다 — 파워업 시퀀스
  도중 펌웨어가 되돌려 쓸 수 있기 때문. 틀리면 한 번 다시 쓰고, 그래도 틀리면 내린다.
- **부팅 시 아무것도 켜지 않는다.** USB를 다시 꽂아도 고전압이 무인으로 올라오지 않는다.
- 시리얼 `force`로 인터록을 해제할 수 있고, 해제할 때 무엇을 해제하는지 출력한다.

## 시리얼 콘솔 (115200)

```
on | hold    레일 올리고 유지          (BUTTON1과 동일)
off | drop   레일 순서 있게 내림        (BUTTON2와 동일)
cut          PWR_EN 즉시 LOW           (BUTTON3과 동일)
status       지금 무엇이 켜져 있다고 믿는지
info         TCON 리셋 + 지오메트리/FW/VCOM/온도
vcom [mv]    VCOM 읽기 / 쓰고 되읽기
run          패널 자가진단 — 패턴 로드 후 GC16
pat 0..5     white / black / 16단 그레이 계단 / 램프 / 체커 / 지오메트리
show, du, init, clear, geo fw|115, mirror on|off, temp <c>, force, help
```

## 빌드 / 업로드

라이브러리 설치 불필요.

```sh
arduino-cli compile -b esp32:esp32:XIAO_ESP32S3 xiao_pmic
arduino-cli upload  -b esp32:esp32:XIAO_ESP32S3 -p /dev/cu.usbmodemXXX xiao_pmic
```

보드 기본값이 `cdc_on_boot=1`이라 `Serial`은 USB로 간다 — UART0(GPIO43/44)로 가지
않는다. 그 두 핀은 이 보드에서 `PWR_EN`과 `TFT_CS`다.

## 이 보드에서 실측된 것

| | |
|---|---|
| HRDY 리셋 해제 | 1605 ms (정상 부팅의 서명. `PROGRESS.md` §1.19) |
| TCON 프로파일 | 1872×1404, FW `Seeed_v.0.1`, LUT `3M29T` — 10.3인치용이다 |
| 패널 | ED115OC1 2760×2070. 해상도 불일치는 알고 감수한다 |
| VCOM 기본값 | 2500 mV, 휘발성 |
| 레일 유지 | **리프레시 후 SYS_RUN을 유지하면 레일이 계속 살아 있다** (2026-09-09) |
| 레일 실측 | VGH ~28 V, VGL ~−20 V, ±15 V. 패널이 실제로 그려지는 것으로 검증됨 |

> IT8951 읽기는 **워드마다** HRDY를 기다려야 한다. 한 번만 기다리면 4 MHz에서
> 워드가 stale로 재판독된다 — `GET_DEV_INFO`가 FW를 `Seeed_v.v.0.1`로 읽어냈고
> 뒤쪽 널 패딩이 밀림을 숨겼다. 1워드짜리 레지스터 읽기에서 같은 일이 나면
> **안 끝난 리프레시가 끝난 것처럼 보인다.**

## FPGA와 같이 쓸 때

⛔ **패널을 J1에 꽂은 채로 FPGA를 붙이면 안 된다.** IT8951이 `ED0-15`/`SDCLK`/
`SDLE`/`GDCLK`를 J1의 바로 그 핀에 물고 있고, 레일을 유지하려면 IT8951은 깨어 있어야
한다. EE03에서 **전원만** 뽑아 별도 브레이크아웃으로 패널에 주고, 데이터·제어는
FPGA가 직접 준다. 테스트포인트에서 뽑으면 J1을 아예 안 건드려도 된다.

전체 배선표·운용 순서·보호 회로는 **[`../docs/WIRING.md`](../docs/WIRING.md)**.

## legacy/

교체 전의 `xiao_pmic`. PMIC 레지스터 주소가 틀려 있었고(`0x00`은 VCOM이 아니라
읽기전용 `TMST_VALUE`, `0x02`는 `VADJ`) 그 상태로 IT8951을 사망 판정했던 코드다.
결론은 §1.19에서 뒤집혔다. 커밋되지 않은 진단 코드(`spi_probe()`)를 담고 있어
보존한다. Arduino는 서브폴더의 `.ino`를 컴파일하지 않는다.
