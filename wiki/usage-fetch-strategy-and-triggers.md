# Usage Fetch Strategy & Refresh Triggers

**언제 캐시를 읽고 언제 CLI를 부르는가.** provider마다 답이 다르고, 그 차이는 provider가 디스크에 무엇을 남기느냐에서 나옵니다.

관련: [Account Model & Usage Attribution](account-model-and-usage-attribution.md) — *어느 계정의* 숫자인가는 그쪽입니다. 이 문서는 *언제 어떻게* 읽는가만 다룹니다.

---

## 1. 캐시 우선(cache-first)의 전제

"캐시 우선"은 **CLI가 스스로 최신 값을 디스크에 남겨줄 때만** 성립합니다. 이 전제가 provider마다 다릅니다.

| Provider | 디스크 캐시 | 누가 갱신하나 | 라이브 읽기 |
| :--- | :--- | :--- | :--- |
| **Claude** | `~/.claude.json` → `cachedUsageUtilization` | CLI가 usage API와 통신할 때. **프로브도 나가면서 갱신**(실측 확인) | `claude --strict-mcp-config -p "/usage"` (~3.7초) |
| **Codex** | `~/.codex/sessions/**/rollout-*.jsonl` → `token_count.rate_limits` | 실행 중인 CLI가 **매 턴** 기록 | 없음 — 파일 재읽기가 곧 라이브 |
| **Antigravity** | **없음** | — | `agy -p "/usage"` (~6.3초) |

→ Antigravity만 프로세스 메모리 캐시(`cachedSnapshot`)를 씁니다. 앱을 끄면 사라지고, 그게 유일한 캐시입니다.

**실측 근거:** `~/.gemini/antigravity-cli` 전체를 `"Five Hour Limit Remaining"`으로 grep 하면 0건입니다. 로그가 이유를 말합니다 — `cache.go:135] Cache(retrieveUserQuotaSummary)` 는 프로세스 내부 캐시입니다.

---

## 2. Codex의 진짜 쿼터 소스 (기존 "남은 이슈" 해소)

`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` 의 `token_count` 이벤트에 **서버가 준 응답이 그대로** 들어 있습니다.

```json
{"timestamp":"2026-08-31T07:33:29.922Z","payload":{"type":"token_count","rate_limits":{
  "limit_id":"codex","plan_type":"free",
  "primary":{"used_percent":99.0,"window_minutes":43200,"resets_at":1789004232},
  "secondary":null,
  "credits":{"has_credits":false,"unlimited":false,"balance":null}}}}
```

읽을 때 반드시 지켜야 할 것:

- **all-null 블록을 건너뛸 것.** API에 도달하기 전의 세션은 `primary`/`secondary`가 전부 `null`인 블록을 씁니다(실측: 당일 최신 롤아웃이 `limit_id:"premium"`에 primary null). 이걸 "사용량 0"으로 읽으면 안 되고, non-null이 나올 때까지 **최신 롤아웃부터 거슬러 올라가야** 합니다(현재 12개까지).
- **창 길이를 가정하지 말 것.** `window_minutes`가 플랜마다 다릅니다 — free는 43200분(30일), 유료는 시간 단위. `"5-Hour"`/`"Weekly"` 라벨을 박아두면 틀린 창을 설명하게 됩니다. 라벨은 `window_minutes`에서 유도합니다.
- `resets_at`은 **epoch 초**입니다(Claude 쪽 ISO8601 문자열과 다름). `resets_in_seconds` 형태도 방어해 둡니다.
- `capturedAt`은 **롤아웃의 `timestamp`** 입니다. 읽은 시각이 아닙니다 — 그래야 오래된 값이 오래됐다고 말할 수 있습니다.
- 파일이 클 수 있으므로 **tail 1MiB만** 읽고 역순 스캔합니다. `token_count`는 매 턴 나오므로 항상 끝 근처에 있습니다.

### 그전에 있던 것 (반복 금지)

`estimatedSnapshot()`이 **sqlite 파일 크기로 토큰을 추정**했습니다: `(logs_2.sqlite + state_5.sqlite) / 120`, 상한 200,000 토큰은 임의값. 실측 7.7MB → "잔여 68%"였고 **실제는 1%**였습니다. 로그를 지우면 쿼터가 회복된 것처럼 보이는 지표입니다.

그리고 forceSync 경로가 **`agy -p /usage`(Antigravity CLI)를 호출**하고 `"Claude and GPT"` 줄을 파싱했습니다. `checkAvailability()`도 `~/.local/bin/agy` 존재를 Codex 근거로 썼습니다. 이 머신엔 `codex` 바이너리가 아예 없습니다(`which codex` → not found) — **CLI 존재를 provider 감지 근거로 쓸 땐 그게 그 provider의 CLI인지 확인하십시오.**

