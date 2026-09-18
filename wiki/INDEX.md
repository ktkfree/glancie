# Glancie Knowledge Wiki Index

이 문서는 Glancie 프로젝트의 핵심 설계 결정, 아키텍처, UI/UX 가이드라인을 추적하기 위한 Master Index입니다.

---

## 📑 문서 목록

- [**Design System & UI Architecture**](design-system-and-color-theme.md)
  - 제로 네온(Zero Neon) 및 뮤트 톤 컬러 시스템 결정 이유
  - AI Provider 대표 아이콘 및 미니멀 레이아웃 구조
  - 안정적인 고정폭 숫자 렌더링 (`RollingDigitsView`)
  - UI 구현 시 금지 사항 및 가이드라인

- [**MenuBar Panel & Popover Architecture**](menubar-panel-and-popover.md)
  - Custom NSPanel 기반 메뉴바 팝오버 구조 (`MenuBarPanelController`)
  - 멀티 스크린 네비게이션 및 세션/주간 쿼터 페이싱 마커
  - 실시간 타이머 및 환경설정 연동

- [**Floating Panel Drag & Placement**](floating-panel-drag-and-placement.md)
  - 🚨 **자석 스냅을 걷어낸 이유** — 계단 함수를 움직이는 창에 적용하면 16px 순간이동, 이징은 그것을 감추는 보정이었을 뿐
  - **`PanelDragAnchor`** — 마우스 다운 한 번에 스크린 좌표로 굳히는 유일한 기준점. 임계값 이전 이동분 · 카드 접힘 기하 · **닫힌 바는 `panel.frame`(캐시된 크기 금지)**
  - **드래그 중에는 아무도 창을 건드리지 않는다** — `updateContentSize` 보류, `checkPlacementDirection` 잠금, `sizingOptions = []`, 고양이 hover에 소유권을 넘기지 않기
  - 히트 테스트는 `event.locationInWindow` / 이동은 `NSEvent.mouseLocation` — 좌표계를 섞으면 클릭이 삼켜집니다
  - 🚨 **창 너비의 주인은 `ContentSizeKey` 가 아니라 SwiftUI** — `sizingOptions = []` 여도 NSHostingView 가 8ms 뒤 콘텐츠 크기를 정수로 내림해 창에 되씁니다. 바의 이상 너비가 항상 반 포인트(`71n + 67.5`, 0.5pt 헤어라인)라 `ceil` 은 창이 절대 유지하지 않을 값을 요구했고, 조기 탈출이 한 번도 못 돌았습니다
  - ⚠️ **증상: 앱을 켜면 바가 좌우로 왔다갔다(가로 스크롤)한다** — 창이 가짜 너비 `Metric.panelWidth = 380` 으로 태어난 뒤 그 가짜 midX 로 재정렬 + 스캐너가 프로바이더 개수를 바꾸며 두 번째 도약. 크기도 저장 / 첫 측정은 재정렬 아닌 복원(`.leading` 핀) / 프레임이 멈출 때까지 `alphaValue = 0`
  - 키워드: 플로팅 바, 드래그, drag, 자석, snap, MagnetDockingEngine, ScreenPlacementEngine, 창 점프, restingBarFrame, ContentSizeKey, 멀티 디스플레이, 위치 저장, 시작 시 흔들림, 좌우로 왔다갔다, 가로 스크롤, 창이 옆으로 밀림, panelWidth, panelHeight, pendingInitialPlacement, PanelReanchor, PanelHorizontalPin, sizeTolerance, NSHostingView 리사이즈, 반 포인트, alphaValue, 첫 노출

- [**Account Model & Usage Attribution**](account-model-and-usage-attribution.md)
  - **쿼터는 계정에, 실행중 여부는 소스(CLI/데스크톱앱)에** — 두 축을 분리하는 이유
  - 계정/플랜/쿼터를 읽는 로컬 파일 전수 지도 (`~/.claude.json`의 `cachedUsageUtilization`, `~/.codex/auth.json` JWT, `google_accounts.json`, Cursor `state.vscdb`)
  - 데스크톱 앱(Claude.app / ChatGPT.app / Gemini.app)의 자체 저장소와 계정 ID 접미사 규칙
  - 멀티 계정(`CLAUDE_CONFIG_DIR` / `CODEX_HOME`) 프로필 발견 및 계정별 쿼터 fetch
  - **캐시 신선도와 CLI 프로브** — `cachedUsageUtilization`이 44시간까지 식은 실측, `claude -p "/usage"` 출력 형식·소요 시간·`CLAUDE_CONFIG_DIR` 프로필 프로브
  - 하드코딩 계정·탐욕적 접두사 매칭·추정치 저장·짧은 프로브 타임아웃·`readDataToEndOfFile` 블로킹 등 실제로 밟은 함정
  - 키워드: account, 계정, multi-account, 멀티 계정, usage attribution, 귀속, provider 로그인, 실행중 감지, in-use, NSWorkspace, FSEvents, 프로필, CLI 프로브, probe, 타임아웃, 캐시 신선도, stale, CLIProcessRunner, /usage

