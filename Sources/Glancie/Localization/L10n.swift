import Foundation

/// Every user-visible string in the app, in both languages.
///
/// Deliberately not a `.strings` resource bundle. `scripts/build_manual.sh`
/// assembles the `.app` by copying the executable alone, so an SPM resource
/// bundle would be missing at runtime and `Bundle.module` would trap — the app
/// would launch fine from `swift run` and crash from `/Applications`. A Swift
/// enum has no such gap, and it buys something a `.strings` file cannot: the
/// compiler refuses to build a case that is missing either language, and
/// interpolated text carries its arguments as associated values instead of
/// positional `%@` tokens that nothing checks.
///
/// Read `.text` to render. It resolves against `Localization.current`, which is
/// safe to touch from any thread — adapters format quota names off the main
/// actor.
public enum L10n {

    // MARK: - Usage state

    case notConnected
    case usageNotMeasured
    case authenticationFailed
    case rateLimited
    case networkError
    case malformedResponse
    case providerError

    case guidanceHeaderConnection
    case guidanceHeaderMeasurement
    case guidanceHeaderAuthentication
    case guidanceHeaderRateLimit
    case guidanceHeaderNetwork
    case guidanceHeaderResponse
    case guidanceHeaderProvider

    case guidanceTitleNotConfigured
    case guidanceTitleNotMeasured
    case guidanceTitleAuthFailed
    case guidanceTitleRateLimited
    case guidanceTitleNetwork
    case guidanceTitleMalformed
    case guidanceTitleProviderError

    case guidanceDetailNotConfigured
    case guidanceDetailNotMeasured
    case guidanceDetailAuthFailed
    case guidanceDetailRateLimited
    case guidanceDetailNetwork
    case guidanceDetailMalformed
    case guidanceDetailProviderError

    // MARK: - Fetch errors

    case errorMissingCredentials
    case errorHTTPStatus(Int)
    case errorInvalidResponse
    case errorNetworkRefreshFailed
    case errorRefreshFailed

    // MARK: - Usage tiers

    case tierAbundant
    case tierSteady
    case tierCaution
    case tierCritical

    // MARK: - Quota names produced by adapters

    case quotaNoteWarning
    case quotaNoteCritical
    case quotaNoteBindingLimit
    case claudeExtraCredits
    case claudeSession5h
    case claudeWeeklyAllModels
    case claudeWeeklyModel(String)
    case codexPrimaryLimit
    case codexSecondaryLimit
    case codexWindowWeeks(Int)
    case codexWindowDays(Int)
    case codexWindowHours(Int)
    case codexWindowMinutes(Int)
    case codexCredits
    case codexBalance(Int)
    case unlimited
    case groqTokenLimit
    case groqRequestLimit
    case groqTokensPerMinute(Int)
    case groqRequestsPerDay(Int)
    case openRouterAccountBalance
    case openRouterAccountBalanceWith(String)
    case openRouterKeyBudget
    case openRouterKeyBudgetWith(String, String)
    case openRouterKeyUnlimited
    case openRouterKeyUsed(String)
    case elevenLabsCharacterUsage
    case googleAccountSuffix(String)

    // MARK: - Menu bar

    case providers
    case updating
    case noProvidersConnected
    case waiting
    case connectedCount(Int, String)
    case refreshing
    case refreshAll
    case settingsEllipsis
    case aboutGlancie
    case quitGlancie
    case noProvidersToShow
    case pickProvidersInSettings
    case openSettings
    case overview
    case screenSuffix(String)
    case on
    case off
    case syncedJustNow
    case syncedMinutesAgo(Int)
    case syncedHoursAgo(Int)
    case syncedDaysAgo(Int)
    case running
    case noUsage
    case onTheBar

    // MARK: - Settings

