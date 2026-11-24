# 随包图片与视频提示词指南（自动生成）

由 `scripts/export_marketplace_catalog.py --target codex --write` 从 MCP 内置写作指南导出，不手工编辑。

新编写或获准改写时先读取对应 writing，特定模式再读 patterns，成品示例按需。同一请求复用已读内容；用户指定的 Skill、写法和格式优先，原样保存时保留用户正文。

| 类型 | Skill / 契约 | 随包版本 | 章节 |
| --- | --- | --- | --- |
| 图片 | `image-prompt-writing` / `ouo-image-prompt-guide-v1` | `4` | [writing](prompt-guides/image/writing.md)、[patterns](prompt-guides/image/patterns.md)、[examples](prompt-guides/image/examples.md) |
| 视频 | `video-prompt-writing` / `ouo-video-prompt-guide-v1` | `7` | [writing](prompt-guides/video/writing.md)、[patterns](prompt-guides/video/patterns.md)、[examples](prompt-guides/video/examples.md) |

## 与服务端指南配合

当前连接提供 get_image_prompt_guide / get_video_prompt_guide 时，可读取对应章节。核对返回的 skillName、contract 和 version；相同 Skill 与契约且可识别版本不低于随包版本时，使用服务端指南。工具缺失、读取失败、返回旧版或版本无法比较时，使用本索引链接的完整随包章节，后续 patterns 和 examples 沿用同一依据，不把旧版写作限制混入新版。不能仅凭工具存在就认定写作指南已更新。

随包内容提供文字写作方法，不证明远程工具、原生引用或模型参数能力。保存、素材绑定、生成参数、费用确认和实际执行仍遵循当前已授权连接的真实契约，不从指南示例推断可用接口。没有生成能力时仍可完成获准的文本任务，不能声称已生成媒体。
