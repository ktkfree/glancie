# 기여 안내

이슈와 PR 모두 환영합니다. 한국어·영어 어느 쪽이든 괜찮습니다.

## 시작하기

```bash
git clone https://github.com/ktkfree/glancie.git
cd glancie
swift build
swift test --parallel
swift run Glancie          # 그냥 띄워 보기
```

macOS 14.0(Sonoma) 이상, Swift 5.9+ 툴체인이 필요합니다.

`.app` 번들이 필요하면 `./scripts/build_manual.sh`를 쓰세요. `/Applications` 설치 여부를 물어보며, `GLANCIE_SKIP_INSTALL=1`로 끄거나 `GLANCIE_INSTALL=1`로 묻지 않고 설치할 수 있습니다.

## 이 프로젝트의 제1 규칙

**확실하지 않은 숫자는 만들지 않습니다.**

읽을 수 없는 값은 추측 대신 "데이터 없음"으로 둡니다. 그럴듯한 기본값(0%, 100%, 마지막 값 복사)으로 채우는 PR은 받지 않습니다. 사용자가 이 바를 보고 "지금 작업을 시작해도 되는지" 판단하기 때문입니다. 틀린 숫자는 없는 숫자보다 나쁩니다.

관련해서 지켜지는 것들:

- API 호출이 실패하면 **같은 인증 키로 얻은 마지막 성공값과 그 원래 측정 시각**을 유지합니다. 지금 시각으로 다시 도장 찍지 않습니다.
- 계정이 바뀌면 이전 계정의 수치를 새 계정에 물려주지 않습니다.
- 쿼터 창이 이미 지났으면 "리셋됨"이지 "100%"가 아닙니다.

## PR 전에

- `swift build && swift test --parallel`이 통과해야 합니다.
- **릴리즈 빌드 경고 0개**를 유지합니다: `swift build -c release`
- 동작을 바꾸는 변경에는 테스트를 붙여 주세요.
- 설계 결정을 바꿨다면 [`wiki/`](wiki/INDEX.md)의 해당 문서도 갱신해 주세요.

## 커밋 메시지

**무엇을 바꿨는지보다 왜 바꿨는지**를 씁니다. 최근 로그를 보면 형태가 보입니다.

```
fix(panel): 잡은 자리가 커서에 붙어 있질 않았다
fix(codex): 여는 줄이 8KB를 넘으면 사용량이 통째로 사라졌다
```

제목만 읽어도 어떤 증상이 사라졌는지 알 수 있게 씁니다.

## 새 Provider 추가하기

1. `AIProviderType`에 case를 추가하고 `displayName`·`sfSymbol`·콘솔 링크를 채웁니다.
2. `Providers/Adapters/`에 `AIProviderProtocol`을 구현한 어댑터를 만듭니다.
3. `ProviderManager`의 어댑터 목록에 등록합니다.
4. 테스트를 붙입니다. 최소한 셋 — 정상 응답 파싱, 잘못된 본문 거부(`testEveryAdapterRejectsAMalformedBody`), HTTP/전송 실패 보존(`testEveryAdapterPreservesTheHTTPFailureStatus`). 뒤의 둘은 모든 어댑터를 훑는 테스트라 자동으로 걸립니다.

쿼터를 확실히 읽을 수 없다면 `isDetected`만 구현하고 사용량은 비워 두세요. 그게 Cursor·Windsurf·Zed·Mistral이 지금 하고 있는 일입니다.

**새 Provider는 새 네트워크 목적지입니다.** 공식 API만 쓰고, 어디로 무엇을 보내는지 PR 설명에 적어 주세요.

## 문자열을 건드릴 때

UI 문자열은 전부 [`Sources/Glancie/Localization/L10n.swift`](Sources/Glancie/Localization/L10n.swift)에 있습니다. case를 추가하고 `pair`에 한국어·영어를 나란히 적습니다.

```swift
case refreshAll
// ...
case .refreshAll:
    return ("모두 새로 고침", "Refresh All")
```

한쪽을 빠뜨리면 컴파일이 안 되고, 영어 자리에 한국어가 남아 있으면 `testEveryEnglishStringIsActuallyEnglish`가 잡습니다. 세 번째 언어를 추가하려면 축을 하나 더 다는 일이라 별도 이슈로 이야기해 주세요.

## 하지 말아 주세요

- **텔레메트리·분석·크래시 리포트 추가** — 이 앱은 사용량 데이터를 어디로도 보내지 않습니다. 예외를 만들 계획이 없습니다.
- **셸을 경유하는 프로세스 실행** — CLI는 절대 경로로 찾은 바이너리만 직접 실행합니다.
- **`ProbeGate`를 우회하는 프로세스 생성** — 폴링 비용과 rate limit이 이 설계의 중심입니다.
- **`print`** — 진단은 `os.Logger`로 나가고 계정 정보는 `privacy: .private`로 가립니다.

## 보안

취약점은 이슈가 아니라 [SECURITY.md](SECURITY.md)의 절차로 제보해 주세요.
