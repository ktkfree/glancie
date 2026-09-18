# 보안 정책

## 취약점 제보

**공개 이슈로 올리지 말아 주세요.** GitHub의 [Security advisories](../../security/advisories/new)로 비공개 제보를 받습니다.

확인되는 대로 회신하고, 수정본과 함께 공개합니다. 제보자가 원하면 크레딧을 남깁니다.

## 이 앱이 만지는 것

Glancie는 사용량을 읽기 위해 **다른 도구의 인증 정보에 접근합니다.** 무엇을 어디까지 하는지 먼저 밝혀 둡니다. 여기서 벗어나는 동작을 발견했다면 그게 곧 취약점입니다.

### 읽는 것

- **로컬 설정 파일** — `~/.claude.json`, `~/.claude/projects/`, `~/.codex/`, `~/.gemini/`, `~/.cursor/`, `~/.config/github-copilot/`, `~/.config/zed/settings.json`, `~/.config/{deepseek,openrouter,groq,moonshot,elevenlabs,mistral}/api_key`
- **환경 변수** — 각 제공업체의 API 키, `CLAUDE_CONFIG_DIR`, `CODEX_HOME`
- 읽기 전용입니다. 이 파일들에 쓰지 않습니다.

### 실행하는 것

- `claude -p "/usage"`, `agy -p "/usage"` 두 개뿐입니다.
- **절대 경로로 찾은 바이너리만 실행하며 셸을 경유하지 않습니다.** 사용자 입력이 명령줄에 들어가는 경로가 없습니다.
- 프로세스 생성은 `ProbeGate`가 단독으로 관리합니다 — 키별 최소 간격, 키별 단일 실행, 전역 동시 실행 1개.

### 내보내는 것

- **분석·텔레메트리·크래시 리포트 엔드포인트가 없습니다.** 사용량 데이터는 어디로도 나가지 않습니다.
- 네트워크 요청은 각 제공업체의 공식 API로만 갑니다: `api.deepseek.com`, `openrouter.ai`, `api.groq.com`, `api.moonshot.cn`, `api.elevenlabs.io`, `api.github.com`, `localhost:11434`(Ollama).
- 그 외 주소는 메뉴에서 사용자가 눌렀을 때 **브라우저로 여는 링크**일 뿐 앱이 요청하지 않습니다.

### 로그

- 진단은 `os.Logger`로만 나갑니다. 계정 식별 정보는 `privacy: .private`로 가립니다.
- `log stream --predicate 'subsystem == "com.glancie"'`로 직접 확인할 수 있습니다.

## 관심 있는 제보

- API 키·토큰·계정 식별자가 로그, 화면, 디스크 어딘가로 **의도보다 넓게** 새는 경로
- 위에 적힌 것 외의 바이너리 실행, 또는 셸을 경유하는 실행 경로
- 위에 적힌 것 외의 네트워크 목적지
- 악의적으로 조작된 제공업체 설정 파일이나 API 응답으로 앱을 임의 코드 실행에 빠뜨리는 경우
- 이메일 마스킹이나 계정 감지 끄기가 실제로는 적용되지 않는 경우

## 범위 밖

- **코드 서명·공증이 없다는 점** — 알려진 상태이며 README에 적어 두었습니다. Gatekeeper 우회 안내 자체는 취약점이 아닙니다.
- 각 제공업체 CLI·API 자체의 취약점 — 해당 제공업체에 제보해 주세요.
- 이미 로컬 파일을 읽을 수 있는 공격자를 전제한 시나리오. Glancie는 그 파일들을 읽는 앱이므로, 같은 권한을 이미 가진 상대를 막지 못합니다.

## 지원 버전

아직 1.0.0 한 줄기뿐입니다. 수정은 `main`에 반영합니다.
