# YouTube 클립 소스 수집 전략 (정책 준수판)

카드(표현/단어/패턴)에 **실제 원어민이 그걸 쓰는 유튜브 클립**을 붙이기 위한
수집·인덱싱·서빙 설계. **YouTube 약관을 위반하지 않는 것을 절대 제약으로 둔다.**

- 관련 기존 설계: `AGENT_CONTEXT.md`
- 이 문서는 이전 리비전(자막 직접 스크래핑 전제)을 **대체**한다.

> ⚠️ `quiz_cards.source_type = 'youtube'`(카드의 *출처*가 유튜브)와 이 기능(카드에
> 유튜브 *예시*를 붙임)은 서로 다른 것이다. 별도 테이블(`card_clips`)로 다룬다.

---

## 0. 결론

**스크래핑 없이 만들 수 있다.** 유튜브를 긁는 대신, **이미 공개 라이선스로
재배포되고 있는 데이터셋**에서 `(video_id, 문장, 시작·종료 시각)`을 얻는다.
유튜브에는 **공식 iframe 재생과 공식 API 메타데이터 조회만** 요청한다.

| 층 | 무엇 | 어디서 | 약관 노출 |
|---|---|---|---|
| 문장 + 타임스탬프 | **YODAS** (CC 라이선스 영상만) | HuggingFace | 없음 — 유튜브 미접촉 |
| 영상 메타데이터 | `videos.list` | 공식 API | 30일 갱신 규칙 준수 |
| 재생 | 공식 iframe `start`/`end` | 공식 임베드 | 권장 방식 |
| 커버리지 공백 | 운영자 수동 캡처 도구 | 사람이 유튜브 UI 사용 | 자동화 아님 |

**핵심 통찰 3개:**

1. **저작권 층과 플랫폼 약관 층은 별개다.** CC BY는 *저작권*을 해결하지만
   *YouTube 접근 약관*은 해결하지 않는다. 이걸 혼동하는 게 이 문제에서 가장 흔한
   실수다. → 해법: 유튜브에서 자막을 가져오지 말고, **제3자가 재배포하는 공개
   라이선스 데이터셋에서** 가져온다. 그러면 두 층이 동시에 해결된다.
2. **수작업이 불가피한 부분이라면, 수작업을 빠르게 만드는 데 공수를 쓴다.** 원시
   복붙(클립당 3분) 대신 캡처 도구(클립당 15초)를 만든다.
3. **패턴을 찾지 말고 문장을 모은다.** 수집과 매칭을 분리하면 한 번 캡처한 문장이
   여러 패턴에 동시 매칭되고, 나중에 추가한 패턴이 과거 캡처에 소급 적용된다.
   수작업 비용이 패턴 수에 비례하지 않고 **누적**된다.

> **24시간 크롤러 + 자체 ASR 방식을 검토했는가?** → **§14.** 결론: 크롤러는 만든다.
> 7단계 중 6단계가 합법이고, 막히는 한 단계(음성 확보)는 **제작자 서면 허가**로
> 뚫는다. 병목은 통념과 달리 "서칭"이 아니다.

---

## 1. 검증된 제약 사실

직접 확인한 것(2026-08). 설계가 여기서 도출된다.