---

## 3. 신선도 임계값은 하나여야 합니다

`UsageSnapshot.stalenessThreshold` (15분) **하나**입니다. `isStale`(표시)과 `ClaudeCodeAdapter.cacheFreshnessWindow`(갱신 판단)가 같은 값을 씁니다.

한때 표시는 15분, 어댑터는 30분이었습니다. **그 사이 구간에서 앱은 스스로 stale이라 표시한 값을 갱신 시도조차 하지 않았습니다.** 사용자에게 보인 증상: `Local Cache/DB · 22분 전 업데이트`.

무해한 어긋남이 아닙니다. 같은 24분 구간에서 실제 세션 사용량은 **31% → 53%** (22포인트) 움직였습니다. Claude Code는 usage API와 통신할 때만 캐시를 다시 쓰므로, 긴 세션 중엔 20분 넘게 안 갱신되는 게 정상입니다.

> **임계값을 두 곳에 두지 마십시오.** 두면 반드시 서로 다른 값이 되고, 그 틈이 사용자에게 보입니다.

---

## 4. `forceSync` 의 의미 — "파일을 다시 읽어라", 그 이상은 아님

`forceSync`는 두 번 틀렸습니다.

**1차 (수정됨):** 매니저의 45초 쿨다운만 뚫고 **어댑터까지 도달하지 않았습니다.** 새로고침 버튼도 결국 같은 파일 읽기를 받았습니다.

**2차 (수정됨):** 어댑터까지 도달시키면서 **프로브 백오프까지 무시하게** 했습니다. 그런데 의미 있는 트리거는 *전부* `forceSync`를 세웁니다 — 스트리밍 감지, settle, 팝오버 열기, 상세 진입, 새로고침 버튼. 즉 "예외적으로 뚫는 경로"가 사실상 유일한 경로였고, 5분 백오프는 한 번도 적용되지 않았습니다.

실측 결과:

```
~/.claude/projects/-…-Glancie-ClaudeProbe/   트랜스크립트 118개
분당 프로브:  6, 5, 5, 4, 4, 4, 3, 3, 3 …    ← 10초에 1회
프로브 타임아웃 20초 > floor 10초            → 항상 2~3개 동시 실행
```

그리고 `claude -p` 1회는 usage 한 줄 읽기가 아닙니다: node 부팅 + **`~/.claude.json`(332KB, projects 116개) 전체 read-modify-write** + **전역 MCP 서버 기동** + usage API 호출. 그 대상 파일을 사용자의 대화형 세션이 동시에 쓰고 있습니다. 증상은 **CLI 먹통과 socket 에러**였습니다.

### 지금의 계약

- **파일은 항상 다시 읽습니다** (`forceSync`와 무관하게). Claude Code가 캐시를 갱신하는 순간 화면도 따라 움직입니다.
- **`forceSync`는 어댑터에서 프로브를 앞당기지 않습니다.** 프로브는 §9의 게이트가 결정하고, 게이트는 **무엇으로도 뚫리지 않습니다.**
- **Codex는 예외가 필요 없습니다.** 롤아웃을 다시 읽는 것 자체가 라이브 읽기이고, 호출 간에 보관하는 상태가 없습니다.

> **"증거가 있으니 뚫어도 된다"는 예외는, 모든 호출자가 그 증거를 가지고 있으면 예외가 아니라 기본 경로입니다.** 뚫을 수 있는 한도는 한도가 아닙니다.

---

## 5. 트리거와 하한 (floor)

`ProviderManager.refreshOnDemand(_:trigger:)` 하나로 모입니다.

| 트리거 | 발화 지점 | floor |
| :--- | :--- | :--- |
| `.activity` | **스트리밍 감지**(in-use 진입) + 턴 종료(settle) | 10초 |
| `.userAction` | 팝오버 열기, 프로바이더 상세 진입 | 10초 |
| (없음) | 새로고침 버튼 — 기존 `forceSync: true` 경로 그대로 | — |

세 트리거 모두 이제 **파일 재읽기**만 보장합니다. 프로세스를 띄우는 일은 §9의 게이트를 통과해야 하고, floor는 그 앞단에서 파일 재파싱 폭주만 막습니다.

### 5.1 감지 시점에 쏴야 합니다, 종료 시점이 아니라

