# pipeline.md — 总导演 SOP

每支视频走以下流水线。所有命令的 cwd / 路径见 CLAUDE.md 的"CLI 调用模板"。

## Step 0 — 解析 + 建 project

输入:用户一句"主题",可选参数 (平台、时长、语言、风格)。

1. 用户没指定时,默认 `platforms=[tiktok]`,`duration_s=30`,`language=en-US`,`style=vlog-warm`。
   - **language 默认 en-US**(用户 2026-04-27 锁定:以后视频配音和文字一律英文,除非用户在本次请求里显式指定别的语言)。voice 默认走 `voices.yaml.en-US.warm = en-US-JennyNeural`(可按 style 改 en-US-AriaNeural / en-US-GuyNeural / en-US-EricNeural)。
2. 生成 `project_id = <YYYYMMDD>-<slug-of-topic>`(slug 取主题前 24 字,非字母数字转 `-`,小写)。
3. 建目录:`projects/<project_id>/{script,images,audio,bgm,renders,logs}/`。
4. 写 `manifest.json`(按 schema,steps.* 全部 `pending`)。

## Step 1 — 出 script.json(默认 in-context,V0.4.1+)

**优先路径(in-context,无需 ANTHROPIC_API_KEY)**:主 Claude 自己 Read `prompts/script-system.md` + 用户给的视频参数,**直接 Write `projects/<id>/script/script.json`**(director-schema:`idx / narration / image_prompt / seed`)。

理由:① 主 Claude 本身就是 LLM,质量 = script-gen 基线;② 直出 director 消费的 schema,省 script-gen "导演视角 → director 视角"转换层;③ 零依赖外部 key。

manifest:`steps.script.status=done / artifact=script/script.json / source=in-context-claude`。

**可选路径(用 script-gen CLI)**:用户显式 `--use-script-gen` 时启用,适用场景:① 长对话迭代打磨(>3 轮反馈) ② SEO 关键词矩阵研究(20+ 变体批量) ③ 用户已设 `ANTHROPIC_API_KEY` 想要 session 持久化。

```bash
cd /home/myclaw/script-gen
uv run python -m cli.main new "<topic>" --platform <mapped> --variant <auto|short|long> --duration <N> \
  2>logs/script.err 1>logs/script.stream
session_id=$(grep "session id" logs/script.err | awk '{print $NF}')
uv run python -m cli.main show "$session_id" > projects/<id>/script/script.raw.json
# 然后跑一个 raw → director-schema 的转换(写主 Claude 当时手活,或 helper 脚本待加 V0.5)
```

manifest:`steps.script.session_id = $session_id` 留着,后续改稿走 `resume` 复用 prompt cache。

**降级流程**:走 in-context 时 script-gen 健康自检 `optional=true / degraded` 不阻塞 `bin/check-health.sh` overall。走 CLI 时若失败(API 超额 / SDK 缺)→ 自动 fallback 到 in-context,不停下问用户(只在 in-context 也失败时停)。

## Step 2 — 并行出 N 张图 + N 段音频 + 1 条 BGM

主 Claude 在**一条消息里发 2N+1 个 Bash 调用**(harness 自动并行,但手动节流到 `max_parallel=4`,避免 pollinations 限流):

```bash
# 每个 scene 一张图(尺寸按平台 aspect 取,见 platforms.yaml)
python3 /home/myclaw/picture-gen/main.py "<image_prompt>" --width <W> --height <H> --no-expand --out projects/<id>/images/.raw/

# 每个 scene 一段音频(voice 按 language+style 取,见 voices.yaml)
/home/myclaw/audio-gen/.venv/bin/python3 /home/myclaw/audio-gen/generate.py "<narration>" -v <voice> -o projects/<id>/audio/scene_NN.mp3

# 整段 1 条 BGM(时长 = max(platforms.duration_target_s) + 2s 给 fade-out 余量)
# style→mood 映射见 CLAUDE.md;style 未指定时不传 -m,让 bgm-gen 自己从 topic 推断
/home/myclaw/bgm-gen/.venv/bin/python3 /home/myclaw/bgm-gen/generate.py "<topic>" -d <total_s+2> [-m <mood>] -o projects/<id>/bgm/track.wav
```

