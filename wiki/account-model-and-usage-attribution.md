# Account Model & Usage Attribution

이 문서는 "이 쿼터가 **누구의 것인가**"를 결정하는 계정(Account) 레이어의 설계 결정을 설명합니다.
`Sources/Glancie/Providers/Accounts/` 전체와 `ProviderManager`의 귀속 로직이 여기에 해당합니다.

---

## 1. 핵심 컨셉 — 두 개의 독립된 축

이 레이어를 이해하는 유일한 열쇠입니다. **섞지 마십시오.**

| 축 | 무엇에 바인딩되는가 | 누가 답하는가 |
| :--- | :--- | :--- |
| **사용량 (쿼터)** | **계정** | provider가 계정별로 집계하므로, 계정이 곧 쿼터 버킷 |
| **실행 중 여부** | **소스** (CLI / 데스크톱 앱 / IDE) | 프로세스가 도는 자리 |

- 계정 2개 = 쿼터 2개. CLI로 읽었든 앱으로 읽었든 **숫자는 계정에 귀속**됩니다.
- 소스는 쿼터 버킷이 **아닙니다.** 소스의 유일한 역할은 "지금 이게 돌고 있나"를 알려주는 것입니다.

> ⚠️ 초기 구현은 이 둘을 `isActive` 하나에 얹었다가 잘못된 귀속을 만들었습니다. 되돌리지 마십시오.
> `usageReadable`(쿼터를 읽을 수 있는가)와 `runningAccounts`/`runningAppAccounts`(지금 도는가)는 끝까지 별개입니다.

---

## 2. 왜 필요했나

`ProviderManager`는 원래 모든 상태를 `AIProviderType` 하나로 키잉했습니다(`snapshots: [AIProviderType: UsageSnapshot]`).
"Claude 86% 남음"은 말할 수 있어도 **"누구의 Claude인지"**는 말하지 못했습니다.

실측으로 확인된 두 가지가 이 전제를 깨뜨립니다.

1. **provider ≠ 계정.** 개발 머신에서 Gemini CLI는 GAIA `110748…`, Gemini 데스크톱 앱은 GAIA `114377…` — **서로 다른 Google 계정**이었습니다. 하나의 "Gemini" 세그먼트 뒤에 두 계정의 쿼터가 섞여 있었습니다.
2. **`.claude` / `.gemini` 디렉토리 존재 여부는 "설치됨"만 알려줍니다.** 계정 정체성과 플랜은 완전히 다른 파일에 있고, 데스크톱 앱은 그 디렉토리를 아예 쓰지 않습니다.

---

## 3. 데이터 소스 지도 (재조사 방지용 — 전부 실측)

### 3.1 정체성 + 쿼터가 모두 로컬에 있는 경우

| Provider | 파일 | 얻을 수 있는 것 |
| :--- | :--- | :--- |
| **Claude Code** | `~/.claude.json` | `oauthAccount`(email, accountUuid, organizationName, **`organizationType`=플랜 티어**) + **`cachedUsageUtilization`** |
| **Codex** | `~/.codex/auth.json` | `tokens.id_token` JWT 페이로드 → `email`, `https://api.openai.com/auth`.`chatgpt_plan_type` / `chatgpt_account_id` / `organizations[]` |
| **Gemini / Antigravity** | `~/.gemini/google_accounts.json` | 문자 그대로 `{"active": …, "old": [...]}` — 계정 목록 |
| | `~/.gemini/oauth_creds.json` | `id_token` → `email`, `sub`(GAIA id) |
| **Cursor** | `…/Cursor/User/globalStorage/state.vscdb` | `ItemTable`의 `cursorAuth/cachedEmail`, `cachedTeam`, `stripeMembershipType`(플랜) |

**`cachedUsageUtilization` 가 이 기능의 핵심입니다.** Claude Code가 스스로 캐싱해 둔 공식 `/usage` 응답이며 다음을 담고 있습니다:
- **`accountUuid`** ← 이게 있어서 "A 계정 이메일 + B 계정 숫자" 사고를 원천 차단할 수 있음
- `fetchedAtMs`, `utilization.five_hour` / `seven_day`(**% used**, `resets_at`), `limits[]`(kind/group/percent/severity/resets_at/is_active), `extra_usage`

