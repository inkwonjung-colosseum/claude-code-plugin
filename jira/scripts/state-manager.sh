#!/usr/bin/env bash
# ============================================================================
# state-manager.sh — .store/state.json R/W 유틸리티
# ============================================================================
#
# [목적]
#   Claude Code 플러그인의 상태를 관리하는 유틸리티입니다.
#   현재 작업 중인 티켓, 할당된 티켓 목록, 작업 이력을 추적합니다.
#
# [사용법]
#   bash state-manager.sh <command> [args...]
#
# [상태 파일 구조] (.store/state.json)
#   {
#     "last_synced_at": "2024-01-15T10:30:00+09:00",
#     "current_ticket": {
#       "id": "12345",
#       "key": "PROJ-123",
#       "summary": "기능 구현",
#       "status": "In Progress",
#       "priority": "High",
#       "type": "Task",
#       "started_at": "2024-01-15T09:00:00+09:00",
#       "branch": "feature/PROJ-123-xxx",
#       "url": "https://company.atlassian.net/browse/PROJ-123",
#       "notes": ""
#     },
#     "my_tickets": [...],
#     "work_history": [...]
#   }
#
# [의존성]
#   - jq: JSON 파싱 및 조작
#   - jira-api.sh: Jira API 호출 (선택적)
#   - git: 브랜치 감지 (선택적)
#
# [작성자]
#   Claude Code Plugin - Atlassian Integration
#
# [작성일]
#   2024
# ============================================================================

# strict 모드 활성화
set -euo pipefail

# ---------------------------------------------------------------------------
# 경로 설정
# ---------------------------------------------------------------------------
# 스크립트 위치 기준으로 플러그인 루트 디렉토리 결정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"

# .store 디렉토리: 설정 및 상태 파일 저장 위치
# 프로젝트 루트(현재 작업 디렉토리)에 저장소 생성
STORE_DIR="${PWD}/.store"

# 상태 파일: 작업 추적용 JSON
STATE_PATH="${STORE_DIR}/state.json"

# 설정 파일: Atlassian 인증 정보
CONFIG_PATH="${STORE_DIR}/config.json"

# jira-api.sh 로드 (함수 사용)
# 2>/dev/null: 파일이 없어도 에러 무시
# || true: source 실패해도 스크립트 계속 실행
source "${SCRIPT_DIR}/jira-api.sh" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 초기화
# ---------------------------------------------------------------------------
# ensure_store: .store 디렉토리 및 state.json 초기화
#
# [목적]
#   플러그인 상태 관리를 위한 디렉토리와 파일이 없으면 생성합니다.
#   첫 실행 시 자동으로 호출됩니다.
#
# [동작]
#   1. .store 디렉토리 생성 (이미 있으면 무시)
#   2. state.json 파일 생성 (이미 있으면 무시)
#
# [초기 상태 구조]
#   {
#     "last_synced_at": null,      // 마지막 동기화 시간
#     "current_ticket": null,      // 현재 작업 중인 티켓
#     "my_tickets": [],            // 할당된 티켓 목록
#     "work_history": []           // 작업 이력
#   }
#
# [파라미터]
#   없음
#
# [반환값]
#   항상 0
ensure_store() {
    # -p: 상위 디렉토리까지 생성, 이미 있으면 무시
    mkdir -p "$STORE_DIR"

    # state.json이 없으면 초기값으로 생성
    if [[ ! -f "$STATE_PATH" ]]; then
        cat > "$STATE_PATH" <<'EOF'
{
    "last_synced_at": null,
    "current_ticket": null,
    "my_tickets": [],
    "work_history": []
}
EOF
        echo "📂 .store/state.json 초기화 완료"
    fi
}

