#!/usr/bin/env bash
# ============================================================================
# jira-api.sh — Jira REST API v3 + Agile API 래퍼
# ============================================================================
#
# [목적]
#   Atlassian Jira의 REST API v3 및 Agile API를 호출하는 CLI 유틸리티입니다.
#   Claude Code 플러그인에서 Jira 관련 작업을 수행할 때 사용됩니다.
#
# [사용법]
#   bash jira-api.sh <command> [args...]
#
# [환경 변수]
#   CLAUDE_PLUGIN_ROOT - 플러그인 루트 디렉토리 (선택사항)
#   ATLASSIAN_DOMAIN   - Jira 도메인 (jira-config.json 없을 때 fallback)
#   ATLASSIAN_EMAIL    - Atlassian 계정 이메일 (jira-config.json 없을 때 fallback)
#   ATLASSIAN_API_TOKEN - API 토큰 (jira-config.json 없을 때 fallback)
#
# [설정 파일]
#   {PLUGIN_ROOT}/.store/jira-config.json - Atlassian 인증 정보 저장
#
# [의존성]
#   - curl: HTTP 요청
#   - jq: JSON 파싱
#   - base64: Basic Auth 인코딩
#
# [작성자]
#   Claude Code Plugin - Atlassian Integration
#
# [작성일]
#   2024
# ============================================================================

# strict 모드 활성화
# -e: 에러 발생 시 즉시 종료
# -u: 정의되지 않은 변수 사용 시 에러
# -o pipefail: 파이프라인에서 에러 발생 시 전체 실패
set -euo pipefail

# ---------------------------------------------------------------------------
# 경로 설정
# ---------------------------------------------------------------------------
# BASH_SOURCE[0]: 현재 스크립트의 절대 경로
# dirname으로 디렉토리 경로 추출 후 cd로 절대 경로 변환
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CLAUDE_PLUGIN_ROOT 환경변수가 있으면 사용, 없으면 스크립트 상위 디렉토리
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"

# 설정 파일 경로 (JSON 형식의 Atlassian 인증 정보)
# 프로젝트 루트(현재 작업 디렉토리)에 저장소 생성
CONFIG_PATH="${PWD}/.store/jira-config.json"

# ---------------------------------------------------------------------------
# 설정 로드 + 검증
# ---------------------------------------------------------------------------
# _load_config: jira-config.json에서 Jira 인증 정보를 로드하는 내부 함수
#
# [동작]
#   1. jira-config.json 존재 여부 확인
#   2. jq를 사용하여 domain, email, api_token 추출
#   3. 환경변수 fallback 적용 (config 값이 없을 경우)
#   4. 도메인 URL의 후행 슬래시 제거 (URL 조합 오류 방지)
#
# [전역 변수 설정]
#   JIRA_DOMAIN  - Jira 서버 도메인 (예: https://company.atlassian.net)
#   JIRA_EMAIL   - Atlassian 계정 이메일
#   JIRA_TOKEN   - API 토큰
#
# [반환값]
#   0: 성공
#   1: 설정 파일 없음
_load_config() {
    # 설정 파일 존재 확인
    if [[ ! -f "$CONFIG_PATH" ]]; then
        echo "⚠️ Jira 플러그인 설정 파일을 찾을 수 없습니다." >&2
        echo "📝 설정 파일 위치: ${CONFIG_PATH}" >&2
        return 1
    fi

    # jq로 JSON에서 값 추출 (// empty: null이면 빈 문자열)
    JIRA_DOMAIN=$(jq -r '.atlassian.domain // empty' "$CONFIG_PATH" 2>/dev/null)
    JIRA_EMAIL=$(jq -r '.atlassian.email // empty' "$CONFIG_PATH" 2>/dev/null)
    JIRA_TOKEN=$(jq -r '.atlassian.api_token // empty' "$CONFIG_PATH" 2>/dev/null)

    # 환경변수 fallback (config 값이 비어있으면 환경변수 사용)
    # ${VAR:-DEFAULT}: VAR이 설정되지 않았거나 비어있으면 DEFAULT 사용
    JIRA_DOMAIN="${JIRA_DOMAIN:-${ATLASSIAN_DOMAIN:-}}"
    JIRA_EMAIL="${JIRA_EMAIL:-${ATLASSIAN_EMAIL:-}}"
    JIRA_TOKEN="${JIRA_TOKEN:-${ATLASSIAN_API_TOKEN:-}}"

    # 후행 슬래시 제거 (URL 조합 시 이중 슬래시 방지)
    # 예: https://example.com/ -> https://example.com
    JIRA_DOMAIN="${JIRA_DOMAIN%/}"
}

