# Design System & UI Architecture

## 1. 개요 및 설계 철학

Glancie는 macOS 데스크톱 환경에서 상시 플로팅되는 AI 사용량 모니터링 도구입니다. 장시간 화면에 노출되는 유틸리티 특성상 **"시각적 피로도 최소화"**와 **"macOS 네이티브 시스템과의 조화"**를 최우선 가치로 둡니다.

---

## 2. 주요 설계 결정 (Why & Decisions)

### 2.1 제로 네온(Zero Neon) 및 글로우(Glow) 배제
- **배경 / 문제점**: 초기 버전의 높은 채도(고채도 녹색/노랑/주황/빨강) 및 캡슐 게이지 테두리의 화이트 스트로크 글로우(`strokeBorder`)가 형광등처럼 번쩍거려 사용자에게 심한 눈부심과 피로감을 유발함.
- **결정 사항**:
  - 모든 형광빛 원색 및 인라인 글로우 오버레이를 완전히 제거.
  - macOS 시스템 네이티브 컬러 토큰(`NSColor.systemGreen`, `systemTeal`, `systemOrange`, `systemRed`) 기반의 차분한 뮤트 톤 적용 (`UsageColorTheme.swift`).
  - 팝오버 텍스트와 아이콘은 원색 대신 Apple 표준 레이블 컬러(`Color.primary`, `Color.secondary`) 사용.

### 2.2 눈모양(페이스 캐릭터) 제거 및 AI Provider 아이콘 단일화
- **배경 / 문제점**: 눈모양(`• ~ •`) 마이크로 캐릭터와 시선 추적 모션이 제한된 28px 플로팅 바 공간을 과도하게 차지하고, 정보 전달의 명확성을 저해함.
- **결정 사항**:
  - 캐릭터 표정 및 파티클을 제거하고, 각 AI Provider(Claude, Codex, Antigravity, Cursor)의 **대표 SF Symbol 아이콘 + 고정밀 % 숫자 + 미니멀 게이지 바** 형태로 레이아웃 단일화 (`ProviderSegmentView.swift`).

### 2.3 안정적인 숫자 렌더링 (RollingDigitsView 글리치 방지)
- **배경 / 문제점**: SwiftUI의 `.contentTransition(.numericText)`가 28px 슬림 바 내에서 렌더링될 때 글리프가 세로로 찌그러지거나 겹쳐 보이는 결함 발생.
- **결정 사항**:
  - 트랜지션 애니메이션 대신 `.monospacedDigit()` 및 `.fixedSize()`를 사용하여 어떠한 경우에도 숫자가 밀리거나 겹치지 않는 안정적인 고정폭 렌더링 구조로 변경.

---

## 3. 컬러 팔레트 스펙 (`UsageColorTheme`)

| 잔여 쿼터 범위 | 시각적 톤 | 적용 토큰 및 투명도 | 의미 |
| :--- | :--- | :--- | :--- |
| **80% ~ 100%** | 은은한 세이지 그린 | `Color(nsColor: .systemGreen).opacity(0.80)` | 쿼터 충분 / 안정 |
| **50% ~ 79%** | 부드러운 뮤트 틸 | `Color(nsColor: .systemTeal).opacity(0.75)` | 정상 사용 |
| **20% ~ 49%** | 따뜻한 웜 앰버 | `Color(nsColor: .systemOrange).opacity(0.80)` | 주의 / 소진 진행 |
| **0% ~ 19%** | 차분한 뮤트 로즈 | `Color(nsColor: .systemRed).opacity(0.75)` | 경고 / 소진 임박 |

---

## 4. 코드 패턴 및 주의사항 (Implementation Rules)

1. **텍스트 및 아이콘 컬러링 금지**:
   - `DetailGlassCardView` 및 `ProviderSegmentView`의 텍스트와 아이콘에 `UsageColorTheme`의 색상을 직접 입히지 마십시오. (텍스트는 항상 `.primary` / `.secondary` 유지)
2. **게이지 바 글로우 추가 금지**:
   - `LiquidCapsuleGauge`에 화이트 오버레이 스트로크나 `.shadow` 글로우를 임의로 추가하지 마십시오.
3. **고정폭 레이아웃 유지**:
   - 퍼센티지 숫자 표시는 항상 `RollingDigitsView` 또는 `.monospacedDigit()`를 사용하여 자릿수 변경 시 레이아웃 흔들림을 방지하십시오.
