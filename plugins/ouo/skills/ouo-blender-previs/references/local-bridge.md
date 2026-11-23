# 本地执行与上传

## Blender

宿主 Codex 使用现有终端或已有 Blender 连接执行本任务脚本，不需要 `ouo_local_*` 工具、桥接器安装或专用制作记录。脚本和工程位于本任务目录；`.blend` 保存后重新打开，核对场景、机位、帧范围及外部素材。实际预览检查和工程重开检查分别说明。

## 启动一次上传

当前原生工具目录或其明确提供的 `toolRoutes` 须能解析 `prepare_local_media_upload`、`complete_local_media_upload` 和 `apply_uploaded_media_to_canvas` 三项操作。聚合目录按实时映射使用 `local_media_upload` 的 `prepare / complete` 及 `manage_canvas_nodes` 的 `uploaded`，保留原 `params`、请求身份与授权范围；不以独立名称未列出判定能力缺失，也不猜测缺少的映射。使用 Python 3.11 以上和 uv，依赖已在脚本中固定；不安装 OUO 本地 MCP，不修改宿主全局配置。

```text
uv run --script <本Skill绝对路径>/scripts/upload_local.py --file <准确预览文件绝对路径> --request-id <本次稳定标识> --name <媒体名称> --handoff <本任务全新交接子目录>
```

使用可保留运行进程的普通终端会话启动，保持同一进程存活。脚本创建交接子目录，不覆盖已有目录，最多等待 20 分钟。脚本只接受一个明确文件，无目录扫描、通配选择、OAuth 或业务 API 地址。它在内存生成一次性密钥，将公共请求写入 `prepare.json`，终端只输出简短阶段，避免终端折行或关闭输入影响参数。读取该文件：

```json
{"phase":"prepare","params":{"request_id":"...","name":"...","manifest":{"file_name":"preview.mp4","file_size":123,"content_type":"video/mp4","file_sha256":"..."},"public_key":{"kty":"EC","crv":"P-256","x":"...","y":"..."}}}
```

这里只展示结构，必须使用实际文件内容。将 `params` 传给原生准备工具；核对返回的原 `uploadId` 与状态，有 `ticket` 才把以下 JSON 写入同目录 `ticket.json`：

```json
{"ticket":"<准备工具返回的完整密文>"}
```

原生远程连接负责 OAuth、账户和空间上下文，只向已有 STS 接口发送文件名、类型、长度、SHA256 与 `group=aigc`。STS 经密文交给这一次本地进程，私钥只在该进程内存；模型、项目文件和日志都不应包含明文临时权限。该密钥不是设备注册，也不用于证明工程或审阅质量。

本地脚本核对原清单、有效期和 HTTPS OSS 对象，用官方 SDK 流式发送，校验实际发送的长度与 SHA256。禁用重定向、环境代理和 SDK 自动重试，保留 TLS 校验。上传结果通过以下结构返回：

```json
{"phase":"complete","params":{"upload_id":"upload_...","file_sha256":"...","outcome":"transferred"}}
```

脚本将实际结果写入 `complete.json`。只将该文件中的真实输出传给原生完成工具。三个交接文件只有公共请求、密文和回执，不含私钥或明文 STS；读取时使用文件工具的原始内容，不从折行的终端画面重建参数。支持可靠标准输入的宿主可省略 `--handoff`，使用同结构逐行交接。

新文件由原上传记录调用现有完成登记；`needUpload=false` 输出 `already_present` 并直接复用既有媒体，不调用 OSS 或后端完成接口。客户端回执不是独立的云端文件校验，最终 URL 和登记仍以已有业务接口为准。

## 中断、取消与恢复

- 准备请求重复时保持原 `request_id`、名称、清单及一次性公钥。服务复用原记录和保留的密文，不重新申请 STS。仍在准备时只查询/重读原记录。
- 密文仅适用于原进程。进程丢失、密文过期或接口结果不明时，用 `get_media_upload` 查询原 `upload_id`；保留当前文件和记录，不换标识自动重传，不声称进程重启即可续传。
- 用户停止时中断该上传进程；脚本在可观察时输出 `cancelled` 或 `needs_reconciliation`。将实际回执送交完成工具，停止后续登记与导入；已开始的 OSS 请求不因本地中断就被认定撤销。没有实际回执时查询原记录并说明未核实。
- `registered=true` 后重复完成只回读原结果；画布保存受理不明时恢复原画布操作，不建立新节点。失败记录不能用新请求掩盖。
- 脚本不实现断点续传或超过 5 GiB 的分片上传。实际失败应报告到相应阶段，保留原文件；不要压缩、拆分或改规格来假装已完成原上传。

## 画布导入

`apply_uploaded_media_to_canvas` 接受既有登记记录，必需 `project_id`、`request_id`、`upload_id`；可选 `title`、`position` 按实时 Schema。无需先收藏个人素材或新建制作任务。服务使用当前目标的编辑会话保存，再独立回读资源节点。

上传授权、画布写入意图与云端付费生成分别匹配用户要求。不要代点 app 专用确认工具；普通用户选文件上传继续使用原生上传卡，本脚本用于用户已明确指定或要求宿主生成后导入的准确本地媒体。
