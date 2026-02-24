---
name: jira-refine
description: Jira 티켓의 내용을 확인하고 현재 프로젝트 맥락을 결합해 구체화된 내용을 티켓의 Description에 업데이트합니다.
user-invocable: false
allowed-tools: Read, Bash
---

# Jira 티켓 구체화 (Refine)

## 동적 컨텍스트

- 현재 상태: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get-state-summary`

## 인자

- action = `$ARGUMENTS[0]` (refine)
- 대상 KEY = `$ARGUMENTS[1]` (예: PROJ-123)

## 작업 순서

1. **티켓 정보 조회**
   `get-issue`를 통해 기존 티켓 정보를 가져옵니다.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/jira-api.sh" get-issue "$ARGUMENTS[1]"
   ```

   반환된 JSON에서 제목(summary), 타입(issuetype), 기존 설명(description) 등을 확인합니다.

2. **프로젝트 맥락 파악**
   현재 프로젝트 레포지토리의 코드 구조, 요구사항 관련 문서, 상태 정보 등을 탐색하고 분석하여 해당 티켓과 관련된 배경 지식을 확보합니다.

3. **구체화(Refining) 및 Atlassian Document Format(ADF) 구성**
   위 1번과 2번 단계에서 얻은 정보를 바탕으로 더욱 구체적이고 구현 가능한 수준의 내용으로 정리합니다. (도출해야 할 설계, 작업 목표, 제약사항 등)
   정리된 내용을 [Atlassian Document Format (ADF) 형식](https://developer.atlassian.com/cloud/jira/platform/apis/document/structure/)을 따르는 JSON 객체 문자열로 구성합니다.

   **주의: 티켓의 내용(Description)만 업데이트하고 다른 속성(상태 등)은 절대 수정하지 않습니다.**

   업데이트할 Payload 예시 (ADF 구조를 래핑):

   ```json
   {
     "fields": {
       "description": {
         "type": "doc",
         "version": 1,
         "content": [
           {
             "type": "paragraph",
             "content": [
               {
                 "type": "text",
                 "text": "여기에 구체화된 내용을 입력합니다."
               }
             ]
           }
         ]
       }
     }
   }
   ```

4. **이슈 내용 업데이트**
   구현된 Payload를 사용해 대상을 업데이트합니다.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/jira-api.sh" update-issue "$ARGUMENTS[1]" '{
     "fields": {
       "description": {
         "type": "doc",
         "version": 1,
         "content": [...]
       }
     }
   }'
   ```

5. **완료 및 사용자 보고**
   업데이트 결과를 확인하고(성공/실패 여부), 구체화된 주요 내용을 사용자에게 간략히 요약하여 마크다운으로 출력합니다.