# ---------------------------------------------------------------------------
# URL 인코딩 (순수 bash — python3 의존성 제거)
# ---------------------------------------------------------------------------
# _url_encode: URL에 사용할 수 없는 문자를 퍼센트 인코딩하는 내부 함수
#
# [목적]
#   JQL 쿼리 등 URL에 포함될 문자열을 안전하게 인코딩합니다.
#   외부 의존성(python3) 없이 순수 bash로 구현했습니다.
#
# [파라미터]
#   $1 - 인코딩할 문자열
#
# [인코딩 규칙]
#   - 알파벳, 숫자, . ~ _ - : 그대로 유지
#   - 공백: %20으로 변환
#   - 기타 문자: %XX (16진수) 형식으로 변환
#
# [예시]
#   _url_encode "assignee = currentUser()"
#   # 반환: assignee%20%3D%20currentUser%28%29
#
# [출력]
#   인코딩된 문자열을 stdout으로 출력
_url_encode() {
    local string="$1"
    local length=${#string}
    local encoded=""

    # 문자열을 한 글자씩 순회
    for (( i = 0; i < length; i++ )); do
        local c="${string:i:1}"
        case "$c" in
            # RFC 3986 Unreserved Characters (인코딩 불필요)
            [a-zA-Z0-9.~_-]) encoded+="$c" ;;
            # 공백은 %20으로 인코딩 (+ 대신)
            ' ') encoded+="%20" ;;
            # 기타 문자는 퍼센트 인코딩
            # printf '%%%02X' "'$c": 문자의 ASCII 코드를 16진수로 변환
            *) encoded+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    echo "$encoded"
}

