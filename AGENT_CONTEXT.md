# AGENT_CONTEXT.md
# Personal English OS — Agent Handoff Document

이 문서는 Claude agent가 컨텍스트 없이 이 프로젝트를 이어받았을 때
즉시 작업을 재개할 수 있도록 작성된 인계 문서입니다.

---

## 프로젝트 개요

**Personal English OS** — AI 기반 영어 학습 앱
- 철학: "3 Inputs, 1 Unified Output" — 채팅/저널/유튜브 3가지 입력이 하나의 SRS 퀴즈 DB로 통합
- 플랫폼: Flutter Desktop (Windows 주 타겟) + Android/iOS
- Local-First: PowerSync + Supabase로 오프라인에서도 0ms 로컬 읽기/쓰기, 멀티 디바이스 실시간 sync

---

## 현재 상태 (2025-06-04 기준)

### 완료된 것

| 항목 | 상태 |
|------|------|
| Flutter 프로젝트 생성 (Windows/Android/iOS/Linux/macOS) | ✅ |
| Supabase DB 스키마 마이그레이션 (테이블 6개) | ✅ 원격 적용됨 |
| Supabase Auth 이메일 확인 비활성화 | ✅ |
| Edge Function `chat` (SSE 스트리밍) | ✅ ACTIVE |
| Edge Function `enrich-core` (단건 즉시 enrich) | ✅ ACTIVE |
| Edge Function `analyze-session` (세션 분석, 카드 auto 생성) | ✅ ACTIVE |
| Edge Function Secrets (OpenAI) | ✅ 등록됨 |
| PowerSync DB 유저 + Publication + WAL 설정 | ✅ Supabase에 적용됨 |
| Flutter 앱 코드 전체 구현 | ✅ `flutter analyze` no issues |
| SM-2 단위 테스트 11개 | ✅ 전부 통과 |
| GitHub 커밋 | ✅ (푸시 미완료 — 아래 참고) |

### 미완료: GitHub 푸시

로컬에 커밋은 완료되었으나 GitHub 푸시에서 403 오류 발생.
토큰 권한 문제로 추정 (fine-grained PAT의 git push 인증 방식 이슈).

**해결 방법:**
```bash
cd /home/hhhddd/projects/eng-ine

# 방법 1: 새 토큰으로 재시도
git remote set-url origin https://sks1cjswo-cmyk:<NEW_TOKEN>@github.com/sks1cjswo-cmyk/eng-gine.git
git push -u origin master

# 방법 2: SSH 키 사용
ssh-keygen -t ed25519 -C "agent" -f ~/.ssh/github_engos -N ""
# 생성된 ~/.ssh/github_engos.pub 를 GitHub Settings → SSH Keys에 등록
git remote set-url origin git@github.com:sks1cjswo-cmyk/eng-gine.git
git push -u origin master
```

### 미완료: PowerSync Dashboard 연결

PowerSync는 API가 없어 Dashboard에서 수동 설정이 필요.
아래 "PowerSync 설정 정보" 섹션 참조.

### 미완료: Flutter 빌드 실행

이 환경(WSL2)은 `clang`, `cmake`, `ninja` 등 Linux 빌드 툴체인이 없어
Flutter Linux 빌드 불가. **Windows에서 클론 후 빌드해야 함.**

---

## 서비스 접속 정보

> 이 파일 자체는 public repo에 올라가므로, 아래 값들 중 민감한 것은
> Supabase Dashboard / PowerSync Dashboard에서 직접 확인하세요.

### Supabase

| 항목 | 값 |
|------|-----|
| Project ID | `kexcjwpbquokdcsfdexp` |
| Project URL | `https://kexcjwpbquokdcsfdexp.supabase.co` |
| Region | ap-southeast-1 |
| Anon Key | `.vscode/launch.json.template` 파일 참조 (실제 값은 Supabase Dashboard > API Keys) |
| Dashboard | https://supabase.com/dashboard/project/kexcjwpbquokdcsfdexp |

### PowerSync

| 항목 | 값 |
|------|-----|
| Supabase 연결 URI | `postgresql://powersync_role:PowerSync_ENG_2024!@db.kexcjwpbquokdcsfdexp.supabase.co:5432/postgres?sslmode=verify-full` |
| Dashboard | https://app.powersync.com |
| Instance URL | **미설정** — Dashboard에서 연결 후 확인 필요 |

