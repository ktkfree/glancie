<h1 align="center">Glancie</h1>

<p align="center">
  Claude Code · Codex · Antigravity… 여러 AI 코딩 도구의 <b>남은 사용량</b>을<br>
  데스크톱에 떠 있는 캡슐 바 하나로 보여주는 macOS 앱
</p>

<p align="center">
  <b>한국어</b> · <a href="README.en.md">English</a>
</p>

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey">
  <img alt="swift" src="https://img.shields.io/badge/Swift-5.9%2B-orange">
  <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <img alt="tests" src="https://img.shields.io/badge/tests-249%20passing-brightgreen">
</p>

<p align="center">
  <a href="#설치">설치</a> ·
  <a href="#지원-provider">지원 Provider</a> ·
  <a href="#프라이버시">프라이버시</a> ·
  <a href="CONTRIBUTING.md">기여</a> ·
  <a href="SECURITY.md">보안</a> ·
  <a href="wiki/INDEX.md">설계 기록</a>
</p>

```text
 ╭──────────────────────────────────────────────────────────────────────────╮
 │ ⠿ │ ✦ Claude 82% ▰▰▰▰▰▱ │ ◈ Codex 45% ▰▰▰▱▱▱ │ ◆ AGY 98% ▰▰▰▰▰▰ │ ⏱ 2h 18m │
 ╰──────────────────────────────────────────────────────────────────────────╯
```

<p align="center">
  <img src="docs/images/bar.png" width="720" alt="Glancie 플로팅 바">
</p>

---

## 이런 분께

- Claude Code를 쓰다 한도가 걸리면 Codex로, 다시 Antigravity로 갈아타는 분
- "지금 어느 쪽이 남아 있지?"를 확인하려고 매번 터미널을 열어 `/usage`를 치는 분
- 한도가 언제 리셋되는지 몰라서 중요한 작업을 시작해도 될지 망설여 본 분

Glancie는 그 확인 과정을 없앱니다. 켜 둔 Provider의 **남은 사용량과 리셋까지 남은 시간**이 화면 위 얇은 바에 항상 떠 있습니다.

세 가지를 약속합니다.

- **서버가 없습니다.** 사용량은 각 도구가 이미 내 Mac에 남긴 파일과 각 제공업체의 공식 API에서만 읽습니다. 어디로도 보내지 않습니다.
- **숫자를 지어내지 않습니다.** 읽을 수 없는 값은 추측 대신 "데이터 없음"으로 둡니다. 이것이 이 프로젝트의 제1 규칙입니다.
- **조용히 돕습니다.** `LSUIElement` 앱이라 Dock을 차지하지 않고, CLI를 함부로 띄워 CPU나 배터리를 태우지 않습니다.

### 하지 않는 것

기대를 먼저 맞춰 두는 편이 낫겠습니다.

- **사용량을 대신 아껴 주지 않습니다.** 보여줄 뿐 요청을 가로채거나 차단하지 않습니다.
- **비용을 계산하지 않습니다.** 청구서를 다루는 앱이 아니라 남은 한도를 보는 앱입니다.
- **macOS 전용입니다.** AppKit `NSPanel` 위에 지어져 있어 Windows·Linux 이식 계획이 없습니다.
- **제공업체가 안 알려주는 값은 못 봅니다.** 공개된 조회 경로가 없으면 그 Provider는 "데이터 없음"으로 남습니다.

---

## 설치

