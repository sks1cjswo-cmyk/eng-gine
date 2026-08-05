# YouTube 클립 소스 수집 전략

카드(표현/단어/패턴)에 **실제 원어민이 그걸 쓰는 유튜브 클립**을 붙이기 위한
수집·인덱싱·서빙 설계.

- 대상 기능: 퀴즈 정답 공개 후 "실제 용례" / enrich 팝업 미리보기 / 카드 상세
- 이 문서의 범위: **클립을 어디서 어떻게 모아 인덱싱할지**
- 관련 기존 설계: `AGENT_CONTEXT.md`

> ⚠️ `quiz_cards.source_type = 'youtube'`(카드의 *출처*가 유튜브)와 이 기능(카드에
> 유튜브 *예시*를 붙임)은 서로 다른 것이다. 별도 테이블(`card_clips`)로 다룬다.

---

## 0. 결론 먼저 (TL;DR)

| | 무엇 | 언제 |
|---|---|---|
| **Track A** | 채널 화이트리스트의 제목·설명 로컬 인덱스 → **해설 클립** | 1~2일 |
| **Track B** | YouGlish 위젯 임베드 → **용례 브라우징** | 반나절 |
| **Track C** | 자체 자막 코퍼스 인덱스 → **실사용 클립** (본편) | 2~4주 |

핵심 판단:

1. **라이브 검색은 불가능하다.** 유튜브를 실시간으로 뒤져 표현을 찾는 건 API로
   안 된다. **자체 인덱스를 미리 구축**하고 앱은 그 인덱스만 조회한다.
2. **자막 수확은 개발자 로컬 머신(Windows)에서 배치로 돌린다.** 클라우드 IP는
   차단된다 → Edge Function / GitHub Actions에서 하면 안 된다.
3. **문장 인덱스는 Supabase에 넣지 않는다.** 무료 티어 DB가 500MB인데 문장
   인덱스만 GB급이다. **로컬 파일이 진실의 원천, Supabase는 확정 클립 서빙 캐시.**
4. **자동 매칭 결과를 그대로 노출하지 않는다.** 오탐 클립 1개가 학습자에게 주는
   손해가 크다. 검수 큐(`review_status`)를 통과한 것만 서빙한다.

---

## 1. 문제 정의: 왜 어려운가

확인된 제약(2026-08 기준):