### AI

| 항목 | 값 |
|------|-----|
| Provider | OpenAI |
| Model | gpt-4o-mini |
| API Key | Supabase Edge Function Secrets에 등록됨 (Dashboard에서 확인 불가, 재등록 필요시 `supabase secrets set`) |

### GitHub

| 항목 | 값 |
|------|-----|
| Repo | https://github.com/sks1cjswo-cmyk/eng-gine |
| Branch | master |

---

## 아키텍처 요약

```
Flutter App (Windows / Android / iOS)
  │
  ├── lib/core/
  │   ├── config/app_config.dart       ← --dart-define으로 주입하는 환경변수
  │   ├── config/router.dart           ← go_router, 인증 리다이렉트
  │   ├── auth/auth_provider.dart      ← Supabase Auth + Riverpod
  │   └── database/
  │       ├── powersync_schema.dart    ← PowerSync 로컬 SQLite 스키마 (Dart)
  │       └── powersync_database.dart  ← DB 초기화 + BackendConnector (로컬→Supabase 업로드)
  │
  ├── lib/features/
  │   ├── auth/                        ← 로그인/회원가입 화면
  │   ├── chat/                        ← Module A: AI 채팅
  │   │   ├── data/chat_repository.dart    ← 로컬 CRUD (sessions, messages)
  │   │   ├── data/chat_provider.dart      ← Riverpod: 세션/메시지 상태, 스트리밍
  │   │   └── presentation/chat_screen.dart ← Desktop split-screen / Mobile UI
  │   ├── quiz/                        ← 1 Unified Output: SRS 퀴즈
  │   │   ├── domain/sm2_algorithm.dart    ← SM-2 순수 구현
  │   │   ├── domain/quiz_card_model.dart  ← 카드 모델 (fromRow)
  │   │   ├── data/quiz_provider.dart      ← 복습 큐, 채점 로직
  │   │   └── presentation/quiz_screen.dart ← Again/Hard/Good/Easy UI
  │   └── card/
  │       └── data/card_repository.dart    ← dedup_key, reinforce, 2단계 enrich
  │
  ├── lib/shared/
  │   ├── theme/app_theme.dart
  │   ├── widgets/app_shell.dart       ← 반응형 셸 (Desktop NavRail / Mobile BottomNav)
  │   └── widgets/enrich_popup.dart    ← 수동 저장 팝업 (enrich-core 호출 후 미리보기)
  │
  └── lib/main.dart                    ← 앱 진입점

Supabase (원격)
  ├── DB Tables: profiles, sessions, messages, quiz_cards, articles, feed_subscriptions
  ├── RLS: 모든 테이블에 auth.uid() = user_id 정책 적용
  └── Edge Functions (ACTIVE):
      ├── chat             ← SSE 스트리밍, AI provider 추상화
      ├── enrich-core      ← 단건 즉시 enrich (수동 저장용)
      └── analyze-session  ← 세션 종료 후 background 분석, 카드 auto 생성(최대 7개)

PowerSync (미연결)
  ← Supabase Postgres WAL을 읽어 각 기기 로컬 SQLite에 실시간 sync
  ← supabase/powersync_sync_streams.yaml 에 Sync Streams 정의 완료
```

---

## 핵심 설계 결정 (변경 금지)

1. **Local-First**: 모든 읽기/쓰기는 로컬 SQLite 먼저. PowerSync가 백그라운드에서 Supabase와 sync.
2. **카드 저장 2경로**:
   - 자동(auto): 세션 종료 → `analyze-session` EF → 대화 분석 → 최대 7개 카드 자동 생성
   - 수동(manual): 텍스트 롱프레스 → `enrich-core` EF → 팝업 미리보기 → 저장
3. **2단계 Enrich**:
   - core(즉시): corrected_text, nuance_explanation, alternative_examples
   - full(배경): synonyms, confusable_with, homonyms, collocations, register
4. **중복 처리**: `dedup_key = sha1(normalize(text))` — 중복 시 새 카드 생성 안 하고 `reinforce_count++`, 복습 우선순위↑
5. **AI Provider 추상화**: `AI_PROVIDER` env var 하나로 OpenAI/Claude/Gemini 전환. `supabase/functions/_shared/ai_provider.ts`

---

## Flutter 앱 실행 방법 (Windows에서)