# ---------------------------------------------------------------------------
# 읽기 함수들
# ---------------------------------------------------------------------------
# get_current_ticket: 현재 작업 중인 티켓을 포맷팅하여 출력
#
# [목적]
#   사용자가 보기 좋은 형식으로 현재 작업 티켓 정보를 표시합니다.
#
# [출력 형식]
#   📌 현재 작업: PROJ-123 "기능 구현" (In Progress) [Priority: High]
#      🕐 시작: 2024-01-15T09:00:00+09:00
#      🔗 https://company.atlassian.net/browse/PROJ-123
#      📝 비고 사항 (notes가 있을 경우)
#
# [파라미터]
#   없음
#
# [반환값]
#   항상 0
get_current_ticket() {
    # 상태 파일이 없으면 null 반환
    if [[ ! -f "$STATE_PATH" ]]; then
        echo "null"
        return
    fi

    # current_ticket 값 조회
    local ct
    ct=$(jq -r '.current_ticket' "$STATE_PATH")

    # null 또는 빈 값인 경우
    if [[ "$ct" == "null" || -z "$ct" ]]; then
        echo "📌 현재 작업 중인 티켓 없음"
    else
        # 포맷팅된 출력
        # \": 따옴표 이스케이프 (jq 문자열 내)
        echo "$ct" | jq -r '"📌 현재 작업: \(.key) \"\(.summary)\" (\(.status)) [Priority: \(.priority)]"'
        echo "$ct" | jq -r '"   🕐 시작: \(.started_at // "N/A")"'
        echo "$ct" | jq -r '"   🔗 \(.url // "N/A")"'

        # notes가 있으면 추가 출력
        if echo "$ct" | jq -e '.notes // empty' >/dev/null 2>&1; then
            echo "$ct" | jq -r '"   📝 \(.notes)"'
        fi
    fi
}

# get_current_ticket_json: 현재 작업 티켓을 JSON으로 출력
#
# [목적]
#   프로그래밍 방식으로 현재 티켓 정보를 사용할 때 JSON 형식으로 반환합니다.
#   Claude Code의 스킬에서 파싱하기 쉬운 형태입니다.
#
# [파라미터]
#   없음
#
# [출력]
#   JSON: current_ticket 객체 또는 null
#
# [사용 예시]
#   current=$(bash state-manager.sh get-current-ticket-json)
#   key=$(echo "$current" | jq -r '.key')
get_current_ticket_json() {
    [[ ! -f "$STATE_PATH" ]] && echo "null" && return
    jq '.current_ticket' "$STATE_PATH"
}

