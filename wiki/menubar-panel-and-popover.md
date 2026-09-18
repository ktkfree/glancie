# MenuBar Panel & Popover Architecture

이 문서는 Glancie의 메뉴바 상주 시스템 및 하이엔드 메뉴바 팝오버(MenuBarPopoverView & MenuBarPanelController)의 구조와 설계 결정을 설명합니다.

---

## 1. 아키텍처 개요

기존 macOS 기본 `NSPopover`의 한계(포커스 해제 시 깜빡임, 서브픽셀 렌더링 제약, 복잡한 네비게이션 애니메이션 시 프레임 드랍 등)를 극복하기 위해 Glancie는 **Custom `NSPanel` 기반의 `MenuBarPanelController`**를 구현했습니다.

```
Status Bar Item (NSStatusItem)
      │
      ▼ (클릭 이벤트)
MenuBarPanelController (NSPanel)
      │
      ▼ (Liquid Glass Background)
MenuBarPopoverView (SwiftUI)
   ├── 1. Overview Screen (전체 Provider 현황 & 미니 게이지)
   ├── 2. Provider Detail Screen (5-Hour, Weekly 게이지, Pacing Marker, 카운트다운 타이머)
   ├── 3. Settings Screen (표시할 Provider On/Off, 햅틱/사운드, 시선 추적, 픽셀 고양이)
   └── 4. Global Action Bar (전체 새로고침, 환경설정, 종료)
```

---

## 2. 핵심 구현 특징

### A. NSPanel 기반 팝오버 (`MenuBarPanelController`)
- **윈도우 레벨**: `level = .popUpMenu` (상시 최상단)
- **외부 클릭 감지**: `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])`를 통해 메뉴바 외부 클릭 시 부드럽게 창 닫힘
- **위치 자동 계산**: `statusItem.button`의 화면 좌표를 기반으로 메뉴바 아이콘 바로 아래 중앙에 정밀 정렬

### B. 멀티 스크린 네비게이션
- `currentScreen` 상태(`ScreenState`: `.overview`, `.providerDetail(AIProviderType)`, `.settings`)를 기반으로 뷰 전환
- `withAnimation(.spring(response: 0.28, dampingFraction: 0.78))`을 적용하여 부드러운 화면 전환 제공

### C. 실시간 쿼터 & 페이싱 마커 (Pacing Marker)
- 주간 쿼터의 경우 현재 소모 추세를 시각적으로 파악할 수 있는 **Pacing Marker** 표시
- 5시간 세션 및 주간 쿼터 잔여 시간(`hourlyResetCountdown`, `weeklyResetCountdown`)을 실시간 카운트다운 문자열(예: `2d 3h 후 재설정`)로 포맷팅

---

## 3. UI/UX 가이드라인 준수
- Apple HIG 네이티브 규격 및 Liquid Glassmorphism 적용
- 제로 네온(Zero Neon) 뮤트 컬러 팔레트 준수
- 모든 버튼 인터랙션 시 `SoundEffectsEngine`을 통한 미세 오디오 피드백 제공
