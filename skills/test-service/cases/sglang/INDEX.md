# SGLang 用例选择索引

先检查目标提交的差异与受影响调用路径，再从下表选择能区分新旧行为的最小用例集。
用例名称是 `run-case.py --case sglang/<名称>` 的参数；具体适用分支、拓扑、阶段和重复次数以该用例 `TEST.md` 为准。
通常适用 `codex/ft-vllm-api-refactor`；debug 分支需记录与适用分支的派生关系。
历史 PASS 不验证新的源码 HEAD。普通选例不读历史报告或所有 run.sh。

| 提交涉及的行为 | 候选用例名称 | 区分能力 / 限制 |
|---|---|---|
| recoverable exception、pause、retry、路由 ACK | `fault-exception-pause-retry` | 异常后四个进程仍在，retry 恢复服务和精度；不能用 kill 替代异常 |
| shutdown 控制线程、活进程退出、overlap | `fault-exception-pause-scale-down` | 主动关闭仍存活的 DP；契约要求 overlap 开、关独立运行 |
| sibling 退出、TP>1 whole-DP shutdown | `fault-tpgt1-whole-dp-shutdown` | TP=4/DP=2；先杀一个 sibling，再验证 shutdown 关闭另一个 |
| process-down、admission、单次缩容 | `fault-kill-pause-scale-down` | 被移除 DP 已死，不能单独证明 shutdown 杀活进程 |
| 多目标缩容 | `fault-kill-pause-double-scale-down` | 一次移除两个 DP |
| 多轮缩容、累积状态 | `fault-kill-pause-continuous-scale-down` | 4→3→2→1；先读冗余专家容量及 survivor unhealthy barrier，成本高 |
| 缩容后再次异常、retry 的成员集合 | `fault-kill-scale-down-exception-retry` | 在已缩小拓扑上验证异常与 retry |
| API 参数、并发操作拒绝、request ID | `fault-rejection-contracts` | 非法请求与进行中操作拒绝；配合受影响的成功路径用例 |
| 节点 watchdog、lease、joiner 生命周期、自动开放路由 | `fault-kill-pause-scale-down-then-rejoin` | 四个独立节点进程组；旧节点退出、新节点 native recovery、路由和精度 |
| rejoin 中 decode CUDA Graph、替换节点 fast path | `fault-kill-pause-scale-down-then-rejoin-cudagraph` | 需要匹配的 Mooncake 能力；普通 rejoin 不能替代 graph 覆盖 |
| continue 模式节点重建 | `fault-kill-continue-whole-node-rejoin` | 原生恢复与自动开放路由 |
| continue 模式空闲进程死亡观察 | `fault-kill-continue-status-only` | 状态/准入观察，不等同完整恢复 |
| continue 模式运行中故障 | `fault-kill-continue-inflight` | 在途请求与失效后的行为 |
| continue 模式可恢复异常 | `fault-exception-continue-discard-resume` | 丢弃当前请求并继续处理 |
| pause 超时、fail-stop | `fault-exception-pause-retry-timeout` | 无人 retry 的截止时间和清理 |
| 原生行为对照，排除 FT 控制影响 | `fault-kill-noft-native-inflight` | 无 FT 的独立对照，不直接验证 FT API |

选例时给出简短的“改动 → 风险 → 用例能证明什么”。多个用例共享同一启动失败时，先解决共同阻塞，不重复启动。
接口正常、进程退出、输出正确是不同证据；仅收到 HTTP 202 不代表操作完成。
所有场景的完整 token 序列必须满足已有 oracle 或契约定义的比较，不能用本次输出注册通过标准。

watchdog endpoint 地址、线程内 socket 所有权等细节不一定有端到端断言。先读 TEST.md 确认覆盖；已有单测可补充，但要分别报告，不能把间接证据当成逐节点实测。
用户要求只跑现有用例时，缺少的场景明确标为覆盖缺口，不临时创建替代场景。

仅在需要时读取：
- 模型、依赖或 timeout 配置：[profile-settings.md](../../references/profile-settings.md)。
- 精度/历史回归归因：[历史索引与验证记录](VALIDATION-HISTORY.md)、对应 `VALIDATION-*.md`；按提交定位，勿全量加载。
