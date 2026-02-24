---
name: jira-work
description: Jira 티켓 작업 시작/완료를 관리합니다. current_ticket을 갱신합니다.
user-invocable: false
allowed-tools: Read, Bash
---

# 작업 시작 / 완료

## 동적 컨텍스트

- 현재 작업: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get-current-ticket`
- 할당 티켓: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get-my-tickets`

## 인자

- action = `$ARGUMENTS[0]` (work 또는 done)
- ticket_key = `$ARGUMENTS[1]` (work 시 필요, 예: PROJ-42)

## 작업

### `work {KEY}` 일 때

1. 아래 명령으로 작업 전환을 실행:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" set-current-ticket "$ARGUMENTS[1]"
   ```
2. 결과를 사용자에게 표시
3. 현재 작업이 이미 있었다면, 이전 작업이 work_history로 이동됨을 안내
4. 필요 시 Jira 상태 전이 제안 (예: "Jira에서 In Progress로 변경할까요?")

### `done` 일 때

1. 아래 명령으로 현재 작업을 완료 처리:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" clear-current-ticket
   ```
2. 결과를 사용자에게 표시
3. 사용자에게 Jira 상태 전이 제안:
   - "Jira에서 Done으로 변경할까요?"
   - 전이를 원하면 `jira-api.sh get-transitions {KEY}` 로 옵션 조회 후 실행

### 에러 처리

- `work` 시 KEY가 없으면: "티켓 키를 입력해주세요. 예: `/jira work PROJ-42`"
- `done` 시 현재 작업이 없으면: "현재 작업 중인 티켓이 없습니다."
