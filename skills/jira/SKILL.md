---
name: jira
description: >
  Jira 오케스트레이터. /jira {action} {args} 형식으로 호출합니다.
  액션을 파싱하여 적절한 하위 Skill 또는 Agent에 작업을 위임합니다.
argument-hint: "[action] [arguments...]"
disable-model-invocation: true
---

# Jira 오케스트레이터

사용자의 `/jira {action} {args}` 명령을 파싱하여 하위 Skill 또는 Agent에 위임합니다.

## 동적 컨텍스트

- 현재 상태: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get-state-summary`

## 라우팅 규칙

`$ARGUMENTS`를 파싱하여 첫 번째 단어(action)에 따라 아래 대상을 호출하세요:

| action       | 위임 대상 (Skill/Agent)   | 설명                                         |
| ------------ | ------------------------- | -------------------------------------------- |
| `me`         | `jira-me` Skill 호출      | 내 Jira 프로필 + 워크로드 조회               |
| `status`     | `jira-sync` Skill 호출    | 현재 상태 표시 (동기화 없이)                 |
| `sync`       | `jira-sync` Skill 호출    | Jira API에서 내 티켓 강제 동기화             |
| `work`       | `jira-work` Skill 호출    | 티켓 작업 시작 (예: `/jira work PROJ-42`)    |
| `done`       | `jira-work` Skill 호출    | 현재 작업 완료 처리                          |
| `get`        | `jira-query` Skill 호출   | 이슈 상세 조회 (예: `/jira get PROJ-42`)     |
| `search`     | `jira-query` Skill 호출   | JQL 검색 (예: `/jira search "project=PROJ"`) |
| `comment`    | `jira-query` Skill 호출   | 코멘트 추가                                  |
| `transition` | `jira-query` Skill 호출   | 상태 전이                                    |
| `board`      | `jira-query` Skill 호출   | 보드 조회                                    |
| `sprint`     | `jira-query` Skill 호출   | 스프린트 조회                                |
| `create`     | `jira-query` Skill 호출   | 이슈 생성                                    |
| `refine`     | `jira-refine` Skill 호출  | 티켓 구체화 (예: `/jira refine PROJ-42`)     |
| `analyze`    | `jira-analyst` Agent 호출 | 워크로드 분석·추천                           |

## 실행 방법

1. `$ARGUMENTS`에서 action과 나머지 인자를 분리합니다
2. 위 테이블에 따라 해당 Skill의 SKILL.md를 읽고 지시에 따라 실행합니다
3. action이 없거나 `help`이면 사용 가능한 명령 목록을 표시합니다

## 도움말 출력

action이 없을 때 아래를 출력하세요:

```
🔧 Jira 플러그인 명령어

  /jira me              내 Jira 프로필 + 워크로드
  /jira status          현재 작업 + 할당 티켓 목록
  /jira sync            Jira에서 내 티켓 동기화

  /jira work KEY        이 티켓 작업 시작
  /jira done            현재 작업 완료

  /jira get KEY         이슈 상세 조회
  /jira search "JQL"    JQL 검색
  /jira create          이슈 생성
  /jira comment KEY "내용"  코멘트 추가
  /jira transition KEY  상태 전이
  /jira refine KEY      티켓 내용을 구체화하여 업데이트

  /jira board           보드 목록
  /jira sprint BOARD_ID 스프린트 조회
  /jira analyze         워크로드 분석·추천
```