# get_my_tickets: 할당된 티켓 목록을 포맷팅하여 출력
#
# [목적]
#   사용자가 보기 좋은 형식으로 할당된 티켓 목록을 표시합니다.
#   Done 상태는 제외되어 있습니다 (Jira 동기화 시 필터링).
#
# [출력 형식]
#   📋 할당된 티켓 (3개, Done 제외):
#      • PROJ-100 [High] In Progress — 긴급 버그 수정
#      • PROJ-101 [Medium] To Do — 기능 개발
#      • PROJ-102 [Low] In Review — 코드 리뷰
#
# [파라미터]
#   없음
#
# [반환값]
#   항상 0
get_my_tickets() {
    if [[ ! -f "$STATE_PATH" ]]; then
        echo "[]"
        return
    fi

    local tickets
    tickets=$(jq '.my_tickets' "$STATE_PATH")
    local count
    count=$(echo "$tickets" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo "📋 할당된 티켓 없음"
    else
        echo "📋 할당된 티켓 (${count}개, Done 제외):"
        # 각 티켓을 포맷팅하여 출력
        echo "$tickets" | jq -r '.[] | "   • \(.key) [\(.priority)] \(.status) — \(.summary)"'
    fi
}

# get_my_tickets_json: 할당된 티켓 목록을 JSON으로 출력
#
# [목적]
#   프로그래밍 방식으로 티켓 목록을 사용할 때 JSON 형식으로 반환합니다.
#
# [파라미터]
#   없음
#
# [출력]
#   JSON: my_tickets 배열
get_my_tickets_json() {
    [[ ! -f "$STATE_PATH" ]] && echo "[]" && return
    jq '.my_tickets' "$STATE_PATH"
}

# get_work_history: 작업 이력을 포맷팅하여 출력
#
# [목적]
#   완료된 작업들의 이력을 표시합니다.
#   최근 5개만 표시하며, 역순(최신순)으로 정렬합니다.
#
# [출력 형식]
#   📜 최근 작업 이력 (10개):
#      • PROJ-99 "완료된 작업" — Done (2024-01-14T10:00 ~ 2024-01-14T18:00)
#
# [파라미터]
#   없음
#
# [반환값]
#   항상 0
get_work_history() {
    if [[ ! -f "$STATE_PATH" ]]; then
        echo "[]"
        return
    fi

    local history
    history=$(jq '.work_history' "$STATE_PATH")
    local count
    count=$(echo "$history" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo "📜 작업 이력 없음"
    else
        echo "📜 최근 작업 이력 (${count}개):"
        # .[-5:]: 마지막 5개만, reverse: 최신순
        echo "$history" | jq -r '.[-5:] | reverse | .[] | "   • \(.key) \"\(.summary)\" — \(.final_status) (\(.worked_from) ~ \(.worked_until))"'
    fi
}

# get_state_summary: 전체 상태 요약 출력
#
# [목적]
#   마지막 동기화 시간, 현재 작업, 할당 티켓을 종합적으로 표시합니다.
#   플러그인 상태를 한눈에 파악할 때 사용합니다.
#
# [출력 형식]
#   🕐 마지막 동기화: 2024-01-15T10:30:00+09:00
#
#   📌 현재 작업: PROJ-123 ...
#
#   📋 할당된 티켓 (3개, Done 제외):
#      • PROJ-100 ...
#
# [파라미터]
#   없음
#
# [반환값]
#   항상 0
get_state_summary() {
    if [[ ! -f "$STATE_PATH" ]]; then
        echo "상태 파일 없음"
        return
    fi

    # 마지막 동기화 시간 (없으면 "동기화 안 됨")
    local synced
    synced=$(jq -r '.last_synced_at // "동기화 안 됨"' "$STATE_PATH")
    echo "🕐 마지막 동기화: ${synced}"
    echo ""

    # 현재 작업 티켓
    get_current_ticket
    echo ""

    # 할당된 티켓 목록
    get_my_tickets
}

# ---------------------------------------------------------------------------
# 쓰기 함수들
# ---------------------------------------------------------------------------
# set_current_ticket: 현재 작업 티켓 설정
#
# [목적]
#   새로운 작업을 시작할 때 호출합니다.
#   기존 작업이 있으면 work_history로 이동 후 새 티켓을 설정합니다.
#
# [동작]
#   1. .store 초기화 확인
#   2. 기존 current_ticket이 있으면 work_history로 이동
#   3. 티켓 정보 조회 (my_tickets 또는 Jira API)
#   4. 현재 Git 브랜치 감지
#   5. current_ticket 설정 (started_at, branch, url 포함)
#
# [파라미터]
#   $1 - key: 이슈 키 (예: PROJ-123)
#
# [반환값]
#   0: 성공
#   1: 티켓을 찾을 수 없음
#
# [출력]
#   성공: ✅ 작업 시작: PROJ-123 "이슈 제목"
#   이전 작업 있음: 📜 이전 작업 PROJ-99 → work_history 이동
#
# [사용 예시]
#   bash state-manager.sh set-current-ticket PROJ-123
set_current_ticket() {
    local key="$1"

    # ISO 8601 형식의 현재 시간
    # sed 's/\(..\)$/:\1': 타임존 형식 수정 (+0900 -> +09:00)
    local now
    now=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\(..\)$/:\1/')

    # 상태 파일 초기화 확인
    ensure_store

    # 기존 작업 중인 티켓이 있으면 work_history로 이동
    local existing
    existing=$(jq -r '.current_ticket.key // empty' "$STATE_PATH")
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        _move_current_to_history
    fi

    # my_tickets에서 티켓 정보 조회
    local ticket_info
    ticket_info=$(jq --arg key "$key" '.my_tickets[] | select(.key == $key)' "$STATE_PATH" 2>/dev/null)

    # my_tickets에 없으면 Jira API에서 조회
    if [[ -z "$ticket_info" ]]; then
        local api_result
        api_result=$(jira_get_issue "$key" "summary,status,priority,issuetype" 2>/dev/null) || true

        if echo "$api_result" | jq -e '.fields' >/dev/null 2>&1; then
            # API 응답에서 필요한 필드만 추출
            ticket_info=$(echo "$api_result" | jq '{
                id: .id,
                key: .key,
                summary: .fields.summary,
                status: .fields.status.name,
                priority: .fields.priority.name,
                type: .fields.issuetype.name
            }')
        else
            echo "❌ 티켓 ${key}를 찾을 수 없습니다." >&2
            return 1
        fi
    fi

    # 현재 Git 브랜치 감지 (git 저장소가 아니면 빈 문자열)
    local branch=""
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

    # Jira 도메인 조회 (URL 생성용)
    local domain
    domain=$(jq -r '.atlassian.domain // empty' "$CONFIG_PATH" 2>/dev/null)
    domain="${domain%/}"

    # state.json 업데이트
    # $info + 추가 필드로 current_ticket 설정
    jq --argjson info "$ticket_info" \
       --arg started "$now" \
       --arg branch "$branch" \
       --arg domain "$domain" \
       '.current_ticket = ($info + {
            started_at: $started,
            branch: $branch,
            notes: "",
            url: ($domain + "/browse/" + $info.key)
        })' "$STATE_PATH" > "${STATE_PATH}.tmp" && mv "${STATE_PATH}.tmp" "$STATE_PATH"

    # 성공 메시지 출력
    local summary
    summary=$(echo "$ticket_info" | jq -r '.summary')
    echo "✅ 작업 시작: ${key} \"${summary}\""

    # 이전 작업 이동 안내
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        echo "   📜 이전 작업 ${existing} → work_history 이동"
    fi

    return 0
}