| # | 사실 | 함의 | 근거 |
|---|---|---|---|
| 1 | `search.list`의 `q`는 제목/설명/태그/채널명만 검색 | 표현으로 영상 검색 **불가** | [docs](https://developers.google.com/youtube/v3/docs/search/list) |
| 2 | `captions.list` / `captions.download`는 **영상 소유자 OAuth 필요**, 타인 영상은 403 | 공식 자막 경로 **없음** | [captions.list](https://developers.google.com/youtube/v3/docs/captions/list) |
| 3 | `search.list` = 100 units, `playlistItems`·`videos.list` = 1 unit/50개 | 검색 대신 열거 | [할당량](https://developers.google.com/youtube/v3/getting-started) |
| 4 | **Non-Authorized Data는 30일 초과 저장 금지 — 이후 삭제 또는 갱신 필수** | 30일 크론이 **의무** | [Developer Policies](https://developers.google.com/youtube/terms/developer-policies) |
| 5 | **30일마다 영상 삭제 여부 확인 의무** | 같은 크론에 통합 | 위와 동일 |
| 6 | **YouTube 시청각 콘텐츠 캐싱 금지** | 영상/음성 재호스팅 불가, 재생은 iframe만 | 위와 동일 |
| 7 | `timedtext` 엔드포인트가 클라우드 IP 차단 | 서버리스 자막 수집 불가 | [issue #593](https://github.com/jdepoix/youtube-transcript-api/issues/593) |
| 8 | **YouGlish: API 외부 경로로 얻은 콘텐츠의 저장·표시·전송 금지. 상업적 사용은 별도 허가 필요** | 아래 §2 참조 | [YouGlish ToS](https://youglish.com/terms) |
| 9 | `youtube_player_iframe`은 Windows 미지원 | 주 타겟 플랫폼 리스크 | [pub.dev](https://pub.dev/packages/youtube_player_iframe) |

### 사실 4·5·6이 이전 설계를 바꾼다

이전 리비전은 `yt_videos`에 제목·조회수를 무기한 보관하고 헬스 체크를 "최적화"로
취급했다. **틀렸다.** API에서 받은 메타데이터는 30일 내 삭제 또는 갱신해야 하고,
영상 생존 확인도 30일 의무다. → §6의 크론은 선택이 아니라 **컴플라이언스 요건**이다.

---

## 2. ⚠️ YouGlish 수작업 저장 계획은 오히려 위반이다

> "정 어렵다면 YouGlish를 수작업으로 검색해서 저장이라도 할거야"

이 계획은 의도와 반대로 **가장 위험한 경로**다. YouGlish ToS는
"API 외부의 어떤 기술이나 소프트웨어로 얻은 YouGlish 콘텐츠도 **접근·저장·표시·전송
금지**"라고 명시한다. YouGlish가 큐레이션한 `(영상, 타임스탬프, 문장)` 조합을
당신 DB에 옮기는 것은 정확히 이 조항에 해당한다. 수작업이어도 마찬가지다 —
조항이 자동화 여부로 구분하지 않는다. 게다가 **상업적 사용은 명시적 허가가 필요**하다.

**대신 이렇게 쓴다:**

| 쓸 수 있는 것 | 쓸 수 없는 것 |
|---|---|
| 위젯을 **라이브 임베드** ("더 많은 예" 탭) | 결과를 DB에 저장 |
| partner key 발급받아 JS API로 제어 | 결과를 자체 클립으로 재가공 |
| 상업화 시 YouGlish에 사전 허가 요청 | 허가 없이 유료 앱에 탑재 |

즉 YouGlish는 **당신이 저장하지 않는 라이브 컴포넌트**로만 쓴다. 그러면 법적 부담이
YouGlish 쪽에 남고 당신은 위젯 사용자일 뿐이다. 저장이 필요한 클립은 §3·§5에서
자체 확보한다.

---

## 3. 데이터 출처: YODAS (본 전략의 핵심)

### 3.1 왜 이게 정답인가

[YODAS](https://huggingface.co/datasets/espnet/yodas) (YouTube-Oriented Dataset for
Audio and Speech, ESPnet):

- **CC 라이선스 영상만** 수집해 구성되었고, 데이터셋 자체가 Creative Commons로 배포됨
- 필드: `video_id`, `duration`, `audio` / 발화 단위로 `utt_id`, `text`,
  **`start`, `end`(초)** ← 우리가 필요한 전부
- **`manual` 서브셋 = 사람이 올린 자막** (파일명 첫 자리 `0`), `automatic` = 자동 자막(`1`)
  → **`manual`만 쓰면 정확도 문제가 대부분 사라진다**
- 500k+ 시간, 100+ 언어. 영어 샤드(`en000`, `en001`, …)가 대규모
- `YODAS2` = 분할 안 된 롱폼 버전 (동일 데이터, 영상 단위)

**얻는 것:**
```
video_id  →  공식 iframe 임베드
text      →  문장 (패턴 매칭 대상)
start,end →  클립 경계
audio     →  (선택) WhisperX로 단어 단위 정렬 정밀화
license   →  CC BY → 상업적 사용도 출처 표기하면 가능
```

**유튜브를 한 번도 긁지 않는다.** 자막·타임스탬프·음성 전부 HuggingFace에서 온다.
유튜브에는 공식 API 메타 조회와 공식 iframe 재생만 요청한다.

### 3.2 보조 출처

| 출처 | 라이선스 | 타임스탬프 | 용도 |
|---|---|---|---|
| **YODAS `manual` (영어)** | CC | ✅ 발화 단위 | **1순위 주력** |
| YODAS `automatic` | CC | ✅ | 커버리지 보강 (구두점 복원 필요) |
| [YouTube-Commons](https://huggingface.co/datasets/PleIAs/YouTube-Commons) | CC-BY | ❌ (본문만) | **CC-BY video_id 화이트리스트**로 활용 |
| MIT OCW | CC BY-**NC**-SA | ✅ (.vtt 배포) | 학술 영어. **비상업만** |
| TED / TED-LIUM | CC BY-**NC**-ND | ✅ | 발표 영어. **비상업만** |
| 미 연방정부 채널 | 공공 도메인 | 대개 ✅ (.gov) | 격식체. 제약 없음 |

**NC(비상업) 표시 주의**: 앱을 유료화할 계획이면 MIT OCW·TED는 못 쓴다. YODAS와
YouTube-Commons는 CC BY(NC 아님)라 출처 표기만으로 상업적 사용이 가능하다.
→ **처음부터 CC BY 소스만으로 구성하는 게 나중에 라이선스 재작업을 없앤다.**

### 3.3 YouTube-Commons에는 타임스탬프가 없다

`video_id, video_link, title, text, channel, channel_id, date, license,
original_language, word_count, character_count` — **본문 통짜 텍스트만** 있고 구간
정보가 없다. 그래서 클립 재생에는 단독으로 못 쓴다.

대신 **2백만 개 CC-BY video_id 목록**으로서 가치가 있다. YODAS와 교집합을 내거나,
수동 캡처 대상 후보를 고를 때 "이건 CC-BY 영상"이라는 사전 필터로 쓴다.

### 3.4 ⚠️ Step 0 — 착수 전 검증 항목

아래는 **직접 확인하지 못했다.** 코드를 쓰기 전에 로컬에서 확인할 것.

```bash
pip install datasets huggingface_hub
python - <<'PY'
from datasets import load_dataset
# 1) 영어 manual 샤드가 실제로 존재하고 로드되는지
ds = load_dataset("espnet/yodas", "en000", split="train", streaming=True)
row = next(iter(ds))
print(row.keys())                 # 2) utt 단위 start/end 필드 실제 이름 확인
print({k: row[k] for k in row if k != "audio"})
PY
```

확인할 것:
1. **영어 `manual` 서브셋 규모** — 목표 400~500시간(§7 콜드스타트)에 충분한가
2. **`start`/`end` 단위** — 초(float)인지, 문서와 실제가 일치하는지
3. **라이선스 정확한 변종** — 데이터셋 카드에 CC BY 몇 조인지, 서브셋별로 다른지
4. **`audio` 재배포 포함 여부** — 서브셋에 따라 다를 수 있음
5. **다운로드 용량** — 영어 전체는 TB급일 수 있음. 스트리밍 모드로 텍스트만 뽑는 경로 확인

**5번이 실무적으로 가장 중요하다.** 음성이 필요 없다면(§4.3 참조) 텍스트+타임스탬프만
스트리밍으로 추출해 디스크 수 GB로 끝낼 수 있다.

---

## 4. 파이프라인

```
[HuggingFace]                      [로컬 Windows 배치]           [Supabase]        [앱]
YODAS manual  ──1──▶ 문장 정규화 ──2──▶ 패턴 매칭 ──3──▶ 점수화 ──4──▶ yt_clips ──▶ iframe
                                                              │       (approved)
YouTube-Commons ─▶ CC-BY id 필터                        검수 ──┘
                                                                yt_videos ◀─5── videos.list
                                                                              (30일 갱신 크론)
```

### [1] 문장 정규화

YODAS 발화 단위는 자막 큐 기준이라 문장 경계와 어긋난다.

```python
# 1-1) 같은 video_id의 발화를 시간순 연결 (utt, start, end)
# 1-2) automatic 서브셋이면 구두점·대문자 복원
#      → deepmultilingualpunctuation 또는 gpt-4o-mini 배치
#      → manual 서브셋은 이미 구두점이 있으므로 건너뜀 (manual 우선 이유)
# 1-3) 문장 분할 (spaCy sentencizer)
# 1-4) 문장 ↔ 발화 타이밍 재정렬
#      sentence.start = 첫 발화의 start (문장이 발화 중간에서 시작하면 비례 보간)
#      sentence.end   = 마지막 발화의 end
# 1-5) 파생 컬럼
#      text_norm  : 소문자, 축약 정규화
#      lemma_text : spaCy 표제어 시퀀스
#      pos_text   : POS 시퀀스
#      wpm        : 발화 속도
```

**클립 경계**:
```
clip.start = sentence.start - 250ms
clip.end   = sentence.end   + 400ms
문맥 필요 패턴은 preroll 옵션으로 앞 1문장 포함
```

발화 단위 타이밍은 정밀도가 ±0.5s 수준이다. 더 필요하면 §4.3.

### [2] 패턴 매칭 — 4계층

`patterns.matcher` jsonb 스펙으로 계층을 선언한다.

| 계층 | 대상 | 구현 | 예 | confidence |
|---|---|---|---|---|
| **L1** | 고정 표현 | `text_norm` 구문 검색 | `long story short` | 1.0 |
| **L2** | 굴절 허용 | `lemma_text` 검색 | `get used to` → *got/getting used to* | 0.95 |
| **L3** | 문법 패턴 | spaCy `Matcher`/`DependencyMatcher` | `would rather + 동사원형` | 0.85 |
| **L4** | 기능적 표현 | 문장 임베딩 최근접 | "정중하게 거절하기" | 0.6 |

```yaml
# tools/corpus/patterns/would_rather.yaml
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
  - layer: L1
    text: "would rather not"   # 의미가 달라 별도 패턴으로 분리
min_confidence: 0.8
```

**정밀도 우선.** L4 결과는 반드시 검수를 거친다. 오탐 클립 1개가 학습자에게 주는
손해가 미탐 1개보다 크다.

### [3] 점수화

```
score = 0.30 * match_confidence
      + 0.20 * transcript_quality      (manual=1.0, automatic=0.6, whisperx=0.8)
      + 0.15 * sentence_completeness   (주어+동사 존재, 문장부호 종료)
      + 0.10 * duration_fit            (3~10s=1.0, 2s↓/15s↑=0)
      + 0.10 * timing_confidence
      + 0.10 * channel_trust
      + 0.05 * accent_diversity_bonus

패널티: 욕설/비속어, wpm > 210 또는 < 90, 문장 3어절 이하,
        동일 영상에서 이미 3개 채택
```

**다양성 제어**: 영상당 패턴별 최대 1개·전체 최대 3개, 채널 독점 방지,
`matched_text` MinHash로 재업로드 중복 제거.

**검수 큐**: `review_status='pending'`으로 업로드 → 관리자 화면에서 승인/거부.
초기 승인율 60% 미만이면 매칭 정밀도를 손봐야 한다는 신호.

### [4] 업로드

`score_upload.py`가 **확정 클립만** service_role로 upsert한다. §5.1 저장 경계 참조.

### [5] 메타데이터 조회 + 30일 갱신 (컴플라이언스 필수)

`videos.list(part=status,contentDetails,snippet,statistics, id=50개씩)` = 1 unit/50.

```
게이트(최초):
  status.embeddable == false                → 거부 (임베드 불가)
  status.license   != 'creativeCommon'      → 거부 (CC 아님 → 라이선스 근거 소실)
  contentDetails.contentRating 연령제한      → 거부
  regionRestriction.blocked 에 KR 포함       → 거부
  duration < 30s or > 3600s                 → 거부

30일 크론 (사실 4·5·6):
  응답에서 id 누락                → alive=false  (삭제/비공개 확인 의무)
  embeddable false로 변경         → alive=false
  license가 CC에서 이탈           → alive=false  ★ 라이선스 드리프트
  regionRestriction에 KR 추가     → alive=false
  title/view_count 등             → 갱신 (또는 삭제) ★ 30일 초과 저장 금지
  metadata_refreshed_at = now()
```

★ **라이선스 드리프트**: 제작자가 나중에 CC BY를 표준 라이선스로 되돌릴 수 있다.
CC 라이선스 자체는 철회 불가지만, 제작자 의사를 존중하고 근거를 유지하기 위해
갱신 시 이탈한 영상은 서빙에서 내린다.

10만 영상 = 2,000 units → 할당량 여유 충분. **이건 공식 API라 클라우드에서 돌려도
IP 차단이 없다** → Supabase Edge Function + cron으로 구현 가능.

---

## 5. 데이터 모델

### 5.1 저장 경계

```
로컬 머신 (진실의 원천, 재처리 자유)     Supabase Postgres (서빙 캐시, 500MB 무료 티어)
├── yodas/  텍스트+타임스탬프 (수 GB)   ├── yt_channels   ~수천행 (출처 표기용)
├── sentences.parquet  수백만~천만 문장  ├── yt_videos     ~10만행 (30일 갱신 대상)
│   ← DB에 절대 안 넣는다               ├── patterns      ~5천행
└── match_runs/  매칭 이력               ├── yt_clips      ~10만행 ≈ 40MB
                                          └── card_clips    사용자별 (PowerSync sync)
```

문장 인덱스는 GB급이라 무료 티어 DB에 못 넣는다. 새 패턴 추가 시 로컬 parquet에서
재매칭 배치를 돌려 확정 클립만 upsert한다.

### 5.2 스키마 (`supabase/migrations/002_yt_clip_corpus.sql`)

```sql
-- ══ 전역 코퍼스: user_id 없음, 인증 사용자 읽기 전용 ══════════════════

create table public.yt_channels (
  id                text primary key,          -- UC...
  title             text,
  accent            text check (accent in ('us','uk','au','ca','ie','other')),
  trust_score       real not null default 0.5,
  -- CC BY 출처 표기 의무 (§8.4)
  attribution_name  text,
  attribution_url   text,
  -- 제작자 서면 허가 (§14.5-①). 크롤러의 음성 확보 단계는 granted 만 대상
  permission_status text not null default 'none'
    check (permission_status in ('none','requested','granted','denied','withdrawn')),
  permission_at     timestamptz,
  permission_note   text                       -- 증빙 위치 (tools/corpus/permissions/*.yaml)
);
create index yt_channels_permission_idx on public.yt_channels (permission_status);

create table public.yt_videos (
  id                    text primary key,      -- 11자 video id (무기한 보관 가능)
  channel_id            text references public.yt_channels(id) on delete cascade,
  title                 text,                  -- ★ API Data → 30일 내 갱신/삭제
  duration_s            int,
  license               text,                  -- 'creativeCommon' 만 서빙
  embeddable            boolean,
  age_restricted        boolean not null default false,
  blocked_regions       text[],
  default_audio_lang    text,
  source_dataset        text check (source_dataset in ('yodas','ytcommons','manual')),
  transcript_source     text check (transcript_source in
                          ('yodas_manual','yodas_auto','whisperx','human')),
  status                text not null default 'discovered'
    check (status in ('discovered','gated','indexed','rejected')),
  rejected_reason       text,
  alive                 boolean not null default true,
  metadata_refreshed_at timestamptz            -- ★ 30일 크론이 갱신
);
create index yt_videos_refresh_idx
  on public.yt_videos (metadata_refreshed_at nulls first) where alive;

create table public.patterns (
  id               text primary key,           -- 'would_rather_bare_inf'
  label_ko         text not null,
  label_en         text,
  kind             text not null
    check (kind in ('lexical','phrasal','syntactic','functional')),
  cefr             text,
  matcher          jsonb not null,
  negative_matcher jsonb not null default '[]'::jsonb,
  clip_count       int not null default 0,     -- 커버리지 루프용 비정규화
  created_at       timestamptz not null default now()
);

create table public.yt_clips (
  id                 uuid primary key default gen_random_uuid(),
  video_id           text not null references public.yt_videos(id) on delete cascade,
  pattern_id         text not null references public.patterns(id) on delete cascade,
  start_ms           int not null,
  end_ms             int not null,
  matched_text       text not null,            -- 매칭된 문장 1개만 (§8)
  context_before     text,
  context_after      text,
  match_layer        text check (match_layer in ('L1','L2','L3','L4')),
  match_confidence   real,
  timing_confidence  real,
  speech_rate_wpm    int,
  capture_mode       text not null default 'dataset'
    check (capture_mode in ('dataset','manual')),
  score              real not null default 0,
  review_status      text not null default 'pending'
    check (review_status in ('pending','approved','rejected')),
  reject_reason      text,
  takedown_requested boolean not null default false,   -- §8
  created_at         timestamptz not null default now()
);
create unique index yt_clips_dedup_idx
  on public.yt_clips (video_id, pattern_id, start_ms);
create index yt_clips_serve_idx on public.yt_clips (pattern_id, score desc)
  where review_status = 'approved' and not takedown_requested;

alter table public.yt_channels enable row level security;
alter table public.yt_videos   enable row level security;
alter table public.patterns    enable row level security;
alter table public.yt_clips    enable row level security;

-- 살아있고 승인된 클립만 노출
create policy "yt_clips: read approved" on public.yt_clips
  for select to authenticated
  using (review_status = 'approved' and not takedown_requested
         and exists (select 1 from public.yt_videos v
                     where v.id = video_id and v.alive));
create policy "yt_videos: read alive" on public.yt_videos
  for select to authenticated using (alive);
create policy "patterns: read"  on public.patterns  for select to authenticated using (true);
create policy "yt_channels: read" on public.yt_channels for select to authenticated using (true);

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
  -- 스냅샷: 코퍼스 테이블은 기기로 sync되지 않으므로 재생 필수값만 복사
  video_id     text not null,
  start_ms     int  not null,
  end_ms       int  not null,
  matched_text text,
  attribution  text,                            -- CC BY 표기 문자열 (§8)
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

-- ══ quiz_cards ↔ patterns 연결 (누락된 고리, §6) ══════════════════════

alter table public.quiz_cards
  add column pattern_id  text references public.patterns(id) on delete set null,
  add column clip_status text not null default 'pending'
    check (clip_status in ('pending','matched','none','failed'));
```

### 5.3 PowerSync sync stream

`supabase/powersync_sync_streams.yaml`에 추가. **코퍼스 테이블은 넣지 않는다.**

```yaml
  # ── Card ↔ YouTube clip links (Module C) ───────────────────────────────────
  user_card_clips:
    auto_subscribe: true
    queries:
      - SELECT * FROM card_clips WHERE user_id = auth.user_id()
```

---

## 6. 누락된 고리: 카드 → 패턴 매핑

카드는 채팅/저널에서 **자유 텍스트**로 생성된다. 클립을 붙이려면 그 카드가 어떤
패턴인지 알아야 한다. 이 단계가 현재 설계에 없다.

`enrich-core` / `analyze-session`에 추가:

```
카드 생성 (original_text, corrected_text)
  → LLM이 pattern_key 후보 추출 (기존 enrich 프롬프트에 필드 1개 추가)
  → patterns 매칭:  정확 일치 → 임베딩 유사 검색 → 없으면 신규 패턴 후보 큐
  → clips-for-card EF → 상위 3개 → card_clips insert
  → 0개면 clip_status='pending' + 커버리지 갭 큐 등록
```

`dedup_key`가 카드 중복을 잡는 것과 같은 층위에서 `pattern_id`가 카드를 코퍼스에
연결한다.

**클립 0개일 때 폴백 순서:**
1. 같은 패턴의 낮은 점수 클립 (score 임계 완화)
2. YouGlish 위젯 라이브 임베드 (§2 — 저장 안 함)
3. LLM 생성 예문 (`alternative_examples`, 이미 있음)

---

## 7. 커버리지와 규모

### 7.1 커버리지 주도 루프

전 세계를 인덱싱하지 않는다. **커리큘럼에서 역산한다.**

```python
TARGET_PER_PATTERN = 3

while True:
    gaps = uncovered_patterns(min_clips=TARGET_PER_PATTERN)
    if not gaps: break
    # 미충족 패턴 성격에 맞는 YODAS 샤드/채널을 우선 처리
    #   구어·슬랭 부족 → 브이로그·팟캐스트 채널
    #   격식체 부족    → 강의·인터뷰
    process(prioritize_shards(gaps))
    if new_clips_this_round == 0:
        dry_rounds += 1
        if dry_rounds >= 2:
            enqueue_manual_capture(gaps)   # §8로 위임
            break
```

### 7.2 콜드스타트 규모 (영어 발화 ≈ 8,500 단어/시간)

| 목표 | 필요 코퍼스 | 비고 |
|---|---|---|
| 상위 1,000 패턴 | **300~500시간** | 고빈도는 어디에나 나온다 |
| 상위 5,000 패턴 | **2,000~4,000시간** | 중빈도 구간 |
| 관용구·슬랭 꼬리 | 수동 캡처 | 무한정 늘려도 안 잡힌다 |

**1단계 목표: YODAS 영어 `manual` 400~500시간으로 상위 1,000 패턴 커버.**
투자 대비 효율이 가장 좋은 구간이다.

### 7.3 CC BY 코퍼스의 약점 — 정직하게

공개 라이선스 영상은 **강의·발표·튜토리얼에 편중**되고 **일상 회화가 얕다.**
그래서 회화체·슬랭·구어 축약은 YODAS로 잘 안 채워진다. 이 공백이 §8 수동 캡처가
존재하는 이유다. 두 트랙은 경쟁이 아니라 **역할 분담**이다.

---

## 8. 수동 캡처 트랙 — "수작업이라도" 를 제대로 만들기

YODAS가 못 채우는 회화체를 사람이 채운다. 단, **원시 복붙이 아니라 도구로.**

### 8.1 법적 근거

| 항목 | 판단 |
|---|---|
| 사람이 유튜브 웹 UI의 "자막 표시" 기능을 보며 문장 1개를 기록 | 유튜브가 사용자에게 제공하는 기능의 정상 사용. 자동화 아님 |
| 문장 **1개 + 포인터(video_id·시각)** 저장 | 인용 범위. 사전·코퍼스 언어학(COCA/BNC 용례행)이 오래 해온 방식 |
| 전체 자막 미러링 | **하지 않는다** |
| 재생 | 공식 iframe. 제작자에게 조회수·수익이 정상 귀속 |

**지키는 선:**
- 클립당 **문장 1개**(+앞뒤 1문장 문맥)만 저장. 전체 자막은 절대 저장하지 않는다
- 영상·음성 파일을 저장하거나 재호스팅하지 않는다 (사실 6)
- `takedown_requested` 플래그와 신고 경로를 처음부터 만들어 둔다
- CC BY 소스는 §8.4의 출처 표기를 UI에 노출

이건 법률 자문이 아니라 설계 판단이다. 유료화 시점에 재검토할 것.

### 8.2 ★ 핵심 아키텍처: 캡처와 매칭을 분리한다

```
❌ 나쁜 방식:  패턴 목록을 들고 → 패턴마다 영상을 찾아 → 클립 1개 확보
               비용 = 패턴 수 × 3분.  5,000패턴 = 250시간. 불가능.

✅ 좋은 방식:  영상을 보며 → 좋은 문장을 캡처 → 나중에 패턴 매칭
               캡처된 문장 1개가 평균 1.8개 패턴에 동시 매칭.
               새 패턴 추가 시 과거 캡처에 소급 적용.
               비용이 패턴 수에 비례하지 않고 누적된다.
```

이 분리가 수동 트랙을 실현 가능하게 만드는 유일한 이유다.

### 8.3 캡처 도구 설계

```
tools/capture/  (Flutter Windows 앱 or Electron — 재사용 가능하면 앱 내 탭)
  ├─ WebView에 공식 embed 로드 (webview_windows, §9와 동일 스택)
  ├─ 재생 중 전역 단축키 Ctrl+Space
  │    → IFrame API getCurrentTime() 으로 현재 시각 확보
  │    → 자동으로 -3.0s 되감기 (사람 반응 지연 보정) 후 구간 반복 재생
  ├─ 문장 입력창: 유튜브 자막 UI를 보며 붙여넣기 또는 타이핑
  ├─ 경계 미세조정: ←/→ 로 start/end 100ms 단위 이동, 즉시 미리듣기
  └─ 저장: video_id, start_ms, end_ms, sentence, note
        → capture_mode='manual', review_status='approved' (본인 캡처는 검수 통과)

후처리 배치 (자동):
  ├─ LLM이 문장을 정규화하고 포함된 패턴을 다중 태깅
  │    "이 문장에 들어있는 학습 가치 있는 표현 패턴을 모두 나열하라"
  ├─ 기존 patterns와 매칭 → yt_clips 다중 insert (문장 1개 → 클립 N개)
  ├─ 신규 패턴 후보는 큐에 적재 (사람이 승인하면 patterns에 등록)
  └─ videos.list로 게이트 통과 확인 (§4-[5])
```

**목표 속도: 클립당 15~20초.** 20분 영상 1편에서 15~30 문장.

### 8.4 CC BY 출처 표기 (의무)

CC BY는 **출처 표기가 조건**이다. 클립 UI에 반드시 노출:

```
채널명 · CC BY 3.0 · 원본 보기
└ 예: "English with Alice · CC BY 3.0 · youtube.com/watch?v=XXX&t=123s"
```

`yt_channels.attribution_name` / `attribution_url`, `card_clips.attribution`에
저장해 오프라인에서도 표기가 유지되게 한다. 구간만 재생하므로 "발췌(excerpt)"임을
함께 표시한다.

### 8.5 처리량 계산 — 실현 가능한가

```
하루 30분 캡처 × 클립당 20초  →  약 90 문장/일
문장당 평균 1.8 패턴 매칭      →  약 160 패턴-클립/일
상위 500 패턴 × 3개 = 1,500개  →  약 10일
상위 1,000 패턴 × 3개 = 3,000개 →  약 19일
```

**하루 30분씩 3주면 상위 1,000 패턴을 수동만으로 채울 수 있다.**
YODAS와 병행하면 훨씬 빨라진다. 수작업 폴백은 허황된 계획이 아니다 — 단 §8.2의
분리 구조가 전제다.

---

## 9. 앱 재생 계층

### 9.1 임베드 URL

```
https://www.youtube.com/embed/{video_id}
  ?start={start_s}&end={end_s}
  &autoplay=1&rel=0&modestbranding=1&iv_load_policy=3&cc_load_policy=1
```

`start`/`end`는 **정수 초**라 정밀도가 부족하다. 밀리초 A-B 반복은 IFrame API 직접 사용:

```js
player.loadVideoById({ videoId, startSeconds: s, endSeconds: e });
// A-B 반복: 200ms 폴링으로 getCurrentTime() >= e 이면 seekTo(s)
```

**금지 사항 재확인**: 스트림 추출·다운로드·재호스팅 금지(사실 6), 광고/브랜딩
우회 금지. 재생은 항상 공식 플레이어.

### 9.2 ⚠️ Windows 플랫폼 리스크 — 가장 먼저 검증할 것

**주 타겟이 Windows인데 `youtube_player_iframe`은 Windows를 지원하지 않는다**
(Android/iOS/macOS/Web만). 이 프로젝트 최대 기술 리스크다.

```
lib/features/youtube/presentation/
  clip_player.dart              ← ClipPlayer 인터페이스 (videoId, startMs, endMs, loop)
  clip_player_iframe.dart       ← Android/iOS/macOS/Web: youtube_player_iframe
  clip_player_windows.dart      ← Windows: webview_windows(WebView2) + 자체 HTML
  assets/player.html            ← IFrame Player API 호스팅, postMessage 브릿지
```

`webview_windows`로 로컬 `player.html`을 띄우고 Dart ↔ JS를 `postMessage`로 연결한다.
`flutter_inappwebview`의 Windows 지원 성숙도도 함께 확인할 가치가 있다.

**착수 전 스파이크 필수**: Windows에서 `webview_windows` + YouTube iframe이 실제로
재생되는지. 여기서 막히면 §8 캡처 도구까지 설계가 달라진다(같은 스택을 쓴다).

---

## 10. 저장소 구조

```
tools/corpus/                    ← 로컬 배치 (Python, 앱 빌드와 무관)
  patterns/*.yaml                ← 패턴 스펙
  00_verify_yodas.py             ← §3.4 Step 0 검증
  01_ingest_yodas.py             ← HF 스트리밍 → 문장 정규화
  02_match.py                    ← L1~L4 패턴 매칭
  03_score_upload.py             ← 점수화 + Supabase upsert
  04_coverage.py                 ← 갭 리포트
  requirements.txt

tools/capture/                   ← §8.3 수동 캡처 도구
tools/review/                    ← 검수 화면

supabase/
  migrations/002_yt_clip_corpus.sql
  functions/clips-for-card/      ← 카드 → 상위 3개 클립
  functions/yt-metadata-refresh/ ← ★ 30일 갱신 크론 (컴플라이언스 필수)
  functions/patterns-match/      ← 텍스트 → pattern_id

lib/features/youtube/
  domain/{clip_model,pattern_model}.dart
  data/clip_repository.dart      ← card_clips 로컬 CRUD + EF 호출
  presentation/clip_player*.dart ← §9.2 플랫폼 분기
  presentation/clip_carousel.dart
```

---

## 11. 실행 순서

| # | 작업 | 산출물 | 예상 |
|---|---|---|---|
| **0** | **Windows WebView 스파이크** (§9.2) | 유튜브 클립 재생 확인 | 0.5일 |
| **1** | **YODAS 검증** (§3.4) | 영어 manual 규모·필드·용량 확인 | 0.5일 |
| 2 | 스키마 마이그레이션 002 + sync stream | 테이블 5개 | 0.5일 |
| 3 | **30일 갱신 크론** (§4-[5]) | 컴플라이언스 확보 | 1일 |
| 4 | 패턴 사전 v1 (상위 300개) | `patterns/*.yaml` | 2일 |
| 5 | YODAS 인제스트 + 문장 정규화 | sentences.parquet | 3일 |
| 6 | 패턴 매칭 + 점수화 + 업로드 | approved 클립 서빙 | 3일 |
| 7 | enrich에 `pattern_id` 매핑 (§6) | 카드 ↔ 패턴 연결 | 1일 |
| 8 | 앱 클립 UI (`clip_carousel`) | 사용자에게 노출 | 2일 |
| 9 | 수동 캡처 도구 (§8.3) | 회화체 공백 보강 | 3일 |
| 10 | YouGlish 위젯 폴백 탭 (§2) | 커버리지 0 대응 | 0.5일 |
| **∥** | **채널 허가 요청 발송** (§14.5-①) | 승낙 50채널 = 2,500시간 | 병행, 회신 대기 |
| 11 | 크롤러 + WhisperX 파이프라인 (§14.8) | 허가 풀 자동 확장 | 4일 |

**∥ 표시는 병행 작업이다.** 허가 요청은 회신에 수 주가 걸리므로 **1번(YODAS 검증)과
동시에 발송을 시작한다.** YODAS로 앱을 띄우는 동안 허가가 쌓이고, 11번 시점에
화이트리스트가 준비되어 있게 만드는 것이 전체 일정을 가장 많이 단축한다.

**0번과 1번을 먼저 하라.** 둘 중 하나가 막히면 이후 계획이 전부 바뀐다.
0번이 막히면 Windows UX 재설계, 1번이 막히면 §8 수동 트랙이 주력이 된다.

## 12. 측정 지표

| 지표 | 목표 |
|---|---|
| 패턴 커버리지 (클립 ≥3개) | 상위 1,000 패턴의 80% |
| 검수 승인율 | 60% 이상 (낮으면 매칭 정밀도 문제) |
| 사용자 스킵률 (`user_action='skipped'`) | 30% 이하 |
| 메타데이터 갱신 지연 | **30일 초과 0건** (컴플라이언스) |
| 클립 사망률 (연간) | 10% 이하, 크론으로 자동 복구 |
| 카드당 클립 노출 지연 | 500ms 이하 (card_clips 로컬 조회) |

---

## 13. 하지 않는 것 (명시)

| 행위 | 이유 |
|---|---|
| `timedtext` 스크래핑 | 비공식 엔드포인트, 클라우드 IP 차단, ToS 회색 |
| `yt-dlp`로 자막·음성 대량 수집 | CC BY는 저작권만 해결, 접근 약관은 별개 |
| YouGlish 결과를 DB에 저장 | YouGlish ToS 명시 위반 (§2) |
| 영상·음성 파일 저장/재호스팅 | 시청각 콘텐츠 캐싱 금지 (사실 6) |
| 전체 자막 미러링 | 인용 범위 초과 |
| API 메타데이터 무기한 보관 | 30일 삭제·갱신 의무 (사실 4) |
| 광고·브랜딩 우회 | ToS 위반 |

---

## 14. 24시간 크롤러 + 자체 ASR 방식 검토

> "크롤러를 개발해서 매일 검색해서 영상을 수집하고 스크립트를 자동 생성한 다음
> 패턴 매칭을 하는 건 안 될까? 유튜브 임베드를 통하기만 하면 어떤 영상이든
> 사용 가능한 거잖아. 문제는 서칭인데 이걸 크롤러로 24시간 수집."

**결론: 크롤러는 만든다. 자체 ASR도 좋은 판단이다. 단 대상 영상 풀을 바꾼다.**

### 14.1 임베드에 대한 인식은 정확하다

YouTube ToS 원문:

> "You may view or listen to Content for your personal, non-commercial use.
> **You may also show YouTube videos through the embeddable YouTube player.**"

임베드 재생은 **명시적으로 허용된 사용**이다. `status.embeddable == true`인 공개
영상이면 CC 라이선스든 표준 라이선스든 재생할 수 있다. 저작권 측면에서도 임베드는
서버에 복제가 일어나지 않아 대부분 관할에서 문제되지 않는다.

**다만 이 허용이 커버하는 건 파이프라인의 마지막 한 단계다.** 아래 §14.2 참조.

### 14.2 7단계로 쪼개면 문제는 1개뿐

| # | 단계 | 수단 | 판정 |
|---|---|---|---|
| 1 | 영상 발견·열거 | `playlistItems.list` (공식 API) | ✅ 합법. 1 unit/50개 |
| 2 | 메타 게이트 | `videos.list` (공식 API) | ✅ 합법 |
| 3 | **음성 확보** | **?** | ❌ **유일한 문제** |
| 4 | ASR 스크립트 생성 | 로컬 WhisperX | ✅ 문제 없음 |
| 5 | 패턴 매칭 | 로컬 spaCy | ✅ 문제 없음 |
| 6 | 문장 단편 저장 | 자체 DB | ✅ 인용 범위 |
| 7 | 재생 | 공식 iframe | ✅ **ToS 명시 허용** |

**7번의 허용이 3번을 커버하지 않는다.** 다른 조항이다. ToS는 자동화 접근에 대해
"you may access the Service using automated means **with YouTube's prior written
permission**"이라고 하고, 다운로드는 허용 목록에 없다.

### 14.3 ★ "문제는 서칭"이라는 진단이 틀렸다

이게 이 절의 핵심이다.

- 유튜브 검색은 **자막을 검색하지 않는다**(사실 1). 그래서 크롤러가 "검색"으로
  새로 찾아낼 것이 애초에 없다. 표현으로 검색하는 기능이 존재하지 않는다.
- 크롤러가 실제로 하는 일은 검색이 아니라 **전수 열거 + 로컬 인덱싱**이다.
  검색은 유튜브가 아니라 **당신의 인덱스**에서 일어난다.
- 그리고 그 열거는 **이미 완전히 합법이고 매우 싸다.** `playlistItems`가 50개당
  1 unit이니 하루 10,000 units로 **50만 영상**을 열거할 수 있다.

**즉 서칭은 병목이 아니다. 이미 해결되어 있다. 진짜 병목은 3번 음성 확보다.**
크롤러를 24시간 돌려도 1·2번만 빨라지고 3번에서 그대로 막힌다.

### 14.4 자체 ASR은 오히려 유튜브 자막보다 낫다

이 부분 판단은 정확하다. WhisperX를 쓰면:

| | 유튜브 자막 | 자체 ASR (WhisperX) |
|---|---|---|
| 타임스탬프 정밀도 | 큐 단위 (±0.5s) | **단어 단위 (±50ms)** |
| 구두점 | manual은 있고 auto는 없음 | **일관되게 있음** |
| 품질 편차 | manual/auto 혼재 | **균일** |
| 문장 분할 정확도 | auto는 사실상 불가 | **정확** |

클립 경계 품질이 이 기능의 체감 품질을 좌우하므로, 자체 ASR은 비용을 들일 가치가
있다. **§4-[1]의 구두점 복원 단계 전체가 사라진다.**

ASR 비용:
```
2,500시간 ÷ faster-whisper large-v3 (약 15x realtime)  ≈ 170 GPU-hours
  RTX 4090 보유 시    → 약 1주 (야간 배치)
  클라우드 GPU 렌탈   → $100~200 (1회성)
```

### 14.5 3번을 뚫는 합법 경로

#### ① 제작자 서면 허가 ★ 최선

ToS가 **명시적으로 허용하는 유일한 경로**다("prior written permission"). 동시에
저작권 층도 해결된다. 그리고 영어 학습 앱은 제안할 명분이 좋다 — **당신이 제작자에게
조회수를 보내준다.**

```
50채널 × 200영상 × 평균 15분 = 2,500시간
```

§7.2 기준 **2,000~4,000시간이면 상위 5,000 패턴을 커버**한다. 즉 **50채널 승낙만
받으면 규모가 충분하다.** 교육 채널 200곳에 제안해 20~30%가 승낙하면 달성된다.

메일 템플릿: `docs/templates/channel_permission_request.md`

허가받은 채널은 `yt_channels.permission_status='granted'`로 표시하고, 허가 증빙
(메일 원문·날짜)을 보관한다. 크롤러는 **이 화이트리스트 안에서만 3번을 수행**한다.

#### ② CC BY 크롤러 — 매일 자동으로 풀이 커진다

원하던 "매일 검색해서 수집"이 여기서 그대로 성립한다. 대상만 CC BY로 한정된다.

```
매일: 채널 업로드 열거 → videos.list → status.license == 'creativeCommon' 필터
      → 신규 CC BY 영상이 매일 자동 유입
```

CC BY는 저작권을 해결한다(상업적 사용도 출처 표기하면 가능). 접근 경로는 여전히
회색이라 ①과 결합하는 게 좋다 — **CC BY 영상의 제작자는 이미 재사용을 허락한
상태이므로 허가 요청 승낙률이 훨씬 높다.** ②로 후보를 찾고 ①로 허가를 받는 조합이
가장 효율적이다.

#### ③ 공개 라이선스 데이터셋 (§3) — 콜드스타트

YODAS로 초기 400~500시간을 즉시 확보한다. ①의 허가를 모으는 동안 앱이 이미 동작한다.

### 14.6 yt-dlp 대량 수집은 기술적으로도 성립하지 않는다

법적 판단을 완전히 제외하고, **24시간 무인 운영이라는 전제 자체가 깨진다.**
2026년 현재:

- **PO Token이 video ID마다 바인딩**된다 → 영상마다 토큰을 새로 발급해야 한다
- **SABR**이 다운로더 연결을 적극적으로 끊는다
- 다운로더들이 수년간 의존한 **`android_sdkless` 클라이언트가 폐기 중**이다
- yt-dlp 위키 표현: **"PO token을 넘겨도 대다수 케이스에서 봇 체크를 우회하지 못한다"**

즉 무인 크롤러가 아니라 **매주 깨지는 파이프라인을 사람이 계속 고치는 일**이 된다.
법적 리스크를 감수하겠다고 결정하더라도 이 방식으로는 24/7 자동화가 안 된다.

### 14.7 리스크 등급 (판단 근거용)

| 등급 | 방식 | 저작권 | 접근 약관 | 기술 안정성 | 실무 리스크 |
|---|---|---|---|---|---|
| 1 | 공개 데이터셋 (YODAS) | ✅ | ✅ | ✅ | 없음 |
| 1 | 제작자 서면 허가 | ✅ | ✅ | ✅ | 없음 |
| 2 | 사람이 캡처 (§8) | 인용 범위 | 자동화 아님 | ✅ | 낮음 |
| 3 | CC BY 영상 yt-dlp | ✅ | ❌ | ❌ | 낮음 (제작자 신고 동기 없음) / 계약 위반 성립 |
| 4 | 일반 영상 yt-dlp 대량 | ❌ | ❌ | ❌ | 중~높음 |

**"위반하지 않는 선"이라는 제약에서는 1~2등급만 쓴다.** 그리고 §14.5에서 보인 것처럼
1~2등급만으로도 규모가 충분하다 — 타협이 아니다.

### 14.8 최종 크롤러 설계

크롤러는 만든다. 이렇게 만든다.

```
── 매일 (클라우드 OK, 공식 API만 사용 → IP 차단·약관 문제 없음) ──────────
  1. 허가 채널 + CC BY 채널의 신규 업로드 발견   playlistItems.list
  2. 게이트 + 라이선스 확인                      videos.list
  3. 30일 메타데이터 갱신 큐 처리 (§4-[5], 컴플라이언스 의무)
  4. 커버리지 갭 리포트 → 다음 허가 요청 대상 채널 추천
  → Supabase Edge Function + cron

── 주 1회 (로컬 GPU, 허가·CC BY 화이트리스트 내에서만) ──────────────────
  5. 신규 영상 음성 → WhisperX → 단어 단위 타임스탬프 스크립트
  6. 문장 분할 + 패턴 매칭 L1~L4 (구두점 복원 단계 불필요)
  7. 점수화 → 검수 큐 → Supabase upsert
```

원래 구상과 다른 점은 **딱 하나**다: 3번(음성 확보)을 **허가받은 채널 + CC BY
영상**으로 한정한다. 크롤러 코드, 24시간 운영, 자체 ASR, 패턴 매칭은 전부 그대로다.

바뀌는 것은 **"어떤 영상을 대상으로 하는가"이고, 이건 코드가 아니라 화이트리스트
테이블 한 개의 문제다.** 그래서 나중에 허가가 늘어나면 코드 변경 없이 확장된다.

---

## 참고 자료

- [YouTube Terms of Service](https://www.youtube.com/static?template=terms) (임베드 허용, 자동화 접근 사전 서면 허가)
- [YouTube API Services — Developer Policies](https://developers.google.com/youtube/terms/developer-policies) (30일 저장 규칙, 캐싱 금지)
- [YouTube API Services Terms of Service](https://developers.google.com/youtube/terms/api-services-terms-of-service)
- [captions.list](https://developers.google.com/youtube/v3/docs/captions/list) (소유자 OAuth 필요)
- [search.list](https://developers.google.com/youtube/v3/docs/search/list) / [할당량](https://developers.google.com/youtube/v3/getting-started)
- [YouTube IFrame Player API](https://developers.google.com/youtube/iframe_api_reference)
- [License types on YouTube](https://support.google.com/youtube/answer/2797468) (CC BY)
- [YODAS 데이터셋](https://huggingface.co/datasets/espnet/yodas) / [YODAS2](https://huggingface.co/datasets/espnet/yodas2) / [논문](https://arxiv.org/html/2406.00899v1)
- [YouTube-Commons](https://huggingface.co/datasets/PleIAs/YouTube-Commons)
- [YouGlish ToS](https://youglish.com/terms) / [Widget](https://youglish.com/api/doc/widget) / [JS API](https://youglish.com/api/doc/js-api)
- [youtube_player_iframe (Windows 미지원)](https://pub.dev/packages/youtube_player_iframe) / [webview_windows](https://pub.dev/packages/webview_windows)
- [WhisperX (단어 단위 정렬)](https://github.com/m-bain/whisperx)
- [yt-dlp PO Token Guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide) / [SABR 다운로더 PR #13515](https://github.com/yt-dlp/yt-dlp/pull/13515) (§14.6 기술 불안정성)
