# director CHANGELOG

## V0.4.3 — 2026-04-27

**接入 bgm-gen V1.0.3 + 加 maintainer §6.8**(reactive 触发自 toothbrush-monsters 视频 bgm 失败)。

接入:
- **bgm-gen V1.0.3** (`347e4ae`):`_add_drums()` 漏 `import pretty_midi`(V1.0.2 健康自检 refactor 把顶层 import 下沉到 `build_midi()` 但漏 `_add_drums()`)。drum_kit ∈ {chase, pop, epic, shaker} 对应 mood {tense, happy, epic, funny} 全踩坑。toothbrush 项目用 funny mood 直接撞,bgm 输出 0 bytes。fix: `_add_drums()` 顶部加 import(同 build_midi pattern)。
- `tool_versions.bgm-gen` 1.0.2 → 1.0.3。

新增 maintainer.md 自警:
- **§6.8 Import-decoupling refactor 必须 grep 全模块 use site**。两个反例:picture-gen V0.2.0→V0.2.1(agent.run / generator.generate_pollinations / planner.expand_prompt 三个 imports 移除时漏 main 引用)、bgm-gen V1.0.2→V1.0.3(pretty_midi 下沉到 build_midi 漏 _add_drums)。**同模式第 2 次复发**,所以入条。
- 完整 refactor checklist 5 步:① `grep -n "<module_name>\." <agent>/**/*.py` ② `grep -n "from <module_name>"` ③ 列受影响函数清单 ④ **production code path smoke test**(不只 `--version --json`)⑤ commit 前 `git diff --cached --stat` 验文件清单(配合 §6.3 Edit-Read miss)
- 根本启示:health-check refactor decouple 不彻底比不 refactor 更糟,**要么彻底要么不动,不要半改**。

CLAUDE.md 自警速查到 8 条。

**反向追溯**:本轮 maintainer §6.1 反例第 2 次复发,而且模式完全相同(import refactor 漏 grep)。这是 SOP 还没"长成"的信号——下次 picture-gen / audio-gen / video-gen 类似 refactor 必须先看 §6.8 checklist。

## V0.4.2 — 2026-04-27

**接入 video-gen V0.3.1 + 加 maintainer §6.6 §6.7 自警**(maintainer pass 第三波,reactive 触发自 tokyo-editor 视频 tail_hold deadlock)。

接入:
- **video-gen V0.3.1** (`af6443e`):tail_hold_s Field range 从 wishful `0.0-1.0` clamp 到实测安全 `0.0-0.3`。SKILL.md 同步。Plans with tail_hold>0.3 现在 pydantic 拒绝(strict failure 优于 silently broken 6s clip)。
- `tool_versions.video-gen` 0.3.0 → 0.3.1(只 manifest 字段,代码无需改;pipeline.md video-gen 调用方式不变)。

新增 maintainer.md 自警:
- **§6.6 SKILL.md 文档边界值 ≠ 实测安全上限**:用 range 上下限前必须 smoke 验证。同源 §6.4 (Pollinations 文档 60req/min 实际单并发)。tokyo plan 用 tail_hold=1.0(SKILL.md 文档允许)直接撞坑。
- **§6.7 Subagent 复杂行为推理实施前必须 single-step smoke verify**:特针对 ffmpeg / filter / 外部 API 类 fix 推荐。tokyo bug 时 Plan subagent root cause 对了(framequeue overflow),但推荐 fix `-loop 1 -t` 与 zoompan per-input-frame 语义冲突,landing 后 inflate 7×。同源 §6.1 (实测优先于推理) 但 surface 不同。

CLAUDE.md 自警速查更新到 7 条(每次自动加载提醒主 Claude)。

**反向追溯效应**:tokyo-editor manifest.json 的 `errors[]` 已正确记录 `tail_hold_attempted=1.0 / tail_hold_used=0.3 / recovered=true`——maintainer SOP §4 "failure budget" 流程在第二支视频跑通时自然触发,无人工介入。该 manifest 字段是反向追溯升级机会的金矿。