# clear_current_ticket: 현재 작업 완료 처리
#
# [목적]
#   작업을 완료했을 때 호출합니다.
#   current_ticket을 null로 설정하고 work_history에 기록합니다.
#
# [동작]
#   1. 현재 작업 중인 티켓이 있는지 확인
#   2. 있으면 work_history로 이동
#   3. current_ticket을 null로 설정
#
# [파라미터]
#   없음
#
# [반환값]
#   항상 0
#
# [출력]
#   완료: ✅ 작업 완료: PROJ-123 "이슈 제목"
#          📜 work_history에 기록됨
#   없음: 📌 현재 작업 중인 티켓이 없습니다.
#
# [사용 예시]
#   bash state-manager.sh clear-current-ticket
clear_current_ticket() {
    ensure_store

    # 현재 작업 중인 티켓 확인
    local existing
    existing=$(jq -r '.current_ticket.key // empty' "$STATE_PATH")
    if [[ -z "$existing" || "$existing" == "null" ]]; then
        echo "📌 현재 작업 중인 티켓이 없습니다."
        return 0
    fi

    # work_history로 이동
    _move_current_to_history

    # 요약 정보 백업 (메시지용)
    local summary
    summary=$(jq -r '.current_ticket.summary // ""' "$STATE_PATH")

    # current_ticket을 null로 설정
    jq '.current_ticket = null' "$STATE_PATH" > "${STATE_PATH}.tmp" && mv "${STATE_PATH}.tmp" "$STATE_PATH"

    echo "✅ 작업 완료: ${existing} \"${summary}\""
    echo "   📜 work_history에 기록됨"
}

# _move_current_to_history: 현재 티켓을 작업 이력으로 이동 (내부 함수)
#
# [목적]
#   set_current_ticket 또는 clear_current_ticket 호출 시
#   기존 current_ticket을 work_history에 보관합니다.
#
# [동작]
#   1. current_ticket 정보를 work_history 배열에 추가
#   2. worked_from, worked_until, final_status 기록
#   3. work_history는 최대 50개 유지 (.[-50:])
#
# [파라미터]
#   없음
#
# [반환값]
#   없음 (jq 결과로 state.json 직접 수정)
_move_current_to_history() {
    local now
    now=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\(..\)$/:\1/')

    # jq로 work_history에 레코드 추가
    # .[-50:]: 최신 50개만 유관 (오래된 기록 삭제)
    jq --arg now "$now" '
        if .current_ticket != null then
            .work_history += [{
                id: .current_ticket.id,
                key: .current_ticket.key,
                summary: .current_ticket.summary,
                worked_from: .current_ticket.started_at,
                worked_until: $now,
                final_status: .current_ticket.status
            }] | .work_history = (.work_history | .[-50:])
        else . end
    ' "$STATE_PATH" > "${STATE_PATH}.tmp" && mv "${STATE_PATH}.tmp" "$STATE_PATH"
}