# jira_validate_config: Jira 설정 유효성 검사
#
# [목적]
#   Jira API 호출 전 필수 설정값들이 모두 있는지 확인합니다.
#   누락된 항목이 있으면 사용자에게 안내 메시지를 출력합니다.
#
# [파라미터]
#   없음
#
# [반환값]
#   0: 모든 설정값 존재 (유효)
#   1: 하나 이상의 설정값 누락 (무효)
#
# [출력]
#   누락된 항목 목록 및 설정 가이드
jira_validate_config() {
    # 설정 로드 (에러는 무시하고 누락 항목 체크)
    _load_config 2>/dev/null || true

    local missing=()

    # 각 필수값 체크 및 누락 시 안내 메시지 추가
    [[ -z "${JIRA_DOMAIN:-}" ]] && missing+=("atlassian.domain — Jira 도메인 (예: https://your-org.atlassian.net)")
    [[ -z "${JIRA_EMAIL:-}" ]] && missing+=("atlassian.email — Atlassian 계정 이메일")
    [[ -z "${JIRA_TOKEN:-}" ]] && missing+=("atlassian.api_token — API 토큰")

    # 누락 항목이 있으면 에러 메시지 출력
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "⚠️ Jira 플러그인 설정 오류"
        echo "━━━━━━━━━━━━━━━━━━━━━━"
        echo "❌ 누락된 필수값:"
        for m in "${missing[@]}"; do
            echo "   • ${m}"
        done
        echo ""
        echo "📝 설정 파일 위치: ${CONFIG_PATH}"
        echo "🔗 API 토큰 생성: https://id.atlassian.com/manage-profile/security/api-tokens"
        echo ""
        echo "설정을 완료한 후 세션을 다시 시작해주세요."
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# HTTP 요청
# ---------------------------------------------------------------------------
# _auth_header: Basic Auth 헤더 생성
#
# [목적]
#   Atlassian API 인증을 위한 Basic Auth 헤더 값을 생성합니다.
#
# [인증 방식]
#   email:api_token 형식을 Base64로 인코딩
#
# [출력]
#   Base64 인코딩된 인증 문자열
#
# [사용 예시]
#   Authorization: Basic {반환값}
_auth_header() {
    # printf로 email:token 형식 생성 후 base64 인코딩
    echo "$(printf '%s:%s' "$JIRA_EMAIL" "$JIRA_TOKEN" | base64)"
}

# _jira_request: Jira API HTTP 요청 수행
#
# [목적]
#   Jira REST API에 HTTP 요청을 보내고 응답을 반환합니다.
#   공통 헤더, 에러 처리, 타임아웃 등을 일괄 처리합니다.
#
# [파라미터]
#   $1 - method: HTTP 메서드 (GET, POST, PUT, DELETE)
#   $2 - endpoint: API 엔드포인트 (예: /rest/api/3/myself)
#   $3 - data: (선택) 요청 본문 JSON (POST, PUT용)
#
# [curl 옵션]
#   -s: 진행률 표시 안 함 (silent)
#   -S: 에러 발생 시 에러 메시지 표시 (show-error)
#   --max-time 30: 30초 타임아웃
#   -w "\n%{http_code}: HTTP 상태 코드를 응답 끝에 추가
#
# [에러 처리]
#   HTTP 400 이상: 에러 JSON을 stderr로 출력 후 1 반환
#
# [반환값]
#   0: 성공 (응답 본문을 stdout으로 출력)
#   1: 실패 (에러 메시지를 stderr로 출력)
_jira_request() {
    local method="$1"
    local endpoint="$2"
    shift 2
    local data="${1:-}"

    # 전체 URL 조합
    local url="${JIRA_DOMAIN}${endpoint}"
    local auth_b64
    auth_b64=$(_auth_header)

    # curl 인자 배열 구성
    local curl_args=(
        -s -S                           # 진행률 숨김, 에러 표시
        --max-time 30                   # 30초 타임아웃
        -H "Authorization: Basic ${auth_b64}"  # Basic Auth 헤더
        -H "Content-Type: application/json"    # JSON 요청
        -H "Accept: application/json"          # JSON 응답 요청
        -X "$method"                    # HTTP 메서드
    )

    # 요청 본문이 있으면 추가 (POST, PUT용)
    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    local response http_code body

    # 요청 실행: 응답 본문과 HTTP 상태 코드를 함께 받음
    # -w 옵션으로 상태 코드를 마지막 줄에 추가
    response=$(curl "${curl_args[@]}" -w "\n%{http_code}" "$url" 2>&1)

    # 마지막 줄에서 HTTP 상태 코드 추출
    http_code=$(echo "$response" | tail -1)

    # 마지막 줄 제외한 나머지가 응답 본문
    body=$(echo "$response" | sed '$d')

    # HTTP 4xx, 5xx 에러 처리
    if [[ "$http_code" -ge 400 ]]; then
        # 에러 메시지를 JSON으로 구성하여 stderr로 출력
        echo "{\"error\": true, \"http_code\": ${http_code}, \"message\": $(echo "$body" | jq -r '.errorMessages[0] // .message // "Unknown error"' 2>/dev/null || echo "\"HTTP ${http_code}\"")}" >&2
        return 1
    fi

    # 성공 시 응답 본문 출력
    echo "$body"
}

# ---------------------------------------------------------------------------
# 사용자
# ---------------------------------------------------------------------------
# jira_get_myself: 현재 인증된 사용자 정보 조회
#
# [API]
#   GET /rest/api/3/myself
#
# [파라미터]
#   없음
#
# [반환값]
#   JSON: 현재 사용자 정보 (accountId, displayName, emailAddress 등)
#
# [사용 예시]
#   result=$(jira_get_myself)
#   echo "$result" | jq -r '.displayName'  # 사용자 이름
jira_get_myself() {
    _load_config
    _jira_request GET "/rest/api/3/myself"
}

