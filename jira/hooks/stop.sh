#!/usr/bin/env bash
# ============================================================================
# stop.sh — 세션 종료 Hook
# ============================================================================
# 1. current_ticket 작업 시간 갱신
# 2. jira-state.json 저장 (다음 세션 복원용)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}"
SCRIPTS="${PLUGIN_ROOT}/scripts"
STATE="${PLUGIN_ROOT}/.store/jira-state.json"

# jira-state.json이 없으면 종료
[[ ! -f "$STATE" ]] && exit 0

# 작업 시간 갱신
bash "${SCRIPTS}/state-manager.sh" update-work-time 2>/dev/null || true