처음엔 settle(쓰기가 3초간 멈춤) 후에만 호출했습니다. **턴이 몇 분씩 스트리밍하면 그동안 화면은 턴 시작 전 수치입니다** — 트리거가 고치려던 바로 그 상황입니다. 지금은 in-use 전이 시점에 즉시 쏘고, settle 호출은 최종 수치용으로 남겨둡니다.

### 5.2 floor에 걸린 트리거는 버리지 말고 미룰 것

버리면 그 감지는 *다음* 버스트를 기다리게 되고, 그게 1분 뒤일 수 있습니다. 실측에서 **12초 지연**이 나온 원인입니다. `pendingOnDemand`로 floor 만료 시점에 예약하면 **감지 → 읽기가 항상 1 floor 이내**로 보장됩니다.

```
수정 전: 4s / 9s / 12s
수정 후: 0s / 1s / 2s
```

### 5.3 settle 태스크 안에서 프로브를 시작하지 말 것

`inUseTasks[provider]`는 **다음 쓰기 이벤트가 취소합니다.** 바쁜 세션은 몇 초마다 이벤트가 나므로, 그 안에서 시작한 4초짜리 프로브는 답을 내기 전에 죽습니다. `ps`로 보면 `claude` 프로세스가 3초마다 중첩 생성되는 모습으로 나타납니다. **분리된 `Task`로 띄우십시오.**

---

## 6. 프로브가 자기 자신을 트리거하는 문제 ⚠️

**`claude`는 `/usage` 포함 모든 실행에 대해 `~/.claude/projects/<슬러그화된 cwd>/*.jsonl` 에 트랜스크립트를 씁니다.**

Glancie의 작업 디렉터리에서 프로브를 돌리면 **감시 중인 프로젝트 디렉터리에 쓰기가 발생**합니다 → FSEvents → 스트리밍 감지 → 프로브 → 쓰기 → … 자기를 먹이는 루프입니다.

실측:
```
~/.claude/projects/-Users-<user>-…-glancie/
  8cc4ceec-….jsonl  2,910 bytes   ← Glancie 자신의 프로브
  → <command-name>/usage
```

콘텐츠 블랙리스트(`<command-name>/usage`, `local-command-caveat`)가 막아주긴 했지만 **그건 마커가 검사 대상인 tail 2KB 안에 우연히 들어왔기 때문**입니다. 파일이 조금만 커지면 뚫립니다.

**해법:** 프로브를 전용 디렉터리에서 실행하고 그 이름을 경로 블랙리스트에 넣습니다.

- `ClaudeCodeAdapter.probeWorkingDirectoryName = "Glancie-ClaudeProbe"`
- `CLIProcessRunner.run(..., workingDirectory:)` → `~/Library/Application Support/Glancie-ClaudeProbe`
- 실제 쓰기 위치: `~/.claude/projects/-Users-<user>-Library-Application-Support-Glancie-ClaudeProbe/`
- `AIActivityRuleRegistry` claude 룰의 `pathBlacklist`에 그 이름

> **트랜스크립트를 남기는 CLI를 프로브로 쓸 땐 cwd를 반드시 격리하십시오.** 다른 도구도 같은 결론에 도달해 있습니다 — `~/.claude/projects/`에 `…-CodexBar-ClaudeProbe` 디렉터리가 있습니다.

---

## 7. Antigravity 프로브의 실제 비용

`agy -p "/usage"` 1회가 하는 일:

- **전체 agy 서버 프로세스 기동** (`server_oauth.go`)
- **Google API 네트워크 호출** — `daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary`
- `doRefreshQuota(force=true)` 3회
- 로그 파일 1개 + 크래시 플레이스홀더 1개 생성

캐시 없이 45초 폴링에 물려 있던 결과:

```
최근 1시간 로그 파일:   67개   (≈54초당 1개 — 폴링 주기와 일치)
오늘:                 711개
전체:               3,107개 / 80MB
```

그리고 타임아웃 8.0초 vs 실측 6.3초 — 여유가 1.7초뿐이라 부하가 조금만 올라가면 SIGTERM으로 죽으면서 로그에 `Failed to refresh cache in background: … context canceled` 가 남았습니다. **20초로 올렸습니다.**

메모리 캐시 적용 후 실측: **2분간 로그 파일 0개** (이전 ≈2개).

단, 메모리 캐시는 `forceSync`가 건너뜁니다. 그래서 agy도 §9의 게이트를 통과해야 하며, floor는 3분입니다 — 디스크 폴백이 없는 provider라 Claude보다 짧지만, 없는 것은 아닙니다.

---

## 8. 프로브 게이트 — 뚫리지 않는 한도 (`ProbeGate`)

프로브를 띄울지 말지는 **어댑터가 아니라 게이트가** 정합니다. 어댑터에 두면 "이 호출자는 예외"라는 판단이 어댑터마다 생기고, §4가 그 결말입니다.

