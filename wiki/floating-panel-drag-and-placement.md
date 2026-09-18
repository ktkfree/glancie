# Floating Panel Drag & Placement

이 문서는 데스크톱에 떠 있는 **플로팅 바**(`FloatingPanel` + `FloatingPanelController`)를 잡고 옮기는 동작과, 그 창을 화면 위에 배치하는 규칙을 설명합니다.

> 메뉴바 아이콘에서 내려오는 팝오버(`MenuBarPanelController`)는 별개의 창입니다 — [MenuBar Panel & Popover Architecture](menubar-panel-and-popover.md) 참고.

---

## 1. 자석 스냅(Magnet Snap)을 걷어낸 이유

초기 요구사항(`prd.md` 2번, `Plan.md` Phase 4)에는 노치 하단·화면 상단 중앙으로 빨려 들어가는 자석 흡착이 있었고, `MagnetDockingEngine.snap(frame:in:)` 이 그것을 구현했습니다. **지금은 없습니다.**

- 스냅 판정은 본질적으로 **계단 함수**입니다: 반경 안이면 16px 보정, 밖이면 0. 커서를 따라다니는 창에 이 값을 그대로 적용하면 반경을 벗어나는 **한 프레임에 16px 순간이동**이 일어납니다.
- 이를 시간 기준 이징(`snapEaseTau` / `snapEaseMaxStep`)으로 덮었습니다. 거리 기준 램프는 커서가 빠를 때 한두 프레임에 소진되어 결국 같은 점프가 되기 때문입니다. 즉 **보정을 감추기 위한 보정**이 드래그 루프 한가운데 상주했습니다.
- 게다가 마우스 업 시점에 이징이 갚지 않은 잔여 보정이 남아, "놓은 자리"와 "저장되는 자리"가 달라졌습니다.

정리하면, 사용자가 실제로 원한 것은 **잡은 지점이 커서에 붙어 있는 것** 하나였고, 자석은 그 요구와 상시 충돌했습니다. 드래그 경로를 단순한 좌표 덧셈으로 되돌리는 대가로 자석을 버렸습니다.

같이 사라진 것들:

| 제거 대상 | 위치 |
| --- | --- |
| `MagnetDockingEngine.snap(frame:in:)` / `SnapResult` / `snapThreshold` | → 엔진 자체가 `ScreenPlacementEngine` 으로 개명 |
| `snapOffset`, `snapEaseTau`, `snapEaseMaxStep`, `lastDragTimestamp`, `isCurrentlySnapped` | `FloatingPanelController` |
| `magneticSnappingEnabled` 환경설정 + "가장자리 자석 스냅" 토글 행 | `GlanciePreferences`, `MenuBarSettingsScreen` |

⚠️ `SoundEffectsEngine.playSnapSound()` 는 **남아 있습니다** — 픽셀 고양이 착지음이 계속 씁니다. 미사용으로 착각하고 지우지 마세요.

### `ScreenPlacementEngine` 에 남은 책임

이름 그대로 "창을 실제 화면 위에 두는" 것만 합니다.

- `screen(for:)` — 점이 속한 화면, 화면 사이/바깥이면 가장 가까운 화면
- `clampToScreens(frame:)` — 프레임을 보이는 영역 안으로 끌어당김
- `topMargin` — 상단에서 끌어내릴 때 남길 여백

---

## 2. `PanelDragAnchor` — 드래그의 유일한 기준점

드래그 중 좌표계가 흔들리는 것이 이 화면의 모든 버그의 근원이었습니다. 창이 움직이기 시작하면 창 좌표계는 기준이 될 수 없고, 카드가 닫히면 창 크기가 바뀌며, 레이아웃 콜백이 그 사이에 또 프레임을 건드립니다.

그래서 **마우스 다운 한 번에 스크린 좌표로 기준을 굳혀두고**, 이후 프레임은 전부 그 기준에서 계산합니다.

```swift
struct PanelDragAnchor {
    let pointer: NSPoint   // 누른 순간의 커서 (스크린 좌표)
    let barFrame: NSRect   // 그때 화면에 보이던 "바"의 프레임
    func origin(for pointer: NSPoint) -> NSPoint   // 단순 델타 덧셈
}
```

세 가지 함정을 생성자가 흡수합니다.

1. **임계값 이전 이동분이 사라지면 안 됨** — 기준은 `dragThreshold`(7pt)를 넘은 시점이 아니라 **누른 시점**입니다. 넘은 시점을 기준으로 잡으면 첫 프레임에서 7pt만큼 잡은 지점이 어긋납니다.
2. **카드가 열려 있을 때** — 창은 카드까지 포함한 큰 프레임입니다. 접으면서 남을 바의 위치를 `opensUpward` 기준으로 직접 계산합니다(아래로 열렸으면 창 상단, 위로 열렸으면 창 하단).
3. 🚨 **카드가 닫혀 있을 때는 `panel.frame` 을 그대로 쓴다** — `restingBarFrame.size` 를 쓰면 안 됩니다. 초기 프레임은 `barHeight` 로 만들어지지만 실제 레이아웃된 창은 그림자 패딩과 고양이 띠까지 포함해 더 큽니다. 캐시된 옛 크기로 바꿔 잡으면 수평 드래그만 해도 **바가 위로 튑니다**.

