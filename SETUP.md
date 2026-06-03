# Personal English OS — 설정 완료 현황

자동 완료된 항목과 남은 수동 단계(PowerSync Dashboard)를 확인하세요.

---

## 완료된 항목 (자동 설정됨)

| 항목 | 상태 |
|------|------|
| Supabase DB 마이그레이션 (테이블 6개) | ✅ 완료 |
| Supabase Auth 이메일 확인 비활성화 | ✅ 완료 |
| Edge Function 배포: chat | ✅ ACTIVE |
| Edge Function 배포: enrich-core | ✅ ACTIVE |
| Edge Function 배포: analyze-session | ✅ ACTIVE |
| Edge Function Secrets (OpenAI) | ✅ 등록됨 |
| PowerSync DB 유저 (powersync_role) | ✅ 생성됨 |
| PowerSync Publication (powersync) | ✅ 생성됨 |
| PowerSync WAL 설정 | ✅ 적용됨 |
| Flutter .vscode/launch.json | ✅ 생성됨 |

---

## 남은 단계: PowerSync Dashboard 연결 (5~10분)

> PowerSync는 외부 서비스라 API 접근이 없어 Dashboard에서 직접 해야 합니다.

### 1단계. PowerSync 계정 생성 및 프로젝트 생성

1. [app.powersync.com](https://app.powersync.com) 접속 → 로그인 or 회원가입
2. **New Project** → 이름: `personal-english-os` → **Create**
3. Development 인스턴스가 자동 생성됩니다

### 2단계. Supabase DB 연결

1. 인스턴스 선택 → 왼쪽 메뉴 **Database Connections** → **Connect to Source Database**
2. **Postgres** 탭 선택
3. URI 입력란에 아래를 붙여넣기:

```
postgresql://powersync_role:PowerSync_ENG_2024!@db.kexcjwpbquokdcsfdexp.supabase.co:5432/postgres?sslmode=verify-full
```

4. **Test Connection** 클릭 → 성공 확인 → **Save Connection**

### 3단계. Supabase Auth 연동

1. 왼쪽 메뉴 **Client Auth** 클릭
2. **Use Supabase Auth** 체크박스 ON
3. **Supabase Project ID** 입력란에 입력: `kexcjwpbquokdcsfdexp`
4. JWT Secret란은 **비워두기** (JWKS 자동 설정됨)
5. **Save and Deploy** 클릭

### 4단계. Sync Streams 설정

1. 왼쪽 메뉴 **Sync Streams** (또는 Sync Rules) 클릭
2. 에디터의 기존 내용을 전부 삭제하고 아래를 붙여넣기:

```yaml
config:
  edition: 3

streams:
  user_sessions:
    auto_subscribe: true
    queries:
      - SELECT * FROM sessions WHERE user_id = auth.user_id()

  user_messages:
    auto_subscribe: true
    queries:
      - >
        SELECT messages.*
        FROM messages
        INNER JOIN sessions ON messages.session_id = sessions.id
        WHERE sessions.user_id = auth.user_id()

  user_quiz_cards:
    auto_subscribe: true
    queries:
      - SELECT * FROM quiz_cards WHERE user_id = auth.user_id()

  user_articles:
    auto_subscribe: true
    queries:
      - SELECT * FROM articles WHERE user_id = auth.user_id()

  user_feed_subscriptions:
    auto_subscribe: true
    queries:
      - SELECT * FROM feed_subscriptions WHERE user_id = auth.user_id()

  user_profile:
    auto_subscribe: true
    queries:
      - SELECT * FROM profiles WHERE id = auth.user_id()
```

3. **Validate** → **Deploy** 클릭

### 5단계. Instance URL 확인

- 왼쪽 상단 **Connect** 버튼 클릭
- **Instance URL** 복사 (예: `https://xxxxxx.powersync.journeyapps.com`)

---

## Flutter 앱 실행

PowerSync URL을 받으면 `.vscode/launch.json`의 `POWERSYNC_URL` 값을 교체하세요:

```json
"--dart-define=POWERSYNC_URL=https://YOUR_INSTANCE.powersync.journeyapps.com"
```

그 다음 VS Code에서 **F5** 또는:

```bash
flutter run -d windows \
  --dart-define=SUPABASE_URL=https://kexcjwpbquokdcsfdexp.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtleGNqd3BicXVva2Rjc2ZkZXhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0OTMxMjEsImV4cCI6MjA5NjA2OTEyMX0.7V5JL5gmU1KgLeDvfobB7tLtX3MT6RgOroCt7uvdrho \
  --dart-define=POWERSYNC_URL=https://YOUR_INSTANCE.powersync.journeyapps.com
```

---

## 빠른 참조 정보

| 항목 | 값 |
|------|-----|
| Supabase Project URL | `https://kexcjwpbquokdcsfdexp.supabase.co` |
| Supabase Anon Key | `eyJhbGci...drho` (launch.json에 이미 설정됨) |
| PowerSync DB URI | `postgresql://powersync_role:PowerSync_ENG_2024!@db.kexcjwpbquokdcsfdexp.supabase.co:5432/postgres?sslmode=verify-full` |
| AI Provider | OpenAI `gpt-4o-mini` |

---

## AI 모델 교체 (필요 시)

```bash
# OpenAI → Claude로 전환
supabase secrets set AI_PROVIDER=claude ANTHROPIC_API_KEY=sk-ant-...

# OpenAI → Gemini로 전환
supabase secrets set AI_PROVIDER=gemini GEMINI_API_KEY=AIza...
```

재배포 불필요 — Secret 변경 즉시 적용됩니다.