| 제약 | 내용 | 근거 |
|---|---|---|
| 자막 검색 불가 | `search.list`의 `q`는 제목/설명/태그/채널명만 검색 | [API 문서](https://developers.google.com/youtube/v3/docs/search/list) |
| 자막 다운로드 불가 | `captions.download`는 **영상 소유자 OAuth** 필요, 200 units | [captions.download](https://developers.google.com/youtube/v3/docs/captions/download) |
| 검색 할당량 | `search.list` = **100 units**/회, 일 기본 10,000 → **하루 100회** | [할당량](https://developers.google.com/youtube/v3/getting-started) |
| 열거는 저렴 | `playlistItems.list` = **1 unit**/50개, `videos.list` = 1 unit/50개 | 위와 동일 |
| 클라우드 IP 차단 | `timedtext` 엔드포인트가 클라우드 IP를 차단 (`IpBlocked`) | [issue #593](https://github.com/jdepoix/youtube-transcript-api/issues/593) |

**따라서:**
- 패턴별 `search.list` 호출은 애초에 성립하지 않는다(패턴 5,000개면 50일).
- 채널 업로드 목록을 `playlistItems`로 통째로 긁는 편이 200배 싸다.
  → 교육 채널 200개 × 500영상 = 100,000영상 = **2,000 units**, 하루면 끝.
- 자막 파이프라인은 서버리스에 올릴 수 없다. 로컬 배치다.

---

## 2. 클립을 3종류로 분리한다

한 덩어리로 보면 전부 어렵지만, 쪼개면 두 종류는 오늘 당장 된다.

### 유형 1 — 실사용 클립 (authentic)
원어민이 자연스럽게 그 표현을 쓰는 3~10초. **교육적으로 가장 가치 있고 가장 비싸다.**
→ Track C (자체 코퍼스)

### 유형 2 — 해설 클립 (explainer)
영어 강사가 그 패턴을 설명하는 영상. 이런 영상은 **제목에 패턴이 그대로 박혀 있다**
("HOW TO USE *WOULD RATHER*", "STOP saying *I'm fine*").
→ **자막이 전혀 필요 없다.** 메타데이터 검색으로 잡힌다. → Track A

### 유형 3 — 용례 브라우징 (mass examples)
"이 표현이 실제로 쓰이는 예 30개를 훑고 싶다" → 직접 구축할 필요 없다.
[YouGlish 위젯](https://youglish.com/api/doc/widget)이 정확히 이 제품이고
[JS API](https://youglish.com/api/doc/js-api)로 재생/속도/이동을 제어할 수 있다
(partner key 필요, 일 100만 impression 초과 시 별도 협의).
→ Track B

UI에서는 카드 하단 탭 3개로 그대로 대응된다: `실제 용례` / `설명 보기` / `더 많은 예`.

---

## 3. Track A — 해설 클립 인덱스 (즉시 착수)

자막이 필요 없으므로 하루 안에 동작한다. **Track C의 커버리지 공백을 메우는
안전망**이기도 하다.

```
1) 채널 화이트리스트 작성 (수동, 150~300개)
   - 영어 교육 채널: mmmEnglish, English with Lucy, Rachel's English,
     Speak English With Vanessa, EnglishAnyone, Learn English with TV Series ...
   - 채널 ID → channels.list(part=contentDetails) → relatedPlaylists.uploads

2) 업로드 전수 열거   playlistItems.list(playlistId=uploads, maxResults=50)
   → 1 unit / 50개.  100,000영상 = 2,000 units

3) 메타데이터 게이트  videos.list(part=status,contentDetails,statistics, id=50개씩)
   → embeddable / 연령제한 / 지역차단 / 길이 / 조회수

4) 제목+설명 로컬 FTS 인덱스 구축 (SQLite FTS5 or Postgres tsvector)

5) 패턴 → 후보 영상 매칭
   - 제목에 패턴 문자열 포함  (정밀도 높음, 최우선)
   - 설명에 포함             (정밀도 중간)
   - 챕터 타임스탬프 파싱     ← 설명란의 "03:12 would rather" 를 긁으면
                                시작 시각까지 공짜로 얻는다 ★
```

★ 5번의 챕터 파싱이 의외로 강력하다. 교육 채널 설명란에는 `mm:ss 주제` 형식
타임스탬프가 흔하고, 이걸 파싱하면 **자막 없이도 정확한 클립 시작점**이 나온다.
정규식: `^\s*(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\s*[-–—)\.]?\s*(.+)$`

챕터가 없으면 영상 시작(0초)부터 재생하되, 클립이 아니라 "영상 링크"로 표시한다.

---

## 4. Track C — 자체 자막 코퍼스 (본편)

### 4.1 파이프라인 7단계

```
[1] 채널 선정 ──> [2] 영상 열거 ──> [3] 메타 게이트 ──> [4] 자막 수확
                                                              │
[7] 업로드+검수 <── [6] 패턴 매칭 <── [5] 문장 재구성 ────────┘
```

전부 **로컬 Windows 머신에서 Python 배치**로 돈다. 결과만 Supabase에 올린다.

#### [1] 채널 선정 — 품질이 여기서 결정된다

우선순위:

1. **수동 자막(manual captions) 보유 채널** — ASR보다 정확도가 압도적. `videos.list`로는
   구분이 안 되므로 `yt-dlp --list-subs`의 `subtitles` vs `automatic_captions`로 판별.
2. **CC BY 라이선스 영상** — `search.list(videoLicense=creativeCommon)` 또는
   `videos.list`의 `status.license == 'creativeCommon'`. 법적 여유가 크다.
3. **TED / TEDx** — 사람이 만든 트랜스크립트가 공개되어 있고 유튜브에도 있다.
   발화가 명료하고 문장이 완결적이다. **콜드스타트 1순위.**
4. 명료한 발화 + 배경음악 적은 채널: 인터뷰, 팟캐스트 영상판, 다큐, 리뷰, 강의.
5. **악센트 균형**: us / uk / au / ca 를 `yt_channels.accent`로 태깅해 서빙 시 분산.

피할 것: 음악 위주, 게임 실황(고함·중첩발화), 하드섭(화면 박힌 자막), 쇼츠(문장 불완결).

#### [2] 영상 열거

Track A와 동일. `playlistItems.list`로 1 unit/50개.

#### [3] 메타데이터 게이트 (자막 수확 전에 걸러서 낭비 제거)

`videos.list(part=status,contentDetails,statistics,snippet)` 50개씩 = 1 unit.

거부 조건:
```
status.embeddable == false                   → 임베드 불가, 무의미
contentDetails.contentRating 연령제한 존재     → 학습앱 부적합
contentDetails.regionRestriction.blocked 에 KR → 한국 사용자 재생 불가
duration < 60s or > 3600s                     → 쇼츠/초장편 제외
snippet.defaultAudioLanguage 가 en* 아님       → (단, null 흔함 → 통과시키고 나중 판별)
```

#### [4] 자막 수확 — `yt-dlp`, 로컬 실행

```bash
yt-dlp --skip-download \
       --write-subs --write-auto-subs \
       --sub-langs "en.*" --sub-format json3 \
       --sleep-requests 1.5 --sleep-interval 2 --max-sleep-interval 5 \
       -o "corpus/%(id)s.%(ext)s" \
       --batch-file video_ids.txt
```

- **`json3` 포맷을 쓰는 이유**: 자동 자막의 경우 `segs[].tOffsetMs`로 **단어 수준
  타이밍**이 들어온다. VTT는 큐(cue) 단위라 클립 경계가 뭉갠다.
- **`--sleep-requests` 필수.** 없으면 IP 차단으로 직행한다.
- 처리량: 영상당 1.5~3초(자막만) → 10,000영상 ≈ 5~8시간. 하룻밤 배치.
- 저장: 10분 영상 자막 ≈ 40KB → 10,000개 ≈ 400MB. 로컬 디스크에 원본 보관
  (새 패턴 추가 시 재매칭용).

**대안(상업화 시)**: 관리형 transcript API를 유료로 쓰거나, CC BY 코퍼스와
TED로만 구성. §7 참조.

#### [5] 문장 재구성 — 여기가 가장 많이 틀리는 지점

자막 큐는 문장 경계와 일치하지 않는다. 그대로 매칭하면 문장이 잘린 클립이 나온다.

```python
# 5-1) 큐 병합 → 연속 토큰 스트림 (token, start_ms, end_ms)
# 5-2) ASR 자막이면 구두점 복원
#      - deepmultilingualpunctuation 또는 LLM 배치(gpt-4o-mini)
#      - 자동자막은 대문자/구두점이 없어 문장 분할이 불가능하다 → 필수 단계
# 5-3) 문장 분할 (spaCy sentencizer)
# 5-4) 문장 ↔ 토큰 타이밍 재정렬
#      sentence.start_ms = first_token.start_ms
#      sentence.end_ms   = last_token.end_ms
# 5-5) 문장별 파생 컬럼
#      text_norm   : 소문자, 축약 정규화(I'd → I would 병기)
#      lemma_text  : spaCy 표제어 시퀀스
#      pos_text    : "PRON/AUX/ADV/VERB" POS 시퀀스
#      wpm         : 발화 속도
```

**클립 경계 확정**:
```
clip.start = sentence.start_ms - 250ms   (앞 무음 > 500ms 면 무음 중앙으로 스냅)
clip.end   = sentence.end_ms   + 400ms
문맥이 필요한 패턴은 preroll 옵션으로 앞 1문장 포함
```

#### [6] 패턴 매칭 — 4계층

`patterns` 테이블의 `matcher` jsonb 스펙으로 계층을 선언한다.

| 계층 | 대상 | 구현 | 예시 |
|---|---|---|---|
| **L1 exact** | 고정 표현 | `text_norm` 문자열/구문 검색 | `"long story short"` |
| **L2 lemma** | 굴절 허용 | `lemma_text` 검색 | `get used to` → *got/getting used to* |
| **L3 syntax** | 문법 패턴 | spaCy `Matcher`/`DependencyMatcher` | `would rather + 동사원형` |
| **L4 semantic** | 기능적 표현 | 문장 임베딩 + pgvector/faiss | "정중하게 거절하기" |

패턴 스펙 예 (`tools/corpus/patterns/would_rather.yaml`):
```yaml
id: would_rather_bare_inf
label_ko: "would rather + 동사원형 (~하는 게 낫겠다)"
label_en: "would rather + bare infinitive"
kind: syntactic
cefr: B1
matchers:
  - layer: L3
    spacy:
      - {LOWER: {IN: ["would", "'d"]}}
      - {LOWER: "rather"}
      - {TAG: "VB"}
negative_matchers:
  # "would rather not" 은 의미가 달라 별도 패턴으로 분리
  - layer: L1
    text: "would rather not"
min_confidence: 0.8
```

**정밀도 우선 원칙**: L1/L2는 confidence 1.0, L3는 0.85, L4는 0.6으로 두고
L4 결과는 검수 큐를 반드시 거친다.

#### [7] 점수화 + 검수 + 업로드

```
score = 0.30 * match_confidence
      + 0.20 * audio_clarity        (배경음악/SNR 추정, 없으면 채널 기본값)
      + 0.15 * sentence_completeness (주어+동사 존재, 문장부호로 종료)
      + 0.10 * duration_fit          (3~10s = 1.0, 2s↓/15s↑ = 0)
      + 0.10 * channel_trust
      + 0.10 * log_normalized_views
      + 0.05 * accent_diversity_bonus

패널티: 욕설/비속어, 광고 구간(스폰서 문구 탐지), wpm > 210 또는 < 90,
        하드섭 존재, 동일 영상에서 이미 3개 이상 채택
```

**중복/다양성 제어**:
- 동일 영상당 패턴별 최대 1개, 전체 최대 3개
- 동일 채널이 패턴 상위 3개를 독점하지 못하게 채널 다양성 강제
- 재업로드 밈 영상 near-dup: `matched_text` MinHash로 제거

**검수 큐**: `review_status = 'pending'` 상태로 업로드 → 간단한 관리자 화면에서
`approved` / `rejected` 판정. 초기 승인율은 40~60% 예상. 이 단계를 건너뛰면
품질 문제가 사용자에게 직접 노출된다.

### 4.2 커버리지 주도 크롤링 루프

전 세계를 인덱싱하지 않는다. **커리큘럼에서 역산한다.**

```python
TARGET_PER_PATTERN = 3   # 최소, 이상적으로 5~10

while True:
    gaps = uncovered_patterns(min_clips=TARGET_PER_PATTERN)
    if not gaps: break
    # 미충족 패턴의 성격에 맞는 채널/장르를 우선 수확
    #   구어/슬랭 부족  → 브이로그, 팟캐스트
    #   격식체 부족     → TED, 강의, 뉴스 인터뷰
    #   기술어휘 부족   → 리뷰, 튜토리얼
    next_batch = prioritize_channels(gaps)
    harvest(next_batch)
    if new_clips_this_round == 0:
        dry_rounds += 1
        if dry_rounds >= 2:
            escalate_to_ondemand(gaps)   # §6
            break
```

**콜드스타트 규모 추정** (영어 발화 ≈ 8,500 단어/시간):

| 목표 | 필요 코퍼스 | 근거 |
|---|---|---|
| 상위 1,000 패턴 (고빈도) | **300~500시간** | 흔한 패턴은 어디에나 나온다 |
| 상위 5,000 패턴 | **2,000~4,000시간** | 중빈도 구간 |
| 관용구·슬랭 꼬리 | 타깃 수확 + 온디맨드 | 무한정 늘려도 안 잡힌다 |

→ **1단계 목표: TED 1,500편(≈450시간)으로 상위 1,000 패턴 커버.** 여기까지가
투자 대비 효율이 가장 좋은 구간이다.

---

## 5. 데이터 모델

### 5.1 저장 경계 (중요)

```
로컬 머신 (진실의 원천)              Supabase Postgres (서빙 캐시)
├── corpus/*.json3      원본 자막      ├── yt_channels     ~300행
├── sentences.parquet   1,500만 문장   ├── yt_videos       ~10만행
│   ≈ 3GB  ← DB에 절대 안 넣는다      ├── patterns        ~5천행
└── match_runs/         매칭 이력      ├── yt_clips        ~10만행 ≈ 40MB
                                        └── card_clips      사용자별
```

Supabase 무료 티어 DB가 500MB이므로 문장 인덱스를 올릴 수 없다. 새 패턴 추가 시
로컬 parquet에서 재매칭 배치를 돌려 확정 클립만 upsert한다.

### 5.2 스키마 (제안 — `supabase/migrations/002_yt_clip_corpus.sql`)

```sql
-- ══ 전역 코퍼스: user_id 없음, 인증 사용자 읽기 전용 ══════════════════

create table public.yt_channels (
  id                   text primary key,          -- UC...
  title                text,
  uploads_playlist_id  text,
  accent               text check (accent in ('us','uk','au','ca','ie','other')),
  caption_kind         text check (caption_kind in ('manual','asr','mixed')),
  license_hint         text check (license_hint in ('standard','creativeCommon')),
  trust_score          real not null default 0.5,
  last_enumerated_at   timestamptz
);

create table public.yt_videos (
  id                 text primary key,            -- 11자 video id
  channel_id         text references public.yt_channels(id) on delete cascade,
  title              text,
  duration_s         int,
  embeddable         boolean,
  age_restricted     boolean not null default false,
  blocked_regions    text[],
  license            text,
  default_audio_lang text,
  caption_kind       text,
  published_at       timestamptz,
  view_count         bigint,
  status             text not null default 'discovered'
    check (status in ('discovered','gated','harvested','segmented','rejected')),
  rejected_reason    text,
  last_checked_at    timestamptz
);
create index yt_videos_status_idx on public.yt_videos (status, last_checked_at);

create table public.patterns (
  id                text primary key,             -- 'would_rather_bare_inf'
  label_ko          text not null,
  label_en          text,
  kind              text not null
    check (kind in ('lexical','phrasal','syntactic','functional')),
  cefr              text,
  matcher           jsonb not null,
  negative_matcher  jsonb not null default '[]'::jsonb,
  clip_count        int not null default 0,       -- 커버리지 루프용 비정규화
  created_at        timestamptz not null default now()
);

create table public.yt_clips (
  id               uuid primary key default gen_random_uuid(),
  video_id         text not null references public.yt_videos(id) on delete cascade,
  pattern_id       text not null references public.patterns(id) on delete cascade,
  start_ms         int not null,
  end_ms           int not null,
  matched_text     text not null,                 -- 매칭된 문장 1개만 저장
  context_before   text,
  context_after    text,
  match_layer      text check (match_layer in ('L1','L2','L3','L4')),
  match_confidence real,
  speech_rate_wpm  int,
  score            real not null default 0,
  review_status    text not null default 'pending'
    check (review_status in ('pending','approved','rejected')),
  reject_reason    text,
  alive            boolean not null default true,
  created_at       timestamptz not null default now()
);
create unique index yt_clips_dedup_idx
  on public.yt_clips (video_id, pattern_id, start_ms);
create index yt_clips_serve_idx
  on public.yt_clips (pattern_id, score desc)
  where review_status = 'approved' and alive;

-- 코퍼스는 읽기 전용 공개, 쓰기는 service_role(로컬 배치)만
alter table public.yt_channels enable row level security;
alter table public.yt_videos   enable row level security;
alter table public.patterns    enable row level security;
alter table public.yt_clips    enable row level security;

create policy "yt_clips: read approved" on public.yt_clips
  for select to authenticated
  using (review_status = 'approved' and alive);
create policy "patterns: read" on public.patterns
  for select to authenticated using (true);
create policy "yt_videos: read" on public.yt_videos
  for select to authenticated using (true);
create policy "yt_channels: read" on public.yt_channels
  for select to authenticated using (true);

grant select on public.yt_channels, public.yt_videos,
               public.patterns, public.yt_clips to authenticated;
grant all    on public.yt_channels, public.yt_videos,
               public.patterns, public.yt_clips to service_role;

-- ══ 사용자 데이터: 이것만 PowerSync로 sync ═══════════════════════════

create table public.card_clips (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  card_id      uuid not null references public.quiz_cards(id) on delete cascade,
  clip_id      uuid references public.yt_clips(id) on delete set null,
  -- 스냅샷: 코퍼스 테이블이 기기로 sync되지 않으므로 재생에 필요한 값을 복사
  video_id     text not null,
  start_ms     int  not null,
  end_ms       int  not null,
  matched_text text,
  clip_kind    text not null default 'authentic'
    check (clip_kind in ('authentic','explainer')),
  rank         int  not null default 0,
  user_action  text check (user_action in ('viewed','liked','skipped','reported', null)),
  created_at   timestamptz not null default now()
);
create unique index card_clips_unique_idx on public.card_clips (card_id, video_id, start_ms);
create index card_clips_card_idx on public.card_clips (user_id, card_id, rank);

alter table public.card_clips enable row level security;
create policy "card_clips: owner access" on public.card_clips
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, update, delete on public.card_clips to authenticated, service_role;

-- ══ quiz_cards ↔ patterns 연결 (누락된 고리, §6 참조) ═════════════════

alter table public.quiz_cards
  add column pattern_id     text references public.patterns(id) on delete set null,
  add column clip_status     text not null default 'pending'
    check (clip_status in ('pending','matched','none','failed'));
```

### 5.3 PowerSync sync stream 추가

`supabase/powersync_sync_streams.yaml` 에 추가. **코퍼스 테이블은 절대 넣지 않는다.**

```yaml
  # ── Card ↔ YouTube clip links (Module C) ───────────────────────────────────
  user_card_clips:
    auto_subscribe: true
    queries:
      - SELECT * FROM card_clips WHERE user_id = auth.user_id()
```

---

## 6. 누락된 고리: 카드 → 패턴 매핑

지금 구조에서 카드는 채팅/저널에서 **자유 텍스트**로 생성된다. 클립을 붙이려면
카드가 어떤 패턴인지 알아야 한다. 이 단계가 현재 설계에 없다.

`enrich-core` / `analyze-session` Edge Function에 추가:

```
카드 생성 (original_text, corrected_text)
  → LLM이 pattern_key 후보 추출 (기존 enrich 프롬프트에 필드 1개 추가)
      "이 문장의 핵심 학습 포인트를 표현 패턴으로 정규화하라"
  → patterns 테이블 매칭
      ├─ 정확 일치        → pattern_id 세팅
      ├─ 임베딩 유사 검색  → 임계값 이상이면 세팅
      └─ 없음             → clip_status='none', 신규 패턴 후보 큐에 적재
  → clips-for-card EF 호출 → 상위 3개 → card_clips insert
      └─ 0개면 clip_status='pending' + 온디맨드 잡 등록
```

`dedup_key`가 카드 중복을 잡는 것과 같은 층위에서, `pattern_id`가 카드를 클립
코퍼스에 연결한다.

**온디맨드 폴백 순서** (클립이 0개일 때 사용자에게 보여줄 것):
1. Track A 해설 클립
2. YouGlish 위젯 (Track B)
3. LLM 생성 예문 (`alternative_examples`, 이미 있음)

동시에 해당 패턴을 커버리지 갭 큐에 넣어 다음 배치에서 수확한다.

---

## 7. 앱 재생 계층

### 7.1 임베드 URL

```
https://www.youtube.com/embed/{video_id}
  ?start={start_s}&end={end_s}
  &autoplay=1&rel=0&modestbranding=1&iv_load_policy=3&cc_load_policy=1
```

`start`/`end`는 **정수 초**라 정밀도가 부족하다. 밀리초 단위 A-B 반복이 필요하면
IFrame Player API를 직접 쓴다:

```js
player.loadVideoById({ videoId, startSeconds: s, endSeconds: e });
// A-B 반복: 200ms 폴링으로 getCurrentTime() >= e 이면 seekTo(s)
```

### 7.2 ⚠️ Windows 플랫폼 리스크

**주 타겟이 Windows인데 `youtube_player_iframe`은 Windows를 지원하지 않는다**
(Android/iOS/macOS/Web만). 이 프로젝트에서 가장 먼저 검증해야 할 기술 리스크다.

권장: 얇은 플랫폼 추상화를 두고 Windows만 분기한다.

```
lib/features/youtube/presentation/
  clip_player.dart              ← ClipPlayer 인터페이스 (videoId, startMs, endMs, loop)
  clip_player_iframe.dart       ← Android/iOS/macOS/Web: youtube_player_iframe
  clip_player_windows.dart      ← Windows: webview_windows(WebView2) + 자체 HTML
  assets/player.html            ← IFrame Player API 호스팅, postMessage 브릿지
```

Windows 쪽은 `webview_windows`로 로컬 `player.html`을 띄우고 Dart ↔ JS를
`postMessage`로 연결한다. `flutter_inappwebview`의 Windows 지원 성숙도도 함께
확인해볼 가치가 있다. 최악의 경우 Windows에서는 기본 브라우저로 열기(열등한 UX).

**착수 전에 스파이크 1개를 먼저 하라**: Windows에서 `webview_windows` + YouTube
iframe이 실제로 재생되는지 확인. 여기서 막히면 전체 기능의 UX 설계가 달라진다.

### 7.3 클립 헬스 체크 (링크 부패)

유튜브 영상은 삭제·비공개·지역차단으로 연 5~10% 사망한다.

`clips-health` Edge Function + cron(주 1회):
```
videos.list(part=status, id=50개씩)  →  1 unit / 50개
  응답에서 누락된 id            → alive=false
  embeddable=false 로 변경      → alive=false
  regionRestriction 에 KR 추가  → alive=false
alive=false 가 되면 해당 패턴의 clip_count 재계산 → 부족하면 갭 큐로
```
10만 영상 = 2,000 units. 할당량 걱정 없다. 이건 클라우드에서 돌려도 된다
(공식 API라 IP 차단 없음).

---

## 8. 법적·ToS 경계

정확히 짚어둘 것:

| 행위 | 판단 |
|---|---|
| 공식 iframe 플레이어로 임베드 재생 | **허용됨.** 유튜브가 권장하는 방식 |
| `start`/`end`로 구간만 재생 | **허용됨.** 공식 파라미터 |
| 스트림 추출·재호스팅·다운로드 후 재생 | **금지.** 하지 않는다 |
| 광고/브랜딩 우회 | **금지.** 하지 않는다 |
| 제3자 영상 자막을 `timedtext`에서 수집 | **회색 지대.** 공식 API 미제공 경로 |

자막 수집 리스크를 낮추는 방법(권장 순서):

1. **CC BY 영상만 수집** — `status.license == 'creativeCommon'`
2. **TED/TEDx** — 트랜스크립트가 공개되어 있다 (CC BY-NC-ND: 재배포 아닌 인덱싱 용도)
3. **연구용 공개 데이터셋** — video ID + 트랜스크립트 쌍을 이미 배포하는 것들
   (HowTo100M, YT-Temporal 계열 등). 라이선스 개별 확인 필요
4. **전체 자막을 서비스에 노출하지 않는다** — DB에는 매칭 문장 1개 + 앞뒤 문맥만
   저장하고, 나머지는 항상 유튜브 임베드로 재생. 이게 §5.1 저장 경계와 일치한다
5. **상업화 시** — 유료 관리형 transcript API로 전환하거나 채널 소유자와 협의

개인 학습용 로컬 인덱스와 공개 상업 서비스의 리스크 등급은 다르다. 유료화 시점에
4~5번을 재검토할 것.

---

## 9. 저장소 구조 (제안)

```
tools/corpus/                      ← 로컬 배치 (Python, 앱 빌드와 무관)
  channels.yaml                    ← 화이트리스트
  patterns/*.yaml                  ← 패턴 스펙
  01_enumerate.py                  ← playlistItems 열거
  02_gate.py                       ← videos.list 게이트
  03_harvest.py                    ← yt-dlp 자막 수확
  04_segment.py                    ← 구두점 복원 + 문장 분할 + 타이밍 정렬
  05_match.py                      ← L1~L4 패턴 매칭
  06_score_upload.py               ← 점수화 + Supabase upsert
  07_coverage.py                   ← 갭 리포트
  requirements.txt

supabase/
  migrations/002_yt_clip_corpus.sql
  functions/clips-for-card/        ← 카드 → 상위 3개 클립
  functions/clips-health/          ← cron 생존 확인
  functions/patterns-match/        ← 텍스트 → pattern_id (enrich 파이프라인용)

lib/features/youtube/
  domain/clip_model.dart
  domain/pattern_model.dart
  data/clip_repository.dart        ← card_clips 로컬 CRUD + EF 호출
  presentation/clip_player*.dart   ← §7.2 플랫폼 분기
  presentation/clip_carousel.dart  ← 카드 하단 3탭

tools/review/                      ← 검수 화면 (간단한 Flutter 탭 or 웹 페이지)
```

---

## 10. 실행 순서

| # | 작업 | 산출물 | 예상 |
|---|---|---|---|
| 0 | **Windows WebView 스파이크** | `webview_windows`로 유튜브 클립 재생 확인 | 0.5일 |
| 1 | 스키마 마이그레이션 002 + sync stream | 테이블 5개 | 0.5일 |
| 2 | Track B: YouGlish 위젯 탭 | 카드에서 "더 많은 예" 동작 | 0.5일 |
| 3 | Track A: 채널 열거 + 제목/챕터 인덱스 | 해설 클립 서빙 | 2일 |
| 4 | 패턴 사전 v1 (상위 300개) | `patterns/*.yaml` | 2일 |
| 5 | enrich에 `pattern_id` 매핑 추가 (§6) | 카드↔패턴 연결 | 1일 |
| 6 | Track C 파이프라인 [4]~[6] | TED 1,500편 인덱싱 | 1주 |
| 7 | 점수화 + 검수 화면 | approved 클립 서빙 | 3일 |
| 8 | 커버리지 루프 + 헬스 cron | 자동 확장 | 2일 |

**2번 → 0번 → 3번 순으로 착수하면 1주 안에 사용자가 볼 수 있는 것이 나온다.**
Track C는 그 뒤에 품질을 올리는 작업이다.

## 11. 측정 지표

| 지표 | 목표 |
|---|---|
| 패턴 커버리지 (클립 ≥3개) | 상위 1,000 패턴의 80% |
| 검수 승인율 | 60% 이상 (낮으면 매칭 정밀도 문제) |
| 사용자 스킵률 (`user_action='skipped'`) | 30% 이하 |
| 클립 사망률 (연간) | 10% 이하, 헬스 cron으로 자동 복구 |
| 카드당 클립 노출 지연 | 500ms 이하 (card_clips 로컬 조회) |

---

## 참고 자료

- [YouTube Data API — search.list](https://developers.google.com/youtube/v3/docs/search/list)
- [YouTube Data API — playlistItems.list](https://developers.google.com/youtube/v3/docs/playlistItems/list)
- [YouTube Data API — 할당량](https://developers.google.com/youtube/v3/getting-started)
- [YouTube IFrame Player API](https://developers.google.com/youtube/iframe_api_reference)
- [YouGlish Widget](https://youglish.com/api/doc/widget) / [JS API](https://youglish.com/api/doc/js-api)
- [youtube-transcript-api — 클라우드 IP 차단 이슈 #593](https://github.com/jdepoix/youtube-transcript-api/issues/593)
- [youtube_player_iframe (Windows 미지원)](https://pub.dev/packages/youtube_player_iframe)
- [webview_windows](https://pub.dev/packages/webview_windows)
