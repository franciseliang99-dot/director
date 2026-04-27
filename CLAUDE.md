# director — 总导演项目级规则

主 Claude 在本目录下扮演"总导演":接收用户的视频主题,串起 4 个本地 CLI + 1 个 skill,产出 YouTube/TikTok 短视频。

## 单一真相源

每支视频是一个 project,目录 `projects/<YYYYMMDD>-<slug>/`,根文件 `manifest.json` 是该 project 的**唯一真相源**。schema 见 `manifest.schema.json`。

- 任何步骤开始前 **Read** manifest;结束后用 **Edit** 改字段(不要 Write 整个文件,避免覆盖并发写)。
- 主 Claude 启动时(用户说"继续 / resume / 看下进度"),先扫所有 project 的 manifest,找 `status=running`(上次崩了)和 `status=failed` 的步骤。

## CLI 调用模板(锁定,不要现查 --help)

| 工具 | 命令 |
|---|---|
| script-gen | `cd /home/myclaw/script-gen && uv run python -m cli.main new "<desc>" --platform <tiktok\|douyin\|reels> --duration <N>` → session id 从 stderr `[script-gen] session id: <id>` 抓取 → `uv run python -m cli.main show <id>` 拿 JSON 到 stdout |
| picture-gen | `python3 /home/myclaw/picture-gen/main.py "<prompt>" --width <W> --height <H> --no-expand --style-anchor "<project_style_anchor>" --out <abs_dir>` (产物 `<dir>/<ts>-<slug>.jpg`,**director 必须重命名为 `scene_NN.jpg`**;`--style-anchor` 取 script.json 顶层 `style_anchor` 字段,所有 scene 共用一条,V0.4.5+ 强制) |
| audio-gen | `/home/myclaw/audio-gen/.venv/bin/python3 /home/myclaw/audio-gen/generate.py "<text>" -v <voice> -o <abs.mp3>` |
| bgm-gen | `/home/myclaw/bgm-gen/.venv/bin/python3 /home/myclaw/bgm-gen/generate.py "<topic 或 mood 描述>" -d <total_s+2> [-m <mood>] [--seed N] -o <abs.wav>` (本地 MIDI+fluidsynth,产物 .wav) |
| video-gen | `Skill('video-gen', "<title prompt> --images abs1.jpg,abs2.jpg,... --aspect <16:9\|9:16> --out <abs.mp4>")` |

**绝对路径强制**:子工具 cwd 各自不同,所有 `--out` / `--images` 一律写绝对路径,不留歧义。

**资产命名锁定**:images 落 `scene_NN.jpg`,audio 落 `scene_NN.mp3`(NN 两位补零)。video-gen 按 idx 配对,改名规则不能改。

## 平台映射(V0.4.0+,script-gen V0.2.0 已加 youtube)

| director 平台 id | aspect | script-gen `--platform` | script-gen `--variant` |
|---|---|---|---|
| `tiktok` | 9:16 | `tiktok` | (n/a) |
| `douyin` | 9:16 | `douyin` | (n/a) |
| `yt_short` | 9:16 | `youtube` | `short`(强制,即便 duration ≤60s) |
| `yt_landscape` | 16:9 | `youtube` | `long`(强制,长视频结构 / chapter / SEO title / thumbnail_text) |

完整字段在 `platforms.yaml`。yt_landscape 长视频会输出新增字段 `chapters[{start_sec,title}] / seo_title / thumbnail_text` —— manifest 不存这些字段(它们在 `script/script.json` 里),但 step 4 后期上传 YouTube 时拿来填 metadata。

## Maintainer 职责(V0.4.0+)

director 不只是"orchestrator",也是 5 agent + 自身的 **maintainer**。改 agent 代码或 director 配置前先 Read `maintainer.md`(SOP / 触发策略 / 谁拍板 / failure budget / smoke test 协议 / **自警清单**)。