다만 **이 캐시만으로는 부족합니다** — 얼마나 오래 식을 수 있는지는 3.4 참조.

### 3.2 데스크톱 앱 — 경로/키 접미사에 계정 ID가 박혀 있음

접미사를 열거하면 곧 계정 열거입니다.

| 앱 | 루트 / 도메인 | 계정 식별 |
| :--- | :--- | :--- |
| **ChatGPT.app** | `~/Library/Application Support/com.openai.chat/` | `conversations-v3-<workspaceUUID>` 디렉토리명. 현재 계정은 prefs `com.openai.chat`의 `activeUserWorkspaceID`(JSON **문자열**) |
| **Claude.app** | `~/Library/Application Support/Claude/config.json` | `lastKnownAccountUuid` (**아래 정정 참조**) |
| **Gemini.app** | prefs `com.google.GeminiMacOS` | `discoveryInteractionRecords_<gaiaID>` 접미사 |
| **Antigravity.app** | `~/Library/Application Support/Antigravity/` | `app_storage.json`엔 계정 정보 **없음**(UI 상태만). 정체성은 `~/.gemini/` 쪽에서 |

> **정정 — `dxt:allowlistEnabled:<uuid>` 는 계정이 아니라 조직입니다.**
> 한때 이 접미사를 계정 열거에 썼는데, 그 uuid는 `.claude.json`의 **`organizationUuid`** 와 일치합니다(실측). 그래서 머신마다 "읽기 불가" 유령 계정이 하나씩 생겼습니다.
> Claude.app의 진짜 계정별 레이아웃은 두 디렉터리 트리이고, 둘 다 **`<accountUuid>/<organizationUuid>/`** 구조입니다:
> `claude-code-sessions/` · `local-agent-mode-sessions/`
> **1단계만** 계정입니다. 2단계까지 열거하면 조직이 여러 개인 계정이 여러 계정으로 쪼개집니다. 이름이 실제 UUID인지도 검사해야 합니다(`AccountFileReader.uuidDirectoryNames`).
>
> **접미사·디렉터리명이 계정 ID라는 추론은 반드시 다른 파일과 대조해 확인하십시오.** 모양이 같은 UUID가 전혀 다른 것을 가리킬 수 있습니다.

### 3.3 멀티 계정의 실제 메커니즘

세 CLI 모두 **네이티브 멀티 계정을 지원하지 않습니다.** 계정당 홈 디렉토리를 통째로 바꾸는 것이 사실상의 표준입니다.

- Claude Code: `CLAUDE_CONFIG_DIR` → 각 디렉토리에 독립 `.claude.json` (**자기 `cachedUsageUtilization` 포함** ← 그래서 계정별 라이브 쿼터를 네트워크 없이 읽을 수 있음)
- Codex: `CODEX_HOME` → 각 디렉토리에 독립 `auth.json`
- Gemini: `google_accounts.json` + `oauth_creds.json`을 프로필 폴더에서 스왑

### 3.4 `cachedUsageUtilization` 는 얼마든지 식습니다 (실측 44시간)

**Claude Code는 새 답이 손에 들어왔을 때만 이 키를 다시 씁니다.** 하루 종일 세션을 돌려도 캐시는 갱신되지 않을 수 있습니다.
실측: 개발 머신에서 `fetchedAtMs`가 **44시간 전**(세션 70% used / 주간 97% used)이었고, 같은 시점 실제 값은 세션 17% / 주간 11%였습니다. 5시간 리셋이 이미 여러 번 지나간 숫자입니다.

→ **파일 캐시만 읽는 구현은 반드시 틀립니다.** 신선도 창을 넘기면 CLI 프로브로 넘어가야 합니다.
→ 프로브가 성공하면 Claude Code가 그 김에 `cachedUsageUtilization`을 다시 씁니다(실측 확인). 즉 **프로브 1회 = 이후 한 창(window) 동안 파일 읽기로 해결**.
→ **창 길이는 `UsageSnapshot.stalenessThreshold`(15분) 하나입니다.** 표시용 임계값과 갱신 판단 임계값이 어긋나 있던 버그와 트리거 설계는 [Usage Fetch Strategy & Triggers](usage-fetch-strategy-and-triggers.md) 참조.