# ---------------------------------------------------------------------------
# 이슈
# ---------------------------------------------------------------------------
# jira_get_my_issues: 현재 사용자에게 할당된 이슈 목록 조회
#
# [API]
#   GET /rest/api/3/search/jql
#
# [JQL 쿼리]
#   assignee = currentUser() AND statusCategory != Done
#   ORDER BY priority DESC, updated DESC
#
#   - 현재 사용자가 담당자인 이슈
#   - Done 상태 제외 (진행 중/대기 중 이슈만)
#   - 우선순위 높은 순, 최근 업데이트 순 정렬
#
# [파라미터]
#   없음
#
# [반환값]
#   JSON: 이슈 검색 결과 (issues 배열 포함)
#
# [최대 결과]
#   50개
jira_get_my_issues() {
    _load_config

    # JQL 쿼리: 담당자=나, 상태!=Done, 우선순위/업데이트순
    local jql="assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC, updated DESC"

    # 가져올 필드 지정 (불필요한 데이터 최소화)
    local fields="summary,status,priority,issuetype,updated,assignee,labels"

    # JQL URL 인코딩
    encoded_jql=$(_url_encode "$jql")

    _jira_request GET "/rest/api/3/search/jql?jql=${encoded_jql}&fields=${fields}&maxResults=50"
}

# jira_get_issue: 특정 이슈 상세 조회
#
# [API]
#   GET /rest/api/3/issue/{issueKey}
#
# [파라미터]
#   $1 - key: 이슈 키 (예: PROJ-123)
#   $2 - fields: (선택) 가져올 필드 (콤마 구분, 기본값: summary,status,priority,...)
#
# [반환값]
#   JSON: 이슈 상세 정보
#
# [사용 예시]
#   jira_get_issue "PROJ-123"
#   jira_get_issue "PROJ-123" "summary,status"
jira_get_issue() {
    _load_config
    local key="$1"
    # 기본 필드: 주요 정보 + 코멘트 + 생성/수정일
    local fields="${2:-summary,status,priority,issuetype,description,assignee,labels,comment,updated,created}"
    _jira_request GET "/rest/api/3/issue/${key}?fields=${fields}"
}

# jira_create_issue: 새 이슈 생성
#
# [API]
#   POST /rest/api/3/issue
#
# [파라미터]
#   $1 - payload: 이슈 생성 JSON (요청 본문)
#
# [payload 구조]
#   {
#     "fields": {
#       "project": {"key": "PROJ"},
#       "summary": "이슈 제목",
#       "issuetype": {"name": "Task"},
#       ...
#     }
#   }
#
# [반환값]
#   JSON: 생성된 이슈 정보 (id, key 등)
jira_create_issue() {
    _load_config
    local payload="$1"
    _jira_request POST "/rest/api/3/issue" "$payload"
}

# jira_update_issue: 이슈 수정
#
# [API]
#   PUT /rest/api/3/issue/{issueKey}
#
# [파라미터]
#   $1 - key: 이슈 키 (예: PROJ-123)
#   $2 - payload: 수정할 필드 JSON
#
# [payload 구조]
#   {
#     "fields": {
#       "summary": "새 제목",
#       ...
#     }
#   }
#
# [반환값]
#   성공 시 빈 응답 (204 No Content)
jira_update_issue() {
    _load_config
    local key="$1"
    local payload="$2"
    _jira_request PUT "/rest/api/3/issue/${key}" "$payload"
}

# jira_search: JQL로 이슈 검색
#
# [API]
#   GET /rest/api/3/search/jql
#
# [파라미터]
#   $1 - jql: JQL 쿼리 문자열
#   $2 - max_results: (선택) 최대 결과 수 (기본값: 20)
#   $3 - fields: (선택) 가져올 필드 (기본값: 주요 필드)
#
# [반환값]
#   JSON: 검색 결과
#
# [사용 예시]
#   jira_search "project = PROJ AND status = Open"
#   jira_search "project = PROJ" 50 "summary,status,assignee"
jira_search() {
    _load_config
    local jql="$1"
    local max_results="${2:-20}"
    local fields="${3:-summary,status,priority,issuetype,updated,assignee}"
    encoded_jql=$(_url_encode "$jql")
    _jira_request GET "/rest/api/3/search/jql?jql=${encoded_jql}&fields=${fields}&maxResults=${max_results}"
}