**节流(实测修正,2026-04-27 V0.2.1)**:
- **picture-gen 实际只能 1 并发**(Pollinations 同 IP 严格限流;首次 4 并发会 429,且触发 ~3min IP cooldown 期间任何并发都拒)。
- **audio-gen 安全 4 并发**(edge-tts 不同 endpoint,无冲突)。
- **bgm-gen 单跑**(fluidsynth CPU 密集)。
- 推荐节奏:audio 1-9 分 3 批 (4+4+1) 一气呵成,BGM 同期或紧接,picture 全程串行(每张 ~1-3min);picture 串行链可放后台单 Bash 运行,与 audio/bgm 错峰。

**管道纪律(2026-04-27 V0.2.2 实测教训)**:
**禁止** `python3 <agent>/main.py ... 2>&1 | tail -N` 这种用法判断成功失败 —— shell pipe 默认 exit code = 最后命令(tail),会吞掉 agent 的真实退出码(实测 picture-gen 在 429 时正确返回 1,但 `| tail -3` 的 PIPESTATUS[0] 仍是 1 而 pipe 整体退 0,主 Claude 误判为成功)。

**正确写法**(任选其一):
```bash
# 1. 重定向到日志文件,不用 pipe
python3 <agent>/main.py ... > /path/to/log 2>&1
status=$?

# 2. 用 PIPESTATUS 显式取首位
python3 <agent>/main.py ... 2>&1 | tail -3
status=${PIPESTATUS[0]}

# 3. 启用 pipefail
set -o pipefail
python3 <agent>/main.py ... 2>&1 | tail -3
status=$?
```

**双重保险**:即便 exit code 对了,**还要看产物文件是否真存在 + 大小 > 0**(Pollinations 可能将来引入"软失败"返回 0 字节)。

**重命名**:picture-gen 写到 `images/.raw/<ts>-<slug>.jpg`,主 Claude 跑完后立刻用 `mv` 重命名为 `images/scene_NN.jpg` 并删 `.raw/`。manifest `steps.images.scenes[i].artifact` 写**重命名后**的路径。

## Step 3 — 资产规范化检查

校验 `images/scene_01.jpg ... scene_NN.jpg` 全部存在、`audio/scene_01.mp3 ... scene_NN.mp3` 全部存在,文件大小 > 0。任何缺失 → manifest 标对应 scene `status=failed`,停下问用户。

`bgm/track.wav` 缺失或大小 0 → manifest `steps.bgm.status=failed`,**自动降级为 skipped,不阻塞**(无 BGM 仍出片,step 5 跳过 bgm 混音)。

## Step 4 — video-gen(M 平台并行)

每个平台一次独立 `Skill('video-gen', ...)`:

```
Skill('video-gen', "<title 来自 script.title> \
  --images projects/<id>/images/scene_01.jpg,scene_02.jpg,... \
  --narration projects/<id>/audio/scene_01.mp3,scene_02.mp3,... \
  --aspect <16:9|9:16> \
  --out projects/<id>/renders/<platform_id>.mp4")
```

V0.3.0+ video-gen 直接吃 `--narration` 一次性出带音轨 mp4(`h264 + aac 192k`)。**narration 数量必须 = scenes 数**,否则 video-gen 报错。video-gen 内部 5 步(plan / render / ffprobe / 自评)由 skill 自管,主 Claude 不重复跑。

**timing 约束**:每个 scene 的 `duration_s` ≥ 对应 narration 实际时长(ffprobe 取)+ ~0.2s buffer。video-gen 会按这个公式 plan,不需要主 Claude 干涉,但要把 audio 时长经 manifest 传过去(`steps.audio.scenes[i].duration_s` 字段)。

## Step 5 — BGM amix + manifest 收尾