`Tests/GlancieTests/PanelDragTests.swift` 가 이 네 가지 경우를 순수 기하 계산으로 고정해 둡니다(음수 좌표 = 주 디스플레이 왼쪽/아래 디스플레이 포함).

---

## 3. 드래그 중에는 아무도 창을 건드리지 않는다

드래그 루프가 단순해진 대신, **드래그 중 프레임을 만질 수 있는 다른 경로를 전부 막아야** 합니다.

- `updateContentSize(_:)` — SwiftUI `ContentSizeKey` 콜백. 드래그 중이면 `pendingContentSize` 에 넣어두고 **마우스 업 이후에** 반영합니다. 드래그 도중의 리사이즈/재앵커/클램프는 커서와 창을 어긋나게 만듭니다.
- `checkPlacementDirection()` — `guard !isDragging`. 드래그 중 상/하 방향이 뒤집히면 앵커 계산의 전제가 무너집니다.
- `hostingView.sizingOptions = []` — NSHostingView가 제약으로 따로 창을 키우면 `restingBarFrame` 만 옛 높이로 남습니다. ⚠️ 단, 이것이 **창 크기의 주인을 `ContentSizeKey` 로 만들지는 않습니다** — 6절 참고.
- `updateContentSize` 의 "크기 같으면 return" 조기 탈출에서도 닫힌 바 상태라면 `restingBarFrame` 을 갱신합니다. **창 크기가 같다고 저장된 앵커가 최신이라는 보장은 없습니다.**
- `.leftMouseDragged` 는 `isCatDragging` 만 보고 양보합니다. `isHoveringCat` 까지 보면 드래그 도중 커서가 고양이 위를 지나가는 순간 바 드래그의 소유권이 넘어갑니다.
- 마우스 업 후 `hasDraggedRecently` 를 푸는 0.18초 지연은 **그 사이 새 드래그가 시작됐으면 건너뜁니다**. 아니면 새 드래그의 클릭 억제가 이전 드래그 타이머에 꺼집니다.

## 4. 놓는 순간

이동은 근사여도 되지만 **어디에 주차하는가는 결정**입니다. 그래서 마우스 업에서만:

1. 밀린 `pendingContentSize` 반영
2. `clampToScreens` 로 화면 안으로
3. 원점을 **정수 픽셀로 반올림** — 이 값이 `panelOriginX/Y` 로 저장되어 다음 실행 때 복원됩니다
4. `checkPlacementDirection()` 재평가

---

## 5. 이벤트 좌표 규칙 (재확인)

드래그와 직접 얽히는 기존 규칙이라 여기 남깁니다.

🚨 **히트 테스트는 `event.locationInWindow`, 절대 실시간 커서 조회가 아님.** 로컬 모니터 블록이 실행될 때 커서는 클릭 지점에서 수백 pt 지나가 있을 수 있습니다(실측: 유휴 메인스레드 50pt, 바쁠 때 250pt). 실시간 조회는 사용자가 누른 적 없는 위치를 히트 테스트하고 클릭을 삼킵니다 — 다른 창에서 쓸어 오며 바를 한 번에 잡으면 첫 시도가 무시되던 원인.

반대로 **창이 이미 움직이는 중이라면 창 좌표계는 기준이 아니므로** `NSEvent.mouseLocation`(스크린) 한 번을 씁니다. 앵커도 스크린 좌표로 잡아 두었기 때문에 이 조합만 일관됩니다.

---

## 6. 창 너비의 실제 주인은 SwiftUI 입니다

`setFrame` 으로 너비를 지정하고 몇 밀리초 뒤에 창을 다시 읽으면 **다른 값이 나옵니다.** `sizingOptions = []` 여도 NSHostingView 는 레이아웃된 콘텐츠 크기를 **정수로 내림해서** 창에 다시 써넣습니다. 실측:

```
setFrame(w: 352) → panel.frame.width == 352
   ↳ 8ms 뒤                 == 351     // SwiftUI 가 되돌렸음
```

바의 이상 너비는 `71n + 67.5` 로 **항상 반 포인트에 떨어집니다**(0.5pt `HairlineDivider`). 예전 코드는 `ceil` 로 352 를 요구했고, 창은 351 로 돌아갔고, 다음 레이아웃 콜백은 다시 1pt 차이를 보고 또 리사이즈했습니다. 결과:

- `updateContentSize` 의 "크기 같으면 return" 조기 탈출이 **단 한 번도 실행되지 못함**
- `restingBarFrame` 이 항상 실제 창보다 1pt 넓게 유지 — 드래그·팝오버·클램프가 전부 화면에 없는 프레임을 기준으로 계산

그래서 지금은 **SwiftUI 와 같은 방향으로 내림합니다**(`rounded(.down)`). 더불어 `sizeTolerance = 1.0` 미만의 차이는 크기 변경으로 치지 않습니다 — 바의 너비는 칩 하나(71pt) 단위로만 움직이므로 서브포인트 차이는 정의상 반올림 불일치일 뿐입니다. `PanelReanchor.frame` 이 원점을 정수로 맞추는 것도 같은 이유입니다 — 앵커가 창과 0.5pt 어긋나면 재측정될 때마다 중심이 한 걸음씩 걷습니다.

