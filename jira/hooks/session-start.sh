#!/usr/bin/env bash
# ============================================================================
# session-start.sh — 세션 시작 Hook
# ============================================================================
# 1. config.json 필수값 검증
# 2. .store/ 초기화
# 3. Jira 동기화 (auto_sync 설정 시)
# 4. current_ticket 컨텍스트 출력
# 5. Git 브랜치 이슈 키 자동 감지
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"
SCRIPTS="${PLUGIN_ROOT}/scripts"
# 프로젝트 루트(현재 작업 디렉토리)에 저장소 생성
STORE="${PWD}/.store"
CONFIG="${STORE}/config.json"
STATE="${STORE}/state.json"

# ---------------------------------------------------------------------------
# 0. 필수 도구 검증
# ---------------------------------------------------------------------------
missing_deps=()
for dep in jq curl git; do
    command -v "$dep" &>/dev/null || missing_deps+=("$dep")
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo "⚠️ Jira 플러그인 필수 도구가 설치되어 있지 않습니다:"
    for d in "${missing_deps[@]}"; do
        echo "   ❌ ${d}"
    done
    echo ""
    echo "💡 brew install ${missing_deps[*]}"
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. 디렉토리 초기화
# ---------------------------------------------------------------------------
bash "${SCRIPTS}/state-manager.sh" ensure-store 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. config.json 검증
# ---------------------------------------------------------------------------
if ! bash "${SCRIPTS}/jira-api.sh" validate-config 2>/dev/null; then
    bash "${SCRIPTS}/jira-api.sh" validate-config
    exit 0
fi

# ---------------------------------------------------------------------------
# 3. 자동 동기화 (설정 확인)
# ---------------------------------------------------------------------------
auto_sync=$(jq -r '.sync.auto_sync_on_session_start // true' "$CONFIG" 2>/dev/null)

if [[ "$auto_sync" == "true" ]]; then
    bash "${SCRIPTS}/state-manager.sh" sync 2>/dev/null || {
        echo "⚠️ Jira 동기화 실패 — 네트워크를 확인해주세요."
    }
else
    # 동기화 안 하더라도 현재 상태 표시
    echo "📋 Jira 자동 동기화 비활성화됨 (/jira sync 으로 수동 동기화 가능)"
    echo ""
    bash "${SCRIPTS}/state-manager.sh" get-current-ticket 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 4. Git 브랜치 이슈 키 자동 감지
# ---------------------------------------------------------------------------
branch_key=$(bash "${SCRIPTS}/state-manager.sh" detect-branch-ticket 2>/dev/null || echo "")

if [[ -n "$branch_key" ]]; then
    current=$(jq -r '.current_ticket.key // empty' "$STATE" 2>/dev/null)
    if [[ "$current" != "$branch_key" ]]; then
        echo ""
        echo "🔍 Git 브랜치에서 이슈 키 감지: ${branch_key}"
        echo "   💡 /jira work ${branch_key} 으로 작업 시작할 수 있습니다."
    fi
fi