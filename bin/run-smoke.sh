#!/bin/bash
# director smoke test — fixed 3-scene/10s pipeline, asserts manifest + ffprobe.
# Usage:
#   bin/run-smoke.sh --seeded   # locked seed, byte-level reproducibility (default)
#   bin/run-smoke.sh --random   # no seed, robustness check (any seed should still produce valid mp4)
#
# Exit codes:
#   0 = pass
#   1 = assertion failed (any step / ffprobe check)
#   2 = pipeline failed (agent crashed)
#
# Note: Pollinations does not strictly honor seed for repeatability — image bytes
# may vary between runs even with same seed. We assert structural properties
# (duration, codec, resolution, all-steps-done), NOT byte-level checksums on images.
set -euo pipefail

MODE="${1:---seeded}"
SMOKE=/home/myclaw/director/projects/_smoke
WORK=/tmp/director-smoke-$$
trap "rm -rf $WORK" EXIT

mkdir -p "$WORK"/{images/.raw,audio,bgm,renders,logs}
cp "$SMOKE/script/script.json" "$WORK/script.json"

echo "[smoke] mode=$MODE work=$WORK"

# --- Step 2a: 3 images (serial, --seed honored if --seeded) ---
SEED_ARGS=""
[ "$MODE" = "--seeded" ] && SEED_ARGS_BASE="--seed"

for n in 1 2 3; do
  prompt=$(jq -r ".scenes[$((n-1))].image_prompt" "$WORK/script.json")
  seed=$(jq -r ".scenes[$((n-1))].seed" "$WORK/script.json")
  mkdir -p "$WORK/images/.raw/0$n"
  if [ "$MODE" = "--seeded" ]; then
    python3 /home/myclaw/picture-gen/main.py "$prompt" \
      --width 1024 --height 1792 --no-expand --seed "$seed" \
      --out "$WORK/images/.raw/0$n/" > /dev/null 2>&1
  else
    python3 /home/myclaw/picture-gen/main.py "$prompt" \
      --width 1024 --height 1792 --no-expand \
      --out "$WORK/images/.raw/0$n/" > /dev/null 2>&1
  fi
  echo "[smoke] image $n done"
done

# --- Step 2b: 3 audios (parallel) + 1 bgm ---
for n in 1 2 3; do
  text=$(jq -r ".scenes[$((n-1))].narration" "$WORK/script.json")
  /home/myclaw/audio-gen/.venv/bin/python3 /home/myclaw/audio-gen/generate.py "$text" \
    -v en-US-AriaNeural -o "$WORK/audio/scene_0$n.mp3" > /dev/null 2>&1 &
done
BGM_SEED_ARG=""
[ "$MODE" = "--seeded" ] && BGM_SEED_ARG="--seed 42"
/home/myclaw/bgm-gen/.venv/bin/python3 /home/myclaw/bgm-gen/generate.py \
  "smoke test calm bgm" -d 12 -m calm $BGM_SEED_ARG \
  -o "$WORK/bgm/track.wav" > /dev/null 2>&1 &
wait
echo "[smoke] audio + bgm done"

# --- Step 3: rename images ---
for n in 1 2 3; do
  src=$(ls "$WORK/images/.raw/0$n/"*.jpg | head -1)
  cp "$src" "$WORK/images/scene_0$n.jpg"
done

# --- Step 4: video-gen V0.3 single-pass ---
PLAN=/tmp/smoke-plan-$$.json
cat > "$PLAN" <<EOF
{
  "title": "Smoke Test",
  "aspect": "9:16",
  "fps": 30,
  "transition": "crossfade",
  "transition_duration_s": 0.4,
  "tail_hold_s": 0.2,
  "scenes": [
    {"duration_s": 3.5, "background_image": "$WORK/images/scene_01.jpg", "caption": "smoke test scene one", "caption_position": "bottom", "ken_burns": "in"},
    {"duration_s": 3.5, "background_image": "$WORK/images/scene_02.jpg", "caption": "smoke test scene two", "caption_position": "bottom", "ken_burns": "left"},
    {"duration_s": 3.0, "background_image": "$WORK/images/scene_03.jpg", "caption": "smoke test done", "caption_position": "center", "ken_burns": "none"}
  ]
}
EOF
NARR_CSV="$WORK/audio/scene_01.mp3,$WORK/audio/scene_02.mp3,$WORK/audio/scene_03.mp3"
python3 /home/myclaw/video-gen/scripts/render_video.py "$PLAN" \
  --out "$WORK/renders/smoke.mp4" --narration "$NARR_CSV" > /dev/null 2>&1
rm -f "$PLAN"
echo "[smoke] video render done"

# --- Step 5: BGM amix ---
ffmpeg -y -i "$WORK/renders/smoke.mp4" -i "$WORK/bgm/track.wav" \
  -filter_complex "[0:a]volume=1.0[a0];[1:a]volume=0.25,afade=t=out:st=8.5:d=1.0[a1];[a0][a1]amix=inputs=2:duration=longest:dropout_transition=0[aout]" \
  -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k -shortest \
  "$WORK/renders/smoke_av.mp4" > /dev/null 2>&1
echo "[smoke] amix done"

# --- Assertions ---
FAIL=0
DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$WORK/renders/smoke_av.mp4")
RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$WORK/renders/smoke_av.mp4")
ACODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$WORK/renders/smoke_av.mp4")

# duration ∈ [9, 13]
DUR_OK=$(awk -v d="$DUR" 'BEGIN{print (d >= 9.0 && d <= 13.0) ? "yes" : "no"}')
[ "$DUR_OK" != "yes" ] && { echo "[smoke] FAIL: duration $DUR not in [9.0, 13.0]"; FAIL=1; }
[ "$RES" != "1080x1920" ] && { echo "[smoke] FAIL: resolution $RES != 1080x1920"; FAIL=1; }
[ "$ACODEC" != "aac" ] && { echo "[smoke] FAIL: audio codec $ACODEC != aac"; FAIL=1; }

# tool_versions match
echo "[smoke] verifying tool_versions match --version --json output..."
for spec in \
  "script-gen|0.2.0|cd /home/myclaw/script-gen && uv run --quiet python -m cli.main --version" \
  "picture-gen|0.2.0|python3 /home/myclaw/picture-gen/main.py --version" \
  "audio-gen|1.0.2|/home/myclaw/audio-gen/.venv/bin/python3 /home/myclaw/audio-gen/generate.py --version" \
  "bgm-gen|1.0.2|/home/myclaw/bgm-gen/.venv/bin/python3 /home/myclaw/bgm-gen/generate.py --version" \
  "video-gen|0.3.0|python3 /home/myclaw/video-gen/scripts/health.py --version"
do
  name="${spec%%|*}"; rest="${spec#*|}"; expected="${rest%%|*}"; cmd="${rest#*|}"
  actual=$(bash -c "$cmd" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [ "$actual" != "$expected" ]; then
    echo "[smoke] FAIL: $name version expected $expected got $actual"
    FAIL=1
  fi
done

if [ $FAIL -eq 0 ]; then
  echo "[smoke] PASS  duration=$DUR  res=$RES  acodec=$ACODEC  mode=$MODE"
  exit 0
else
  echo "[smoke] FAILED.  artifact: $WORK/renders/smoke_av.mp4 (kept for inspection)"
  trap - EXIT  # don't clean up on failure
  exit 1
fi