### 3.5 CLI 프로브: `claude -p "/usage"`

실측 출력(파서가 의존하는 형식):

```
You are currently using your subscription to power your Claude Code usage

Current session: 17% used · resets Sep 2 at 11:19pm (Asia/Seoul)
Current week (all models): 11% used · resets Sep 8 at 1:59pm (Asia/Seoul)

Last 24h · 318 requests · 4 sessions
```

- **소요 시간 5.4~5.9초** (웜 상태 기준). 예산은 넉넉히 — 20초로 잡았습니다.
- 플랜에 따라 `Current week (Opus):` / `(Sonnet):` 줄이 추가로 나옵니다.
- 리셋 문구에 **연도가 없고 타임존 이름이 붙습니다**. 명시된 존으로 파싱하고, 하루 이상 과거로 계산되면 다음 해로 롤오버(12월→1월 전용 케이스).
- `claude usage` 같은 서브커맨드는 **없습니다**(v2.1 기준). `-p "/usage"`가 유일한 경로이며, 슬래시 커맨드가 로컬에서 처리되므로 모델 호출 비용은 없습니다.
- **프로브는 전용 cwd에서 돌려야 합니다.** `claude`는 모든 실행에 대해 `~/.claude/projects/<슬러그화된 cwd>`에 트랜스크립트를 씁니다. 감시 중인 디렉터리에서 돌리면 프로브가 스스로를 트리거합니다 — 상세는 [Usage Fetch Strategy & Triggers §6](usage-fetch-strategy-and-triggers.md).
- **보조 프로필 프로브는 `CLAUDE_CONFIG_DIR`를 넘겨야 합니다.** 안 넘기면 기본 계정 숫자를 다른 계정 이름표에 붙이게 됩니다. 단 기본 프로필(`~/.claude.json`)은 예외 — 그 경우 `homeDirectory`는 `~/.claude`라서 넘기면 오히려 엉뚱한 곳(`~/.claude/.claude.json`)을 보게 됩니다. 판별 기준: `configPath == homeDirectory + "/.claude.json"` 일 때만 설정.

### 3.7 Antigravity CLI가 인증한 계정은 로그에만 있습니다

`~/.gemini/antigravity-cli/antigravity-oauth-token` 은 **불투명 refresh token** 입니다 — JWT가 아니라 디코드할 게 없습니다. `google_accounts.json`은 다른 질문(공유 Google 로그인이 누구인가)에 답하고, CLI는 routinely 다른 사람으로 로그인돼 있습니다.

디스크에서 답하는 유일한 곳은 CLI 자신의 로그입니다. 매 실행마다 남습니다:

```
~/.gemini/antigravity-cli/log/cli-<yyyymmdd>_<hhmmss>.log
  … server_oauth.go:192] applyAuthResult: email=someone@example.com, authMethod=consumer, quotaProject=
```

- 파일명이 시간순으로 **문자열 정렬**됩니다 → 3,000개를 stat 할 필요 없이 이름만 내림차순 정렬.
- 인증 전에 죽은 런은 답이 없으므로 몇 개까지 거슬러 올라가야 합니다(현재 8개).
- **로그 줄은 계약이 아닙니다.** 매칭 실패 시 소스를 버리지 말고 공유 목록으로 폴백하십시오.
- **공유 주소와 일치할 때만 공유 계정 키를 물려받게** 하십시오. 별개 로그인에 `activeAccountKey`를 붙이는 게 원래 버그를 다른 자리에서 반복하는 것입니다(§4.3의 "ID 기준 통일"은 *같은 로그인*일 때만 적용됩니다).

### 3.6 시도하지 말아야 할 것