**요구사항** — macOS 14.0(Sonoma) 이상, Swift 5.9+ 툴체인(Xcode 15+ 또는 [swift.org](https://www.swift.org/download/) 툴체인)

아직 배포 릴리즈가 없습니다. 지금은 소스에서 빌드해야 합니다.

```bash
git clone https://github.com/ktkfree/glancie.git
cd glancie

# 1) 그냥 한번 띄워 보기
swift run Glancie

# 2) 마음에 들면 .app으로 만들기
./scripts/build_manual.sh
```

`build_manual.sh`는 릴리즈 빌드 → `.app` 번들 → ZIP까지 만들고, **`/Applications` 설치 여부는 물어봅니다.** 묻지 않게 하려면 `GLANCIE_INSTALL=1`(설치) 또는 `GLANCIE_SKIP_INSTALL=1`(건너뛰기)을 붙이세요. DMG가 필요하면 `./scripts/build-dmg.sh`를 쓰면 됩니다.

### ⚠️ 앱이 안 열릴 때 (Gatekeeper)

Glancie는 아직 **서명·공증(notarization)되지 않았습니다.** 직접 빌드하지 않고 받은 `.app`을 처음 열면 macOS가 막습니다. Finder에서 **우클릭 → 열기**를 한 번 하거나, 아래를 실행하세요.

```bash
xattr -dr com.apple.quarantine /Applications/Glancie.app
```

`swift run`이나 `swift build`로 직접 빌드한 바이너리는 해당하지 않습니다.

---

## 처음 실행하면

설정할 게 없습니다. Glancie가 이 Mac에 **설치·로그인된 도구를 알아서 찾아** 그것만 켭니다.

1. 메뉴바에 `✨` 아이콘이 생깁니다.
2. 화면에 캡슐 바가 뜨고, 감지된 Provider가 세그먼트로 하나씩 들어옵니다.
3. 원하는 자리로 드래그해 두면 다음 실행에도 그 자리에 뜹니다.

언어도 알아서 맞춥니다. macOS 언어 설정이 한국어면 한국어로, 그 외에는 영어로 뜹니다.

보고 싶은 Provider를 직접 고르고 싶다면 메뉴바 `✨` → **설정 → 표시할 프로바이더**에서 켜고 끄면 됩니다.

---

## 사용법

| 하고 싶은 것 | 방법 |
| :--- | :--- |
| **바 옮기기** | 좌측 그립(`⠿`)이나 빈 영역을 잡고 드래그. 화면 밖으로는 나가지 않습니다 |
| **자세히 보기** | Provider 세그먼트를 클릭 → 세션/주간/모델별 쿼터와 리셋 카운트다운 카드가 열립니다. 다른 세그먼트를 누르면 카드가 닫히지 않고 내용만 바뀝니다 |
| **지금 바로 갱신** | 메뉴바 `✨` → **모두 새로 고침** |
| **설정 열기** | 메뉴바 `✨` → **설정…** |
| **앱 정보 보기** | 메뉴바 `✨` → **Glancie 정보** → 버전, 소스 링크, 만든 사람 |
| **종료** | 메뉴바 `✨` → **Glancie 종료** 또는 `pkill -f Glancie` |

### 설정에서 바꿀 수 있는 것

- **언어** — `시스템 설정 따름` · `한국어` · `English`. 바꾸면 즉시 반영됩니다
- **표시할 프로바이더** — 바에 올릴 Provider 선택 (최소 1개)
- **계정 감지 / 이메일 가리기** — 아래 [프라이버시](#프라이버시) 참고
- **햅틱 & 사운드**, **시선 추적** — 인터랙션 피드백 토글
- **픽셀 고양이** — 바 위를 걸어다니는 컴패니언. 클릭·드래그에 반응하고 털색(품종)을 고를 수 있습니다

### 바가 알려주는 것

- **게이지와 %** — 남은 양입니다. 줄어든 양이 아닙니다
- **⏱ 카운트다운** — 다음 리셋까지 남은 시간
- **점멸(펄스)** — 그 Provider가 지금 실제로 작업 중입니다. 턴이 끝나면 곧바로 쿼터를 다시 읽습니다
- **"데이터 없음"** — 읽을 수 있는 값이 없다는 뜻입니다. 0%가 아닙니다

---

## 지원 Provider

### 사용량이 실제로 보이는 Provider

| Provider | 바에 보이는 값 | 연결하려면 |
| :--- | :--- | :--- |
| **Claude Code** | 세션(5시간)·주간·모델별 잔여율 | `claude` CLI 설치 + 로그인 |
| **OpenAI Codex** | 세션·주간 rate limit 잔여율 | `codex` CLI 설치 + 로그인 |
| **Antigravity (AGY)** | Gemini 5시간/주간, Claude·GPT 모델별 잔여율 | `agy` CLI 설치 + 로그인 |
| **GitHub Copilot** | Premium Interactions, Chat Requests 월간 잔여율 | Copilot 로그인 (`~/.config/github-copilot`) |
| **DeepSeek** | 남은 잔액 | `DEEPSEEK_API_KEY` |
| **OpenRouter** | 남은 크레딧과 키 한도 | `OPENROUTER_API_KEY` |
| **Groq** | TPM/RPM 잔여율 | `GROQ_API_KEY` |
| **Moonshot Kimi** | 남은 잔액 | `MOONSHOT_API_KEY` 또는 `KIMI_API_KEY` |
| **ElevenLabs** | 티어와 남은 문자 수 | `ELEVENLABS_API_KEY` 또는 `XI_API_KEY` |
| **Ollama** | 설치된 모델과 로드 상태 | `ollama serve` 실행 중 (`localhost:11434`) |

### 감지만 되는 Provider

**Cursor · Windsurf · Zed AI · Mistral AI** — 설치와 로그인은 감지하지만, 공개된 사용량 조회 경로가 없어 **"데이터 없음"**으로 표시합니다. 그럴듯한 추정치를 만들어 채우지 않습니다.

쓰시는 도구가 없나요? [Provider 추가 요청](https://github.com/ktkfree/glancie/issues/new)을 열어 주세요. 사용량을 어디서 읽을 수 있는지(API·파일·CLI 명령) 알려주시면 가장 빠릅니다.

### 멀티 계정

`CLAUDE_CONFIG_DIR`, `CODEX_HOME`으로 프로필을 나눠 쓰고 있다면 **각각 별개 계정으로 읽고**, 쿼터를 해당 계정에 귀속시킵니다. 계정을 바꿔 로그인하면 이전 계정의 숫자를 새 계정에 물려주지 않습니다.

---

## 자주 겪는 문제

<details>
<summary><b>API 키를 넣은 Provider가 <code>.app</code>에서만 안 보입니다</b></summary>

Finder나 Launchpad에서 실행한 앱은 셸 환경 변수를 물려받지 않습니다. 터미널에서 `export DEEPSEEK_API_KEY=...`를 해 뒀어도 `.app`은 그 값을 볼 수 없습니다.

**가장 간단한 해결책은 키를 파일로 두는 것입니다.** 환경 변수를 쓰는 Provider는 모두 아래 경로도 함께 읽습니다.

```bash
mkdir -p ~/.config/deepseek && echo "sk-..." > ~/.config/deepseek/api_key
chmod 600 ~/.config/deepseek/api_key
```

| Provider | 파일 경로 |
| :--- | :--- |
| DeepSeek | `~/.config/deepseek/api_key` |
| OpenRouter | `~/.config/openrouter/api_key` |
| Groq | `~/.config/groq/api_key` |
| Moonshot Kimi | `~/.config/moonshot/api_key` |
| ElevenLabs | `~/.config/elevenlabs/api_key` |
| Mistral AI | `~/.config/mistral/api_key` |

CLI 기반 Provider(Claude · Codex · AGY)와 Copilot, Ollama는 이 문제와 무관합니다.
</details>

<details>
<summary><b>Provider가 "감지됨"인데 숫자가 "데이터 없음"입니다</b></summary>

둘은 다른 얘기입니다. **감지됨**은 "이 Mac에서 해당 CLI나 앱을 찾았다"는 뜻이고, 사용량은 별도로 읽습니다.

- Cursor · Windsurf · Zed · Mistral은 검증된 수집 경로가 없어 **항상** 데이터 없음입니다
- 그 외 Provider라면 로그인이 풀렸거나, API 키가 만료됐거나, 아직 사용 기록이 없는 경우입니다
- 한 번도 성공한 적 없는 값은 비워 둡니다. 0%로 채우지 않습니다
</details>

<details>
<summary><b>숫자가 갱신되지 않고 멈춘 것 같습니다</b></summary>

API 호출이 실패하면 Glancie는 **같은 인증 키로 얻은 마지막 성공값과 그 원래 측정 시각**을 그대로 유지하고, 갱신 실패 상태를 표시합니다. 오래된 숫자를 지금 값인 척 새로 도장 찍지 않기 때문입니다.

즉시 다시 시도하려면 메뉴바 → **모두 새로 고침**을 누르세요. 상세 카드를 여는 것도 즉시 조회를 트리거합니다.
</details>

<details>
<summary><b>바가 사라졌습니다 / 화면 밖으로 나갔습니다</b></summary>

바는 보이는 화면 영역 밖으로는 나가지 않게 되돌립니다. 그래도 안 보인다면 외장 모니터를 분리한 뒤 위치가 남은 경우일 수 있습니다. 저장된 위치를 초기화하세요.

```bash
pkill -f Glancie
defaults delete com.glancie.app
```
</details>

<details>
<summary><b>백그라운드에서 CPU나 배터리를 먹지 않나요? rate limit(429)에 걸리진 않나요?</b></summary>

그러지 않도록 만든 것이 이 앱 설계의 중심입니다.

- **캐시 우선** — 도구가 디스크에 남긴 값을 먼저 읽고, 그 값이 15분보다 오래됐을 때만 프로세스를 띄웁니다
- **45초 주기** — 백그라운드 갱신은 45초마다 한 번
- **프로세스 생성 독점 관리** — CLI 프로브는 키별 최소 간격(`claude` 5분 / `agy` 3분), 키별 단일 실행, **전역 동시 실행 1개**로 제한됩니다
- **작업이 끝난 순간에만 추가 조회** — 파일 감시로 실제 토큰 스트리밍만 골라내고, 마지막 쓰기 후 3초가 지나면 그 자리에서 한 번 다시 읽습니다

배경과 실제로 밟았던 함정은 [`wiki/usage-fetch-strategy-and-triggers.md`](wiki/usage-fetch-strategy-and-triggers.md)에 정리해 두었습니다.
</details>

<details>
<summary><b>삭제하고 싶습니다</b></summary>

```bash
# 1. 실행 중인 프로세스 종료
pkill -f Glancie

# 2. 설치된 앱 삭제
rm -rf /Applications/Glancie.app

# 3. 저장된 설정(창 위치, 사운드, 활성 Provider, 언어 등) 초기화
defaults delete com.glancie.app 2>/dev/null || true
defaults delete Glancie 2>/dev/null || true
```

Glancie는 `/Applications` 바깥에 아무것도 설치하지 않습니다. 남는 것은 위 환경설정뿐입니다.
</details>

---

## 프라이버시

Glancie는 **사용량 데이터를 어디로도 보내지 않습니다.** 분석·텔레메트리·크래시 리포트 엔드포인트가 없습니다. 코드에 등장하는 외부 주소는 각 제공업체의 공식 API와, 메뉴에서 눌렀을 때 열리는 콘솔·상태 페이지 링크뿐입니다.

**읽는 것**

- CLI 실행 — `claude -p "/usage"`, `agy -p "/usage"`. 절대 경로로 찾은 바이너리만 실행하며 셸을 경유하지 않습니다
- 로컬 파일 — `~/.claude.json`, `~/.claude/projects/`, `~/.codex/`, `~/.gemini/`, `~/.cursor/`, `~/.config/github-copilot/`, `~/.config/zed/settings.json`, `~/.config/{deepseek,openrouter,groq,moonshot,elevenlabs,mistral}/api_key`
- 환경 변수 — 위 [지원 Provider](#지원-provider) 표의 키들과 `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `GITHUB_TOKEN`/`COPILOT_TOKEN`

**믿지 말고 확인하세요.** 코드에 등장하는 모든 주소는 한 줄로 볼 수 있습니다.

```bash
grep -rhoE 'https?://[^"]+' Sources/ | sort -u
```

목록에 있는 것은 제공업체 API와 브라우저로 여는 링크뿐입니다. 전체 범위는 [`SECURITY.md`](SECURITY.md)에 정리해 두었습니다.

**보호 장치**

- **이메일 마스킹이 기본값** — 계정은 `i***@gmail.com` 형태로 표시됩니다. 바가 화면 공유 중인 화면 위에 떠 있기 때문입니다
- **계정 감지를 끌 수 있습니다** — 설정에서 끄면 어떤 Provider의 계정 파일도 읽지 않고, 쿼터 게이지만 동작합니다
- **진단 로그는 `os.Logger`로만** 나가고 계정 정보는 `privacy: .private`로 가립니다

---

## 개발

```bash
swift build
swift test --parallel      # 249개 테스트
```

실제 로그인된 CLI/API를 호출하는 통합 테스트는 기본적으로 건너뜁니다. Claude와 Antigravity가 설치·인증되어 있고 사용량 데이터가 있는 환경에서만 켜세요.

```bash
GLANCIE_RUN_LOCAL_INTEGRATION_TESTS=1 swift test --filter testRealLocalAdaptersFetching
```

디버그 로그는 이렇게 봅니다. 카테고리는 `provider`(어댑터·프로브), `watcher`(파일 감시·활동 필터), `accounts`(계정 발견·귀속) 셋입니다.

```bash
log stream --predicate 'subsystem == "com.glancie"' --level debug
```

### CI

[`.gitlab-ci.yml`](.gitlab-ci.yml) — 메인테이너의 자체 호스팅 GitLab에서 테스트를 돌리고 DMG를 패키징합니다.

PR에 붙는 자동 검사는 아직 없습니다. 위 두 명령을 직접 돌려 주세요.

<details>
<summary><b>프로젝트 구조</b></summary>

```
Sources/Glancie/
├── App/              NSApplication 진입점, 메뉴바 status item
├── Panel/            NSPanel 플로팅 창, 드래그, 화면 배치
├── Providers/
│   ├── Core/         AIProviderProtocol, ProviderManager, ProbeGate,
│   │                 FSEventsWatcher, 활동 필터, 제로컨피그 스캐너
│   ├── Adapters/     Provider별 사용량 수집 (14개)
│   └── Accounts/     계정 발견·식별·사용량 귀속
├── Views/            메인 바, 메뉴바 화면, 게이지, 상세 카드, 픽셀 고양이
├── Localization/     언어 결정과 문자열 카탈로그 (한국어·영어)
├── DesignSystem/     머티리얼, 스프링, 컬러 테마, 사운드
├── Storage/          UserDefaults 환경설정
└── Support/          os.Logger, Locked<Value>
```
</details>

---

## 기여

이슈와 PR 모두 환영합니다. 한국어·영어 어느 쪽이든 괜찮습니다.

- **버그 제보 · Provider 추가 요청** — [이슈 열기](https://github.com/ktkfree/glancie/issues/new). Provider 요청은 사용량을 어디서 읽을 수 있는지(API·파일·CLI 명령) 같이 적어 주세요
- **코드 기여** — [`CONTRIBUTING.md`](CONTRIBUTING.md)에 개발 환경, 커밋 규칙, 새 Provider 추가하는 법이 있습니다
- **취약점 제보** — 공개 이슈가 아니라 [`SECURITY.md`](SECURITY.md)의 절차로 부탁드립니다

PR 전에 `swift build && swift test --parallel`이 통과하는지, 릴리즈 빌드 경고가 0개인지 확인해 주세요.

한 가지만 기억해 주세요 — **확실하지 않은 숫자는 만들지 않습니다.** 읽을 수 없으면 "데이터 없음"으로 둡니다.

---

## 로드맵

- [ ] **스크린샷** — README에 실제 화면이 필요합니다
- [ ] **배포 릴리즈** — GitHub Releases에 빌드된 `.app`을 올려야 합니다
- [ ] **코드 서명·공증** — 배포 바이너리가 서명되지 않아 Gatekeeper 우회가 필요합니다
- [ ] **Cursor · Windsurf · Zed · Mistral 쿼터** — 검증된 수집 경로가 확인되면 추가합니다
- [ ] **언어 추가** — 현재 한국어와 영어 둘입니다. 세 번째 언어는 [`L10n.swift`](Sources/Glancie/Localization/L10n.swift)에 축을 하나 더 다는 일입니다

---

## 문서

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — 개발 환경, 커밋 규칙, 새 Provider 추가하기
- [`SECURITY.md`](SECURITY.md) — 이 앱이 읽는 것·실행하는 것·내보내는 것, 취약점 제보
- [`wiki/INDEX.md`](wiki/INDEX.md) — 설계 결정 기록 색인. **왜** 그렇게 만들었는지가 여기 있습니다

---

## 라이선스

[MIT](LICENSE) — 만든 사람: [강프로의 연구실](https://www.storyqbe.com)

Glancie는 Anthropic, OpenAI, Google, GitHub, Cursor, Codeium, Zed Industries, DeepSeek, Moonshot AI, Mistral AI, Groq, ElevenLabs, OpenRouter와 아무 관련이 없으며 이들로부터 보증받지 않았습니다. 제품명은 각 소유자의 상표이며 해당 도구를 식별하기 위해서만 사용했습니다.