**自警清单关键项**(完整见 maintainer.md §6):
1. 实测优先于推理 — 改 agent 源码前必须 reproducible failure
2. 管道纪律 — `| tail` 吞 PIPESTATUS,用 `> log 2>&1` / `${PIPESTATUS[0]}` / `set -o pipefail`
3. Edit-Read miss — Edit 失败要立刻 Read+重 Edit,git commit 前 `git diff --cached --stat` 验文件清单
4. Pollinations 单并发 — picture-gen 全程串行,不信公开文档限流数字
5. Optional agent 设计 — 标 `extra.optional=true` 前必须真有 fallback 路径,fallback 质量不显著低于本 agent
6. SKILL.md 文档边界值 ≠ 实测安全上限 — 用 range 上下限前必须 smoke 验证(default 一般可信)
7. Subagent 复杂行为推理实施前必须 single-step smoke verify — ffmpeg/filter/外部 API 类 fix 推荐尤其
8. Import-decoupling refactor 必须 grep 全模块 use site — health-check 类改动每个用 import name 的函数都要自 import / 共享 deferred / top try-import;production smoke 不只 --version

## 健康自检(V0.3.0+)

每个 agent 都实现了 `--version --json` 健康自检接口(`name / version / healthy / ts / deps[] / env[] / checks[] / reasons[] / extra{severity}`,exit 0=ok / 1=degraded / 2=broken)。director 调用统一封装:

```bash
/home/myclaw/director/bin/check-health.sh
# stdout: {"director_check_ts":"...", "overall":"ok|degraded|broken|missing-or-error", "agents":[...]}
# exit:   0=ok / 1=degraded / 2=broken / 3=missing-or-error
```

**何时调**:
- **每次开新 project** 调一次,把结果写入 `manifest.tool_health` + `manifest.tool_versions` 自动填(不再靠 grep 代码 / 手填字符串)
- 用户说"看下健康 / 谁挂了"时单独跑

**结果应用**:
- `overall=broken` 而某 agent broken 是因 env(如 ANTHROPIC_API_KEY 未设)→ 走对应降级路径(降级矩阵已涵盖)
- `overall=missing-or-error` → 停下问用户,可能是新机器 / 路径漂移 / 软链坏了

## bgm-gen mood 映射

bgm-gen 的 `--mood` 是 8 选 1:`calm / tense / sad / happy / epic / mystery / funny / cozy`。director 按 manifest 的 `style` 字段映射(用户未指定 `style` 时,**让 bgm-gen 自己从 topic 关键词推断,不传 `-m`**):

| director style | bgm-gen mood |
|---|---|
| `vlog-warm` | `cozy` |
| `news` | `calm` |
| `story` | `epic` |
| `explain` | `calm` |
| `comedy` | `funny` |
| `thriller` | `tense` |

时长:`-d` 传**视频总时长 + 2s**(给末尾 fade-out 余量,ffmpeg 在 step 5 截到视频总长)。

## 失败/重试纪律

- 每个步骤(每个 scene)**最多 2 次自动重试**,第 3 次失败必须停下问用户(护 API 额度)。
- 不用 `sleep` 轮询、不用 `|| true` 吞错、不用 `--no-verify`;失败先看 manifest `errors[]` + `logs/<step>-<ts>.log` 定位根因。
- `bgm-gen` 失败(fluidsynth 缺 / SoundFont 缺 / mood 不存在)→ manifest `steps.bgm.status=failed`,**降级为 skipped 继续出片**(BGM 是非关键路径,无 BGM 不影响视频可看)。

## 不在仓内提交产出物

`projects/` 是产出物不是源码,`.gitignore` 已排除。CHANGELOG / 配置 / schema / pipeline.md 才是 director 的源码。

## 版本号 + CHANGELOG

director 自身改动(CLAUDE.md / pipeline.md / schema / 配置 / 新增 helper 脚本)走全局规则:递增版本、CHANGELOG 追加条目、与代码改动同 commit。版本号在 `CHANGELOG.md` 顶部。

## 调用 video-gen 后

video-gen skill 会自己跑 5 步(plan → render → ffprobe 验证 → 自评)。director 拿到 mp4 路径后,**回写 manifest** `steps.video.<platform>.artifact`,不重复跑评估。