- **`https://api.anthropic.com/api/oauth/usage` 직접 폴링** — 429가 매우 공격적이라 사실상 불가능(`User-Agent: claude-code/<ver>` 필수, Retry-After 없음). 로컬 캐시 파일이 확실히 우월합니다.
- **데스크톱 앱 디렉토리를 FSEvents로 감시해 "실행 중" 판단** — Electron 캐시 churn 때문에 추측이 됩니다. `NSWorkspace` 실행 알림을 쓰십시오.
  단 **예외**: Claude.app의 `claude-code-sessions` / `local-agent-mode-sessions`는 진짜 트랜스크립트라 감시 가치가 있습니다. 서버에 사는 일반 채팅은 IndexedDB churn만 남기므로 여전히 `NSWorkspace` 영역입니다. 그 둘을 UI에서도 분리했습니다 — 펄스하는 `생성 중`(LiveStreamBadge) vs 정적인 `앱 열림`(AppOpenBadge).

---

## 4. 설계 결정

### 4.1 fetch 단위 = provider가 아니라 계정
`AIProviderAdapter.fetchUsagePerAccount(forceSync:)`가 **계정별 스냅샷 배열**을 반환합니다.
프로토콜 익스텐션의 기본 구현이 기존 `fetchUsage()`를 배열로 감싸므로, 계정을 구분할 수 없는 나머지 어댑터는 무변경입니다.
Claude/Codex만 오버라이드해 전 프로필을 읽습니다.

### 4.2 바(bar)에 표시할 계정 = "지금 작업 중인 계정"
`ProviderManager.representativeSnapshot(for:among:)`.
컨셉을 따르면 자연히 도출됩니다 — 소스의 실행중 신호가 계정을 가리키고, 그 계정이 지금 쿼터를 쓰는 계정입니다. 실행중이 없으면 가장 최근 측정된 계정.
**바 UI는 provider 단위를 유지합니다.** 세그먼트를 계정 수만큼 늘리지 않기로 한 명시적 결정입니다.

### 4.3 계정 병합/분리 규칙
`ResolvedAccount.absorb()` — **계정 ID가 같으면 하나로 병합**(Claude CLI + Claude Desktop = 한 로그인, 소스만 둘), **다르면 끝까지 별개**(Gemini CLI vs 데스크톱).
Gemini 계열은 `gemini.cli` / `antigravity.cli` / `antigravity.ide`가 같은 `google_accounts.json`을 보므로, ID 기준을 **`cliSubject() ?? activeEmail`로 통일**해야 합니다. 안 하면 한 로그인이 3개 계정으로 쪼개집니다.

### 4.4 발견됨 ≠ 읽을 수 있음
`AccountIdentity.usageReadable`.
Gemini 데스크톱 계정은 prefs에 ID만 남기므로 발견은 되지만 쿼터는 못 읽습니다 → UI에 `사용량 없음`. 추측한 숫자를 채우지 않습니다.

### 4.5 추정치는 저장하지 않는다
`AccountUsageStore.record()`가 `strategyUsed == .simulated`인 스냅샷을 거부합니다.
저장하면 몇 주 뒤 "3주 전 기준 79%"로 되살아나 실측과 구분되지 않습니다.

### 4.6 신선도 규칙은 fetch 경로 전체가 공유한다
`ClaudeCodeAdapter.usage(for:)` 하나가 **"따뜻한 캐시 → 라이브 프로브 → 식은 캐시"** 순서를 담고, `fetchUsagePerAccount`와 `fetchUsage`가 둘 다 이걸 부릅니다.

한때 신선도 검사와 CLI 폴백이 `fetchUsage`에만 있었고, `fetchUsagePerAccount`는 캐시를 무검사로 반환했습니다. **`ProviderManager`가 실제로 부르는 건 `fetchUsagePerAccount` 뿐이라서**(`refreshProvider` / `refreshAll`) 폴백 코드는 "읽을 수 있는 프로필이 하나도 없을 때"만 도달했고 — 즉 사실상 죽은 코드였고 — 앱은 이틀 전 숫자를 계속 띄웠습니다.
**교훈: 폴백 로직은 실제 호출되는 진입점에 있어야 합니다.** 계정별 경로가 생기면 단일 경로는 자동으로 레거시가 됩니다.

### 4.7 파싱 실패는 nil이지, 기본값이 아니다
`parseClaudeUsageOutput`은 세션 줄을 못 찾으면 `nil`을 반환합니다.
이전 구현은 매칭이 하나도 안 돼도 `90%` 잔여 · 리셋 4시간 · 주간 리셋 3일을 채워 스냅샷을 만들었습니다. 로그인 프롬프트나 잘린 출력이 **`.cliStatusProbe` 배지를 달고** 실측처럼 바에 올라갑니다. 4.4/4.5의 "추측을 표시하지 않는다" 원칙이 파서에도 그대로 적용됩니다.