# jira_add_comment: 이슈에 코멘트 추가
#
# [API]
#   POST /rest/api/3/issue/{issueKey}/comment
#
# [파라미터]
#   $1 - key: 이슈 키 (예: PROJ-123)
#   $2 - comment_text: 코멘트 내용 (일반 텍스트)
#
# [요청 본문]
#   Jira API v3의 Atlassian Document Format (ADF) 사용
#   {
#     "body": {
#       "type": "doc",
#       "content": [{"type": "paragraph", "content": [...]}]
#     }
#   }
#
# [반환값]
#   JSON: 생성된 코멘트 정보
jira_add_comment() {
    _load_config
    local key="$1"
    local comment_text="$2"

    # ADF(Atlassian Document Format) 형식으로 JSON 생성
    local payload
    payload=$(jq -n --arg text "$comment_text" '{
        body: {
            type: "doc",
            version: 1,
            content: [{
                type: "paragraph",
                content: [{
                    type: "text",
                    text: $text
                }]
            }]
        }
    }')

    _jira_request POST "/rest/api/3/issue/${key}/comment" "$payload"
}

# jira_get_transitions: 이슈의 상태 전이 옵션 조회
#
# [API]
#   GET /rest/api/3/issue/{issueKey}/transitions
#
# [파라미터]
#   $1 - key: 이슈 키 (예: PROJ-123)
#
# [반환값]
#   JSON: 가능한 전이 목록 (transitions 배열)
#
# [용도]
#   상태 변경 전 가능한 다음 상태 목록 확인
jira_get_transitions() {
    _load_config
    local key="$1"
    _jira_request GET "/rest/api/3/issue/${key}/transitions"
}

# jira_transition: 이슈 상태 변경 (전이)
#
# [API]
#   POST /rest/api/3/issue/{issueKey}/transitions
#
# [파라미터]
#   $1 - key: 이슈 키 (예: PROJ-123)
#   $2 - transition_id: 전이 ID (jira_get_transitions에서 조회)
#
# [요청 본문]
#   {"transition": {"id": "31"}}
#
# [반환값]
#   성공 시 빈 응답 (204 No Content)
#
# [사용 예시]
#   # 먼저 가능한 전이 조회
#   jira_get_transitions "PROJ-123"
#   # 전이 ID로 상태 변경
#   jira_transition "PROJ-123" "31"
jira_transition() {
    _load_config
    local key="$1"
    local transition_id="$2"

    local payload
    payload=$(jq -n --arg id "$transition_id" '{transition: {id: $id}}')

    _jira_request POST "/rest/api/3/issue/${key}/transitions" "$payload"
}

# jira_assign_issue: 이슈 담당자 변경
#
# [API]
#   PUT /rest/api/3/issue/{issueKey}/assignee
#
# [파라미터]
#   $1 - key: 이슈 키 (예: PROJ-123)
#   $2 - account_id: Atlassian 계정 ID (accountId)
#
# [요청 본문]
#   {"accountId": "5b10a2844c20165700ede21g"}
#
# [반환값]
#   성공 시 빈 응답 (204 No Content)
#
# [참고]
#   account_id는 사용자 검색 API 또는 사용자 프로필에서 확인 가능
jira_assign_issue() {
    _load_config
    local key="$1"
    local account_id="$2"

    local payload
    payload=$(jq -n --arg aid "$account_id" '{accountId: $aid}')

    _jira_request PUT "/rest/api/3/issue/${key}/assignee" "$payload"
}

# ---------------------------------------------------------------------------
# 프로젝트
# ---------------------------------------------------------------------------
# jira_get_projects: 접근 가능한 프로젝트 목록 조회
#
# [API]
#   GET /rest/api/3/project/search
#
# [파라미터]
#   $1 - max_results: (선택) 최대 결과 수 (기본값: 50)
#
# [반환값]
#   JSON: 프로젝트 목록 (values 배열)
#
# [용도]
#   이슈 생성 시 프로젝트 키 확인
jira_get_projects() {
    _load_config
    local max_results="${1:-50}"
    _jira_request GET "/rest/api/3/project/search?maxResults=${max_results}"
}

