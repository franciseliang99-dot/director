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