V0.3.0+ video-gen 已经把 narration 合进 mp4 第二条流(aac 192k)。step 5 只剩 BGM 混入。

**有 BGM** (`steps.bgm.status=done`):BGM 衰减到 25% 跟现有 narration 轨 amix

```
ffmpeg -i renders/<platform>.mp4 \
       -i bgm/track.wav \
       -filter_complex "[0:a]volume=1.0[a0];[1:a]volume=0.25,afade=t=out:st=<video_total_s-1.5>:d=1.5[a1];[a0][a1]amix=inputs=2:duration=longest:dropout_transition=0[aout]" \
       -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 192k -shortest renders/<platform>_av.mp4
```

**关键**:`amix duration=longest` + `-shortest` 让最终长度由 video 决定。`-c:v copy` 不重编 video,只重编 audio。

**无 BGM** (`steps.bgm.status=skipped/failed`):**直接复用 video-gen 出片**,不跑 ffmpeg

```
cp renders/<platform>.mp4 renders/<platform>_av.mp4
# 或者干脆 manifest.steps.video.<platform>.artifact 直接指向 <platform>.mp4 不做拷贝
```

manifest `steps.video.<platform>.artifact` 改为 `_av.mp4`(有 BGM)或保持 `<platform>.mp4`(无 BGM)。所有关键 step (`status in {done, skipped}`) 后,manifest 新增 `completed_at`。

**对比 V0.3.0 之前(V0.2.x)**:那时 step 5 还要先 concat narration / 再三轨 ffmpeg amix(narration + bgm + video)。V0.3.0 把 narration 移进 video-gen 单 pass mux 后,step 5 只剩 BGM 一项,管道更短、长度更精确(直接走 video-gen plan 公式,不再有 V0.2.4 时观察到的 0.3s drift)。

## 降级矩阵

| 故障 | 处置 |
|---|---|
| script-gen Anthropic 超额 | 切 `--model claude-haiku-4-5-20251001`;或停下让用户手填 `script/script.json` 直接进 step 2 |
| picture-gen pollinations 503/429 | **重试必须串行**(IP cooldown);picture-gen 已正确返回 exit 1,**前提是不要 `\| tail` 吞 PIPESTATUS**(见"管道纪律");3 次失败 → 整体停,manifest `steps.images.partial=true` |
| audio-gen edge-tts 文本太长 | 按句号切多段调用,合并 mp3(文本 > 5000 字时主动拆分) |
| audio-gen voice 不存在 | 退回默认 `zh-CN-XiaoxiaoNeural` 或 `en-US-JennyNeural` |
| bgm-gen fluidsynth/SoundFont 缺 / mood 不存在 | manifest `steps.bgm.status=failed` → **自动降级 skipped**,step 5 走"无 BGM"分支 |
| video-gen ffprobe 验证失败 | 不自动重跑,manifest `steps.video.<p>.status=failed`,停下问用户 |
| 某 scene 死活出不来 | **默认 stop-the-world**(质量优先);用户可显式说"跳过 scene N 用 N-1 张" |

## Resume 协议

主 Claude 启动后用户说"继续":

1. 扫 `projects/*/manifest.json`,找最新 `completed_at` 为空的 project。
2. 找第一个 `status` 不是 `done` / `skipped` 的 step:
   - `running` → 上次崩了,manifest `errors[]` 里有上次错;改回 `pending` 重跑。
   - `pending` / `failed` → 直接重跑该 step(per-scene 粒度:images/audio 数组里只跑 status≠done 的 idx)。
3. script-gen 改稿走 `resume <session_id> -m "<反馈>"`,session_id 来自 manifest。

## 平台分叉决策

- 同 duration 不同 aspect:**共享前置**(script/images/audio 复用),只 step 4 分叉。
- 不同 duration:script 必须分叉(剧本节奏不同),建另一个 project 而不是同 project 多变体。
- TikTok 文案要更"抓人" → 走 script-gen `resume` 加一轮 `-m "把开头改得更抓眼"`,生成 `script_v2.json`,manifest 加 `script_variant` 字段。
