# maintainer.md — 总导演的"维护职责"SOP

director 在 V0.3.0+ 不只是"orchestrator"(串视频),还是 5 个 agent (`script-gen / picture-gen / audio-gen / bgm-gen / video-gen`) + 自身的 **maintainer**。本文件是该职责的 SOP,主 Claude 改 agent 代码或 director 自身配置前先 Read。

## 1. 触发策略

| 类型 | 触发条件 | 红线 |
|---|---|---|
| **Reactive(默认)** | pipeline 跑挂 / 现场打补丁 ≥1 次 / agent exit 撒谎 / manifest.errors[] 反复同因 | 必有现场痛点;不是"觉得可以更优"就改 |
| **Proactive(限额)** | **事件驱动**:`backlog P2+ 累积 ≥5 条` 或 `连续 2 支视频出同类问题`(不机械按"每 N 支") | 无现场痛点禁止 proactive 改 agent;director 自己 CLAUDE.md/pipeline.md 可零成本 proactive |

**反模式**(禁止):"借口刷版本号刷绿色"、"为未来可能的需求加抽象"、"看着不顺手就重构"。

## 2. 谁拍板(对齐全局 CLAUDE.md "最优执行" 例外)

| 情形 | 主 Claude 自决 | 必须问用户 |
|---|---|---|
| 单文件 bug fix(P0/P1) | ✅ | — |
| README / CHANGELOG / 元数据补登 | ✅ | — |
| agent minor 行为升级(reactive 触发) | ✅ | — |
| 统一接口设计(跨 agent) | 设计自决,**实施前给 1 屏提案** | 接口 schema |
| 加新功能改产品方向(平台 / 风格 / 模板) | — | **必问** |
| 跨 agent 分层调整(动职责边界) | — | **必问** |
| **引入外部付费 API / 配额消耗 > 当前 2x** | — | **必问(成本红线)** |
| 不可逆 / 凭证 / 删历史 | — | **必问** |

成本红线是 V0.3.0 三方合议时新 subagent 加的隐形项,**不要忘**。

## 3. 升级 SOP(每 agent 通用,5 步)

1. **director CHANGELOG 起 `## upcoming/<agent>-vX.Y.Z` 占位**(标记意图,不 commit)。
2. **进 agent repo 改代码 + 自测 + bump `__version__`**(单 repo 闭环)。
3. **agent CHANGELOG 顶部加段** + agent commit(commit message 带版本号)。
4. **回 director 跑 smoke test**(见 §5)— 通过后改 `CLAUDE.md` CLI 模板 / `pipeline.md` 受影响段 / `platforms.yaml` 受影响项 / `manifest.schema.json` 受影响字段 / `bin/check-health.sh` 命令模板。
5. **director CHANGELOG 写"接入 <agent> vX.Y.Z,变更:..." + bump 自身版本 + commit**(独立 commit,**不跨 repo**)。

**版本号约定**:
- agent 行为变更 = `minor`(0.2 → 0.3),bug fix = `patch`(0.2.1)
- director 接 agent minor 升级 = director `patch`(SOP 微调)
- director 自己加新平台 / step / 大段 SOP = director `minor`
- maintainer 协议本身的引入 = director `V0.3.0`,沉淀 = `V0.4.0`(本次)

**版本号 lockfile**(待落地,V0.5+):`director/versions.lock` 钉 5 个 agent 版本组合。升级走"先 agent bump → director lockfile bump"两阶段,避免连环 bump 把 director 版本号刷爆。

## 4. Failure budget + Rollback

**Failure budget**:同一 agent 升级失败 ≤2 次;第 3 次冻结该 agent + 起 issue 找用户(对齐全局"3 次失败停下问")。

**Rollback 触发**:
- smoke test 失败 → 立刻回滚 director 这边的 CLAUDE.md / pipeline.md commit;agent commit **留着标 `## V0.x.y — REVERTED`**(不要删 git history,留着自警)
- 紧接着出新视频时同 agent 出新错(同根因) → 同样回滚 + 标 REVERTED + 起 issue

## 5. Smoke test 协议

**夹具位置**:`projects/_smoke/`(在 `.gitignore` 里 — 产物不入仓,但 manifest + script.json 入仓,见 §5.5)。

**形态**:3-scene / 10s / 9:16 / 锁 seed 的固定 mini 项目。一次 smoke run ≈ 90 秒(Pollinations 串行 3 张 + edge-tts 并行 3 段 + bgm-gen 一条 + video-gen V0.3 single-pass)。

**双跑**(新 subagent 加的关键增强):
- **跑 1:锁 seed**(`bin/run-smoke.sh --seeded`)— 验回归(产物字节级断言)
- **跑 2:不锁 seed**(`bin/run-smoke.sh --random`)— 验稳健性(只断言长度/编码/codec,不断言字节)

只跑前者会掩盖随机性 bug(seed 解决了边界 case,但 random seed 可能踩另一个分支)。

