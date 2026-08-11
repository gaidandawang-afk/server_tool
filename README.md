# server_tool

`server_tool` 是面向多人共享 GPU 服务器的轻量 agent 项目。它把长期安全规则、
领域能力、确定性远程执行和一次性任务材料分开，避免为每次操作向根目录堆脚本。

## 能力

- `remote-ops`：安全连接、任务生命周期和 artifact。
- `manage-image`：SGLang SSH 镜像的构建、部署和验证。
- `build-sgl-kernel-npu`：编译并安装 Ascend(NPU) 的 SGLang kernel wheel 到可在运行时
  选择的不可变版本目录。
- `ascend-sglang-env-replication`：在新服务器上复刻 Ascend(NPU) SGLang 容器环境，
  参照历史成功流程而非重新摸索。
- `install-environment`：共享基础运行环境安装。
- `build-source`：Mooncake、SGLang 等源码的隔离构建。
- `run-service`：任务内服务启动、观察和清理。
- `test-service`：按源码分支的 `TEST.md + run.sh` 执行用例。
- `debug-service`：在具体用例失败后定位根因。

每次任务先从 `profiles/task.example.env` 复制一个忽略的 `.local.env` profile，
显式选择源码、容器、GPU、端口和依赖版本目录，再读取对应 skill。一次性任务材料
统一放在 `work/<profile>/<task>/`。

## 目录

```text
AGENTS.md                 始终生效的协作与远程安全规则
GOD.md                    server_tool 自身的架构优化规则
profiles/                 平坦的 task profile 示例和本地配置
skills/                   九个独立能力、提交用例、引用、资产和叶子脚本
tools/                    SSH 传输、后台运行、状态、日志、等待和 artifact 工具
tests/                    工具的本地安全与接口测试
work/                     Git ignored 的 task-local 工作区和 artifact
```

远程执行使用 `tools/server_tool.py`。稳定用例位于
`skills/test-service/cases/`，并通过 `skills/test-service/scripts/run-case.py`
组合提交的执行单元；外部项目只可作为设计参考，不是运行时依赖。

典型测试入口：

```powershell
python tools\server_tool.py --profile profiles\<profile>.local.env check
python skills\test-service\scripts\run-case.py `
  --profile profiles\<profile>.local.env `
  --case sglang/fault-kill-pause-scale-down `
  --name fault-kill-pause-scale-down `
  --repeat 2
```

`check` 和 `run` 会在远程启动前检查 profile 选择的 GPU；任何已有 compute
process 都会使任务快速失败。工具只报告冲突，不识别、终止或复用该进程。

只有用户明确授权与既有任务共享 GPU 时，测试入口才可增加
`--allow-busy-gpus`。该选项不清理既有进程，并把启动前检测到的 PID 和显存占用
写入 invocation provenance；默认行为仍是快速失败。