---

## 7. 시작 직후의 가로 흔들림

창은 SwiftUI 가 바를 잴 수 있기 **전에** 만들어집니다. 그래서 첫 프레임은 언제나 추측치였고, 예전 코드는 그 추측치 `Metric.panelWidth = 380` 으로 창을 열고 첫 측정값이 도착하면 **그 가짜 프레임의 midX 를 기준으로 다시 가운데 정렬**했습니다. 오차의 절반만큼 바가 옆으로 밀려난다는 뜻입니다.

실측(저장 위치 x=1400, 프로바이더 3개로 그려졌다가 스캐너가 4개를 돌려줌):

```
예전:  x=1449 (폭 280)  →  x=1414 (폭 351)     // 오른쪽 49px, 다시 왼쪽 35px
지금:  x=1365 (폭 351)                          // 한 번
```

세 가지를 고쳤습니다.

1. **크기도 저장합니다.** `panelWidth` / `panelHeight` 가 `panelOriginX/Y` 옆에 들어갔고, 창은 지난번에 진짜로 가졌던 크기로 태어납니다. 그러면 첫 측정값이 창과 이미 일치해 아무것도 움직이지 않습니다.
2. **첫 측정은 재정렬이 아니라 복원입니다.** `pendingInitialPlacement` 이 창 생성 시점에 정해지고 첫 `updateContentSize` 가 소비합니다. 이때만 `PanelHorizontalPin.leading` — 사용자가 주차해 둔 모서리가 그대로 남습니다. 세션 중의 폭 변화는 예전처럼 `.center`(다이나믹 아일랜드처럼 제 중심을 중심으로 숨 쉽니다).
   - `.restored(NSRect)` — 위치+크기 둘 다 있음. 높이가 변했어도(고양이 토글) 바가 매달린 모서리를 지킵니다.
   - `.restoredOrigin(NSPoint)` — 크기를 저장하지 않던 빌드의 환경설정. 모서리만 복원하고, 이번 실행이 크기를 기록해 다음부터 정확해집니다.
   - `.topCenter` — 저장된 게 없음. **측정된** 폭으로 메뉴바 아래 가운데.
3. **프레임이 멈추기 전까지는 보여주지 않습니다.** 패널은 `alphaValue = 0` 으로 태어나고, 레이아웃이 `revealSettleWindow`(0.14s) 동안 조용해지면 드러납니다. 시작 직후에는 정당한 도약이 하나 더 있습니다 — `ZeroConfigScanner` 가 답하면 프로바이더 개수가 바뀝니다 — 그 둘을 전부 화면 밖에서 끝내는 게 목적입니다. `revealHardDeadline`(0.6s) 가 상한이라, 레이아웃이 끝내 오지 않아도 바가 안 보이는 일은 없습니다.

🚨 **드래그가 시작되면 `pendingInitialPlacement` 을 버립니다.** 안 그러면 드래그 뒤에 밀려 있던 첫 레이아웃이 마우스 업 직후에 도착해 바를 저장된 모서리로 되돌려버립니다.

위치 저장도 마우스 업 전용이 아니게 됐습니다 — `persistRestingFrame()` 이 닫힌 상태의 레이아웃이 확정될 때도 호출됩니다. 프로바이더가 늘어 바가 재정렬되면 저장된 원점도 같이 움직여야 다음 실행이 똑같은 곳에서 열립니다. 값이 실제로 바뀌었을 때만 씁니다 — 레이아웃 콜백 안에서 @AppStorage 에 같은 숫자를 다시 쓰면 렌더 패스만 하나 늘어나기 때문입니다.

`Tests/GlancieTests/PanelPlacementTests.swift` 가 재앵커 규칙과 세 복원 경로를 순수 기하로 고정해 둡니다.

---

## 키워드

플로팅 바, floating panel, FloatingPanelController, 드래그, drag, PanelDragAnchor, 앵커, 잡은 지점, grab point, 자석, 자석 스냅, magnet, snap, MagnetDockingEngine, ScreenPlacementEngine, clampToScreens, 멀티 디스플레이, multi display, 클램프, dragThreshold, hasMovedPastThreshold, isDragging, hasDraggedRecently, updateContentSize, ContentSizeKey, sizingOptions, NSHostingView, restingBarFrame, opensUpward, checkPlacementDirection, 팝오버 접힘, 창 점프, jump, 순간이동, locationInWindow, NSEvent.mouseLocation, 이벤트 지연, 픽셀 고양이 충돌, PixelCat, panelOriginX, panelWidth, panelHeight, 위치 저장, 크기 저장, 시작 시 흔들림, 좌우 이동, 가로 스크롤, pendingInitialPlacement, InitialPlacement, PanelReanchor, PanelHorizontalPin, sizeTolerance, rounded(.down), ceil, alphaValue, revealSettleWindow, revealHardDeadline, NSHostingView 리사이즈, 반 포인트, HairlineDivider