## V0.4.1 — 2026-04-27

**零 API-key 路径** — 解决 "无 ANTHROPIC_API_KEY → script-gen broken → overall broken" 的 day-1 痛点(三方合议 D 方案落地)。

新增:
- **`prompts/script-system.md`** — 主 Claude in-context 出 director-schema script.json 的 system prompt(直出 `idx / narration / image_prompt / seed`,跳过 script-gen 的"导演视角 schema → director 视角 schema"转换层)。含平台风格速查表 + TikTok 风险红线(品牌词/医疗算法降权词/NSFW 误判/FDA 警告项,从 earwax plan agent 提炼)。
- **`pipeline.md` step 1 重写**:默认走 in-context (无需 key);可选 `--use-script-gen` 走原 CLI 路径(适用长对话迭代>3 轮 / SEO 矩阵 20+ 变体 / session 持久化)。降级流程:CLI 失败自动 fallback in-context,只在 in-context 也失败时停下问用户。
- **`bin/check-health.sh` `optional` 豁免**:agent 自报 `extra.optional=true` 时,其 broken/degraded/error **不升级** overall(其他非 optional agent 的 worst 决定 overall)。本 release 只 script-gen 标 optional;其余 4 个仍 critical。
- **`maintainer.md` §6.5 Optional agent 设计选择**:加第 5 条自警(标 optional 前必须真有 fallback / fallback 质量不显著低 / 何时回头去掉)。
- **`CLAUDE.md` 自警清单速查** 加第 5 条简短版(每次自动加载提醒)。

**配套 upstream**:script-gen V0.2.1 (commit `a7959e5`) 标 `extra.optional=true`,severity 仅 key 缺失时从 `broken` 降 `degraded`(SDK 缺仍 broken,无 env 能修)。

**实测结果**:`bin/check-health.sh` 本 release 后输出:
```
overall: ok
script-gen 0.2.1 degraded opt=true   ← 不计入 overall
picture-gen 0.2.0 ok
audio-gen 1.0.2 ok
bgm-gen 1.0.2 ok
video-gen 0.3.0 ok
EXIT: 0
```

之前 V0.4.0 是 `overall=broken / EXIT=2`(script-gen ANTHROPIC_API_KEY 缺)。day-1 痛点消除。

**为什么不上方案 E (script-gen backend switcher 加 Pollinations / ollama / template adapter)** — 500 行 + 4 backend 维护矩阵,而 D 方案 30 行解决 99% 痛点。如果 in-context 长期够用,E 永远不需要做(script-gen 退化为 session/show 的 archive 工具,这本来就是 hex 架构合理终态)。E 留 reactive 触发(in-context 真不够用时再做)。

## V0.4.0 — 2026-04-27

**Maintainer 协议沉淀 + 接入两个 agent V 升级**(三波 maintainer pass 收尾)。

接入两个 agent 升级:
- **video-gen V0.3.0** (`9565fb6`):narration 单 pass mux 合进 video。**pipeline.md step 4 加 `--narration scene_NN.mp3,...` 参数**;**step 5 删除 narration concat + 三轨 amix 段**,只剩 BGM 二轨 amix(narration 已在 video 第二条流);BGM 缺失时 step 5 直接 `cp <p>.mp4 <p>_av.mp4` 不跑 ffmpeg。**长度更精确**:V0.3 single-pass 严格按 `sum(d)+N*tail-(N-1)*xd` 公式(本次 9-scene 重渲 earwax = 44.20s,V0.2 两步合是 43.90s 漂 0.30s)。
- **script-gen V0.2.0** (`b070d86`+`faa3b64`):youtube 平台 + 长视频独立 system prompt。**CLAUDE.md 平台映射段重写**:`yt_short → script_gen_platform=youtube --variant short`,`yt_landscape → script_gen_platform=youtube --variant long`(原"临时映射 reels"已知短板**消除**)。**platforms.yaml** yt_short / yt_landscape 改用 native youtube + 加 `script_gen_variant` 字段。

