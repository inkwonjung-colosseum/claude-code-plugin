# 🔌 Atlassian Jira Plugin for Claude Code

Claude Code에서 Jira 티켓을 직접 관리하는 플러그인입니다.

## ✨ 주요 기능

| 기능         | 명령어                     | 설명                             |
| ------------ | -------------------------- | -------------------------------- |
| 🔄 동기화    | `/jira sync`               | Jira에서 내 할당 티켓 가져오기   |
| 📋 상태 확인 | `/jira status`             | 현재 작업 + 할당 티켓 목록       |
| 👤 내 정보   | `/jira me`                 | 프로필 + 워크로드 조회           |
| 🎯 작업 시작 | `/jira work KEY`           | 티켓 작업 시작 (상태 추적)       |
| ✅ 작업 완료 | `/jira done`               | 현재 작업 완료 처리              |
| 🔍 이슈 조회 | `/jira get KEY`            | 이슈 상세 조회                   |
| 🔎 검색      | `/jira search "JQL"`       | JQL로 이슈 검색                  |
| 💬 코멘트    | `/jira comment KEY "내용"` | 이슈에 코멘트 추가               |
| 🔀 상태 전이 | `/jira transition KEY`     | 이슈 상태 변경                   |
| 📝 구체화    | `/jira refine KEY`         | 프로젝트 맥락으로 티켓 설명 보강 |
| ➕ 생성      | `/jira create`             | 새 이슈 생성                     |
| 📊 분석      | `/jira analyze`            | 워크로드 분석 · 우선순위 추천    |
| 🏗️ 보드      | `/jira board`              | 보드 목록 조회                   |
| 🏃 스프린트  | `/jira sprint BOARD_ID`    | 스프린트 조회                    |

## 📦 설치

```bash
claude plugin add inkwonjung-colosseum/claude-code-plugin
```

## ⚙️ 설정

플러그인을 설치한 후, **플러그인이 적용된 프로젝트**에서 아래 설정 파일을 생성해야 합니다.

### 1. Atlassian API 토큰 발급

[Atlassian API Token 관리](https://id.atlassian.com/manage-profile/security/api-tokens) 페이지에서 토큰을 생성하세요.

### 2. 설정 파일 생성

프로젝트 내 `.store/config.json` 파일을 생성합니다:

```json
{
  "atlassian": {
    "domain": "https://your-org.atlassian.net",
    "email": "your-email@example.com",
    "api_token": "your-api-token"
  },
  "sync": {
    "auto_sync_on_session_start": true
  }
}
```

> ⚠️ `.store/config.json`에는 API 토큰이 포함되므로, 프로젝트의 `.gitignore`에 `.store/`를 추가하세요.

## 🗂️ 프로젝트 구조

```
.
├── .claude-plugin/
│   └── plugin.json          # 플러그인 메타데이터
├── hooks/
│   ├── hooks.json           # Hook 이벤트 정의
│   ├── session-start.sh     # 세션 시작 (동기화, 브랜치 감지)
│   ├── session-end.sh       # 세션 종료
│   └── ...                  # 기타 Hook 스크립트
├── scripts/
│   ├── jira-api.sh          # Jira REST API 래퍼
│   └── state-manager.sh     # 상태 관리 (현재 작업, 티켓 목록, 이력)
├── skills/
│   ├── jira/                # 오케스트레이터 (명령어 라우팅)
│   ├── jira-me/             # 내 정보 조회
│   ├── jira-work/           # 작업 시작/완료
│   ├── jira-query/          # 이슈 조회/검색/코멘트/전이
│   ├── jira-sync/           # 동기화/상태 표시
│   └── jira-refine/         # 티켓 내용 구체화
├── agents/
│   └── jira-analyst.md      # 워크로드 분석 에이전트
├── .mcp.json                # MCP 서버 설정
└── .lsp.json                # LSP 설정
```

## 🔧 의존성

| 도구   | 용도        | 설치              |
| ------ | ----------- | ----------------- |
| `jq`   | JSON 파싱   | `brew install jq` |
| `curl` | HTTP 요청   | 기본 설치됨       |
| `git`  | 브랜치 감지 | 기본 설치됨       |

## 📄 라이선스

MIT