# jira_get_project: 특정 프로젝트 상세 조회
#
# [API]
#   GET /rest/api/3/project/{projectKey}
#
# [파라미터]
#   $1 - key: 프로젝트 키 (예: PROJ)
#
# [반환값]
#   JSON: 프로젝트 상세 정보 (key, name, issueTypes 등)
jira_get_project() {
    _load_config
    local key="$1"
    _jira_request GET "/rest/api/3/project/${key}"
}

# ---------------------------------------------------------------------------
# 보드 / 스프린트 (Agile API)
# ---------------------------------------------------------------------------
# jira_get_boards: 보드 목록 조회
#
# [API]
#   GET /rest/agile/1.0/board
#
# [파라미터]
#   $1 - project_key: (선택) 프로젝트 키로 필터링
#
# [반환값]
#   JSON: 보드 목록 (values 배열)
#
# [용도]
#   스크럼/칸반 보드 ID 확인
jira_get_boards() {
    _load_config
    local project_key="${1:-}"
    local endpoint="/rest/agile/1.0/board"

    # 프로젝트 키가 있으면 필터링 파라미터 추가
    [[ -n "$project_key" ]] && endpoint="${endpoint}?projectKeyOrId=${project_key}"

    _jira_request GET "$endpoint"
}

# jira_get_board_sprints: 보드의 스프린트 목록 조회
#
# [API]
#   GET /rest/agile/1.0/board/{boardId}/sprint
#
# [파라미터]
#   $1 - board_id: 보드 ID
#   $2 - state: (선택) 스프린트 상태 필터 (기본값: active,future)
#
# [state 값]
#   - active: 진행 중인 스프린트
#   - future: 예정된 스프린트
#   - closed: 완료된 스프린트
#
# [반환값]
#   JSON: 스프린트 목록 (values 배열)
jira_get_board_sprints() {
    _load_config
    local board_id="$1"
    local state="${2:-active,future}"  # 기본: 진행 중 + 예정
    _jira_request GET "/rest/agile/1.0/board/${board_id}/sprint?state=${state}"
}

# jira_get_sprint_issues: 스프린트의 이슈 목록 조회
#
# [API]
#   GET /rest/agile/1.0/sprint/{sprintId}/issue
#
# [파라미터]
#   $1 - sprint_id: 스프린트 ID
#   $2 - fields: (선택) 가져올 필드 (기본값: 주요 필드)
#
# [반환값]
#   JSON: 이슈 목록 (issues 배열)
#
# [용도]
#   스프린트 백로그 확인
jira_get_sprint_issues() {
    _load_config
    local sprint_id="$1"
    local fields="${2:-summary,status,priority,issuetype,assignee}"
    _jira_request GET "/rest/agile/1.0/sprint/${sprint_id}/issue?fields=${fields}&maxResults=50"
}

# ---------------------------------------------------------------------------
# 워크로그
# ---------------------------------------------------------------------------
# jira_get_worklogs: 이슈의 작업 기록(워크로그) 조회
#
# [API]
#   GET /rest/api/3/issue/{issueKey}/worklog
#
# [파라미터]
#   $1 - key: 이슈 키 (예: PROJ-123)
#
# [반환값]
#   JSON: 워크로그 목록 (worklogs 배열)
#
# [용도]
#   작업 시간 추적, 시간 보고서 작성
jira_get_worklogs() {
    _load_config
    local key="$1"
    _jira_request GET "/rest/api/3/issue/${key}/worklog"
}

