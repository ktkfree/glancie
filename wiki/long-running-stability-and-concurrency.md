# Long-Running Stability & Concurrency

**항상 켜져 있는 앱이 오래 살아 있을 때 무너지는 지점들.** 몇 분 돌려서는 절대 보이지 않고, 하루를 넘기면 반드시 보입니다.

관련: [Usage Fetch Strategy & Refresh Triggers](usage-fetch-strategy-and-triggers.md) — *언제 CLI를 부르는가*는 그쪽입니다. 이 문서는 **부른 다음에 죽지 않는 법**을 다룹니다.

---

## 0. 이 문서가 생긴 이유

사용자 보고: *"오래 실행해두면 갑자기 socket 에러도 발생하는 것 같고, 너무 빈번한 `.claude` 호출 때문인지 claude CLI 가 먹통되는 현상도 발생함."*

1차 원인은 프로브 폭주였고 그건 fetch strategy 문서 §4/§8이 다룹니다. 하지만 그 부하는 **원인이 아니라 증폭기**였습니다. 10초마다 프로세스를 띄우자 평소엔 몇 시간에 한 번 열릴까 말까 한 레이스 창들이 매분 열렸을 뿐입니다. 폭주를 막아도 아래 것들은 그대로 남아 있었습니다.

> **부하를 줄여 증상이 사라졌다면, 고친 게 아니라 재현 확률을 낮춘 것입니다.** 레이스는 따로 닫으십시오.

---

## 1. 어댑터는 MainActor 위에서 돌지 않습니다

`ProviderManager`는 `@MainActor`입니다. 그래서 어댑터도 그럴 것 같지만 **아닙니다.**

```swift
// ProviderManager (@MainActor) 안에서
let fetched = try await adapter.fetchUsagePerAccount(forceSync: forceSync)
//                     ^^^^^^^ 이 함수 본문은 협력 풀에서 실행됩니다
```

`AIProviderAdapter`는 actor도, `@MainActor`도 아닌 평범한 프로토콜입니다. non-isolated `async` 함수는 호출자의 액터를 물려받지 않고 제네릭 실행자로 넘어갑니다. 즉 **어댑터의 저장 프로퍼티는 전부 공유 가변 상태**입니다.

실제로 두 개가 동시에 들어옵니다:

```
45초 주기 스윕 ─┐
                ├─→ 같은 ClaudeCodeAdapter 인스턴스 → lastProbeAttempt / cachedSnapshot 동시 변형
activity 트리거 ─┘
```

Dictionary 동시 변형은 stale read가 아니라 **힙 손상**입니다. 장시간 실행 후의 원인 불명 크래시는 여기를 먼저 의심하십시오.

### 1.1 왜 `actor`로 바꾸지 않았나

프로토콜에 동기 요구사항이 있습니다:

```swift
var isDetected: Bool { get }        // MenuBar가 동기적으로 읽습니다
```

actor로 만들면 이건 `nonisolated` 계산 프로퍼티여야 하고, 그러면 결국 **뒤에 락이 필요합니다.** 요구사항을 `async`로 바꾸면 `isProviderDetected` → 뷰 body까지 전염됩니다. 락 하나로 끝날 일에 프로토콜과 호출부 전체를 바꾸는 건 남는 장사가 아닙니다.

**채택: `Locked<Value>`** (`Sources/Glancie/Support/Locked.swift`)

```swift
private let detected = Locked(false)
public var isDetected: Bool { detected.value }        // 어디서든 읽기 가능
...
detected.value = found                                 // checkAvailability에서 쓰기

// get → set 사이에 끼어들면 안 되는 경우
counter.withValue { $0 += 1 }
```

저장된 가변 상태를 가진 어댑터는 전부 이 패턴입니다: `ClaudeCodeAdapter`, `AntigravityAdapter`, `CursorAdapter`, `OpenAI_CodexAdapter`. 클래스에는 `@unchecked Sendable`을 붙입니다 — 락으로 보증한다는 선언입니다.

> **어댑터에 `private var`를 새로 추가한다면 그건 이미 버그입니다.** `Locked`로 감싸거나 액터로 옮기십시오.

### 1.2 매니저 쪽 단일 실행

락은 자료구조를 지킬 뿐, **같은 CLI를 두 번 띄우는 것**은 막지 못합니다. 그건 `ProviderManager`가 provider별로 막습니다.

```swift
if let existing = inFlightRefreshes[provider] {
    await existing.value      // 이미 가져오는 중인 답을 기다린다
    return
}
```