```
actor ProbeGate
  ├─ 키별 최소 간격   claude: 프로파일당 5분 / agy: 3분
  ├─ 키별 단일 실행   같은 키의 프로브가 떠 있으면 거절
  └─ 전역 동시 1개    provider가 달라도 두 개는 안 됨
```

세 가지 모두 **논블로킹 거절**입니다. 큐잉하지 않습니다 — 20초짜리 프로브를 줄 세우면 거절보다 나쁜 결과가 되고, 모든 호출자에겐 파일 캐시라는 폴백이 있습니다. **거절은 항상 안전합니다.** 나이를 밝히는 값이, 사용자 세션을 대가로 산 최신 값보다 낫습니다.

`bypassBackoff` 같은 파라미터를 다시 만들지 마십시오. 그게 §4의 2차 실패입니다.

### 8.1 프로브는 MCP 서버를 띄우면 안 됩니다

`claude -p`는 기본적으로 **전역 `mcpServers` 전부를 기동**합니다. 이 머신 기준 `atlassian` 1개 — OAuth를 들고 소켓을 여는 프로세스가, 전부 로컬에서 답할 수 있는 질문 때문에 매 프로브마다 뜹니다.

`--strict-mcp-config`를 `--mcp-config` 없이 주면 **MCP 서버 0개**입니다. 실측 부수 효과로 프로브 시간도 ~5.9초 → **3.7초**로 줄었습니다.

### 8.2 프로브는 자기 배설물을 치워야 합니다

`claude`는 실행마다 트랜스크립트를 남기고 **정리하지 않습니다.** 실측 118개. `ClaudeCodeAdapter.pruneProbeTranscripts()`가 매 프로브 후 최근 5개만 남깁니다.

디렉터리는 이름으로 찾습니다(슬러그 규칙을 재현하지 않음) — 경로를 디렉터리명으로 납작하게 만드는 규칙은 `claude`의 사정이고, 여기서 추측한 규칙은 그게 바뀌는 날 조용히 안 맞기 시작합니다.

---

## 9. 함정 요약

1. **임계값 이중화** — 표시용과 갱신용을 따로 두면 그 사이 구간에서 stale 표시 + 갱신 없음. (§3)
2. **`forceSync`가 어댑터까지 안 감** — 매니저 쿨다운만 뚫고 끝나면 새로고침 버튼이 파일 읽기를 반환. (§4)
   - **그 반대편 실패:** **`forceSync`가 프로브 한도까지 뚫음** — 모든 트리거가 그 플래그를 세우므로 한도가 사라짐. 10초마다 `claude` 기동 → **사용자 CLI 먹통 + socket 에러**. 한도는 게이트에 두고 예외를 만들지 마십시오. (§4, §8)
3. **취소되는 태스크 안에서 프로브 시작** — 다음 이벤트가 죽임. (§5.3)
4. **floor에 걸린 트리거를 drop** — 다음 버스트까지 지연이 무한정 늘어남. (§5.2)
5. **프로브 트랜스크립트가 감시 대상에 떨어짐** — 자기 유발 루프. (§6)
6. **프로브 타임아웃을 실측 없이 잡음** — Claude(4.5s vs 5.9s), Antigravity(8s vs 6.3s) 둘 다 같은 실수. **새 프로브는 실측부터.**
7. **다른 provider의 CLI를 감지/프로브 근거로 사용** — Codex 어댑터가 `agy`를 봤습니다. (§2)
8. **프로브가 MCP 서버를 끌고 옴** — `--strict-mcp-config` 없이 `claude -p`를 쓰면 전역 MCP 서버가 매번 기동됩니다. (§8.1)
9. **같은 어댑터에 두 개의 fetch가 동시 진입** — 45초 스윕과 activity 트리거가 겹치면 어댑터 내부 캐시를 두 스레드가 씁니다. `ProviderManager`가 provider별 단일 실행으로 막습니다.
10. **감시 루트를 `hasPrefix`로 판정** — `~/.claude`가 `~/.claude-work`와 `~/.claude.json`에도 걸립니다. 경계(`/`)까지 비교하십시오.
11. **시간 의존 테스트** — `testCLIUsageReportIsParsedIntoRemainingPercentages`의 픽스처가 `"resets Sep 2 at 11:19pm"`인데 벽시계와 비교해, 매년 9월 2일 23:19부터 실패했습니다. 지난 리셋이 카운트다운을 멈추는 건 **정상 동작**입니다. 파서에 `now`를 주입하고 테스트에서 고정하십시오.