    case settings
    case accounts
    case accountsFootnote
    case accountDetection
    case accountDetectionSubtitle
    case maskEmail
    case maskEmailSubtitle
    case noAccountsDetected
    case scanAgain
    case providersOnBar
    case providersOnBarFootnote
    case detected
    case atLeastOneProvider
    case shown
    case hidden
    case experienceSection
    case hapticsAndSound
    case hapticsAndSoundSubtitle
    case eyeTracking
    case eyeTrackingSubtitle
    case pixelCat
    case pixelCatSubtitle
    case coatColor
    case language
    case languageFootnote
    case languageSystem

    // MARK: - Provider detail

    case refreshFailed(String)
    case showingLastMeasurement
    case sessionQuota
    case connectionStatus
    case checkSignInState
    case quotaDetail
    case quotaDetailFootnote
    case howThisWasRead
    case noSignInFound
    case accountsFootnoteAttribution
    case refreshThisProvider
    case planUsageDashboard
    case serviceStatusPage
    case providerSettingsEllipsis
    case providerSession(String)
    case providerWeekly(String)

    // MARK: - Detail card

    case quotaDetailFor(String)
    case noDataWithReason(String)
    case close
    case weeklyQuota
    case weeklyRemaining
    case resetLine(TimeInterval)
    case weeklyQuotaAccessibility(Int, String)
    case weeklyQuotaAwaiting(String)
    case remainingByModel
    case dashboard
    case refresh

    // MARK: - Quota components

    case notConnectedShort
    case resetShort
    case noData
    case awaitingRemeasurement
    case remainingSuffix
    case captionNoData(String)
    case captionAwaiting(String, String)
    case captionRemaining(String, Int, String)
    case suggestedPace(Int)
    case empty
    case modelQuotaAccessibility(String, String, Int)

    // MARK: - Activity badges

    case working
    case aiTaskInProgress
    case appOpen
    case desktopAppRunning
    case countdownDaysHours(Int, Int)
    case countdownDays(Int)
    case countdownHoursMinutes(Int, Int)
    case countdownHours(Int)
    case countdownMinutes(Int)
    case countdownSoon
    case resetAtTime(String)
    case updatedJustNow
    case updatedMinutesAgo(Int)
    case updatedHoursAgo(Int)

    // MARK: - Bar

    case usageBar
    case refreshingUsage
    case openQuotaCard
    case openQuotaDetail
    case segmentNotConnected(String)
    case segmentLimitReset(String)
    case segmentRemaining(String, Int)
    case segmentNoData(String)
    case limitResetAwaiting
    case remainingPercentTier(Int, String)
    case suffixWorking
    case suffixAppRunning
    case suffixCurrentlyWorking
    case providerNoData(String, String)
    case providerRemaining(String, Int, String)

    // MARK: - About

    case about
    case glancieTagline
    case viewSourceOnGitHub
    case license
    case theMaker
    case makerName
    case makerSite
    case makerTagline
    case makerBio
    case makerStatProducts
    case makerStatLive
    case makerLocation
    case enterTheLab
    case otherProducts
    case allProducts(Int)
    case experimental
    case productIVent
    case productIVentSummary
    case productAptMap
    case productAptMapSummary
    case productQbeTools
    case productQbeToolsSummary
    case productUnbubble
    case productUnbubbleSummary
    case productQuantPersona
    case productQuantPersonaSummary

    // MARK: - Pixel cat

    case catOrangeTabby
    case catCalico
    case catTuxedo
    case catTurkishAngora
    case catBlack
    case catCompanion(String)

    /// The rendered string, in whichever language is current.
    public var text: String {
        Localization.current == .korean ? pair.ko : pair.en
    }