- 엔트리 정리는 **Task 내부 `defer`**에 둡니다. 바깥 `await` 뒤에 두면, 기다리던 호출자가 취소됐을 때 아직 도는 fetch의 엔트리를 지워버리고 두 번째가 옆에 붙습니다.
- `refreshAll`도 어댑터를 직접 부르지 않고 `refreshProvider`를 경유합니다. **직접 부르던 그 코드가 스윕과 트리거가 겹치던 지점이었습니다.**

---

## 2. 프로세스를 띄우는 코드의 수명 관리 (`CLIProcessRunner`)

### 2.1 `readabilityHandler` + `close()` 는 안전하지 않습니다

```swift
// 이렇게 하지 마십시오
pipe.fileHandleForReading.readabilityHandler = nil
try? pipe.fileHandleForReading.close()
```

핸들러는 **Foundation이 소유한 큐**에서 돕니다. `nil` 대입은 다음 호출을 막을 뿐, *지금 실행 중인* 호출을 기다려주지 않습니다. 그 호출 안의 `handle.availableData`가 닫힌 fd를 만나면 `NSFileHandleOperationException`을 던지고, **Objective-C 예외는 Swift에서 잡을 수 없습니다.** 프로세스가 그대로 죽습니다.

프로브 빈도가 높을수록 이 창이 커집니다. 10초마다 띄우던 동안은 하루에 수천 번 열렸습니다.

**채택: 우리가 소유한 fd + dispatch read source**

```swift
let readFD = dup(pipe.fileHandleForReading.fileDescriptor)   // run() 이후에
try? pipe.fileHandleForReading.close()

let source = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: ...)
source.setEventHandler { /* read(2) 직접 */ }
source.setCancelHandler { close(readFD) }                    // ← 핵심
source.resume()
```

`cancel()`은 **in-flight 이벤트 핸들러가 반환한 뒤에만** 취소 핸들러를 부릅니다. close 시점이 언어 차원에서 보장됩니다.

`dup`은 이중 close를 피하기 위한 것입니다: Pipe의 `FileHandle`은 dealloc 때 자기 fd를 닫으므로, 우리가 쓸 복사본을 따로 들고 원본은 즉시 닫습니다. `dup`은 반드시 **`process.run()` 성공 이후에** 하십시오 — 그 전에 read end를 건드리면 Foundation이 spawn 시점에 참조합니다.

### 2.2 `readDataToEndOfFile` 로 돌아가지 마십시오

EOF는 **모든 write end 복사본이 닫혀야** 옵니다. 자식이 죽어도 손자가 하나 들고 있으면 read는 영원히 블로킹되고, 타임아웃은 장식이 됩니다. 이건 이미 한 번 밟은 함정입니다.

### 2.3 재개는 한 번, 정리는 완료 지점에

- `OutputCollector.claimCompletion()`이 **첫 호출자에게만 true**를 돌려줍니다. 종료와 타임아웃 중 누가 먼저 오든 continuation은 정확히 한 번 재개됩니다.
- 타이머/소스 취소는 `finish()`가 아니라 `collector.onCompletion`에 답니다. 그래야 `finish()`가 순수한 "continuation 재개"로 남고, 정리 순서를 한 곳에서 봅니다.
- setter는 **이미 완료된 상태면 즉시 실행**합니다. 프로세스가 핸들러 등록보다 빨리 끝나는 경우가 실제로 있습니다.

---

## 3. 감시 경로는 경계까지 비교하십시오

```swift
eventPath.hasPrefix(mapping.path)   // ✗
```

`~/.claude`는 `~/.claude-work`의 접두사이고 `~/.claude.json`의 접두사이기도 합니다. 두 번째 프로필의 쓰기가 첫 번째 프로필의 것으로 귀속됩니다.

```swift
FSEventsWatcher.path(eventPath, isWithin: mapping.path)   // ✓ 경계(`/`)까지
```

지금은 두 경로가 같은 provider라 증상이 안 보입니다. **접두 관계인 루트가 서로 다른 provider가 되는 날 조용히 틀리기 시작합니다.** 계정 귀속(`resolveAccount`)도 같은 함수를 씁니다.

---

## 4. 상시 실행 앱에서 타이머를 `init`에 두지 마십시오

`PixelCatEngine`이 `init`에서 0.12초 타이머와 1초 타이머를 시작했습니다. 결과:

- `@Published` 변경 → **초당 8회 SwiftUI 재렌더**
- 설정에서 고양이를 꺼도 (`pixelCatEnabled == false`) 엔진 객체는 살아 있으므로 계속 돎
- 전체 화면 창에 가려도, 디스플레이가 잠들어도 계속 돎

**채택: 표시 상태에 연동**

```swift
public init() {}                       // 아무것도 시작하지 않음

.onAppear  { catEngine.viewAppeared() }
.onDisappear { catEngine.viewDisappeared() }
```

