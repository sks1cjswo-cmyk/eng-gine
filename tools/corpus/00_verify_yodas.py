#!/usr/bin/env python3
"""
Step 0 검증 — YODAS 데이터셋이 클립 파이프라인에 쓸 수 있는지 확인한다.

docs/YOUTUBE_CLIP_SOURCING.md §3.4 의 5개 항목을 확인:
  1. 영어 manual 서브셋이 실제로 로드되는가
  2. utterance 단위 start/end 필드가 존재하고 단위가 초인가
  3. 라이선스 표기
  4. audio 재배포 포함 여부
  5. 텍스트만 스트리밍으로 뽑을 수 있는가 (용량 회피)

로컬 머신에서 실행할 것 (클라우드 아님):
    pip install datasets huggingface_hub
    python tools/corpus/00_verify_yodas.py

YODAS 샤드 명명 규칙: <lang><3자리>, 첫 자리가 0이면 manual 자막, 1이면 automatic.
따라서 en000 = 영어 manual, en100 = 영어 automatic (문서 기준, 실제 확인 대상).
"""

from __future__ import annotations

import argparse
import itertools
import sys

MANUAL_SHARDS = ["en000", "en001", "en002"]
AUTO_SHARDS = ["en100", "en101"]


def probe_shard(shard: str, n: int) -> dict | None:
    """샤드 하나를 스트리밍으로 열어 스키마와 샘플을 확인한다."""
    from datasets import load_dataset

    print(f"\n{'=' * 68}\n샤드: {shard}\n{'=' * 68}")
    try:
        ds = load_dataset("espnet/yodas", shard, split="train", streaming=True)
    except Exception as exc:  # 샤드명이 틀렸거나 접근 불가
        print(f"  ✗ 로드 실패: {type(exc).__name__}: {exc}")
        return None

    rows = list(itertools.islice(iter(ds), n))
    if not rows:
        print("  ✗ 행이 없음")
        return None

    first = rows[0]
    print(f"  ✓ 로드 성공 — 컬럼: {sorted(first.keys())}")

    # [2] 타이밍 필드 탐색: 명세는 start/end 지만 실제 이름이 다를 수 있다
    timing = {k: first[k] for k in first if any(
        t in k.lower() for t in ("start", "end", "time", "dur", "offset"))}
    if timing:
        print(f"  ✓ 타이밍 후보 필드: {timing}")
    else:
        print("  ✗ 타이밍 필드 없음 → 클립 경계를 만들 수 없다. "
              "YODAS2(영상 단위) 또는 WhisperX 정렬 경로를 검토할 것")

    # [4] audio 포함 여부 — 있으면 스트리밍이라도 디코딩 비용이 든다
    if "audio" in first:
        a = first["audio"]
        keys = sorted(a.keys()) if isinstance(a, dict) else type(a).__name__
        print(f"  ✓ audio 필드 존재 ({keys}) → 텍스트만 필요하면 remove_columns 로 제외")
    else:
        print("  · audio 필드 없음 (텍스트 전용 샤드)")

    # 샘플 발화 — 구두점 유무가 manual/automatic 판별의 실질 지표
    text_key = next((k for k in ("text", "transcript", "sentence") if k in first), None)
    if text_key:
        print(f"\n  샘플 발화 (필드 '{text_key}'):")
        for i, r in enumerate(rows[:n]):
            t = str(r[text_key])[:100]
            times = {k: r[k] for k in timing} if timing else {}
            print(f"    [{i}] {times} {t!r}")
        punctuated = sum(
            1 for r in rows if any(c in str(r[text_key]) for c in ".?!"))
        print(f"\n  구두점 포함 발화: {punctuated}/{len(rows)} "
              f"→ {'manual 계열로 보임' if punctuated > len(rows) * 0.5 else 'ASR 계열, 구두점 복원 필요'}")
    else:
        print("  ✗ 텍스트 필드를 못 찾음")

    # [5] video_id — 임베드에 반드시 필요
    vid_key = next((k for k in first if "video" in k.lower() and "id" in k.lower()), None)
    if vid_key:
        print(f"  ✓ video id 필드: '{vid_key}' = {first[vid_key]!r}")
    else:
        # utt_id 에 video_id 가 접두어로 박혀 있는 경우가 있다
        utt = first.get("utt_id") or first.get("id")
        print(f"  ! 독립 video id 필드 없음. utt_id={utt!r} 에서 파싱 가능한지 확인할 것")

    return {"shard": shard, "columns": sorted(first.keys()), "timing": list(timing)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--shards", nargs="*", default=MANUAL_SHARDS + AUTO_SHARDS[:1])
    ap.add_argument("-n", type=int, default=5, help="샤드당 확인할 행 수")
    args = ap.parse_args()

    try:
        import datasets  # noqa: F401
    except ImportError:
        print("datasets 미설치:  pip install datasets huggingface_hub", file=sys.stderr)
        return 2

    ok = [r for s in args.shards if (r := probe_shard(s, args.n))]

    print(f"\n{'=' * 68}\n요약\n{'=' * 68}")
    print(f"  접근 가능한 샤드: {len(ok)}/{len(args.shards)}")
    for r in ok:
        print(f"    {r['shard']}: timing={r['timing'] or '없음'}")

    if not ok:
        print("\n  ✗ 진행 불가 — 샤드명 규칙이 바뀌었을 수 있다.")
        print("    https://huggingface.co/datasets/espnet/yodas/tree/main/data 에서")
        print("    실제 디렉터리명을 확인하고 --shards 로 넘길 것")
        return 1
    if not any(r["timing"] for r in ok):
        print("\n  ✗ 타이밍 없음 — docs/YOUTUBE_CLIP_SOURCING.md §8 수동 캡처가 주력이 된다")
        return 1

    print("\n  ✓ 파이프라인 진행 가능. 다음: 01_ingest_yodas.py")
    print("\n  남은 수동 확인 항목:")
    print("    · 데이터셋 카드의 라이선스 정확한 변종 (CC BY 몇 조, 서브셋별 차이)")
    print("    · 영어 manual 서브셋 총 시간 (목표 400~500시간)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