**断言**:
- `manifest.steps.*.status ∈ {done, skipped}`
- 产物 mp4 存在 + ffprobe `duration ∈ [9.0, 13.0]s`
- 产物 mp4 含 audio stream `codec_name=aac`
- `manifest.tool_versions` 与各 agent `--version --json` 输出 `version` 字段一致

**何时跑**:
- 任何 agent 升级后(SOP §3 第 4 步)
- 任何 director CLAUDE.md / pipeline.md 改完
- **不在每次出真视频时跑**(浪费 Pollinations 配额,只在升级后跑)

**失败处理**:见 §4 Rollback。

## 6. 自警清单(从已发生反例提炼)

每次 maintainer pass 开始前 Read 一次,避免重蹈覆辙。

### 6.1 实测优先于推理(V0.2.2 起)

**反例**:V0.2.1 推断 picture-gen 有 exit-0-but-failed bug,Explore subagent 推理推荐改源码。**5 行 mock Python 验证后证伪** — picture-gen 实际正确返回 exit 1,bug 在 director 端 `| tail -3` 吞 PIPESTATUS。**改 agent 源码前必须 reproducible failure**;subagent 推理不算证据。

### 6.2 管道纪律(V0.2.2 起,V0.3.0 自踩)

**反例**:V0.2.2 写过的"管道纪律"段,V0.3.0 写 `bin/check-health.sh` 测试时**自己又踩了一次**(`./check-health.sh | jq` exit 0 而 direct 是 2)。

**规则**:`python3 <agent>/main.py ... 2>&1 | tail -N` 是错的(pipe exit = 最后命令 = 0)。三种正确写法:
- `> log 2>&1` 重定向(不用 pipe)
- `${PIPESTATUS[0]}` 显式取首位
- `set -o pipefail` 让 pipe 取首失败

**双重保险**:exit code + 产物文件存在 / 大小校验。

### 6.3 Edit-Read miss(V0.4.0 起)

**反例**:script-gen V0.1.1 + V0.2.0 commit 都漏了 `pyproject.toml` + `CHANGELOG.md` — Edit 工具要求先 Read 才能 Edit,我两次都没 catch Edit 拒绝错误,导致 agent metadata 落后于代码两个版本。后续 follow-up commit 才补登。

**规则**:每次 Edit 失败(`InputValidationError: file not read`),**立刻 Read + 重 Edit + 进同一 commit**;不要假设 Edit 静默成功。git commit 前必看 `git diff --cached --stat` 确认文件清单符合预期。

### 6.8 Import-decoupling refactor 必须 grep 全模块 use site(V0.4.3 起)

**反例**:
- picture-gen V0.2.0 加 `--version --json` 时把 `from picture_gen.agent import ...` 从模块顶层移除,但 `main()` 内还引用 → NameError(V0.2.1 修)
- bgm-gen V1.0.2 把 `import pretty_midi` 顶层下沉到 `build_midi()`,但漏改 `_add_drums()` 也用 `pretty_midi.X` → NameError(V1.0.3 修,**同模式第 2 次复发**)

**规则**:任何"为健康自检 / 性能 / 解耦"目的的 import refactor,**实施前 grep 整个模块**所有 use site,确保每个用 import name 的函数都自己 import 或共享一个 deferred-import helper。

**Refactor checklist(每次跑)**:
1. `grep -n "<module_name>\." <agent>/**/*.py` 找所有 dotted use(`pretty_midi.X` / `anthropic.X` / etc.)
2. `grep -n "from <module_name>" <agent>/**/*.py` 找所有 from-import use
3. 列出受影响函数清单,**每个函数都要么 ① 自己 import ② 接收依赖作参数 ③ 模块 top-level try-import + None-check**
4. **production code path smoke test**(不只是 `--version --json`):跑一次真实命令(`generate.py "test"` / `main.py "test"`)验证 NameError 不复发
5. agent commit 前 `git diff --cached --stat` 验文件清单完整(配合 §6.3 Edit-Read miss)

**根本启示**:health-check refactor 的"诚意"是想 decouple 重依赖让 healthcheck 在 lib 缺失时仍能 report broken。但 decouple 不彻底会**比不 refactor 更糟**(silently break production)。要么彻底(全 module 改)要么不动,**不要半改**。

### 6.7 Subagent 复杂行为推理实施前必须 single-step smoke verify(V0.4.2 起)

**反例**:video-gen V0.3.1 修 tail_hold_s deadlock 时,Plan subagent 给的 root cause 诊断**正确**(ffmpeg framequeue 在 tpad clone stage overflow),但推荐的 fix 方案 A(`-loop 1 -t` per png input,声称 zoompan `d=` 会 hard-cap output frame count)与 zoompan 实际语义冲突——zoompan `d` 是 *per-input-frame* multiplier,loop input 7.5s × 30fps = 225 帧 → 40500 output frames per scene,tokyo plan 渲到 **1180s / 35K frames / 42MB**,正是 V0.2.0→V0.2.1 history 早警告过的 anti-pattern。