`viewAppeared()`가 `NSApplication.didChangeOcclusionStateNotification`도 구독해서, **가려지면 멈추고 다시 보이면 재개**합니다. `startLoops()`는 `guard animationTimer == nil`로 중복 시작을 막습니다.

> 유휴 상태의 메뉴바 앱은 애니메이션할 이유가 없습니다. 배터리 임팩트는 사용자가 앱을 지우는 이유가 됩니다.

---

## 5. 로깅: `print` 금지

FSEvents 경로에서 `print`는 **이벤트당 한 줄**입니다. 스트리밍 중이면 초당 수십 줄이고, 그 포매팅은 필터링을 하는 그 스레드에서 일어나며, 번들로 실행되는 순간 아무도 그 stdout을 읽지 않습니다.

**채택: `GlancieLog`** (`Sources/Glancie/Support/GlancieLog.swift`) — `com.glancie` 서브시스템에 카테고리 3개.

| 카테고리 | 대상 |
| :--- | :--- |
| `provider` | 어댑터, fetch 전략, 프로브 |
| `watcher` | FSEvents, 활동 필터, 실행중 상태 |
| `accounts` | 계정 발견/귀속 |

```bash
log stream --predicate 'subsystem == "com.glancie"' --level debug
```

`Logger`는 **아무도 안 듣고 있으면 비용이 없습니다.** 대신 보간에 privacy를 명시하십시오 — provider 이름 같은 건 `.public`, 계정 요약처럼 사람을 식별할 수 있는 건 `.private`. 로그는 그것이 나온 창보다 오래 삽니다.

---

## 6. 비용이 사용자 히스토리와 함께 자라는 코드

45초마다 도는 코드의 비용은 **사용자가 이 도구를 얼마나 오래 썼는지에 비례하면 안 됩니다.** 실측으로 걸린 세 곳:

| 위치 | 자라던 것 | 해법 |
| :--- | :--- | :--- |
| `OpenAI_CodexAdapter.rolloutFiles` | `~/.codex/sessions` 전체 재귀 + 파일마다 `stat` → 정렬 → **상위 12개만 사용** (실측 678MB) | `YYYY/MM/DD` 이름이 zero-padded라 **내림차순 = 최신순**. 최신 날짜부터 내려가다 12개 채우면 중단 |
| `ClaudeCodeAdapter.usage` | `~/.claude.json` **332KB / projects 116개**를 트리거마다 재파싱 | `AccountFileReader.cachedJSON` — mtime+size가 같으면 `stat` 한 번으로 끝 |
| 프로브 트랜스크립트 | `claude`가 실행마다 남기고 **정리하지 않음** (실측 118개) | `pruneProbeTranscripts()`가 매 프로브 후 최근 5개만 유지 |

프로브 디렉터리는 **이름으로 찾습니다**(슬러그 규칙을 재현하지 않음). 경로를 디렉터리명으로 납작하게 만드는 규칙은 `claude`의 사정이고, 여기서 추측한 규칙은 그게 바뀌는 날 조용히 안 맞기 시작합니다.

---

## 7. 함정 요약

1. **`@MainActor` 매니저가 어댑터까지 보호한다고 착각** — non-isolated `async` 본문은 협력 풀에서 돕니다. (§1)
2. **어댑터에 맨 `private var`** — 스윕과 트리거가 겹치면 Dictionary 동시 변형. (§1)
3. **in-flight 엔트리를 바깥 `defer`에서 정리** — 취소된 대기자가 남의 엔트리를 지웁니다. (§1.2)
4. **`readabilityHandler = nil` 직후 `close()`** — catch 불가능한 ObjC 예외로 프로세스가 죽습니다. (§2.1)
5. **`readDataToEndOfFile`** — 손자 프로세스가 write end를 들고 있으면 타임아웃이 무력화됩니다. (§2.2)
6. **감시 루트를 `hasPrefix`로 판정** — `~/.claude`가 `~/.claude-work`를 삼킵니다. (§3)
7. **타이머를 `init`에서 시작** — 꺼도, 가려도, 잠들어도 계속 돕니다. (§4)
8. **핫 패스의 `print`** — 이벤트당 한 줄, 필터링 스레드에서 포매팅. (§5)
9. **주기 작업의 비용이 히스토리에 비례** — 오래 쓴 사용자일수록 앱이 무거워집니다. (§6)

---

## 8. 회귀 방지

`Tests/GlancieTests/ProbePacingTests.swift`가 게이트의 한도와 경로 경계를 고정합니다. 특히:

```swift
XCTAssertGreaterThanOrEqual(ClaudeCodeAdapter.probeMinimumInterval, 60)
```

10초로 되돌아가는 것이 이번 사고였으므로, **숫자 자체를 테스트가 지킵니다.**
