---
name: test-service
description: Select existing tests from source changes, execute their contracts, and interpret bounded evidence.
---

# Test Service

## 选例：模型负责判断

1. 读用户指定提交的 diff 与必要调用路径；记录基线和目标提交。范围未给定时检查目标提交，避免擅自把整条分支当成范围。
2. SGLang 先读 `cases/sglang/INDEX.md`，再只读候选用例的 `TEST.md`。其他组件只搜索对应 `cases/<component>/`。
3. 用“改动 → 风险 → 能区分该行为的用例”说明最小集合，核对源码分支、拓扑、依赖、oracle、重复与变体要求。
4. 尊重用户指定的场景，不能以邻近用例代替。缺失覆盖明确报告；历史通过不验证当前提交。
5. 常规运行直接使用契约的 run.sh；仅在修改契约、排查具体失败或确认未写明的覆盖时读取实现和 helper。

## 执行：复用机械入口

按 `../remote-ops/references/workflow.md` 的执行步骤与恢复规则操作；第一次远程执行还需读取 `../remote-ops/SKILL.md`。
已有完整测试契约自己启动和清理服务，无需再加载 run-service、镜像或安装 skill，除非任务确实需要这些能力。

```powershell
python skills/test-service/scripts/run-case.py --profile <profile> --case <component/case> --name <unique-run> --summary
```

用户已明确授权共享所选 GPU 时附加 `--allow-busy-gpus`。不根据 profile 或旧记录推断本次授权。
用例按 TEST.md 保留因果 barrier、逐请求证据和冷启动独立目录，不把用例内的机械步骤搬回对话逐条执行。

断线后先恢复连接，再观察同一 run，不能重发 run：

```powershell
python skills/test-service/scripts/run-case.py --profile <profile> --case <component/case> --name <existing-run> --resume --summary --destination work/<profile>/<task>/artifacts/<run>-final
```

`--resume` 只等待并取回一个已有 run。提交是否成功不明时先 `status` 核对；没有状态不等于未提交。
结果会核对 `--case` 与原 invocation 的用例身份；不一致或缺少身份时返回 INCOMPLETE，不能算作所选用例通过。
常规运行使用 `--summary` 只取摘要。用 `scripts/summarize-result.py <artifact-directory>` 读取已取回证据，无需连接 S；退出 0=PASS、1=FAIL、2=INCOMPLETE。
摘要不完整时先恢复观察；准备失败先排查传输；实际用例失败再按失败断言读取对应日志片段，必要时进入 debug-service。

## 按需加载与证据

- 调整模型、依赖或超时参数时读 `references/profile-settings.md`；不默认加载全部选项。
- 创建或修改契约时读 `references/evidence.md`。一个用例是 TEST.md + run.sh；公共机械操作属于本 skill 的 scripts/。
- 通过必须有终态、exit 0、非空且全部通过的断言；阶段/接口/进程/精度证据不能互相替代。
- 首个共同启动失败先定位，不堆更多 GPU 实验。单测与端到端覆盖分别报告。
- 日志、历史和 profile 留在磁盘；在 task-local TASK.md 只保存目标、选例理由、run 名、已核验事实、证据路径与下一步。