### 사전 요구사항
- Flutter 3.32+ 설치 (https://flutter.dev/docs/get-started/install/windows)
- VS Code + Flutter/Dart 확장

### 1. 클론 및 패키지 설치
```bash
git clone https://github.com/sks1cjswo-cmyk/eng-gine.git
cd eng-gine
flutter pub get
```

### 2. launch.json 설정
`.vscode/launch.json.template`을 복사해서 `.vscode/launch.json`으로 만들고
아래 값을 채워넣기:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Personal English OS (Windows)",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=SUPABASE_URL=https://kexcjwpbquokdcsfdexp.supabase.co",
        "--dart-define=SUPABASE_ANON_KEY=<Supabase Dashboard > API Keys > anon public>",
        "--dart-define=POWERSYNC_URL=<PowerSync Dashboard > Connect > Instance URL>"
      ]
    }
  ]
}
```

### 3. 실행
```bash
# VS Code에서 F5
# 또는 터미널에서:
flutter run -d windows \
  --dart-define=SUPABASE_URL=https://kexcjwpbquokdcsfdexp.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=POWERSYNC_URL=https://xxx.powersync.journeyapps.com
```

---

## PowerSync Dashboard 설정 (미완료 — 수동 필요)

1. https://app.powersync.com 접속
2. New Project → `personal-english-os`
3. **Database Connections** → URI 입력:
   ```
   postgresql://powersync_role:PowerSync_ENG_2024!@db.kexcjwpbquokdcsfdexp.supabase.co:5432/postgres?sslmode=verify-full
   ```
4. **Client Auth** → Use Supabase Auth ON → Project ID: `kexcjwpbquokdcsfdexp` → Save and Deploy
5. **Sync Streams** → `supabase/powersync_sync_streams.yaml` 내용 붙여넣기 → Validate → Deploy
6. Instance URL 복사 → launch.json의 `POWERSYNC_URL`에 입력

---

## Supabase CLI 사용법 (이 환경에서)

```bash
# CLI 경로
/tmp/opencode/supabase

# 인증 토큰 (환경변수로 설정)
export SUPABASE_ACCESS_TOKEN=<Supabase Dashboard > Account > Access Tokens에서 확인>

# 자주 쓰는 명령
/tmp/opencode/supabase secrets list
/tmp/opencode/supabase secrets set KEY=value
/tmp/opencode/supabase functions deploy <name>
/tmp/opencode/supabase db push --password "2qnxhU86T5JwPcO4"

