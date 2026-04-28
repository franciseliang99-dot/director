# director

Total-director: orchestrates four local CLIs and one Claude Code skill into a YouTube/TikTok/Reels short.

```
script-gen ──┐
picture-gen ─┤
audio-gen ───┼──► director ──► video-gen (skill) ──► .mp4
bgm-gen   ──┘
```

Each video is a project under `projects/<YYYYMMDD>-<slug>/` with `manifest.json` as the single source of truth — every step reads/writes the manifest, never overwrites it as a whole file.

## Sibling tools

- [script-gen](https://github.com/franciseliang99-dot/script-gen) — script + scene plan (optional; in-context fallback)
- [picture-gen](https://github.com/franciseliang99-dot/picture-gen) — Pollinations image generation
- [audio-gen](https://github.com/franciseliang99-dot/audio-gen) — edge-tts narration
- [bgm-gen](https://github.com/franciseliang99-dot/bgm-gen) — procedural MIDI→WAV background music
- [video-gen](https://github.com/franciseliang99-dot/video-gen) — ffmpeg + Pillow render skill

Director runs *inside* Claude Code — Claude reads `pipeline.md`, drives each sibling tool by CLI, edits the manifest, and reports.

## Run

Open this directory in Claude Code and prompt with a topic:

```
new short video about HTTP/3 multiplexing, tiktok 9:16, 30 seconds
```

Director will scaffold a project, draft a script, generate scenes / narration / BGM, render the video, and write outputs back to the manifest.

## Health check

```bash
bin/check-health.sh
# overall: ok | degraded | broken | missing-or-error
```

Each sibling agent implements `--version --json` with a uniform schema (`name / version / healthy / deps[] / env[] / checks[] / reasons[]`). `degraded` agents (e.g. script-gen with no `ANTHROPIC_API_KEY`) trigger documented fallback paths instead of stopping the pipeline.

## Platforms

| director platform id | aspect | script-gen `--platform` | `--variant` |
|---|---|---|---|
| `tiktok` | 9:16 | `tiktok` | (n/a) |
| `douyin` | 9:16 | `douyin` | (n/a) |
| `yt_short` | 9:16 | `youtube` | `short` |
| `yt_landscape` | 16:9 | `youtube` | `long` |

## Repository contents

- `pipeline.md` — step-by-step playbook Claude follows
- `manifest.schema.json` — JSON schema for every project's `manifest.json`
- `platforms.yaml` — per-platform field map + aspect ratio
- `bin/check-health.sh` — aggregate health check across siblings
- `CHANGELOG.md` — version history

## License

MIT — see [LICENSE](LICENSE).
