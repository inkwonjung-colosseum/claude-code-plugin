---
name: jira-sync
description: Jira에서 내 할당 티켓을 동기화하고 현재 상태를 표시합니다.
user-invocable: false
allowed-tools: Read, Bash
---

# Jira 동기화 / 상태 표시

## 동적 컨텍스트

- 현재 상태: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get-state-summary`

## 인자

- action = `$ARGUMENTS[0]` (status 또는 sync)

## 작업

### `status` 일 때
동적 컨텍스트의 현재 상태를 그대로 마크다운 포맷으로 예쁘게 출력하세요.
추가 API 호출 없이 state.json 기반 정보만 사용합니다.

### `sync` 일 때
아래 명령으로 Jira API와 동기화를 실행하세요:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" sync
```

동기화 완료 후 결과를 사용자에게 마크다운 포맷으로 출력하세요.
동기화 결과에는 다음이 포함됩니다:
- 동기화된 티켓 수
- 현재 작업 중인 티켓 (있으면)
- 할당된 티켓 목록 (우선순위 순)