- [**Usage Fetch Strategy & Refresh Triggers**](usage-fetch-strategy-and-triggers.md)
  - **언제 캐시를 읽고 언제 CLI를 부르는가** — provider가 디스크에 무엇을 남기느냐로 갈립니다 (Claude `cachedUsageUtilization` / Codex 롤아웃 / Antigravity 없음)
  - **Codex의 진짜 쿼터 소스**: `~/.codex/sessions/**/rollout-*.jsonl` 의 `token_count.rate_limits` — all-null 블록 건너뛰기, `window_minutes`로 창 라벨 유도
  - 신선도 임계값은 `UsageSnapshot.stalenessThreshold` **하나** — 표시용/갱신용을 따로 두면 "stale이라 표시하면서 갱신은 안 함" 구간이 생깁니다
  - `forceSync` = **"파일을 다시 읽어라", 그 이상 아님** — 한때 프로브 백오프까지 건너뛰게 했다가 10초마다 `claude`를 띄웠습니다
  - 🚨 **`ProbeGate`** — 프로세스를 띄우는 판단은 어댑터가 아니라 게이트가. 키별 최소 간격(claude 5분 / agy 3분) · 키별 단일 실행 · **전역 동시 1개**, 무엇으로도 뚫리지 않음
  - **`claude -p`에는 `--strict-mcp-config`** — 없으면 프로브마다 전역 MCP 서버가 전부 기동됩니다 (실측 5.9초 → 3.7초)
  - **트리거**: 스트리밍 감지(즉시) · 턴 종료 · 팝오버 열기 · 상세 진입 · 새로고침 버튼. floor에 걸리면 drop이 아니라 defer
  - ⚠️ **프로브가 자기를 트리거하는 루프** — `claude`가 cwd 슬러그로 트랜스크립트를 씁니다. 전용 cwd + 경로 블랙리스트로 격리
  - Antigravity 프로브의 실제 비용(서버 기동 + Google API 호출, 시간당 로그 67개 / 80MB)
  - 키워드: cache-first, 캐시 우선, forceSync, refresh, 갱신, 새로고침, 트리거, trigger, floor, 하한, ProbeGate, 프로브 게이트, backoff, 백오프, rate limit, strict-mcp-config, MCP, debounce, staleness, 신선도, rate_limits, rollout, 롤아웃, used_percent, window_minutes, 프로브 루프, feedback loop, cwd, 작업 디렉터리, probeWorkingDirectory, refreshOnDemand, 지연, latency

- [**Long-Running Stability & Concurrency**](long-running-stability-and-concurrency.md)
  - 🚨 **증상: 오래 켜두면 socket 에러 + `claude` CLI 먹통** — 원인 추적과 닫은 레이스 전부
  - **어댑터는 `@MainActor` 위에서 돌지 않습니다** — non-isolated `async` 본문은 협력 풀. 어댑터의 저장 프로퍼티는 공유 가변 상태이고, 스윕과 트리거가 겹치면 Dictionary 동시 변형(=힙 손상)
  - `actor` 대신 **`Locked<Value>`** 를 고른 이유(프로토콜의 동기 `isDetected` 요구사항), `ProviderManager`의 provider별 in-flight 단일 실행
  - ⚠️ **`FileHandle.readabilityHandler` + `close()` 는 안전하지 않음** — `availableData`가 catch 불가능한 ObjC 예외를 던집니다. `dup` + `DispatchSource` read source + `setCancelHandler`로 close 시점을 보장
  - **감시 경로는 경계(`/`)까지 비교** — `~/.claude`가 `~/.claude-work`/`~/.claude.json`을 삼킵니다
  - **타이머를 `init`에 두지 말 것** — PixelCat이 꺼도/가려도/잠들어도 초당 8회 재렌더하던 이유. appear/disappear + `occlusionState` 연동
  - `print` 금지 → **`GlancieLog`** (os.Logger, `provider`/`watcher`/`accounts` 3 카테고리)
  - **주기 작업 비용이 히스토리에 비례하면 안 됨** — Codex 롤아웃 전체 재귀 stat, `~/.claude.json` 332KB 재파싱, 프로브 트랜스크립트 118개 누적
  - 키워드: 크래시, crash, 먹통, hang, socket 에러, 장시간 실행, long-running, 메모리, 누수, leak, 동시성, concurrency, data race, 레이스, actor, MainActor, Sendable, Locked, 락, NSLock, in-flight, single-flight, 단일 실행, Process, Pipe, FileHandle, 파일 디스크립터, fd, DispatchSource, readabilityHandler, 타임아웃, timeout, hasPrefix, 경로 매칭, Timer, 배터리, energy impact, occlusion, print, Logger, os_log, 성능, performance, stat, 재귀 열거
