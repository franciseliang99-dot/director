# 主 Claude in-context 出 director-schema script.json

director V0.4.1+:当 `bin/check-health.sh` 报 script-gen `optional=true / degraded`(无 ANTHROPIC_API_KEY 或用户主动跳过)时,**主 Claude 直接 Read 这份 prompt + 用户输入,Write `projects/<id>/script/script.json`**,不调 script-gen CLI。

这条路径与 script-gen 在产物质量上等效(都是 Claude),但**直出 director 真正消费的 schema**(`idx / narration / image_prompt / seed`),省掉 script-gen 的"导演视角 schema → director 视角 schema"转换层。

## 你(主 Claude)要做的事

读用户给的视频参数(主题、平台、时长、语言、风格),Write 一个完整的 `script.json`,严格按下面的 schema。

**hard rules**:
- **不许 fabricate file paths** — `image_prompt` 是给 picture-gen 的文本,**不是**真实图片路径(那个由 picture-gen 出图后 director 重命名为 `scene_NN.jpg`)。
- **不许调任何外部 API**(包括 Anthropic、Pollinations、本地模型)— 你就是 LLM。
- **每个 narration 长度对齐 voice 时长**:英文 ~150 wpm = 2.5 词/秒,中文 ~5 字/秒。 `duration_s` 至少 = `narration 朗读时长 + 0.3s buffer`,最大 ≤ 6s(video-gen V0.3 上限)。
- **language 默认 en-US**(用户 2026-04-27 锁定:配音+字幕 一律英文,除非用户在本次请求里显式指定别的语言)。voice 默认 `en-US-JennyNeural`(warm),按 style 切 `en-US-AriaNeural` / `en-US-GuyNeural` / `en-US-EricNeural`。`narration` + `caption` 都用英文写,`caption` 上限 50 拉丁字符。
- **scene 数 = 3-9**(video-gen V0.3 cap 是 10,留 1 个余量给 video-gen 内部 plan 调整)。
- **总视频时长**:`sum(duration_s) ≈ 用户给的目标 duration ± 5%`。

## 平台风格速查(对应 platforms.yaml)

| platform id | aspect | 节奏要求 |
|---|---|---|
| `tiktok` / `douyin` / `yt_short` | 9:16 vertical | 第 1 秒抓人 hook;每 scene 3-7s;caption ≤ 12 CJK 字 / 50 拉丁字符 |
| `yt_landscape` | 16:9 horizontal | 15s 价值承诺(非 3s hook);3-7 chapter 60-180s;**额外字段** `chapters[{start_sec,title}] / seo_title (≤70字符) / thumbnail_text (≤6字)` |

## TikTok 风险红线(从首支 earwax 视频 plan agent 提炼)

- ❌ **不出现品牌词**(Q-tip / Kleenex / 等注册商标),用通用名("cotton swabs" / "facial tissues")
- ❌ **不出现 cure / guaranteed / "doctors hate this" / "medical breakthrough"**(医疗算法降权词)
- ❌ **不要真实人体/医疗近距图**(NSFW 误判 + 用户反感),坚持 **flat illustration / cartoon / diagram** 风格
- ❌ **不提 FDA 警告项**(earwax candle、特定补充剂等)
- ❌ **不踩 ASMR 标签**(某些垂类对此敏感)
- ✅ 末尾软提示 "consult a professional" / "follow for more"
- ✅ video description 加固定 "Educational only — consult a healthcare provider for medical concerns."

## 输出 schema(director 直接消费)

写到 `projects/<id>/script/script.json`,**严格** JSON,无 markdown 围栏。

```json
{
  "title": "string — 视频标题(自由格式,不做长度限制;长视频会再用 seo_title)",
  "platform": "tiktok" | "douyin" | "yt_short" | "yt_landscape",
  "duration_sec": int (用户给的目标),
  "language": "zh-CN" | "en-US" | ...,
  "voice": "string — edge-tts voice id, 如 zh-CN-XiaoxiaoNeural / en-US-AriaNeural(按 voices.yaml 选)",
  "bgm_mood": "calm | tense | sad | happy | epic | mystery | funny | cozy",
  "source": "in-context-claude (director V0.4.1+)",
  "scenes": [
    {
      "idx": int (1-indexed, 连续),
      "duration_s": float (1.5 ≤ d ≤ 6.0, video-gen V0.3 强约束),
      "caption": "string — 屏幕上的字幕(短,≤12 CJK / 50 拉丁字符)",
      "narration": "string — 朗读文本(对齐 duration_s × wpm)",
      "image_prompt": "string — 给 picture-gen 的文本提示 (含画风/调色板/构图,9:16 或 16:9 按 platform aspect)",
      "seed": int (可选, 用于 reproducibility, 默认 42 + idx)
    }
  ]
}
```

**长视频额外字段**(platform=`yt_landscape` 必填):

```json
{
  ...所有上面字段...,
  "chapters": [{"start_sec": int, "title": "string ≤ 24 字"}],
  "seo_title": "string ≤ 70 字符,含 1-2 个 SEO 关键词",
  "thumbnail_text": "string ≤ 6 字"
}
```

## 写完后

把文件写到 `/home/myclaw/director/projects/<project_id>/script/script.json`,然后告诉用户已写完,继续 pipeline.md 的 Step 2(并行 picture-gen / audio-gen / bgm-gen)。

不要在用户消息里复述完整 JSON(挤 token),只说"已写到 …,9 scene,总 60s"这样的摘要。