**规则**:subagent 给 ffmpeg / 复杂 filter 链 / 系统行为类的 fix 推荐时,**实施前必须 single-step smoke verify root cause + fix mechanism**(30 秒 mock 跑一下),不能直接 full landing。

**判断要点**:
- ✅ subagent 给 ffmpeg flag / filter 改动 / library API 调用 → smoke verify 必须
- ✅ subagent 给 single-file 文档 / config 改 → smoke verify 可选(改动 reversible 且小)
- ✅ subagent 给跨 agent 接口设计 → smoke verify 必须(影响多个 repo)
- ❌ subagent 给纯文本(README / commit message)→ 不需要 smoke

这条跟 §6.1 (实测优先于推理 picture-gen 误判) 同源,但 surface 不同——§6.1 是"subagent 推理某 agent 有 bug,实测发现没有";§6.7 是"subagent 推理 root cause 对了,但推荐的 fix 实测发现破坏其他不变量"。

### 6.6 SKILL.md 文档边界值 ≠ 实测安全上限(V0.4.2 起)

**反例**:video-gen V0.2.x SKILL.md 写 `tail_hold_s` range `0.0-1.0`(default 0.3),tokyo-editor 用 1.0 触发 ffmpeg deadlock,video 卡 6s。实际只 default 0.3 被验证过,1.0 是 wishful spec。Plan agent 给我的 video plan 时按 0-1.0 范围设计,直接撞坑。同源 §6.4 (Pollinations 4 并发文档允许实际坏)——**文档允许 ≠ 实测安全**。

**规则**:边界值用前必须**小样本测**(文档里默认值通常是经过验证的 sweet spot;range 上下限值得怀疑)。
- 用文档默认值 → 可信
- 用 range 上限/下限 → 必须 smoke 确认
- 用 range 中间值 → 一般可信但有疑必验

**适用场景**:ffmpeg filter 参数 / 外部 API rate limit / TTS voice list / model token cap / etc.

### 6.5 Optional agent 设计选择(V0.4.1 起)

**反例**:V0.4.0 之前 script-gen 强依赖 `ANTHROPIC_API_KEY`,key 缺失就 `broken`,`bin/check-health.sh` overall 必 broken/degraded,首支 earwax 视频在这卡住一次。

**规则**:agent 在 health JSON 里加 `extra.optional: true` 自我标记"可选 — 我挂了不阻塞 pipeline"。前提是 director 必须有 fallback 路径(script-gen 的 fallback 是 V0.4.1+ 的"主 Claude Read `prompts/script-system.md` in-context 出 script.json")。

**判断要点**(下次想标 optional 时自问):
- ① 有没有真正的 fallback?光标 optional 但没 fallback 是欺骗
- ② fallback 质量是不是不显著低于本 agent?显著低则不能标(silently 降质)
- ③ 标 optional **不等于** 删 agent。何时仍需要原 agent?要写进 CHANGELOG(script-gen V0.2.1 写了:长对话迭代 / SEO 矩阵 / 离线场景)

**何时回头去掉 optional**:fallback 路径长期不够用(reactive 触发) 或 该 agent 升级到与 fallback 不可替代的程度。

### 6.4 Pollinations 单并发(V0.2.1 起)

**反例**:首支视频 4 并发 picture-gen 触发 429,IP 进入 ~3min cooldown。subagent 估"60 req/min 阈值"过乐观,**不可信**。

**规则**:picture-gen 必须**全程串行**(audio-gen 可 4 并发,bgm-gen 单跑)。任何外部 API 限流以**实测为准**,不信公开文档数字。

## 7. 与 5 个 agent 的接口契约

| agent | 当前版本(V0.4.0 时) | 契约文件 |
|---|---|---|
| script-gen | V0.2.0 | `cli/main.py:main` + `app/prompts.py:build_system_prompt(platform, duration_sec, variant)` |
| picture-gen | V0.2.0 | `main.py:main` |
| audio-gen | V1.0.2 | `generate.py:main` |
| bgm-gen | V1.0.2 | `generate.py:main` |
| video-gen | V0.3.0 | `scripts/render_video.py:main` (CLI) + `SKILL.md` (skill) + `scripts/health.py` (health) |

每个 agent **必须**实现 `--version` (plain) + `--version --json` (健康自检 JSON,字段对齐 director 协议)。

## 8. 跟 CLAUDE.md / pipeline.md 的关系

- `CLAUDE.md`:**自动加载**到主 Claude context,锁定每次都要顾的"调用契约 + 命名规范 + 平台映射 + 失败纪律"。
- `pipeline.md`:**按需 Read**,跑视频时 Step 0~5 SOP。
- `maintainer.md`(本文件):**按需 Read**,改 agent 代码或 director 配置前看一眼。

不重复以上两份的内容,只补充 maintainer 角色专属的元规则。