### 4.8 포기한 접근
- **계정을 바의 1급 엔트리로** — 세그먼트가 계정 수만큼 늘어 바가 붐빔
- **비활성 계정을 네트워크로 갱신** — 위 429 문제. 대신 마지막 스냅샷 + stale 표시

---

## 5. 함정 (실제로 밟은 것들)

1. **접두사 매칭은 너무 탐욕적입니다.** `.codex` 접두사가 **`~/.codexbar`(전혀 다른 앱)** 를 잡았습니다.
   `AccountFileReader.profileDirectories(in:prefix:)`는 접두사 뒤에 구분자(`-` `_` `.`)가 오거나 정확히 일치할 때만 인정합니다.
2. **어댑터에 계정을 하드코딩하지 마십시오.** `AntigravityAdapter`가 `chasibatik74@gmail.com`을 하드코딩해 두어, 올바르게 resolve된 계정을 덮어썼습니다(ID는 A인데 이메일은 B). `ProviderManager.attribute()`는 nil인 필드만 채우므로 하드코딩이 항상 이깁니다.
   **후속(더 나쁨):** 하드코딩을 걷어낸 뒤에도 resolver가 `google_accounts.json`의 `active`를 Antigravity **CLI** 소스에 붙였습니다. CLI는 자기 OAuth 토큰을 따로 들고 있고, 실제로는 `old`에 있는 주소로 인증돼 있었습니다 — 즉 **A 계정의 쿼터를 B 계정 이름 아래 표시**. 조용해서 하드코딩보다 위험합니다. 정답은 §3.7 참조.
3. **한 provider에 여러 소스가 동시에 "signed in"** 일 수 있습니다. 단일 스냅샷 어댑터의 귀속은 반드시 `AccountResolver.primarySourceID`(그 어댑터가 실제로 읽는 소스)를 우선해야 합니다. 안 그러면 정렬 순서에 따라 데스크톱 계정이 CLI 숫자를 가져갑니다.
4. **`ISO8601DateFormatter`는 소수점 6자리를 못 읽습니다.** 페이로드가 `.848396`을 주므로 정규식으로 소수부를 제거한 뒤 파싱합니다(`ClaudeCodeAdapter.parseTimestamp`).
5. **`utilization`/`percent`는 "사용한 %"입니다.** UI는 전부 잔여 기준이므로 `100 - x`로 뒤집습니다.
6. **복원된 스냅샷의 카운트다운은 감쇠시켜야 합니다.** `UsageSnapshot.agedToNow()` — 이미 지난 리셋은 `nil`로(모른다). 안 하면 만료된 카운트다운을 임박한 것처럼 표시합니다.
7. **CLI 프로브 타임아웃을 실행 시간보다 짧게 잡으면 폴백 전체가 조용히 죽습니다.** `claude -p "/usage"`는 ~5.9초인데 예산이 4.5초였습니다. 매번 SIGTERM으로 죽었고, 아무도 에러를 보지 못했습니다. **새 프로브를 추가할 땐 실측부터 하십시오.**
8. **`readDataToEndOfFile()`은 타임아웃을 무력화합니다.** EOF는 파이프 쓰기단 **전부**가 닫혀야 오므로, 자식이 죽어도 손자가 fd를 쥐고 있으면 영원히 블록됩니다. `readabilityHandler`로 스트리밍 수집하고, SIGTERM 후 1초 뒤 SIGKILL까지 에스컬레이션합니다(`CLIProcessRunner`).
9. **타임아웃 시 부분 출력을 돌려주지 마십시오.** 잘린 사용량 리포트는 그럴듯한 오답으로 파싱됩니다. `CLIProcessRunner`는 타임아웃이면 `nil`을 반환하고, 호출자는 (나이를 정직하게 표시하는) 캐시로 폴백합니다.


---

## 6. 코드 패턴