    /// Both languages, side by side so a reviewer can see a translation drift
    /// without opening two files. One exhaustive switch, so neither language can
    /// be forgotten for a case.
    var pair: (ko: String, en: String) {
        switch self {

        // MARK: Usage state
        case .notConnected:
            return ("연결 대기 중", "Not connected")
        case .usageNotMeasured:
            return ("사용량 측정 미지원", "Usage not measurable")
        case .authenticationFailed:
            return ("인증 실패", "Authentication failed")
        case .rateLimited:
            return ("요청 한도 초과", "Rate limited")
        case .networkError:
            return ("네트워크 오류", "Network error")
        case .malformedResponse:
            return ("응답 해석 실패", "Unreadable response")
        case .providerError:
            return ("제공자 오류", "Provider error")

        case .guidanceHeaderConnection:
            return ("연결 상태", "Connection")
        case .guidanceHeaderMeasurement:
            return ("측정 지원", "Measurement")
        case .guidanceHeaderAuthentication:
            return ("인증 상태", "Authentication")
        case .guidanceHeaderRateLimit:
            return ("요청 한도", "Rate limit")
        case .guidanceHeaderNetwork:
            return ("네트워크", "Network")
        case .guidanceHeaderResponse:
            return ("응답 해석", "Response")
        case .guidanceHeaderProvider:
            return ("제공자 오류", "Provider error")

        case .guidanceTitleNotConfigured:
            return ("실제 쿼터 데이터를 가져오지 못했습니다", "No real quota data could be read")
        case .guidanceTitleNotMeasured:
            return ("이 provider는 사용량 측정을 지원하지 않습니다", "This provider does not report usage")
        case .guidanceTitleAuthFailed:
            return ("인증이 거부되었습니다", "Authentication was rejected")
        case .guidanceTitleRateLimited:
            return ("요청 한도를 초과해 읽지 못했습니다", "The read was refused for exceeding the rate limit")
        case .guidanceTitleNetwork:
            return ("제공자에 연결하지 못했습니다", "Could not reach the provider")
        case .guidanceTitleMalformed:
            return ("응답에서 쿼터를 읽어내지 못했습니다", "No quota could be read from the response")
        case .guidanceTitleProviderError:
            return ("제공자가 오류를 반환했습니다", "The provider returned an error")

        case .guidanceDetailNotConfigured:
            return (
                "CLI·앱 로그인 상태 또는 연결 설정을 확인하세요.",
                "Check that the CLI or app is signed in and configured."
            )
        case .guidanceDetailNotMeasured:
            return (
                "설치는 감지했습니다. 다만 이 앱이 읽을 수 있는 쿼터를 내보내지 않아, 로그인해도 표시할 수치가 없습니다.",
                "It was detected on this Mac, but it publishes no quota this app can read — signing in will not produce a figure."
            )
        case .guidanceDetailAuthFailed:
            return (
                "API 키가 만료되었거나 권한이 없습니다. 키를 다시 발급하거나 로그인을 갱신하세요.",
                "The API key has expired or lacks permission. Reissue the key, or sign in again."
            )
        case .guidanceDetailRateLimited:
            return (
                "제공자가 조회를 일시적으로 거부했습니다. 한도가 풀리면 다음 갱신에서 자동으로 복구됩니다.",
                "The provider turned the lookup away for now. It recovers on the next refresh once the limit clears."
            )
        case .guidanceDetailNetwork:
            return (
                "네트워크 연결 상태를 확인하세요. 연결이 돌아오면 다음 갱신에서 자동으로 복구됩니다.",
                "Check your network connection. It recovers on the next refresh once the connection returns."
            )
        case .guidanceDetailMalformed:
            return (
                "제공자가 답하기는 했지만 형식이 예상과 달랐습니다. 제공자가 API를 바꿨다면 앱 업데이트가 필요합니다.",
                "The provider answered, but not in the shape expected. If it changed its API, this app needs an update."
            )
        case .guidanceDetailProviderError:
            return (
                "제공자 쪽 문제일 수 있습니다. 계속되면 제공자의 상태 페이지를 확인하세요.",
                "This may be on the provider's side. If it keeps happening, check their status page."
            )

        // MARK: Fetch errors
        case .errorMissingCredentials:
            return ("사용량 조회 인증 정보가 없습니다.", "No credentials for reading usage.")
        case .errorHTTPStatus(let status):
            return ("사용량 조회 실패 (HTTP \(status))", "Usage read failed (HTTP \(status))")
        case .errorInvalidResponse:
            return ("사용량 응답을 해석할 수 없습니다.", "The usage response could not be read.")
        case .errorNetworkRefreshFailed:
            return ("네트워크 오류로 사용량을 갱신하지 못했습니다.", "Usage could not be refreshed: network error.")
        case .errorRefreshFailed:
            return ("사용량을 갱신하지 못했습니다.", "Usage could not be refreshed.")

        // MARK: Usage tiers
        case .tierAbundant:
            return ("여유", "Abundant")
        case .tierSteady:
            return ("안정", "Steady")
        case .tierCaution:
            return ("주의", "Caution")
        case .tierCritical:
            return ("임박", "Critical")

        // MARK: Quota names
        case .quotaNoteWarning:
            return ("주의", "Warning")
        case .quotaNoteCritical:
            return ("임박", "Critical")
        case .quotaNoteBindingLimit:
            return ("현재 적용 중인 한도", "Currently binding limit")
        case .claudeExtraCredits:
            return ("추가 사용량 크레딧", "Extra usage credits")
        case .claudeSession5h:
            return ("세션 (5시간)", "Session (5h)")
        case .claudeWeeklyAllModels:
            return ("주간 (전체 모델)", "Weekly (all models)")
        case .claudeWeeklyModel(let model):
            return ("주간 (\(model))", "Weekly (\(model))")
        case .codexPrimaryLimit:
            return ("기본 한도", "Primary limit")
        case .codexSecondaryLimit:
            return ("보조 한도", "Secondary limit")
        case .codexWindowWeeks(let weeks):
            return ("\(weeks)주 한도", "\(weeks)-week limit")
        case .codexWindowDays(let days):
            return ("\(days)일 한도", "\(days)-day limit")
        case .codexWindowHours(let hours):
            return ("\(hours)시간 한도", "\(hours)-hour limit")
        case .codexWindowMinutes(let minutes):
            return ("\(minutes)분 한도", "\(minutes)-minute limit")
        case .codexCredits:
            return ("크레딧", "Credits")
        case .codexBalance(let balance):
            return ("잔액 \(balance)", "Balance \(balance)")
        case .unlimited:
            return ("무제한", "Unlimited")
        case .groqTokenLimit:
            return ("토큰 한도 (TPM)", "Token limit (TPM)")
        case .groqRequestLimit:
            return ("요청 한도 (RPD)", "Request limit (RPD)")
        case .groqTokensPerMinute(let tokens):
            return ("분당 \(tokens) 토큰", "\(tokens) tokens/min")
        case .groqRequestsPerDay(let requests):
            return ("일일 \(requests) 요청", "\(requests) requests/day")
        case .openRouterAccountBalance:
            return ("계정 잔액", "Account balance")
        case .openRouterAccountBalanceWith(let amount):
            return ("계정 잔액 (\(amount))", "Account balance (\(amount))")
        case .openRouterKeyBudget:
            return ("API 키 예산", "API key budget")
        case .openRouterKeyBudgetWith(let remaining, let limit):
            return ("API 키 예산 (\(remaining) / \(limit))", "API key budget (\(remaining) / \(limit))")
        case .openRouterKeyUnlimited:
            return ("API 키 (무제한)", "API key (unlimited)")
        case .openRouterKeyUsed(let usage):
            return ("API 키 (\(usage) 사용)", "API key (\(usage) used)")
        case .elevenLabsCharacterUsage:
            return ("문자 사용량", "Character usage")
        case .googleAccountSuffix(let suffix):
            return ("Google 계정 ···\(suffix)", "Google account ···\(suffix)")

        // MARK: Menu bar
        case .providers:
            return ("프로바이더", "Providers")
        case .updating:
            return ("업데이트 중", "Updating")
        case .noProvidersConnected:
            return ("연결된 프로바이더 없음", "No providers connected")
        case .waiting:
            return ("대기 중", "Waiting")
        case .connectedCount(let count, let freshness):
            return ("\(count)개 연결 · \(freshness)", "\(count) connected · \(freshness)")
        case .refreshing:
            return ("새로 고침 중...", "Refreshing…")
        case .refreshAll:
            return ("모두 새로 고침", "Refresh All")
        case .settingsEllipsis:
            return ("설정...", "Settings…")
        case .aboutGlancie:
            return ("Glancie 정보", "About Glancie")
        case .quitGlancie:
            return ("Glancie 종료", "Quit Glancie")
        case .noProvidersToShow:
            return ("표시할 프로바이더가 없습니다", "No providers to show")
        case .pickProvidersInSettings:
            return ("설정에서 추적할 AI 프로바이더를 선택하세요.", "Choose which AI providers to track in Settings.")
        case .openSettings:
            return ("설정 열기", "Open Settings")
        case .overview:
            return ("전체 현황", "Overview")
        case .screenSuffix(let title):
            return ("\(title) 화면", "\(title) screen")
        case .on:
            return ("켜짐", "On")
        case .off:
            return ("꺼짐", "Off")
        case .syncedJustNow:
            return ("방금 기준", "as of just now")
        case .syncedMinutesAgo(let minutes):
            return ("\(minutes)분 전 기준", "as of \(minutes)m ago")
        case .syncedHoursAgo(let hours):
            return ("\(hours)시간 전 기준", "as of \(hours)h ago")
        case .syncedDaysAgo(let days):
            return ("\(days)일 전 기준", "as of \(days)d ago")
        case .running:
            return ("실행 중", "Running")
        case .noUsage:
            return ("사용량 없음", "No usage")
        case .onTheBar:
            return ("바에 표시 중", "On the bar")

        // MARK: Settings
        case .settings:
            return ("설정", "Settings")
        case .accounts:
            return ("계정", "Accounts")
        case .accountsFootnote:
            return (
                "각 프로바이더의 로그인 정보를 로컬 파일에서만 읽습니다. 네트워크 요청이나 토큰 저장은 없습니다.",
                "Sign-in details are read from local files only. No network requests, nothing stored."
            )
        case .accountDetection:
            return ("계정 감지", "Account detection")
        case .accountDetectionSubtitle:
            return ("CLI와 데스크톱 앱의 로그인 계정을 찾습니다", "Finds accounts signed into CLIs and desktop apps")
        case .maskEmail:
            return ("이메일 가리기", "Mask email")
        case .maskEmailSubtitle:
            return ("i***@gmail.com 형태로 표시", "Shown as i***@gmail.com")
        case .noAccountsDetected:
            return ("감지된 계정이 없습니다.", "No accounts detected.")
        case .scanAgain:
            return ("계정 다시 검색", "Scan again")
        case .providersOnBar:
            return ("표시할 프로바이더", "Providers on the bar")
        case .providersOnBarFootnote:
            return (
                "‘감지됨’은 이 Mac에서 해당 CLI 또는 앱을 찾았다는 뜻입니다.",
                "“Detected” means the CLI or app was found on this Mac."
            )
        case .detected:
            return ("감지됨", "Detected")
        case .atLeastOneProvider:
            return ("최소 하나의 프로바이더는 표시되어야 합니다", "At least one provider has to stay on the bar")
        case .shown:
            return ("표시", "Shown")
        case .hidden:
            return ("숨김", "Hidden")
        case .experienceSection:
            return ("경험 및 인터랙션", "Experience & interaction")
        case .hapticsAndSound:
            return ("햅틱 & 사운드", "Haptics & sound")
        case .hapticsAndSoundSubtitle:
            return ("선택과 상호작용에 촉각 피드백", "Tactile feedback on selection and interaction")
        case .eyeTracking:
            return ("시선 추적", "Eye tracking")
        case .eyeTrackingSubtitle:
            return ("커서를 따라 눈동자가 움직임", "The eyes follow your cursor")
        case .pixelCat:
            return ("픽셀 고양이", "Pixel cat")
        case .pixelCatSubtitle:
            return ("바 위에 앉는 동반자", "A companion that sits on the bar")
        case .coatColor:
            return ("털색", "Coat")
        case .language:
            return ("언어", "Language")
        case .languageFootnote:
            return (
                "‘시스템 설정 따름’은 macOS의 언어 설정을 씁니다. 한국어면 한국어로, 그 외에는 영어로 표시합니다.",
                "“Follow System” uses your macOS language setting: Korean if that is Korean, English otherwise."
            )
        case .languageSystem:
            return ("시스템 설정 따름", "Follow System")

        // MARK: Provider detail
        case .refreshFailed(let reason):
            return ("갱신 실패: \(reason)", "Refresh failed: \(reason)")
        case .showingLastMeasurement:
            return (" 마지막 측정값입니다.", " Showing the last measurement.")
        case .sessionQuota:
            return ("세션 쿼터", "Session quota")
        case .connectionStatus:
            return ("연결 상태", "Connection")
        case .checkSignInState:
            return ("해당 CLI/앱 로그인 상태 또는 설정을 확인해 주세요.", "Check that the CLI or app is signed in and configured.")
        case .quotaDetail:
            return ("쿼터 상세", "Quota detail")
        case .quotaDetailFootnote:
            return (
                "세로 눈금은 리셋까지 유지 가능한 권장 페이스입니다.",
                "The vertical tick marks the pace that lasts until reset."
            )
        case .howThisWasRead:
            return ("이 수치를 가져온 방식", "How this figure was read")
        case .noSignInFound:
            return ("로그인 정보 없음", "No sign-in found")
        case .accountsFootnoteAttribution:
            return (
                "쿼터는 계정별로 집계됩니다. 위 미터는 ‘바에 표시 중’인 계정 기준입니다.",
                "Quota is tallied per account. The meter above follows the account marked “on the bar”."
            )
        case .refreshThisProvider:
            return ("이 프로바이더 새로 고침", "Refresh this provider")
        case .planUsageDashboard:
            return ("요금제 사용량 대시보드", "Plan usage dashboard")
        case .serviceStatusPage:
            return ("서비스 상태 페이지", "Service status page")
        case .providerSettingsEllipsis:
            return ("프로바이더 설정...", "Provider settings…")
        case .providerSession(let name):
            return ("\(name) 세션", "\(name) session")
        case .providerWeekly(let name):
            return ("\(name) 주간", "\(name) weekly")

        // MARK: Detail card
        case .quotaDetailFor(let provider):
            return ("\(provider) 쿼터 상세", "\(provider) quota detail")
        case .noDataWithReason(let reason):
            return ("\(reason) (데이터 없음)", "\(reason) (no data)")
        case .close:
            return ("닫기", "Close")
        case .weeklyQuota:
            return ("주간 쿼터", "Weekly quota")
        case .weeklyRemaining:
            return ("주간 잔여", "Weekly left")
        case .resetLine(let seconds):
            // Under a minute the countdown is already a whole phrase ("곧 리셋"),
            // so appending the word again would stutter.
            guard seconds >= 60 else { return ("곧 리셋", "Resets soon") }
            let countdown = quotaCountdownText(seconds)
            return ("\(countdown) 리셋", "Resets \(countdown)")
        case .weeklyQuotaAccessibility(let percent, let tier):
            return ("주간 쿼터 잔여 \(percent) 퍼센트, \(tier)", "Weekly quota, \(percent) percent left, \(tier)")
        case .weeklyQuotaAwaiting(let resetText):
            return ("주간 쿼터, \(resetText), 재측정 대기 중", "Weekly quota, \(resetText), awaiting re-measurement")
        case .remainingByModel:
            return ("모델별 잔여 쿼터", "Remaining by model")
        case .dashboard:
            return ("대시보드", "Dashboard")
        case .refresh:
            return ("새로 고침", "Refresh")

        // MARK: Quota components
        case .notConnectedShort:
            return ("미연결", "Not connected")
        case .resetShort:
            return ("리셋됨", "Reset")
        case .noData:
            return ("데이터 없음", "No data")
        case .awaitingRemeasurement:
            return ("재측정 대기", "Re-measuring")
        case .remainingSuffix:
            return ("남음", "left")
        case .captionNoData(let caption):
            return ("\(caption), 데이터 없음 (연결 대기 중)", "\(caption), no data (not connected)")
        case .captionAwaiting(let caption, let resetText):
            return ("\(caption), \(resetText), 재측정 대기 중", "\(caption), \(resetText), awaiting re-measurement")
        case .captionRemaining(let caption, let percent, let tier):
            return ("\(caption) 잔여 \(percent) 퍼센트, \(tier)", "\(caption), \(percent) percent left, \(tier)")
        case .suggestedPace(let percent):
            return ("권장 페이스 \(percent) 퍼센트", "Suggested pace \(percent) percent")
        case .empty:
            return ("소진", "Empty")
        case .modelQuotaAccessibility(let name, let type, let percent):
            return ("\(name) \(type) 잔여 \(percent) 퍼센트", "\(name) \(type), \(percent) percent left")

        // MARK: Activity badges
        case .working:
            return ("생성 중", "Working")
        case .aiTaskInProgress:
            return ("AI 작업 진행 중", "AI task in progress")
        case .appOpen:
            return ("앱 열림", "App open")
        case .desktopAppRunning:
            return ("데스크톱 앱 실행 중", "Desktop app running")
        case .countdownDaysHours(let days, let hours):
            return ("\(days)일 \(hours)시간 후", "in \(days)d \(hours)h")
        case .countdownDays(let days):
            return ("\(days)일 후", "in \(days)d")
        case .countdownHoursMinutes(let hours, let minutes):
            return ("\(hours)시간 \(minutes)분 후", "in \(hours)h \(minutes)m")
        case .countdownHours(let hours):
            return ("\(hours)시간 후", "in \(hours)h")
        case .countdownMinutes(let minutes):
            return ("\(minutes)분 후", "in \(minutes)m")
        case .countdownSoon:
            return ("곧 리셋", "Resets soon")
        case .resetAtTime(let time):
            return ("\(time)에 리셋됨", "reset at \(time)")
        case .updatedJustNow:
            return ("방금 업데이트", "Updated just now")
        case .updatedMinutesAgo(let minutes):
            return ("\(minutes)분 전 업데이트", "Updated \(minutes)m ago")
        case .updatedHoursAgo(let hours):
            return ("\(hours)시간 전 업데이트", "Updated \(hours)h ago")

        // MARK: Bar
        case .usageBar:
            return ("Glancie 사용량 바", "Glancie usage bar")
        case .refreshingUsage:
            return ("사용량 새로고침 중", "Refreshing usage")
        case .openQuotaCard:
            return ("상세 쿼터 카드를 엽니다", "Opens the detailed quota card")
        case .openQuotaDetail:
            return ("상세 쿼터를 엽니다", "Opens the detailed quota")
        case .segmentNotConnected(let provider):
            return ("\(provider) · 연결 대기 중 (데이터 없음)", "\(provider) · not connected (no data)")
        case .segmentLimitReset(let provider):
            return ("\(provider) · 한도가 리셋됨 (재측정 대기)", "\(provider) · limit reset (re-measuring)")
        case .segmentRemaining(let provider, let percent):
            return ("\(provider) · 잔여 \(percent)%", "\(provider) · \(percent)% left")
        case .segmentNoData(let reason):
            return ("데이터 없음 (\(reason))", "No data (\(reason))")
        case .limitResetAwaiting:
            return ("한도가 리셋됨, 재측정 대기 중", "Limit reset, awaiting re-measurement")
        case .remainingPercentTier(let percent, let tier):
            return ("잔여 \(percent) 퍼센트, \(tier)", "\(percent) percent left, \(tier)")
        case .suffixWorking:
            return (", 작업 중", ", working")
        case .suffixAppRunning:
            return (", 앱 실행 중", ", app running")
        case .suffixCurrentlyWorking:
            return (", 현재 AI 작업 중", ", currently working")
        case .providerNoData(let provider, let reason):
            return ("\(provider), 데이터 없음 (\(reason))", "\(provider), no data (\(reason))")
        case .providerRemaining(let provider, let percent, let tier):
            return ("\(provider), 잔여 \(percent) 퍼센트, \(tier)", "\(provider), \(percent) percent left, \(tier)")

        // MARK: About
        case .about:
            return ("정보", "About")
        case .glancieTagline:
            return (
                "여러 AI 코딩 도구의 남은 사용량을 바 하나로 보여줍니다",
                "Every AI coding tool's remaining usage, in one bar"
            )
        case .viewSourceOnGitHub:
            return ("GitHub에서 소스 보기", "View source on GitHub")
        case .license:
            return ("라이선스", "License")
        case .theMaker:
            return ("만든 사람", "The maker")
        case .makerName:
            return ("강프로의 연구실", "Kang Pro's Lab")
        case .makerSite:
            return ("storyqbe.com", "storyqbe.com")
        case .makerTagline:
            return ("궁금하면, 일단 만듭니다.", "If I get curious, I just build it.")
        case .makerBio:
            return (
                "iOS 앱, 웹 서비스, 크립토 실험까지. 퇴근 후의 시간을 모아 여러 개의 제품을 굴리는 1인 메이커입니다.",
                "iOS apps, web services, crypto experiments — a solo maker running several products, built in the hours after work."
            )
        case .makerStatProducts:
            return ("제품", "Products")
        case .makerStatLive:
            return ("운영중", "Live")
        case .makerLocation:
            return ("서울", "Seoul")
        case .enterTheLab:
            return ("연구실 둘러보기", "Enter the lab")
        case .otherProducts:
            return ("다른 제품", "Other products")
        case .allProducts(let count):
            return ("전체 \(count)개", "All \(count)")
        case .experimental:
            return ("실험중", "Experimental")
        case .productIVent:
            return ("iVent (아이벤트)", "iVent")
        case .productIVentSummary:
            return ("아이 스케줄, 가족이 함께 관리해요", "Manage your kid's schedule together, as a family")
        case .productAptMap:
            return ("급지도", "Geubjido")
        case .productAptMapSummary:
            return ("실거래가로 보는 아파트 급지 지도", "Apartment tier maps, powered by real transaction data")
        case .productQbeTools:
            return ("qbetools (큐브툴즈)", "QbeTools")
        case .productQbeToolsSummary:
            return ("칩·슬라이더로 조작하는 생활 계산기", "Everyday calculators, reimagined with chips and sliders")
        case .productUnbubble:
            return ("unbubble", "unbubble")
        case .productUnbubbleSummary:
            return ("필터 버블 밖의 유튜브를 발견하다", "Discover YouTube beyond the filter bubble")
        case .productQuantPersona:
            return ("퀀트페르소나", "QuantPersona")
        case .productQuantPersonaSummary:
            return (
                "서로 다른 AI 투자 페르소나의 실전 트랙레코드",
                "Live track records from AI agents with distinct investing personas"
            )

        // MARK: Pixel cat
        case .catOrangeTabby:
            return ("치즈 태비", "Orange Tabby")
        case .catCalico:
            return ("삼색이", "Calico")
        case .catTuxedo:
            return ("턱시도", "Tuxedo")
        case .catTurkishAngora:
            return ("터키시 앙고라", "Turkish Angora")
        case .catBlack:
            return ("검은 고양이", "Black Cat")
        case .catCompanion(let breed):
            return ("고양이 컴패니언: \(breed)", "Cat companion: \(breed)")
        }
    }
}
