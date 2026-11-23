# 制作工具与数据

先读 `get_production_contract`，再按当前工具输入 schema 构造参数。工具存在不等于所有阶段当前均可执行。

创建或推进内置角色提取、场景提取或拆分镜前，核对返回的 `builtinAdapters`：对应条目须有 `executionAvailable=true`；`character_extract`/`scene_extract` 还须有 `pricingBasis=usage_settlement` 及明确不预消费的 `costNotice`，`storyboard` 阶段的 `text`/`script` 须在 `usageSettlementStages` 中明确包含 `storyboard`。字段缺失、旧报价标记或不匹配均表示当前尚未支持此路径，使用用户允许的 Codex 文本阶段或保留缺口，不自动切换执行方式或绕过费用流程。不要通过准备任务或 `advance_production_run(max_submissions=0)` 试探计费；查询原回执使用 `get_production_run` 和 `get_business_task`。

## 创建与恢复

- 用 `show_project_picker` 选择画布，或用 `target_project` 验证用户已指定的准确目标；保留实际 project ID。
- `list_productions(project_id)` 找已有记录，`get_production(production_id)` 恢复总览。读 `view=sources/episodes/scenes/entities/states/shots/assets/jobs/outputs/editorialReviews/editorialTargets/reviews/timelines` 获取完整内容；下一页沿用返回的 `expected_version`，不要拿总览的前 30 个素材当全部素材。
- `save_production` 创建/替换完整 `ProductionGraph`。修改必须带原 production_id、expected_version 和稳定 request_id；失败后保留同一请求的完整内容。原稿和旧状态不覆盖，追加新来源 ID、状态 ID。
- `set_production_engines` 保存阶段选择，先按 `engineOptions` 核对该阶段实际可用的执行器。新选择使用 `host` 表示当前宿主按 Skill 编写或检查内容，`builtin` 对用户称“OUO 生成服务”；镜头显式设置（包括 auto）优先于全剧设置。当前没有宿主媒体能力协商和阶段执行接入，图像、视频、声音及合成仅支持 `builtin`/`auto`，媒体自动模式也使用 OUO 服务。不能以宿主编排为由，将选择 `host` 的媒体任务提交给 OUO。历史 `codex` 值按契约兼容，旧选择及回执保留原样；旧选择可读且允许保持原值保存其他内容，新选择及新任务会验证能力；已受理任务继续查询原回执，现有成果保留。文本选择 `host` 后，直接保存编写或审阅成果，不提交该阶段的 OUO 任务。所有真实生成均遵循对应服务的费用授权。

宿主支持媒体生成须由实际可调用的图片、视频、音频或渲染工具证明，并核对其输入、参考素材、授权和产物回传合同；仅有 Skill、消息发送、MCP serverTools 或文本采样能力不能证明。当前未接入时说明缺口，不伪造能力字段。宿主已经生成的真实媒体可以经原生上传登记和准确素材绑定作为已有素材复用，不直接写任意本地路径、URL 或手工成功回执。成片核对也按当前宿主实际查看、播放及媒体信息能力记录证据，未查看的项目用 `not_checked`，不能只凭提示词写“通过”。

核心层级是 `sources → episodes → scenes → shots`；全剧共享 `entities → states → assets`。每个镜头引用真实 sceneId，场景引用 episodeId。全部 ID 是稳定业务制作 ID，不能拿显示名称、业务任务号或 Canvas ID 替代。

### 制作规格与脚本字段

实时制作契约含 `productionPreferences` 时，在拆镜前用 `save_production.graph.preferences` 或 `set_production_engines.preferences` 保存真实用户选择：`aspectRatio` 为准确宽高比，`videoModels` 为当前目录的准确模型名，可包含多个。`set_production_engines` 可只传 preferences，仍带准确版本及稳定 request_id；传入的是完整偏好结构。此步骤不计费、不确认生成。

