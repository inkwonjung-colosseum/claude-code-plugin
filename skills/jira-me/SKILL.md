---
name: jira-me
description: 내 Jira 프로필과 현재 워크로드를 조회합니다.
user-invocable: false
allowed-tools: Read, Bash
---

# 내 Jira 정보 조회

## 동적 컨텍스트

- 내 프로필: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/jira-api.sh" get-myself`
- 현재 작업: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get-current-ticket`
- 할당 티켓: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get-my-tickets`
- 작업 이력: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get-work-history`

## 작업

위 동적 컨텍스트의 정보를 종합하여, 사용자에게 가독성 좋은 마크다운 포맷으로 출력하세요.

출력에 포함할 내용:
1. **내 프로필** — 이름, 이메일, accountId
2. **현재 작업 중인 티켓** — 있으면 상세 표시, 없으면 "없음"
3. **할당된 티켓 목록** — 우선순위 순으로 정렬
4. **최근 작업 이력** — 최근 5개까지
