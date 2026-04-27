# director CHANGELOG

## V0.1.0 — 2026-04-27

初版骨架。建立总导演调度协议,主 Claude 串联 4 个本地 CLI + 1 个 skill 产出短视频。

新增:
- `CLAUDE.md`:项目级元规则(单一真相源、CLI 调用模板锁定、绝对路径强制、资产命名锁定、平台映射缺口、失败重试纪律)
- `pipeline.md`:Step 0~5 SOP(parse→script→并行 picture+audio→规范化→video-gen×M 平台→后期合音);降级矩阵;resume 协议;平台分叉决策
- `platforms.yaml`:tiktok / douyin / yt_short / yt_landscape 预设(aspect、分辨率、时长、script-gen 平台映射)
- `voices.yaml`:edge-tts 中英常用 voice 短名表(language × style → voice id)
- `manifest.schema.json`:每 project 的单一真相源 schema(project_id / platforms / tool_versions / steps with per-scene status / errors)
- `.gitignore`:排除 projects/ 产出物
- `CHANGELOG.md`(本文件)

已知缺口:
- `bgm-gen` 未实装(目录空),pipeline 永远 skip
- `script-gen --platform` 无 `youtube` 选项,yt_landscape / yt_short 临时映射到 `reels`
- `video-gen` V0.2 不接 narration 音频,需要 step 5 用 ffmpeg 后期合入(等 V0.3)