# jira_add_worklog: 이슈에 작업 기록(워크로그) 추가
#
# [API]
#   POST /rest/api/3/issue/{issueKey}/worklog
#
# [파라미터]
#   $1 - key: 이슈 키 (예: PROJ-123)
#   $2 - time_spent: 작업 시간 (예: "2h", "30m", "1d 2h")
#   $3 - comment: (선택) 작업 설명
#
# [요청 본문]
#   {
#     "timeSpent": "2h",
#     "comment": { ADF 형식 }
#   }
#
# [반환값]
#   JSON: 생성된 워크로그 정보
#
# [사용 예시]
#   jira_add_worklog "PROJ-123" "2h" "버그 수정"
#   jira_add_worklog "PROJ-123" "30m"
jira_add_worklog() {
    _load_config
    local key="$1"
    local time_spent="$2"
    local comment="${3:-}"

    local payload
    payload=$(jq -n --arg ts "$time_spent" --arg c "$comment" '{
        timeSpent: $ts,
        comment: {
            type: "doc",
            version: 1,
            content: [{
                type: "paragraph",
                content: [{
                    type: "text",
                    # 코멘트가 없으면 기본 텍스트 사용
                    text: (if $c == "" then "작업 기록" else $c end)
                }]
            }]
        }
    }')

    _jira_request POST "/rest/api/3/issue/${key}/worklog" "$payload"
}

# ---------------------------------------------------------------------------
# 메타데이터
# ---------------------------------------------------------------------------
# jira_get_priorities: 우선순위 목록 조회
#
# [API]
#   GET /rest/api/3/priority
#
# [반환값]
#   JSON: 우선순위 목록 (예: Highest, High, Medium, Low, Lowest)
#
# [용도]
#   이슈 생성 시 우선순위 ID/Name 확인
jira_get_priorities() {
    _load_config
    _jira_request GET "/rest/api/3/priority"
}

# jira_get_labels: 라벨 목록 조회
#
# [API]
#   GET /rest/api/3/label
#
# [반환값]
#   JSON: 라벨 목록
#
# [용도]
#   이슈 필터링, 태그 관리
jira_get_labels() {
    _load_config
    _jira_request GET "/rest/api/3/label"
}

# jira_get_statuses: 상태 목록 조회
#
# [API]
#   GET /rest/api/3/status
#
# [반환값]
#   JSON: 모든 상태 목록
#
# [용도]
#   상태 ID/Name 확인, 워크플로우 이해
jira_get_statuses() {
    _load_config
    _jira_request GET "/rest/api/3/status"
}

# jira_get_issue_types: 이슈 타입 목록 조회
#
# [API]
#   GET /rest/api/3/issuetype
#
# [반환값]
#   JSON: 이슈 타입 목록 (예: Bug, Task, Story, Epic)
#
# [용도]
#   이슈 생성 시 이슈 타입 ID/Name 확인
jira_get_issue_types() {
    _load_config
    _jira_request GET "/rest/api/3/issuetype"
}