先用 `list_models(kind=video)` 读取当前空间目录，再读每个选中模型的 `get_model_parameters`，保存前核对其模式、比例、可用时长、参考及声音规则。模型契约可能在 `rules` 中给出条件限制，不仅看通用 `duration` 描述。每镜指定实际 `stagePrompts.generate_videos.modelName`、已编写 `text` 与完整 `modelParam`；无统一全剧时长上限。准备及派发时会拒绝未选模型、不同画幅和不足以承载已保存镜头的时长，实际可用范围仍按实时模型契约检查。旧记录没有 preferences 时保持可读，继续规划前先补齐选择。

实时镜头 schema 支持 `storyboard` 时，将 `dialogue`、`action`、`emotion`、`lighting`、`reference`、`scene`、`focalLength`、`sceneTag` 和 `soundEffect` 分别持久保存，按原稿核对，不从混合提示词反推事实。`description`、`durationSeconds`、角色身份和场景名称沿用各自字段，图像/视频 `stagePrompts` 分别投影到原生 `shotPrompt`/`motionPrompt`。旧工具缺少新字段时，保留有分节的制作说明，并用原生 `write_script`/`edit_script` 保存真实脚本字段；不能发送实时 schema 未声明的字段。

## 连续性最小示例

以下是制作记录的工具数据片段，执行时补齐完整 schema 和其他对象；这些 JSON 不写入用户的剧本文本节点或生成提示词。状态记录不要求逐条创建画布节点；是否需要状态参考素材按 [工作流框架](canvas-workflow.md#素材复用与视觉变体) 判断。

```json
{
  "entities": [{"entityId":"hero","kind":"character","name":"主角","initialStateId":"coat_ok"}],
  "states": [
    {"stateId":"coat_ok","entityId":"hero","version":1,"label":"外套完整","patch":{"coat":"完整"}},
    {"stateId":"coat_torn","entityId":"hero","version":2,"label":"外套破损","parentStateId":"coat_ok","patch":{"coat":"右袖撕裂"}}
  ],
  "shots": [
    {"shotId":"tear","sceneId":"street","title":"袖口撕裂","order":0,"storyTime":10,"entityIds":["hero"],
      "events":[{"eventId":"tear_event","entityId":"hero","fromStateId":"coat_ok","toStateId":"coat_torn","description":"被门框勾破"}],
      "assetRequirements":[{"entityId":"hero","role":"character_reference","stateAt":"in"},{"entityId":"hero","role":"character_reference","stateAt":"out"}]},
    {"shotId":"leave","sceneId":"street","title":"离开","order":1,"storyTime":11,"stateFromShotId":"tear","entityIds":["hero"]}
  ]
}
```

`scene.order` 是集内场次顺序，`shot.order` 只在该场次内排序。需要交叉剪辑、插入闪回后返回原场次时，为该集全部镜头填写唯一 `editOrder`，它是跨场次的剪辑顺序；不要用 `storyTime` 排剪辑。原生画布分镜按 `editOrder` 排列，整集 `timelines.clips` 也应按同一剪辑方案编排。共享场景资产是 `kind=scene` 的 entity；叙事场次是 `ProductionScene`，两者不能用同一显示名称代替准确引用。

`storyTime` 是故事中的时间。`stateFromShotId` 继承同一分支的完整状态；`stateSources` 为单个实体指定准确来源，可以显式合并同时发生的平行分支。闪回用独立 continuityBranch 和对应早期状态建立根；所有来源的故事时间必须不晚于当前镜头。需要恢复状态时记录修补、换装等事件，不能覆盖旧状态。

例如主角在 `tear` 撕破外套，另一地点的 `break_key` 折断钥匙，随后 `join` 会合：

```json
{"shotId":"join","sceneId":"street","title":"会合","order":2,"storyTime":30,
 "stateFromShotId":"tear","entityIds":["hero","key"],
 "stateSources":[{"entityId":"key","fromShotId":"break_key"}]}
```

这样主角状态来自 `tear`，钥匙状态来自 `break_key`；修改任一事件会重新解析会合镜头及真实消费者。不能只把 `join.stateIn` 写成两个最终状态，这会丢失其来源。`stateIn` 在有来源时是状态断言，不能覆盖已继承的状态。

`sourceSpans` 用 Python/Unicode 字符索引的 `[start,end)` 指向原文；提供 quote 时必须逐字一致。保留原稿中对白和发声类型。对白、机位、小镜头区间、切镜理由按当前 Shot schema 保存；没有专用字段时放入有清晰分节的 description，不能发送 schema 外字段。

## 生成前编导审阅

`editorialReviews` 保存对已编写内容的审阅，`reviews` 保存对真实媒体输出的检查。没有生成媒体时即可保存编导审阅，不创建虚构 outputId。

1. 先保存本轮原稿、分集、实体、状态、分镜和提示词，再读取准确版本。跨页读取均带同一 `expected_version`。按实际审阅范围选择一集或全剧，从总览 `editorialReview.targets` 或 `view=editorialTargets` 的 items 中读取对应 `episodeId` 的 `inputDigest`；全剧的 episodeId 为 null。原样使用工具返回的摘要，不自行猜测或用请求摘要替代。
2. 按用户目标、所选写作 Skill 与适用于本次任务的编导规则检查实际读到的内容。追加记录包含稳定 `reviewId`、`episodeId`（全剧为 null）、本次查看的 `productionVersion`、对应的 `inputDigest`、`reviewer`、`method`、`verdict` 和 `checks`。使用 `save_production` 保存完整制作图，保留全部旧记录，沿用准确版本及稳定请求 ID。
3. 新记录使用 `reviewer=agent`，method 按实际检查选择 `script_analysis` 或 `storyboard_review`。当前可信用户评审入口未接通，不能新增 `reviewer=user` 或 `method=user_confirmation`；历史 `codex` 值及原评审记录保留原样，不迁移或重写。checks 的 aspect 为 `source_fidelity`、`entity_identity`、`shot_coherence`、`cut`、`screen_direction`、`continuity`、`dialogue`、`timing` 或 `prompts`，每项 evidence 写出实际依据及问题所在。只记录已经执行的检查；未检查项使用 `not_checked`。`passed` 要求本记录全部检查通过，存在失败项用 `needs_changes`，仅有待核对项用 `inconclusive`。
4. 保存时版本或摘要冲突，重新读取并核对受影响内容后提交。旧审阅不可删除、改写或重排；修订完成后追加新 `reviewId`。查看 `view=editorialReviews` 返回的 `editorialReviewContext[reviewId]` 的 `currentInputs` 和 `latestForTarget`，不要把已失效或被后续审阅替代的结论当作当前通过。状态、前置事件、分镜顺序或素材引用等有关输入变化需要重新检查；运行进度和单独增加审阅不会使内容审阅失效。

`prompts` 检查的 evidence 说明本次已读取并应用的写作 Skill 和用户要求，并指出实际内容是否满足目标、事实和约束是否一致、台词与画面是否明确对应及模型是否支持。用户明确选择其他写法时按其依据审阅，自然段、声画表、分镜脚本或模型结构化格式都可满足。参数和引用核对不能单独代替写作审阅，未检查的项目保留 `not_checked`。审阅不自动授权改写用户给定提示词；按 [视频提示词审阅](video-prompts.md#独立审阅与保存) 处理实际问题后，对准确新输入追加审阅。

这些记录表达具体检查证据，不表示未检查的项目已通过。按用户目标处理发现的问题；内容审阅和用户对剧情的确认都不授予生成、重做或静默扣费权限。

## 上传与素材复用

1. 本地素材用 `upload_media` 原生文件选择卡，等用户实际上传；只保留 upload_id，不索取文件内容。宿主本任务生成或用户明确指定的准确文件，可按 [本机 Blender 上传流程](../../ouo-blender-previs/references/local-bridge.md) 使用随包脚本及原生准备/完成入口直传，复用实际已登记 upload_id。不能猜路径、伪造回执或把上传当成后续生成授权。
2. `bind_production_asset` 用真实已登记 upload_id，或准确的 library + asset_id，绑定 entity_id、state_id、role。绑定不生成、不扣费，也不等于保存个人库或分享团队。
3. 有多项候选时 `show_production_assets` 显示原生素材卡；按 media_kind、精确状态和参考用途选。团队素材必须有明确 canUse。
4. 总览 analysis 检查缺口与冲突。`role` 在需求和素材间保持一致；`stateAt=in/out` 分开表达变化镜头的首尾。角色声音与可见形象可以使用不同用途。

不要手工拼永久 URL、libraryId 或可用性。绑定工具保存准确来源凭据；生成素材从制作任务的真实输出自动回写。没有匹配的上传/库存/旧结果才准备素材生成步骤，并绑定 entityId/stateId/assetRole。

视频默认使用多参考模式，将角色、场景、道具及当前状态素材直接传入实时契约的分类型 reference_* 数组，或 Kling 的 image_list.image_url / video_list.video_url。先读取实际模型和参数，核对多参考能力、数量限制及各素材用途；不为每个镜头安排首帧生成。缺少共享实体/状态素材时才增加相应素材生成任务，绑定 entityId/stateId/assetRole，后续镜头复用。已有素材齐全时，generate_videos 可以作为首个付费步骤，不依赖 generate_images。

已选素材必须进入该型号及模式实际接收的媒体字段。图片生成使用 image_ref；用户选择首尾帧模式时使用该模式的真实帧字段。素材 URL 只出现在提示词、描述、额外元数据或供应商 element_id 中不能证明已关联。未核验的原生 media/文件/网页扩展不用于准确素材绑定；先选择已支持的字段或保留缺口，不能声称模型已使用素材。

角色/场景变体生成使用各自第一张已确认的基础图作图生图母图，并保留真实来源。按当前模型契约把母图传入 `image_ref` 等已支持字段；母图仍在本次 run 中生成时，只能通过真实支持的依赖输出引用填入参考参数，不能编造未来 URL。当前工具若无法提前创建带未完成母图依赖的计划，就先完成母图、回查并绑定真实输出，再准备变体步骤。缺少图生图能力时保留缺口，不自动另起文生图任务。

## 任务 DAG 与结果

`create_production_run` 准备本集或一批可管理的步骤。每步包含稳定 stepId、stage、kind、title、parameters，以及可选 shotId/episodeId 或生成素材的 entityId/stateId/assetRole。生成参数来自实时模型契约；OUO 生成服务参数先由 `prepare_business_task` 核对。

需要填充已连接分镜的原生素材占位时，先读取该项目下准确节点的 `editRevision`，并在实时步骤 schema 支持时增加 `canvasTarget={"nodeId":"准确节点ID","expectedEditRevision":"sha256:当前修订"}`。适用于 image/video/video_merge/voice_timbre/voice_synthesis/music 媒体步骤；目标种类、忙碌状态和修订在生成前重新核验。一个运行的不同步骤使用不同目标，省略该字段保持新建目标行为。回填继续使用原节点及原任务凭据，使已有下游引用自动解析结果；不能通过改 nodeId 或重建 run 来覆盖别人的内容。

镜头生成请求的实际 prompt、negative_prompt、已选模型和已保存 modelParam 必须与制作记录一致。模型专用改写先保存到 prompt.modelParam.prompt；Kling multi_prompt 或 draft_upscale 同样先保存和审阅。依赖输出可以填写媒体字段，不能覆写提示词或模型。准备和恢复提交均会检查。

画布中已经插入原生 `@` 的提示词单独保留，不把编译标记作为模型正文，也不把模型正文直接写回覆盖引用。绑定已有目标的生成准备返回 `canvasPromptPreserved=true` 时，核对其提示词摘要并回读原节点；模型请求仍使用制作记录中的准确参数。修改剧情时先用 `set_prompt` 更新画布文字及引用并读取新修订，同时保存、审阅对应模型正文，再创建匹配授权的新生成意图。同一请求恢复时保持原目标、提示词和模型参数，旧操作凭据不重写。

需要同一镜头的可选静帧图与视频使用不同模型或措辞时，分别保存 `prompt.stagePrompts.generate_images` 与 `prompt.stagePrompts.generate_videos`。每项是完整的 text、negativeText、modelName、modelParam；显式阶段项替代该阶段的共享提示词合同，未设置的阶段沿用原 prompt。只保存本次实际需要的阶段，两个阶段不自动建立依赖。多参考视频直接绑定准确素材，先审阅后将 prompt.status 设为 ready，不要求先生成镜头图片。

- `dependsOn` 只表达必须成功的上游步骤。
- `references` 明确 fromStepId、outputIndex 和 parameterPath。仅在需要本次 run 尚未完成的素材输出时设置，路径替换必须已存在的参数字段，例如 `["model_param","reference_images",0]` 或 `["model_param","image_list",0,"image_url"]`。已绑定可用素材直接使用准确 mediaRef，不能自己填未来 URL。
- 已有素材引用与镜头前后顺序不同；不要为纯剪辑顺序建立不必要的媒体依赖。
- 内置文本/提取任务成功后，用原 taskCode 和准确 kind 调 `get_business_task` 取实际结果，再归一到已有实体、场景、镜头 ID；不要另建一套重名实体。
- 结果输出自动入制作记录，包含原任务和镜头归属。制作完成后仍需检查真实媒体。

`advance_production_run(max_submissions=0)` 不提交新生成，但会查询现有任务并准备就绪报价或按实际用量扣费提示，不能视为纯只读查询。涉及内置提取或拆分镜时，先完成上文的不预消费能力核验。真正执行时保持同一 run_id；每次调用有界，循环到完成或确实需要用户输入。不要用无意义的高频轮询；按照实际任务的排队和运行状态等待。

## 费用与停止

`prepare_production_budget` 只展示审核卡。费用授权由用户真实点击创建，Agent 不调用 app 专用的 `respond_production_budget`。per_task 绑定 stepId + parameterDigest；episode 绑定 episodeId；run/bounded_silent 仍限定模型、阶段、单笔、总额、期限和重试次数。

预估价格与实际结算可能不同，按工具披露处理，不能把 token 预估描述成硬扣费上限。只有明确返回 usage_settlement 的任务可在金额未知时执行；其他任务缺少匹配报价时改用用户允许的 Codex 创作阶段，或保留缺口，不能从其他流程的零价推断免费。

内置角色提取、场景提取和拆分镜不做积分预消费，准备结果为 pricingBasis=usage_settlement、points=null、finalCostMayDiffer=true，并有明确的实际 token 扣费提示。提取使用 character_extract/scene_extract；拆分镜使用 storyboard 阶段的 text/script，其他文本/脚本阶段仍按各自报价，不能跨阶段复用授权。null 表示金额未知，不是免费；不调用预消费接口，也不伪造 0 或 0.01 积分。逐任务确认用 per_task，省略 total/perTask，传 stepId、parameterDigest、retryLimit=0、acknowledgeVariableCost=true 及明确模型、阶段和有效期；也可使用覆盖当前任务的有效 backend_balance 授权。没有真实确认或有效静默授权仍不提交。任务成功但没有真实账单时 actualPoints 仍为 null，unpricedTaskCount 记录未取得费用的任务数量。Codex + Skill 路径也可独立完成这些文本阶段。

图片、视频及 `finalCostMayDiffer=true` 的内置任务可使用准确逐任务授权（stepId、parameterDigest、retryLimit=0），或用户明确选择的 backend_balance 静默授权；两者均要求 acknowledgeVariableCost=true 和真实卡片确认。backend_balance 不传 total/perTask，服务端回显 null，不伪造无限大额度；仍传 allowedModels、allowedStages、expiresAt、retryLimit。授权范围覆盖同一 run 中尚未就绪的后续步骤，可由 run 卡的 authorizationScope 获取完整模型和阶段列表，不能仅使用当前分页或已报价步骤推断全量范围。

backend_balance 按账户余额及实际费用结算，不承诺金额上限。余额不足时保留已完成结果和当前计划；确认未受理且零扣费的余额失败可以充值后沿用原 run 与授权继续，不消耗生成失败重试次数。unknown 仍须查询原任务，不能以充值为理由重发。其他限额模式对可变结算任务仍要求逐项确认，不能自动扩大用户原授权。

视频按实际时长、token 等结算，图片按实际返回数量结算，最终费用可能超过预估；旧 fixed_generation_quote 同样按可变结算处理。普通生成确认也须披露实际结算可能更高。工具契约核验免费的 video_merge 无需付费额度，但仍保留单次提交及恢复凭据。

失联后用 get_production_run 读取原凭据；unknown 表示受理待核实，不能换 ID 重发。有明确失败且原授权允许重试时，预先登记 retryOf 的有界重试链；重试仍绑定同一逻辑步骤与准确输入。用户停止时 control_production_run，已有任务按真实取消窗口处理；停止后续调度不等于退费。

## 画布和成片

先按 [工作流框架](canvas-workflow.md) 确定本集节点、共享素材和镜头对应，再读取 `get_canvas_editing_contract` 及当前工具 schema。默认通过 `edit_canvas` 创建原生文本、脚本、图片、视频、合成节点和相应分组/引用；脚本使用 `write_script` 保存分镜，不能把脚本的生成输入当成已保存分镜。缺少专门的提取目录字段时使用真实脚本字段和制作记录，不新增伪字段。

已有节点先逐个读取 `read_project_node` 的 `editRevision`，作为本次 `expected_nodes`；新节点用同批创建键引用。参数使用 `update.parameters`，图片到视频的引用使用契约支持的参考连线；实际生成仍需准确媒体参数，不能只凭连线报告绑定成功。保存后用原 `get_canvas_operation` 和独立项目读取核对内容、分组、连线与参数，保留实际节点映射和操作回执。通过当前制作契约保存真实 `canvasBindings`，不编造素材、输出或任务。

只将真实图片、视频、音频素材节点连接到分镜；必要素材为空时也先保留准确类型的 MCP 占位。原稿、脚本及状态说明不能作为视频参考输入。每个角色独立建立音色音频节点，素材/需求沿用 `role=voice`、`mediaKind=audio` 和准确基础状态，发声镜头再明确列出需求。连接后通过 `edit_canvas` 的 `{action:"set_prompt",node_id,parts}` 写入文字与原生引用，使用准确 `source_node_id`、`media_kind` 和主输出 `output_index:0`。已有来源和目标先读取并传修订，同批来源用先前 `$key`，省略 `connection_id`。实际媒体完成后检查原节点结果及下游引用；普通“@角色名”不等于原生引用，模型媒体参数仍须真实绑定。

`sync_production_canvas` 是制作图投影入口。调用前核对其实际输出方式：若会将全部实体、状态或分段代理展开成文本节点，就不用于默认制作画布。只有投影确实满足所选结构，或用户明确要求完整数据视图时才采用；不猜测工具不存在的布局选项。已有投影通过 get / control 查询和恢复同一已授权意图，读取真实操作回执并独立核验。用户已停止或否定的旧方案不能自动 resume。

分批上限按实时契约；作用范围可能包含相邻节点和分组成员，不能只按动作条数估算。批次未知或部分保存时先核查原操作，不换请求 ID 重建，也不覆盖用户在此期间的修改。只修改本轮目标，保存成功不表示图片/视频已经生成或合成已执行。

当前仅顺序拼接：以 timelines 记录准确 outputId 与已保存镜头顺序，按 `video_merge` 合同提交合成步骤；默认使用完整片段，不自动裁剪、重排或额外编排音轨。输出 ID、媒体 URL、原生时间线节点不是同一个概念，未渲染的时间线不能称为可播放成片；交付实际结果并检查播放、源片段音画、接点及首尾完整性。

当前不支持新增字幕压制、转场、音量混合或高级输出规格；剧本或本次用户明确要求时说明限制并保留待完成项，不静默忽略；顺序拼接不依赖其他剪辑能力。

合成步骤使用 `stage=compose_episode`、`kind=video_merge` 和准确 `episodeId`，不绑定单个 shotId 或实体。完整覆盖该集镜头，并按 editOrder 或场次/镜头顺序排列；同一镜头可连续拆段，不能漏镜或把故事时间当剪辑顺序。单镜头分集允许一个片段，不要复制片段凑数量。

每个片段使用仍有效的已保存视频 output，或本次 run 的明确视频依赖 `references`。引用路径只能替换 `clips[index].url` 或 `audio_tracks[index].audio_url`；视频依赖保留准确镜头及所属分集，共享音频可不绑定分集。相同 URL 对应多个输出时用 timeline 中的准确 outputId 消除歧义。成功重试可继续供应原逻辑依赖。

合成仅引用制作记录中工具返回且仍有效的输出，保留原任务、输出索引和对应输入版本；不能手写成功状态、来源或任务号冒充回执。遇到 `PRODUCTION_OUTPUT_RECEIPT_REQUIRED`，用原 run_id 调 advance_production_run、`max_submissions=0` 补齐历史来源，再读取新制作版本；不要创建新任务。上传/素材库成品片段以 output.assetId 绑定已核验的同种媒体，优先复用。

有 timeline 时，实际提交保留其中准确片段、音轨、位置和裁剪。秒转帧前读取真实源视频帧率并保存到 clip.sourceFrameRate；不能用整集 fps 猜测源片段帧率。当前 video_merge 合同支持帧单位片段、秒单位音轨及 480P/720P/1080P 分辨率，不提供字幕、音量、格式或输出帧率覆盖。超出能力的要求保留为待渲染事项，不能静默丢弃后宣称交付完成；默认规格也仍需检查真实产物。

设置了 `preferences.aspectRatio` 时，timeline 必须保留该画幅。现有合成仅沿用 16:9 的分辨率映射（480P 有原生像素舍入），非 16:9 的合成在创建计划和提交前返回 `PRODUCTION_COMPOSITION_SETTINGS_UNSUPPORTED`；当前接口没有已核验的比例控制，不将正确的竖屏 timeline 擅自换成横屏。开工前告知这项缺口，保留所选画幅和已有片段；没有 timeline 同样不能绕过检查。无新规格字段的旧记录保留原兼容路径。

查看真实产物后，在 `reviews` 追加检查记录，再用 save_production 保存。记录准确 `outputId`、本次实际查看的 `productionVersion`、`reviewer=agent`、method、verdict 和 checks；不要把检查结论追加到 shot.description 或提示词。先保存输出并读取当前版本，再检查；检查期间版本变化时重新核对。已有检查不可删除、替换或重排，历史 `codex` 值保留原样；重新检查追加新的 reviewId。

```json
{"reviewId":"review_join_1","outputId":"output_join_1","productionVersion":12,
 "reviewer":"agent","method":"playback","verdict":"passed",
 "checks":[{"aspect":"continuity","outcome":"passed","evidence":"逐帧查看该输出，外套右袖与上一镜一致破损，钥匙保持折断。"}]}
```

新记录的 method 使用 visual_inspection、playback 或 metadata；只记录实际执行的方法。当前可信用户评审入口未接通，不能新增 `reviewer=user` 或 `method=user_confirmation`。checks 的 aspect 可为 identity、continuity、framing、motion、cut、audio、subtitles、completeness、technical。`passed` 要求本记录中全部检查通过；未查看的内容用 not_checked + inconclusive。记录检查不会授权重做，也不会使输入或媒体失效；输入改变使旧输出 stale 后，该输出的旧检查不能算作当前验收。单项检查通过不代表整集所有质量项已经检查。
