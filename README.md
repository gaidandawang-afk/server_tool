# server_tool

`server_tool` 是面向多人共享 GPU 服务器的轻量 agent 项目。它把长期安全规则、
领域能力、确定性远程执行和一次性任务材料分开，避免为每次操作向根目录堆脚本。

## 能力

- `remote-ops`：安全连接、任务生命周期和 artifact。
- `manage-image`：SGLang SSH 镜像的构建、部署和验证。
- `install-environment`：共享基础运行环境安装。
- `build-source`：Mooncake、SGLang 等源码的隔离构建。
- `run-service`：任务内服务启动、观察和清理。
- `test-service`：按源码分支的 `TEST.md + run.sh` 执行用例。
- `debug-service`：在具体用例失败后定位根因。

每次任务先从 `profiles/task.example.env` 复制一个忽略的 `.local.env` profile，
再读取对应 skill。一次性任务材料统一放在 `work/<profile>/<task>/`。

## 目录

```text
AGENTS.md                 始终生效的协作与远程安全规则
GOD.md                    server_tool 自身的架构优化规则
profiles/                 平坦的 task profile 示例和本地配置
skills/                   七个独立能力及其引用、资产和叶子脚本
tools/                    未来的通用远程执行工具
work/                     Git ignored 的 task-local 工作区和 artifact
```

当前阶段只固化结构和能力边界。Mooncake 构建、SGLang 服务运行和测试逻辑应在出现
明确任务后，按对应 skill 的规则以最小实现补充。
