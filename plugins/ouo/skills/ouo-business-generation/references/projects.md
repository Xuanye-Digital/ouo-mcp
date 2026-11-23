# 项目定位、目录与协作

## 项目与具体画布定位

缺少准确画布目标时，优先调用聊天内的 `show_project_picker`。选择器支持文件夹、画布空间、近期条目、当前目录搜索和分页。按返回状态继续：

- `selected` 已包含原生表单的实际用户选择和目标核验结果。沿用返回的 `followupRead` 继续原任务。
- `awaiting_selection` 等待用户选择。卡片由 app 专用 `choose_project` 核验目标并交回实际选择。当 `clientContext.proactiveTextFallback=true` 时，先在同一回复中展示真实文字选项及适用的设置提示，再等待选择。按 `textSelectionReads` 解释用户选中的编号或目录操作，具体画布仍用 `target_project` 核验。
- `declined` 或 `cancelled` 结束选择。目录修订失效时刷新重新选择，绑定不匹配或无权限时保留原目标。

用户已经明确指定具体画布 ID、链接或本轮唯一确定的真实目录目标时，直接用 `target_project` 核验，不再重复展示选择卡。沿用其概览、revision 和 followupRead 继续 [画布读取](canvas.md#项目和画布读取)，不紧接着重读同一概览。用户只问有多少或要求文字清单时可以使用目录数据直接回答。明确说“最近”时选择器传 `recent=true`；搜索仅覆盖当前目录，不称作全部项目的全局搜索。项目名称重复时让卡片显示所在路径再选择，不猜第一项或 activeCanvasId。

用户已给出项目或画布空间名称及其中的画布名称时，例如“MO1 的画布1”，先按真实目录找到该容器，再读取其内部画布；同一路径下唯一匹配时直接 `target_project` 核验并继续原任务，无需再要求用户在选择器点击一次。目录未读完、同名、路径不符或无法访问时保留歧义，不能猜 ID、模糊匹配后自动选择或把容器 ID 当画布 ID。后续只补充项目名时，保留原消息已指定的画布名。

卡片返回 `ouo-project-selection-v1` 和对应实际用户提交消息后，沿用其 `followupRead` 继续原任务。选择只确定本轮操作目标。宿主明确不支持原生卡片或旧工具目录没有选择器时，可将真实选项放入宿主仍支持的单选表单。均不可用时使用简短文字选择。

### 用户反馈卡片未出现

工具成功返回、资源可读或 `awaiting_selection` 都不证明宿主已经显示卡片。先实际调用选择器，不能只口头称“已打开”；用户明确说“从头到尾没出现”“打不开”或“空白”后，视为本次选择的显示失败，不再只回复“请在选择器中选择”。

保留原任务、项目路径和已经明确的画布名。优先复用本次选择器的真实 `items`、路径及导航/分页参数，必要时沿原目录只读补查；目标能唯一核实时直接定位。仍有歧义时，在对话中列出当前页真实名称和路径，让用户文字选择，说明有下一页时继续按原参数读取。不要自动重复打开同一选择器或再换一张同链路表单；用户明确要求重试时才重试。文字选择后由 `target_project` 重新核验权限，不代调用 app 专用选择动作，也不产生付费许可。没有真实目录时说明当前无法读取，不编选项或声称已选定。

需要由 Agent 解析准确名称或检查目录时，用 `list_projects` 读取当前业务空间的项目/文件夹目录，文件夹用 `parent_id` 继续读取。工具契约支持 `canvas_space_id` 时，对画布空间条目使用该参数列出内部具体画布；不能把登录授权的 OUO 空间 ID 填到这里，也不能把容器条目 ID 直接用作节点操作的 `project_id`。旧服务未暴露这个参数时不要调用未知入口或猜测 ID。

用户说“最近的项目/画布”时，当前 schema 支持 `recent` 才传 `recent=true`，读取后端本次返回的近期条目；不要猜文件夹或把第一项视为用户选择。近期条目仍可能是画布空间容器，按其实际类型继续读取内部画布，再明确定位。它不是全部访问历史，也不切换网页或激活项目。

`ouo-project-directory-v2` 在根目录、文件夹、近期条目和内部画布中都把已知身份字段返回为精确十进制字符串。`parent_id` 原样使用返回 ID；不要转为 JavaScript Number，长 ID 禁止数值输入。目录默认 20 条；原样使用 `nextRead` 续读，`totalScope=returned_collection` 仅统计本次后端集合。`PROJECT_DIRECTORY_CHANGED` 后从 offset=0、无 expected_revision 重新读取；不拼接两版内容。目录 revision 仅用于目录读取，不是当前节点的编辑前提。`activeCanvasListed` 依据完整本次集合，不代表当前页一定含该画布。

内部目录返回 `directoryKind=space_canvases`、`canvasSpaceId` 和精确字符串形式的具体画布 ID。`activeCanvasId` 仅是已观察的激活状态；不在可见列表时 `activeCanvasListed=false`，不得改选第一项或视为已有权限。根据用户明确目标选择实际返回的画布，再用 `target_project` 核验，后续携带其明确的项目及修订参数。目录读取不切换网页、不修改激活画布，也不能扩大已绑定项目的授权。

## 协作成员与分享配置

当前工具目录包含 `read_canvas_access` 时，可以只读核验已有配置。`view=members` 传准确 `collaboration_item_id`，它是可配置的画布空间或独立画布条目，不是授权 OUO 空间；空间内的具体画布可能继承父级配置，不能猜测或自动替换目标。`view=shares` 只传准确 `canvas_space_id`。已绑定具体项目的连接不能借父级查询扩大范围；需要其他容器时使用当前账户未绑定项目的连接。

`memberId` 是团队成员记录，`memberUserId` 才是真实用户，缺失时保留 unknown；enabled、角色和配置中出现某人都不能证明当前有编辑权、在线或已持节点锁。在线与占用使用 `read_canvas_collaboration` 读取；实际编辑仍须核对当前权限、占用和修订。

分享读取仅含后端本次返回的仍有效配置，不是已撤销/过期历史或全部访问审计。公开/私密、是否允许复制及查看节点参数均按返回值解释，缺失或未来规则不套默认值；`backendCanCopyProject` 也不是用户复制许可。工具不输出分享短码、不打开链接、不发布/关闭分享、不配置成员。账号、积分、头像和未知字段不会投影。

完整汇总与本页 items 分开，原样使用 `nextRead` 翻页；`CANVAS_ACCESS_CHANGED` 后从首读重来，不拼接不同视图、目标、身份或版本。revision 只用于配置读取，不是节点编辑前提或权限凭据。聊天用自然语言概括，不回显原始 JSON 和内部 ID。

## 项目创建与元数据修改

发现 `prepare_project_change` 后，按用户明确意图准备创建、重命名、封面修改或移动。沿用真实目录的精确字符串 ID；`parent_id` 是所在目录或画布空间容器，不是授权 OUO 空间。根目录/文件夹中创建 `folder` 或 `space`，已有 `space` 中创建 `project`。重命名和封面修改给出准确 `item_id` 及其所在 `parent_id`；标题最多 50 个 UTF-16 单元，封面复用用户明确选择的已知批准 HTTPS 图片。

只有当前 schema 的 action 包含 move 时，才能移动已有条目：提供准确 item_id、原 parent_id 和明确 destination_parent_id，目标只能是已读取的文件夹或显式字符串 "0" 表示根目录。不要把授权 OUO 空间、画布空间容器、网址或文件系统路径当作目标。卡片显示原位置和完整目标路径，用户实际确认后提交；移入自身/子目录、父级关系不完整或路径变化时重读。无关目录新增条目不会阻断。get_project_change 的 directoryRead 指向目标，sourceDirectoryRead 指向原目录；受理之后仍须核验目标中准确条目和原位置已无该条目，不能只凭目标名称报告完成。

同一意图保留同一 `request_id` 和全部原参数。准备工具只读业务并保存私有记录；展示卡片后等待用户实际点击。`respond_project_change` 是 app 专用动作，Agent 不代点击、不推断确认，也不使用脚本绕过。用户取消或确认过期后停止此记录。卡片不自动切换激活画布或打开浏览器。

只有当前 schema 的 action 包含 activate，且用户明确要求设置空间当前画布时，才准备该动作。使用未绑定具体项目的当前账户连接，parent_id 填目录返回的画布空间容器 ID，item_id 填其中准确 project ID，不传标题、封面或目标目录。它们都不是授权 OUO 空间 ID。卡片显示空间、原画布及目标画布；已是当前画布时只读说明，无需提交。确认前会复核原选择、成员关系和可见名称，其他节点或无关画布修改不会阻断。accepted 是实际受理，persisted 与 activationChanged 只在独立 GET 核实 activeCanvasId 后为真；后续他人再次切换会使当前匹配失效。该选择是否影响所有成员由现有后端决定，不能称为仅本机设置。它不打开浏览器、不改变 MCP 项目绑定、不保存节点或执行生成；targetRead 只用于后续明确的项目读取。未知提交仍只查询原记录，不通过另一请求再次切换。

只有当前 schema 的 action 包含 duplicate 时，才可按明确意图复制准确的 project 或 space，不能复制 folder。使用未绑定具体项目的当前账户连接，传原 item_id 和所在 parent_id，不传标题、封面或目标目录。现有后端决定副本名称、位置和复制范围；确认卡针对来源的目录元数据，不能承诺固定源快照或完整图内容已比对。成功后 sourceItemId 是原对象，itemId 是返回的新对象，copiedItemTitle 和 copiedParentId 来自回执；按 directoryRead 核实准确副本，不按同名或最近新增条目猜测。copyContentVerified=false，不把目录匹配说成所有节点已独立验证。后续打开时先核验 targetRead；复制本身不切换页面、激活画布或启动节点。

用 `get_project_change` 读取原记录；只有 `accepted=true` 且 `persisted=true` 时，才能报告本次回读已完成。`accepted` 单独为真只表示收到后端受理回执；`submitting/unknown` 时不重放、不换请求 ID 重建，也不按同名项目猜测成功。`conflict` 表示确认前对象发生变化，应重新读取和确认。`targetRead` 只是下一次 `target_project` 的准确入口，不代表访问权或全局选中。

项目管理只保护原记录的单次提交，不保证不同请求或连接间全局幂等；并发修改后须重新回读核验。移动不切换网页或激活项目，不写画布快照，也不保证并发条件下的原子移动。内部 ID、网址、协议字段和回执不输出到聊天。

## 在线协作与节点占用

用户询问谁在编辑或节点被谁占用时，当前目录包含 `read_canvas_collaboration` 才使用该工具。明确具体画布的 `project_id`，`view=editors` 读取在线编辑者，`view=locks` 读取节点占用；需要定位一个节点时只在 locks 视图传准确 `element_id`。`relatedRead` 可读取另一视图，两次读取期间状态可能变化；这不是 MCP 连接列表。查询保持只读，不改变占用或画布内容。

`userRelation=current_user` 只表示同一业务账号；同账号的多个浏览器会话仍分别返回，不能据此声称当前窗口持有锁。`elementLockObservation=not_listed` 只说明本次未返回该元素锁，不证明节点存在、无人编辑或已有写权限。向用户解释实际返回的占用者，不展示 sessionRef、内部字段或协议 JSON；不要承诺锁到期后一定可写。`backendTimeUnit=not_documented` 时原始整数时间戳不转换倒计时，也不推算是否已过期。

协作占用按本次实际涉及的节点和分组锁判断：未占用就通过既有编辑入口继续，由执行器取锁；被占用就保留该步、继续其他无依赖的已授权工作，锁释放前不反复重试，不释放他人锁。其他用户或 Agent 在线、正在操作其他节点或持有无关元素锁，不构成整张画布停止条件。协作读取既不授予写权限，也不代表写入被拒绝；不将在线名单读取作为每次编辑的前置条件。恢复规则见 [团队协作范围](canvas.md#团队协作范围)。

汇总覆盖完整匹配集合，默认只返回 20 条明细。按 `nextRead` 原样续读；`COLLABORATION_CHANGED` 后从 offset=0 且不带旧 expected_revision 重读，不能拼接变化前后的结果。协作 revision 只用于此次读取，不能作为节点的 editRevision 或编辑授权；实际编辑与结果回填仍按当前修订及保存回执核验。
