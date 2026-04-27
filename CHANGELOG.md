# director CHANGELOG

## V0.2.0 — 2026-04-27

接入 bgm-gen (V1.0.1,本地 MIDI+fluidsynth)。BGM 从"占位 skip"升级为完整流水线步骤,失败自动降级 skip 不阻塞出片。

变更:
- `CLAUDE.md`:CLI 模板表 bgm-gen 行替换成实际命令;新增"bgm-gen mood 映射"段(director style → 8 个 mood 枚举的映射表 + 时长规则);失败纪律段把"未装是常态"改为"失败自动降级 skipped"
- `pipeline.md`:Step 2 并行批从 `2N` 扩到 `2N+1`,加入 BGM 调用(BGM 单独一批避开 fluidsynth CPU 冲击);Step 3 BGM 缺失自动降级;Step 5 后期合音改为分支(有 BGM 走 `amix` 双轨 + 25% 衰减 + 末尾 1.5s fade-out / 无 BGM 走原 narration-only);降级矩阵补 bgm-gen 行
- `manifest.schema.json`:`steps.bgm` 字段补全 (`mood` 8 选 1 枚举 / `artifact` / `duration_s` / `seed`)
- `.gitignore`:补 `*.wav` `*.mid` (bgm-gen 产物)

已知缺口(剩余):
- `script-gen --platform` 无 `youtube` 选项,yt_landscape / yt_short 临时映射到 `reels`
- `video-gen` V0.2 不接 narration 音频,需要 step 5 用 ffmpeg 后期合入(等 V0.3)
- bgm-gen 自身 CHANGELOG 漏记 V1.0.1(代码 `__version__="1.0.1"`,CHANGELOG 顶部仍是 V1.0.0)— 不影响 director 接入,只是 bgm-gen 仓内的小遗漏

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
