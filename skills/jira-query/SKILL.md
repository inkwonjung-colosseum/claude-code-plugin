---
name: jira-query
description: Jira 이슈 조회, JQL 검색, 코멘트, 상태 전이, 보드, 스프린트를 실행합니다.
user-invocable: false
allowed-tools: Read, Bash
---

# Jira 조회 / 검색 / 코멘트 / 전이

## 동적 컨텍스트

- 현재 작업: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get-current-ticket`

## 인자

- action = `$ARGUMENTS[0]` (get | search | comment | transition | board | sprint | create)
- 나머지 인자 = `$ARGUMENTS[1:]`

## 작업

### `get {KEY}`
이슈 상세 조회:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/jira-api.sh" get-issue "$ARGUMENTS[1]"
```
결과 JSON을 파싱하여 마크다운으로 출력:
- 키, 제목, 상태, 우선순위, 타입
- 담당자, 라벨
- 설명 (있으면)
- 최근 코멘트 (있으면, 최근 3개까지)

### `search "JQL"`
JQL 검색:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/jira-api.sh" search "$ARGUMENTS[1]"
```
결과를 테이블 형식으로 출력.

### `comment {KEY} "내용"`
코멘트 추가:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/jira-api.sh" add-comment "$ARGUMENTS[1]" "$ARGUMENTS[2]"
```

### `transition {KEY} {상태명?}`
상태 전이:
1. 먼저 가능한 전이 목록 조회:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/jira-api.sh" get-transitions "$ARGUMENTS[1]"
   ```
2. 상태명이 주어지면 매칭되는 전이 실행, 없으면 목록 표시
3. 전이 실행:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/jira-api.sh" transition "$ARGUMENTS[1]" "{transition_id}"
   ```

### `board {PROJECT?}`
보드 목록:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/jira-api.sh" get-boards "$ARGUMENTS[1]"
```

### `sprint {BOARD_ID}`
스프린트 조회:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/jira-api.sh" get-board-sprints "$ARGUMENTS[1]"
```
활성 스프린트의 이슈도 함께 조회하여 표시:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/jira-api.sh" get-sprint-issues "{sprint_id}"
```

### `create`
이슈 생성. 사용자에게 다음 정보를 질문:
- 프로젝트 키 (필수)
- 이슈 타입 (Task, Bug, Story 등)
- 제목 (필수)
- 설명 (선택)
- 우선순위 (선택)

정보를 수집한 후 JSON 페이로드를 구성하여:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/jira-api.sh" create-issue '{...}'
```

### 에러 처리
- KEY가 필요한 명령에 KEY가 없으면 안내 메시지
- Jira API 에러 발생 시 원인 설명 + 해결 방법 안내