# ---------------------------------------------------------------------------
# 동기화
# ---------------------------------------------------------------------------
# sync_my_tickets: Jira에서 할당 티켓 동기화
#
# [목적]
#   Jira API를 호출하여 현재 사용자에게 할당된 티켓 목록을 가져와
#   state.json의 my_tickets를 업데이트합니다.
#
# [동작]
#   1. Jira 설정 검증
#   2. jira_get_my_issues API 호출
#   3. 응답을 my_tickets 형식으로 변환
#   4. state.json 업데이트
#
# [JQL 쿼리]
#   assignee = currentUser() AND statusCategory != Done
#   ORDER BY priority DESC, updated DESC
#
# [파라미터]
#   없음
#
# [반환값]
#   0: 동기화 성공
#   1: 동기화 실패 (설정 오류 또는 API 오류)
#
# [출력]
#   진행: 🔄 Jira 동기화 중...
#   성공: 📋 Jira 동기화 완료 (N개 할당 티켓, Done 제외)
#   실패: ❌ Jira 동기화 실패
#
# [사용 예시]
#   bash state-manager.sh sync
sync_my_tickets() {
    ensure_store

    # Jira 설정 검증
    if ! jira_validate_config >/dev/null 2>&1; then
        jira_validate_config
        return 1
    fi

    echo "🔄 Jira 동기화 중..."

    # 내 이슈 조회
    local result
    result=$(jira_get_my_issues 2>&1)

    # API 응답 검증 (.issues 필드 존재 여부)
    if ! echo "$result" | jq -e '.issues' >/dev/null 2>&1; then
        echo "❌ Jira 동기화 실패" >&2
        echo "   응답: ${result}" >&2
        return 1
    fi

    # URL 생성용 도메인 조회
    local domain
    domain=$(jq -r '.atlassian.domain // empty' "$CONFIG_PATH" 2>/dev/null)
    domain="${domain%/}"

    # Jira API 응답 → my_tickets 형식 변환
    # 필요한 필드만 추출하고 URL 추가
    local tickets
    tickets=$(echo "$result" | jq --arg domain "$domain" '[.issues[] | {
        id: .id,
        key: .key,
        summary: .fields.summary,
        status: .fields.status.name,
        priority: (.fields.priority.name // "None"),
        type: (.fields.issuetype.name // "Task"),
        updated: .fields.updated,
        url: ($domain + "/browse/" + .key)
    }]' 2>/dev/null)

    # 동기화 시간 기록
    local now
    now=$(date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\(..\)$/:\1/')

    # state.json 업데이트
    jq --argjson tickets "$tickets" \
       --arg now "$now" \
       '.my_tickets = $tickets | .last_synced_at = $now' \
       "$STATE_PATH" > "${STATE_PATH}.tmp" && mv "${STATE_PATH}.tmp" "$STATE_PATH"

    # 결과 출력
    local count
    count=$(echo "$tickets" | jq 'length')

    echo "📋 Jira 동기화 완료 (${count}개 할당 티켓, Done 제외)"
    echo ""
    get_current_ticket
    echo ""

    # 티켓 목록 출력
    if [[ "$count" -gt 0 ]]; then
        echo "$tickets" | jq -r '.[] | "   • \(.key) [\(.priority)] \(.status) — \(.summary)"'
    fi
}

# ---------------------------------------------------------------------------
# 작업 시간 갱신 (stop hook 용)
# ---------------------------------------------------------------------------
# update_work_time: 현재 티켓의 상태를 최신으로 갱신
#
# [목적]
#   Claude Code 세션 종료 시(stop hook) 자동 호출되어
#   현재 작업 티켓의 상태를 Jira에서 최신으로 갱신합니다.
#
# [동작]
#   1. current_ticket이 있는지 확인
#   2. Jira API에서 최신 상태 조회
#   3. state.json의 current_ticket.status 업데이트
#
# [파라미터]
#   없음
#
# [반환값]
#   항상 0 (에러 무시)
#
# [용도]
#   세션 종료 시 자동 실행 (hook 설정 필요)
#
# [사용 예시]
#   # hooks.json에서 설정
#   {
#     "SessionEnd": ["bash state-manager.sh update-work-time"]
#   }
update_work_time() {
    # 상태 파일이 없으면 종료
    [[ ! -f "$STATE_PATH" ]] && return

    # 현재 작업 중인 티켓 확인
    local existing
    existing=$(jq -r '.current_ticket.key // empty' "$STATE_PATH")
    [[ -z "$existing" || "$existing" == "null" ]] && return

    # Jira에서 최신 상태 조회
    local latest_status
    latest_status=$(jira_get_issue "$existing" "status" 2>/dev/null | jq -r '.fields.status.name // empty' 2>/dev/null) || true

    # 상태 업데이트
    if [[ -n "$latest_status" ]]; then
        jq --arg status "$latest_status" '.current_ticket.status = $status' \
            "$STATE_PATH" > "${STATE_PATH}.tmp" && mv "${STATE_PATH}.tmp" "$STATE_PATH"
    fi
}

# ---------------------------------------------------------------------------
# Git 브랜치에서 이슈 키 감지
# ---------------------------------------------------------------------------
# detect_branch_ticket: 현재 Git 브랜치명에서 Jira 이슈 키 추출
#
# [목적]
#   Git 브랜치 이름에 포함된 이슈 키를 자동으로 감지합니다.
#   브랜치 기반 자동 작업 시작에 활용할 수 있습니다.
#
# [지원 브랜치 패턴]
#   - feature/PROJ-123-description
#   - bugfix/PROJ-123
#   - PROJ-123-description
#   - hotfix/PROJ-456-urgent-fix
#
# [정규식]
#   [A-Z]+-[0-9]+ : 대문자 프로젝트 키 + 하이픈 + 숫자
#
# [파라미터]
#   없음
#
# [출력]
#   감지된 이슈 키 (예: PROJ-123) 또는 빈 출력
#
# [반환값]
#   0: 정상 (감지되지 않아도)
#
# [사용 예시]
#   key=$(bash state-manager.sh detect-branch-ticket)
#   if [[ -n "$key" ]]; then
#     bash state-manager.sh set-current-ticket "$key"
#   fi
detect_branch_ticket() {
    # 현재 브랜치명 조회
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

    # git 저장소가 아니면 종료
    [[ -z "$branch" ]] && return

    # 브랜치명에서 이슈 키 패턴 추출
    # 예: feature/PROJ-123-xxx -> PROJ-123
    local key
    key=$(echo "$branch" | grep -oE '[A-Z]+-[0-9]+' | head -1)
    [[ -z "$key" ]] && return

    # 이미 현재 작업인지 확인 (중복 방지)
    local current
    current=$(jq -r '.current_ticket.key // empty' "$STATE_PATH" 2>/dev/null)
    if [[ "$current" == "$key" ]]; then
        return
    fi

    # 감지된 키 출력
    echo "$key"
}

# ---------------------------------------------------------------------------
# CLI 디스패처
# ---------------------------------------------------------------------------
# _main: CLI 명령어 디스패처
#
# [목적]
#   커맨드 라인에서 호출된 명령어를 적절한 함수로 라우팅합니다.
#
# [사용법]
#   bash state-manager.sh <command> [args...]
#
# [명령어 목록]
#   읽기:
#     get-current-ticket      현재 작업 티켓 (포맷팅)
#     get-current-ticket-json 현재 작업 티켓 (JSON)
#     get-my-tickets          할당 티켓 목록 (포맷팅)
#     get-my-tickets-json     할당 티켓 목록 (JSON)
#     get-work-history        작업 이력
#     get-state-summary       전체 상태 요약
#
#   쓰기:
#     set-current-ticket <KEY>  작업 시작
#     clear-current-ticket      작업 완료
#     sync                      Jira 동기화
#
#   유틸리티:
#     ensure-store            .store 초기화
#     update-work-time        작업 시간 갱신
#     detect-branch-ticket    Git 브랜치 이슈 키 감지
_main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        # 초기화
        ensure-store)           ensure_store ;;

        # 읽기 (포맷팅)
        get-current-ticket)     get_current_ticket ;;
        get-my-tickets)         get_my_tickets ;;
        get-work-history)       get_work_history ;;
        get-state-summary)      get_state_summary ;;

        # 읽기 (JSON)
        get-current-ticket-json) get_current_ticket_json ;;
        get-my-tickets-json)    get_my_tickets_json ;;

        # 쓰기
        set-current-ticket)     set_current_ticket "$@" ;;
        clear-current-ticket)   clear_current_ticket ;;
        sync)                   sync_my_tickets ;;

        # 유틸리티
        update-work-time)       update_work_time ;;
        detect-branch-ticket)   detect_branch_ticket ;;

        # 도움말
        help|*)
            echo "사용법: bash state-manager.sh <command> [args...]"
            echo ""
            echo "Commands:"
            echo "  ensure-store              .store/ 초기화"
            echo ""
            echo "  # 읽기 (포맷팅)"
            echo "  get-current-ticket        현재 작업 티켓"
            echo "  get-my-tickets            할당 티켓 목록"
            echo "  get-work-history          작업 이력"
            echo "  get-state-summary         전체 상태 요약"
            echo ""
            echo "  # 읽기 (JSON)"
            echo "  get-current-ticket-json   현재 작업 티켓 (JSON)"
            echo "  get-my-tickets-json       할당 티켓 목록 (JSON)"
            echo ""
            echo "  # 쓰기"
            echo "  set-current-ticket <KEY>  작업 시작"
            echo "  clear-current-ticket      작업 완료"
            echo "  sync                      Jira 동기화"
            echo ""
            echo "  # 유틸리티"
            echo "  update-work-time          작업 시간 갱신 (stop hook)"
            echo "  detect-branch-ticket      Git 브랜치 이슈 키 감지"
            ;;
    esac
}

# 직접 실행 시 _main 호출
# BASH_SOURCE[0] == $0: 스크립트가 직접 실행된 경우 (source가 아님)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _main "$@"
fi