# Flutter (flutter SDK 경로)
export PATH="/tmp/opencode/flutter/bin:$PATH"
flutter analyze
flutter test
```

---

## DB 스키마 핵심 테이블

### quiz_cards (핵심 — 1 Unified Output)
```sql
id, user_id, session_id, source_type(chat|journal|youtube),
card_type(sentence|word|phrase), save_mode(auto|manual),
error_category(grammar|unnatural|vocab|null),
original_text, corrected_text, nuance_explanation, context_snippet,
alternative_examples(jsonb), synonyms(jsonb), confusable_with(jsonb),
homonyms(jsonb), collocations(jsonb), register,
enrich_status(pending|core|full|failed),
dedup_key(unique per user), reinforce_count,
ease_factor, interval_days, repetitions, next_review_at  ← SM-2 필드
```

### sessions
```sql
id, user_id, source_type, title,
status(active|ended|analyzing|analyzed|error),
created_at, ended_at
```

---

## 다음 작업 우선순위

1. **[완료] GitHub 푸시** — SSH 방식으로 변경 후 완료
2. **[즉시] PowerSync Dashboard 연결** — 위 5단계 수동 설정
3. **[즉시] 패키지 업그레이드** — 아래 "패키지 업그레이드 현황" 섹션 참고
4. **[Windows에서] 빌드 테스트** — `flutter run -d windows`
5. **[Phase 2] Module B: Journal Reader**
   - URL 붙여넣기 → Supabase Edge Function에서 서버사이드 페칭 → Readability 본문 추출
   - RSS 구독 자동 수집
   - 문장/단어 탭 → enrich 팝업 (Chat과 동일 로직 재사용)
6. **[Phase 2] 카드 브라우저 탭** — 저장된 카드 전체 보기, enrich_status 필터
7. **[Phase 2] 통계 탭** — 복습 이력, 오류 카테고리별 분포

---

## 패키지 업그레이드 현황

> `flutter pub outdated` 기준 (2026-06-06)

### 안전 업그레이드 (flutter pub upgrade — 즉시 가능)

| 패키지 | 현재 | 최신 | 비고 |
|--------|------|------|------|
| `cupertino_icons` | 1.0.8 | 1.0.9 | - |
| `shared_preferences` | 2.5.3 | 2.5.5 | - |
| `supabase_flutter` | 2.12.4 | 2.14.1 | - |

```bash
flutter pub upgrade
```

### 메이저 업그레이드 (pubspec.yaml 수동 수정 필요 — 코드 변경 동반)

| 패키지 | 현재 | 최신 | 영향도 |
|--------|------|------|--------|
| `flutter_riverpod` | 2.6.1 | 3.3.1 | **높음** — v3 breaking changes, AsyncNotifier API 변경 |
| `riverpod_annotation` | 2.6.1 | 4.0.2 | **높음** — riverpod v3와 세트 업그레이드 필요 |
| `riverpod_generator` | 2.6.5 | 4.0.3 | **높음** — riverpod v3와 세트 업그레이드 필요 |
| `riverpod_lint` | 2.6.5 | 3.1.3 | **높음** — riverpod v3와 세트 업그레이드 필요 |
| `go_router` | 14.8.1 | 17.3.0 | **중간** — redirect/guard API 일부 변경 |
| `powersync` | 1.18.0 | 2.2.0 | **높음** — v2 breaking changes, connector API 변경 가능 |
| `build_runner` | 2.5.4 | 2.15.0 | **낮음** — dev 의존성, 코드 영향 없음 |
| `custom_lint` | 0.7.6 | 0.8.1 | **낮음** — dev 의존성 |
| `flutter_lints` | 5.0.0 | 6.0.0 | **낮음** — 새 lint 규칙 추가될 수 있음 |

업그레이드 권장 순서:
1. `build_runner`, `flutter_lints`, `custom_lint` 먼저 (안전)
2. `riverpod` 계열 일괄 업그레이드 (flutter_riverpod + riverpod_annotation + riverpod_generator + riverpod_lint 동시에)
3. `go_router`
4. `powersync` (마지막 — powersync_database.dart BackendConnector 확인 필요)

### 폐기(discontinued) 패키지 — 주의

| 패키지 | 상태 | 조치 |
|--------|------|------|
| `build_resolvers` | discontinued (transitive) | `build_runner` 업그레이드 시 자동 해결 예정 |
| `build_runner_core` | discontinued (transitive) | `build_runner` 업그레이드 시 자동 해결 예정 |

### EOL(End of Life) 전환 예정 패키지 — 주의

| 패키지 | 현재 | Resolvable | 비고 |
|--------|------|------------|------|
| `powersync_flutter_libs` | 0.4.15+1 | 0.5.0+eol | `powersync` v2 업그레이드 시 같이 해결 |
| `sqlite3_flutter_libs` | 0.5.42 | 0.6.0+eol | `powersync` v2 업그레이드 시 같이 해결 |

---

## 환경 변수 전체 목록

| 변수 | 위치 | 값 |
|------|------|-----|
| `SUPABASE_URL` | Flutter `--dart-define` | `https://kexcjwpbquokdcsfdexp.supabase.co` |
| `SUPABASE_ANON_KEY` | Flutter `--dart-define` | Supabase Dashboard > API Keys |
| `POWERSYNC_URL` | Flutter `--dart-define` | PowerSync Dashboard > Connect |
| `AI_PROVIDER` | Supabase Edge Function Secret | `openai` |
| `OPENAI_API_KEY` | Supabase Edge Function Secret | 등록됨 |
| `OPENAI_MODEL` | Supabase Edge Function Secret | `gpt-4o-mini` |

AI 모델 교체:
```bash
export SUPABASE_ACCESS_TOKEN=<Supabase Dashboard > Account > Access Tokens에서 확인>
/tmp/opencode/supabase secrets set AI_PROVIDER=claude ANTHROPIC_API_KEY=sk-ant-...
```

---

## 테스트

```bash
export PATH="/tmp/opencode/flutter/bin:$PATH"
cd /home/hhhddd/projects/eng-ine

# 전체 정적 분석
flutter analyze        # → No issues found

# SM-2 단위 테스트 (11개)
flutter test test/features/quiz/sm2_algorithm_test.dart
```