# ---------------------------------------------------------------------------
# 연결 테스트
# ---------------------------------------------------------------------------
# jira_test_connection: Jira 연결 테스트
#
# [목적]
#   설정된 인증 정보로 Jira API 연결이 정상인지 확인합니다.
#
# [동작]
#   1. 설정 유효성 검사
#   2. myself API 호출
#   3. 사용자 정보 표시
#
# [파라미터]
#   없음
#
# [반환값]
#   0: 연결 성공
#   1: 연결 실패
#
# [출력]
#   성공: ✅ Jira 연결 성공 + 사용자 정보
#   실패: ❌ Jira 연결 실패 + 에러 메시지
jira_test_connection() {
    # 설정 검증
    if ! jira_validate_config; then
        return 1
    fi

    _load_config
    local result
    result=$(jira_get_myself 2>&1)

    # 응답에 accountId가 있으면 성공
    if echo "$result" | jq -e '.accountId' >/dev/null 2>&1; then
        local name email
        name=$(echo "$result" | jq -r '.displayName')
        email=$(echo "$result" | jq -r '.emailAddress')
        echo "✅ Jira 연결 성공"
        echo "   👤 ${name} (${email})"
        echo "   🌐 ${JIRA_DOMAIN}"
        return 0
    else
        echo "❌ Jira 연결 실패" >&2
        echo "   응답: ${result}" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# CLI 디스패처
# ---------------------------------------------------------------------------
# _main: CLI 명령어 디스패처
#
# [목적]
#   커맨드 라인에서 호출된 명령어를 적절한 함수로 라우팅합니다.
#
# [동작]
#   첫 번째 인자를 명령어로 해석하여 해당 함수 호출
#   인식하지 못하는 명령어는 help 표시
#
# [사용법]
#   bash jira-api.sh <command> [args...]
#
# [명령어 목록]
#   validate-config    설정 검증
#   test               연결 테스트
#   get-myself         내 프로필 조회
#   get-my-issues      내 할당 이슈
#   get-issue          이슈 상세
#   create-issue       이슈 생성
#   update-issue       이슈 수정
#   search             JQL 검색
#   add-comment        코멘트 추가
#   get-transitions    전이 옵션
#   transition         상태 변경
#   assign-issue       담당자 변경
#   get-projects       프로젝트 목록
#   get-project        프로젝트 상세
#   get-boards         보드 목록
#   get-board-sprints  보드 스프린트
#   get-sprint-issues  스프린트 이슈
#   get-worklogs       워크로그 조회
#   add-worklog        워크로그 추가
#   get-priorities     우선순위 목록
#   get-labels         라벨 목록
#   get-statuses       상태 목록
#   get-issue-types    이슈 타입 목록
_main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        # 설정 및 연결
        validate-config)    jira_validate_config ;;
        test|test-connection) jira_test_connection ;;

        # 사용자
        get-myself)         jira_get_myself "$@" ;;

        # 이슈 관리
        get-my-issues)      jira_get_my_issues "$@" ;;
        get-issue)          jira_get_issue "$@" ;;
        create-issue)       jira_create_issue "$@" ;;
        update-issue)       jira_update_issue "$@" ;;
        search)             jira_search "$@" ;;
        add-comment)        jira_add_comment "$@" ;;
        get-transitions)    jira_get_transitions "$@" ;;
        transition)         jira_transition "$@" ;;
        assign-issue)       jira_assign_issue "$@" ;;

        # 프로젝트
        get-projects)       jira_get_projects "$@" ;;
        get-project)        jira_get_project "$@" ;;

        # 보드/스프린트
        get-boards)         jira_get_boards "$@" ;;
        get-board-sprints)  jira_get_board_sprints "$@" ;;
        get-sprint-issues)  jira_get_sprint_issues "$@" ;;

        # 워크로그
        get-worklogs)       jira_get_worklogs "$@" ;;
        add-worklog)        jira_add_worklog "$@" ;;

        # 메타데이터
        get-priorities)     jira_get_priorities "$@" ;;
        get-labels)         jira_get_labels "$@" ;;
        get-statuses)       jira_get_statuses "$@" ;;
        get-issue-types)    jira_get_issue_types "$@" ;;

        # 도움말
        help|*)
            echo "사용법: bash jira-api.sh <command> [args...]"
            echo ""
            echo "Commands:"
            echo "  validate-config          설정 파일 검증"
            echo "  test                     연결 테스트"
            echo "  get-myself               내 프로필"
            echo "  get-my-issues            내 할당 이슈 (Done 제외)"
            echo "  get-issue <KEY>          이슈 상세 조회"
            echo "  create-issue <JSON>      이슈 생성"
            echo "  update-issue <KEY> <JSON> 이슈 업데이트"
            echo "  search <JQL> [max]       JQL 검색"
            echo "  add-comment <KEY> <TEXT>  코멘트 추가"
            echo "  get-transitions <KEY>    전이 옵션 조회"
            echo "  transition <KEY> <ID>    상태 전이"
            echo "  assign-issue <KEY> <AID> 담당자 변경"
            echo "  get-projects [max]       프로젝트 목록"
            echo "  get-project <KEY>        프로젝트 상세"
            echo "  get-boards [PROJECT]     보드 목록"
            echo "  get-board-sprints <ID>   보드 스프린트"
            echo "  get-sprint-issues <ID>   스프린트 이슈"
            echo "  get-worklogs <KEY>       워크로그 조회"
            echo "  add-worklog <KEY> <TIME> 워크로그 추가"
            echo "  get-priorities           우선순위 목록"
            echo "  get-labels               라벨 목록"
            echo "  get-statuses             상태 목록"
            echo "  get-issue-types          이슈 타입 목록"
            ;;
    esac
}

# 직접 실행 시 _main 호출
# BASH_SOURCE[0] == $0: 스크립트가 직접 실행된 경우 (source가 아님)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _main "$@"
fi
