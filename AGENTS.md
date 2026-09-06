# Server Tool 协作规范

server_tool 服务于多人共享 GPU 服务器。模型理解提交、选择用例、分析证据；skill 提供按需知识，脚本执行确定性操作。

## 进入项目与上下文

1. 先运行 `git status --short --branch`，不覆盖或混入他人未提交改动。
2. 优先使用用户指定的 task/profile；恢复时先读该任务的 `work/<profile>/<task>/TASK.md`，再核对当前事实。多个候选无法区分时询问，不按文件时间猜测“当前任务”。
3. 只读取本次能力的 SKILL.md 和它按条件要求的引用，不默认通读 README、全部 skills、profiles、历史验证或经验池。
4. 普通验证从 `skills/test-service/SKILL.md` 开始；远程操作从 `skills/remote-ops/SKILL.md` 开始。镜像、安装、Mooncake 构建、独立服务、失败调试分别按需选择 manage-image、install-environment、build-mooncake-wheel、run-service、debug-service。
5. 只有改变本项目架构、目录、skill 边界、profile 或远程接口时，完整读取 `GOD.md`。
6. 在 TASK.md 保留目标/提交范围、profile 路径、用户授权及约束、选例与理由、run 名/状态、证据路径、下一步。只记影响后续决定的事实，不复制日志、完整 profile 或逐条操作历史；在提交运行、终态、阻塞与结束时更新。
7. 常规观察先看摘要；仅失败相关的断言、源码片段和日志进入上下文。网络未连通是“状态未知”，不是“用例失败”。

## 始终适用的安全边界

- 本地已提交源码是事实来源，禁止远端手改受版本控制代码。密钥、密码、令牌、本地 profile 不得提交。
- 多人服务器上不修改、复用或清理他人的文件、环境、容器、端口与进程。
- 共享 GPU 必须有用户针对本次运行的明确授权；每张所选 GPU 空闲显存须超过 30 GiB。已有 compute 进程不是拒绝条件，但保留其 PID/显存信息，绝不控制它们。`--allow-busy-gpus` 仅记录已取得的授权。
- 远程操作前重新检查目录、端口、GPU、容器、进程；旧记录只提供线索。
- 远端持久化限制在 `/data2/iws`，镜像归档只放 `/data1/images`。
- 成功和失败都保留提交号、命令、状态、日志及可取回 artifact。

## Task 与执行

- 一个逻辑 task 一个平坦 profile，独占任务根、源码 worktree、显式端口段和 artifact 根；端口冲突快速失败，不调度。GPU 默认可为 all，但只检查/使用显式所选集合。
- 基础环境仅含一次安装的不变 Python/CUDA/依赖、Mooncake、缓存和加载脚本。从待测源码开始的构建、服务、变量、GPU、端口、测试、临时文件和输出都属于 task。
- ABI 敏感或需并存的包放在不可覆盖的显式版本目录；profile 直接选目录，不用 current/latest、全局激活或隐式依赖回退。启动前验证版本、导入路径和必要符号。
- 执行从本地所选分支 HEAD 得到提交，不在 profile/用例硬编码 hash；远端用当前 task 独立 worktree。
- 修改 SGLang/Mooncake 等源码时创建独立本地 worktree 与 `codex/debug/<profile>-<issue>` 分支；instrumentation/修复本地提交后才同步验证。不擅自删除 debug 分支、worktree 或远端证据。
- 非平凡远程操作写成明确输入脚本。长任务完全脱离 SSH 文件描述符，通过短连接 status/logs/wait/fetch；所有等待有界，断线不能抹除任务或证据。
- 每个 task 自己启动、观察和清理服务；只清理记录并核验所有权的 PID/PGID，不宽泛匹配，不杀/重启不属于当前 task 的服务。
- 输入、临时工作和输出分开；只取 output、必要 control 和小型 provenance。执行与断线恢复步骤见 `skills/remote-ops/references/workflow.md`。

## 测试与调试

- 稳定用例属于 `skills/test-service/cases/`，一个 TEST.md + run.sh，声明源码分支、阶段状态、接口/进程断言、精度、重复方式和必要 artifact；只提交已执行或用户明确要求固化的用例。
- 外部项目只作设计参考，执行规则、oracle、结果不得依赖外部测试项目；待测仓库只保存产品源码自己的测试。
- 只并行同阶段独立请求；保留因果 barrier。每次冷启动独立 run 名和 artifact 目录，绝不覆盖前次。
- 定位先读代码、日志、脚本；信息不足先补针对性证据，禁止堆实验。
- 只有实际用例失败并进入根因定位，debug-service 才加载经验池；不能替代本次证据，验证修复后仍须用户确认才能更新。

## 文件归属与提交

- tools/：通用 SSH、SFTP、任务状态和 artifact；对应 skill/scripts/：领域叶子操作；manage-image：镜像配置与生命周期；test-service/cases/：稳定测试契约。
- 一次性实验、包装、任务摘要和生成物只放忽略的 work/，不提交；不建根级 scripts/，不把单次事故命令直接提升为永久脚本。
- 所有仓库更新通过 Git 提交保存，每个提交一个目的并说明原因和验证。提交前检查暂存区，运行相关验证及 `git diff --check`。
- 只清理由当前任务创建且路径已核实的临时内容。