新增:
- **`maintainer.md`**(新文件,本 release 主交付):
  - §1 触发策略(Reactive 默认 + Proactive 事件驱动 ≥5 P2+ backlog 或 2 支视频同因)
  - §2 谁拍板 4 例外(单文件 fix 自决 / 接口设计提案 / 产品方向必问 / 跨层必问 / **成本红线 >2x 必问**)
  - §3 5 步升级 SOP(director 占位 → agent 改测 bump → agent commit → smoke → director 同步 + commit)
  - §4 Failure budget ≤2 + Rollback 触发(smoke 失败 / 同 agent 紧接出新错)
  - §5 Smoke test 协议(锁 seed + 不锁 seed 双跑;断言 manifest + ffprobe + tool_versions 三方对齐)
  - **§6 自警清单 4 条**(实测优先 / 管道纪律 / Edit-Read miss / Pollinations 单并发,**全部从本轮 maintainer pass 自身踩坑提炼**)
  - §7 5 agent 接口契约表
- **`projects/_smoke/`** smoke test 夹具(`manifest.json` + `script/script.json` 入仓,产物不入):3-scene 10s 9:16,固定 prompt + 锁 seed + 期望断言。
- **`bin/run-smoke.sh`**:smoke runner,`--seeded` / `--random` 双跑模式,断言 duration ∈ [9,13]s + resolution 1080×1920 + audio codec aac + 5 agent --version 与 manifest.tool_versions 一致。
- **`CLAUDE.md`**:加"Maintainer 职责"段引用 maintainer.md + 列自警清单 4 条简短版(每次自动加载就提醒主 Claude)。
- **`.gitignore`**:加 `projects/_smoke/` 例外(夹具入仓,产物 images/audio/bgm/renders/logs 不入)。

**剩余已知缺口**(对比 V0.3.0):
- ~~script-gen 无 youtube~~ ✅ 解决(V0.2.0)
- ~~video-gen V0.2 不接 narration~~ ✅ 解决(V0.3.0)
- bgm-gen mood 关键词覆盖窄(8 mood + 中英关键词)— 留 V1.1 (低优,reactive 触发)

**版本号 lockfile**(P3,留 V0.5)— `versions.lock` 钉 5 agent 版本组合,升级走两阶段。本 release 暂未实施,因为本轮 5 agent + director 一次升级到位,lockfile 收益要等下个 P2+ 升级波次才显著。

## V0.3.0 — 2026-04-27

