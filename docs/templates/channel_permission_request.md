# 채널 자막 인덱싱 허가 요청 템플릿

`docs/YOUTUBE_CLIP_SOURCING.md` §14.5-① 용. YouTube ToS가 명시적으로 허용하는
경로("prior written permission")를 확보하기 위한 것.

## 운영 원칙

1. **요청 범위를 좁게 쓴다.** "영상을 쓰게 해달라"가 아니라 "음성을 텍스트로 옮겨
   검색 색인을 만들고, 재생은 공식 임베드로 하겠다"까지 구체적으로 적는다.
   범위가 좁으면 승낙률이 오른다.
2. **제작자 이득을 먼저 말한다.** 임베드 재생이므로 조회수·시청 시간·광고 수익이
   전부 제작자에게 귀속된다. 이게 이 제안의 핵심 설득 포인트다.
3. **CC BY 영상을 가진 채널을 먼저 접촉한다.** 이미 재사용을 허락한 제작자이므로
   승낙률이 훨씬 높다.
4. **회신은 원문 그대로 보관한다.** 발신일·수신일·회신 전문을 남기고
   `yt_channels.permission_status='granted'`로 표시한다. 이게 허가의 증빙이다.
5. **거절·무응답 채널은 화이트리스트에 넣지 않는다.** 무응답은 허가가 아니다.

## 메일 본문 (영어)

> Subject: Permission request — indexing your captions for an English learning app
>
> Hi {CHANNEL_NAME},
>
> I'm building a small English learning app for Korean learners. When a learner
> saves an expression they're studying, the app shows them a few short clips of
> that expression being used naturally by a native speaker — so they hear it in
> real context instead of just reading a definition.
>
> Your videos are exactly the kind of clear, natural English I'd like learners to
> hear, so I'm writing to ask permission for two specific things:
>
> 1. Transcribing the speech in your videos to text, and keeping a searchable
>    index of those sentences with their timestamps.
> 2. Storing single sentences from that index (roughly 5–10 seconds of speech
>    each) as pointers into your videos.
>
> What I would **not** do:
>
> - I won't host, re-upload, or serve your video or audio anywhere. Playback is
>   always the official YouTube embedded player, so **all views, watch time, and
>   ad revenue stay with you.**
> - I won't publish your full transcripts. Only the individual sentence that
>   matches what a learner is studying is ever shown.
> - I won't remove or bypass any YouTube branding, ads, or player controls.
>
> Every clip credits your channel by name with a link back to the video at that
> timestamp, so learners who like a clip can go watch the full video.
>
> If you'd rather not, that's completely fine — just say so and I won't index your
> channel. And if you say yes now but change your mind later, email me and I'll
> remove your content within a few days, no questions asked.
>
> Would you be OK with this?
>
> Thanks for your time,
> {YOUR_NAME}
> {CONTACT_EMAIL} · {APP_NAME}

## 회신 기록 형식

```yaml
# tools/corpus/permissions/{channel_id}.yaml
channel_id: UCxxxxxxxxxxxxxxxxxxxxxx
channel_title: "..."
contact: "..."
requested_at: 2026-08-12
responded_at: 2026-08-15
status: granted        # granted | denied | no_response | withdrawn
scope: "transcription + sentence-level index + official embed playback"
response_quote: |
  (회신 원문을 그대로 붙여넣는다)
notes: ""
```

`status: granted` 인 채널만 `yt_channels.permission_status='granted'`로 올리고,
크롤러의 음성 확보 단계(§14.8-5)는 이 목록만 대상으로 한다.

`withdrawn`으로 바뀌면 해당 채널의 클립을 `takedown_requested=true`로 일괄 표시하고
서빙에서 즉시 제외한다.