- **읽기 전용 원칙**: 모든 resolver는 파일만 읽습니다. provider가 없는 머신에서 throw 금지 — 빈 배열이 정답입니다.
- **SQLite**: 시스템 `import SQLite3`로 충분(신규 의존성 없음). 앱이 WAL 잠금을 쥐고 있으므로 반드시 `file:…?immutable=1` 읽기 전용 URI로 엽니다.
- **prefs 읽기**: `defaults` 프로세스를 띄우지 말고 `CFPreferencesCopyAppValue` / `CFPreferencesCopyKeyList`. 실패 시 `PropertyListSerialization`으로 폴백(일부 앱이 JSON 변환 불가한 바이너리 blob 보유).
- **JWT**: 서명 검증 없이 payload만 base64url 디코드(`JWTClaims.payload`). 패딩을 직접 채워야 합니다. **토큰 원문은 절대 저장·로깅 금지.**
- **로그 마스킹**: 콘솔은 창보다 오래 남으므로, 표시 설정과 무관하게 로그의 이메일은 항상 마스킹(`maskedLabel`).
- **CLI 프로브**: 전부 `CLIProcessRunner.run(command:arguments:timeout:environment:)`를 거칩니다. 바이너리 탐색(`~/.local/bin` → `/opt/homebrew/bin` → `/usr/local/bin`), PATH 보정, 스트리밍 수집, SIGTERM→SIGKILL, 타임아웃 시 `nil`이 여기에 한 번만 구현돼 있습니다. `environment`로 프로필 선택 변수(`CLAUDE_CONFIG_DIR`, `CODEX_HOME`)를 넘깁니다. **GUI 앱은 로그인 셸 PATH를 상속하지 않으므로** 직접 `Process`를 띄우지 마십시오.
- **실행 중 감지**: CLI는 FSEvents(`ActivitySignal(provider, accountID)`, 최장 접두사 매칭), GUI 앱은 `NSWorkspace` 실행/종료 알림 + `AccountSource.bundleIdentifiers`.

### 실측 번들 ID
`com.anthropic.claudefordesktop` · `com.openai.chat`, `com.openai.codex`(ChatGPT.app이 이걸 씀) · `com.google.GeminiMacOS` · `com.google.antigravity` · `com.todesktop.230313mzl4w4u92`(Cursor)

---

## 7. 남은 이슈

- `CursorAdapter`(로그 폴더 개수)가 **추정치를 `.localFileCache`로 표기**합니다. `.simulated`로 정정 필요 — 그래야 배지가 정직해지고 `AccountUsageStore`가 자동으로 걸러냅니다.
- **`AccountUsageStore`에 덮이지 않는 낡은 레코드가 남습니다.** `record()`는 기존보다 오래된 스냅샷을 거부하는데(`existing.capturedAt > snapshot.capturedAt`), Codex 스냅샷의 `capturedAt`은 **롤아웃 시각**이라 옛 코드가 남긴 레코드보다 오래될 수 있습니다. 그러면 영원히 덮이지 않습니다. 실측: `codex | CLI Probe | 잔여 100% | 2026-09-02T08:38:34Z` 가 잔여 1%인 실측값에 밀리지 않고 남아 있습니다. 라이브 값이 있는 동안은 UI에 안 나오지만 사라지면 튀어나옵니다. 파일: `~/Library/Application Support/Glancie/account-usage.json`.
- Gemini/Antigravity는 플랜 티어를 로컬에서 못 읽어 `planName`이 `nil`입니다(하드코딩된 "Google AI Pro"를 제거한 결과). Codex는 롤아웃의 `plan_type`이 토큰의 것보다 신선하므로 그쪽을 우선합니다.
- `agy`가 인증 계정을 **로그로만** 노출합니다(§3.7). 포맷이 바뀌면 조용히 공유 계정으로 폴백하므로, 귀속이 이상해 보이면 로그 파싱부터 의심하십시오.

### 해소됨 (이 문서 갱신 시점)

- ~~Codex의 실제 쿼터 경로 재조사~~ → 롤아웃 `token_count.rate_limits`. [Usage Fetch Strategy §2](usage-fetch-strategy-and-triggers.md)
- ~~프로브 예산 실측 미검증~~ → Antigravity 6.3초 실측 후 8초→20초. Codex는 프로브 자체를 제거(파일이 라이브 소스).