**Maintainer 协议第二波 — 统一健康自检接口落地**(对应 backlog #7,P0 杠杆投资)。

5 个 agent 全部加了 `--version --json` 健康自检接口(各自独立 commit + minor bump):

| agent | from | to | new behavior |
|---|---|---|---|
| audio-gen | 1.0.1 | **1.0.2** | `--version --json` 探测 edge-tts;edge_tts import 下沉到函数内 |
| picture-gen | 0.1.0 | **0.2.0** | 探测 urllib + anthropic(可选)+ ANTHROPIC_API_KEY env |
| bgm-gen | 1.0.1 | **1.0.2** | 探测 pretty_midi + fluidsynth + FluidR3_GM.sf2;pretty_midi import 下沉 |
| script-gen | 0.1.0 | **0.1.1** | 探测 anthropic + ANTHROPIC_API_KEY(critical);所有 heavy import 下沉到 cmd_* / main 内部 |
| video-gen | 0.2.4 | **0.2.5** | 新文件 `scripts/health.py`(skill 不变);探测 ffmpeg + ffprobe + Pillow + pydantic + Noto CJK 字体 |

director 端落地:
- 新文件 `bin/check-health.sh` — 调 5 个 agent 收 JSON,合并成 `{director_check_ts, overall, agents[]}`,timeout 8s/agent;`overall ∈ {ok, degraded, broken, missing-or-error}`,exit 0/1/2/3 同语义。
- `manifest.schema.json` 加 `tool_health` optional 字段(`checked_at / overall / agents[]`),不破已有 schema。
- `CLAUDE.md` 加"健康自检"段:每开新 project 调一次自动填 manifest.tool_versions + tool_health;用户问"谁挂了"时单跑。

**杠杆收益**:首次跑就发现 `script-gen broken` (`ANTHROPIC_API_KEY 未设`,与首支视频遭遇一致)— 从此 director 启动时秒发现这类 env 缺口,不需要等真跑 pipeline 时才挂。

**实测脚踢**:写 check-health.sh 时自己又踩了一次"管道吞 exit code"(`./check-health.sh | jq` exit 0 而 direct 是 2)。V0.2.2 写过的"管道纪律"段第一次自我应用就被忽略——已加进 maintainer.md 的"自警清单"(等收尾 V0.4.0 时落)。

## V0.2.2 — 2026-04-27

**纠错 + 管道纪律 + bgm-gen 元数据对齐**(maintainer pass 第一波,实测驱动)。

V0.2.1 写"picture-gen exit-0-but-failed bug"是**误判**——mock `urllib.error.HTTPError(429)` 验证后,picture-gen `main.py:47-51` 的 `try/except Exception → return 1` 是健康的,真实 exit code 在 429 时确实是 1。问题在 director 端 `python3 <agent>/main.py ... 2>&1 | tail -3` 的 shell pipe **吞 PIPESTATUS** —— pipe exit = 最后命令(tail)= 0,picture-gen 的真实退出码被掩盖,主 Claude 当时误以为是 picture-gen 自身 bug。

**变更**:
- `pipeline.md` 新增"管道纪律"段(2026-04-27 V0.2.2 实测教训)— 禁止 `| tail` 吞 PIPESTATUS,给 3 种正确写法(`> log 2>&1` / `${PIPESTATUS[0]}` / `set -o pipefail`),双重保险:exit code + 产物文件存在/大小校验。
- `pipeline.md` 降级矩阵 picture-gen 行 — "exit code 0 即使 429,要看 stderr"改为"已正确返回 exit 1,前提是不要 `| tail` 吞 PIPESTATUS"。
- `bgm-gen` upstream commit `d31286e` 补登 V1.0.1 CHANGELOG(代码 `__version__` 早是 1.0.1,顶部条目漏更)— director maintainer 第一次通过"实跑 → manifest.tool_versions 不一致 → 反向推动 upstream 修元数据",证明 maintainer SOP 反馈环路有效。

**没改 picture-gen**(P0 #1 取消):mock 验证后 picture-gen 行为正确,无需 bump。这次反例本身要写进 maintainer.md(等 SOP 沉淀):**实测验证根因优于 subagent 推理,改 agent 源码前必须 reproducible failure**。

## V0.2.1 — 2026-04-27

首支视频实跑后的 SOP 修正(项目:`20260427-earwax-removal`,60s 英文 explain TikTok)。

实测教训:
- **Pollinations 实际单并发**:首次 4 并发触发 HTTP 429,触发后 IP 进入 ~3min cooldown,期间任何并发都拒。pipeline.md `max_parallel=4` 不适用 picture-gen,改为 picture-gen 全程**串行**;audio-gen / bgm-gen 不受影响。
- **picture-gen exit code bug**:网络 429 时 exit code 仍是 0,只能看 stderr / 产物文件检测失败。降级矩阵补这条。
- **amix `duration=first` 错误**:V0.2.0 step 5 用 `duration=first`,当 narration 短于 video 时(本支 narration 41.57s vs video 43.90s)会截掉视频末段。修正为 `duration=longest` + `-shortest` 让 video 决定最终长度。同步 audio bitrate 显式 `-b:a 192k`(默认 128k 偏低)。

变更:
- `pipeline.md` Step 2 节流规则改写(picture 串行 / audio 4 并发 / bgm 单跑);Step 5 ffmpeg 命令修 `duration=longest`;降级矩阵补 picture-gen exit-0-but-failed 行。

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
