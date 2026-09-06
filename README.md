# server_tool

`server_tool` 是面向多人共享 GPU 服务器的轻量 agent 项目。它把长期安全规则、
领域能力、确定性远程执行和一次性任务材料分开，避免为每次操作向根目录堆脚本。

## Agent 入口

进入项目遵循 AGENTS.md 的按需加载规则。验证任务从 test-service 开始：查看提交差异，
用精简 INDEX 定位候选 TEST.md，保留 agent 的选例判断；历史报告与参数细节只在需要时展开。
执行和网络切换遵循 [操作清单](skills/remote-ops/references/workflow.md)。
任务目标、选例理由、run 名、证据路径和下一步保存在忽略的 `work/<profile>/<task>/TASK.md`，
下一位 agent 可从该文件恢复，不需要重读对话或全部历史。

## 能力

- `remote-ops`：安全连接、任务生命周期和 artifact。
- `manage-image`：SGLang SSH 镜像的构建、部署和验证。
- `install-environment`：共享基础运行环境安装。
- `build-mooncake-wheel`：Mooncake CUDA EP/PG 开发 wheel 的隔离构建与验证。
- `run-service`：任务内服务启动、观察和清理。
- `test-service`：按源码分支的 `TEST.md + run.sh` 执行用例。
- `debug-service`：在具体用例失败后定位根因，并维护仓库内的可复用调试经验池。

每次任务先从 `profiles/task.example.env` 复制一个忽略的 `.local.env` profile，
显式选择源码、容器、GPU、端口和依赖版本目录，再读取对应 skill。一次性任务材料
统一放在 `work/<profile>/<task>/`。

## 目录

```text
AGENTS.md                 始终生效的协作与远程安全规则
GOD.md                    server_tool 自身的架构优化规则
profiles/                 平坦的 task profile 示例和本地配置
skills/                   七个独立能力、提交用例、引用、资产和叶子脚本
tools/                    SSH 传输、后台运行、状态、日志、等待和 artifact 工具
tests/                    工具的本地安全与接口测试
work/                     Git ignored 的 task-local 工作区和 artifact
```

远程执行使用 `tools/server_tool.py`。稳定用例位于
`skills/test-service/cases/`，并通过 `skills/test-service/scripts/run-case.py`
组合提交的执行单元；外部项目只可作为设计参考，不是运行时依赖。

调试经验池位于 `skills/debug-service/pool.json`，只通过
`python skills/debug-service/scripts/manage_pool.py` 读取或更新，不依赖其他仓库。

典型测试入口：

```powershell
python tools\server_tool.py --profile profiles\<profile>.local.env check
python skills\test-service\scripts\run-case.py `
  --profile profiles\<profile>.local.env `
  --case sglang/fault-kill-pause-scale-down `
  --name fault-kill-pause-scale-down `
  --repeat 2
```

`check` 和 `run` 会在远程启动前检查 profile 选择的 GPU；每张所选 GPU 必须有
超过 30 GiB 的可用显存。已有 compute process 不再作为拒绝条件，但会把启动前检测到
的 PID 和显存占用写入 provenance，工具不会识别、终止或控制这些进程。

`--allow-busy-gpus` 保留为显式共享授权的兼容性确认项；当前 GPU 评审以可用显存门槛
为准，不因其他进程存在而失败。

## 经跳板传输与 GitHub 拉取

当前 SSH 客户端使用 Paramiko，不会自动读取 OpenSSH `ProxyJump`。可先建立仅监听
本机的 SSH 转发，再让本地 profile 指向该端口，并为该端点配置已核对的服务器主机密钥。

在高延迟连接上，profile 可显式设置：

```dotenv
SOURCE_GIT_URL=https://github.com/owner/source.git
TOOLS_GIT_URL=https://github.com/owner/server_tool.git
```

先将源码和 server_tool 的本地提交推送到对应 GitHub 仓库。执行仍以干净本地分支
HEAD 为事实来源；S 浅拉取该提交，不追随远端最新分支。测试脚本和附件仅从 server_tool
已提交文件中选择，按 Git blob 的 SHA256 校验，因此不受 Windows CRLF checkout 影响，
也不会发送忽略的 profile、缓存或凭据。拉取失败会保存 preparation.log 和失败结果。
GitHub URL 不接受内嵌凭据；此方式要求 S 已能读取对应仓库。

未设置相应 URL 时，该部分继续使用原有上传方式，供 task-local 探针等输入使用。

`fetch` 将 output 和 control 打包为单个 gzip tar，经一次 SFTP 下载，校验 SHA256 后
安全解包；拒绝软链接、硬链接和路径逃逸。`fetch --summary` 仅取回结果、断言、提交和
容器证据及控制状态。完整日志留在 S，可用 `logs` 查看，或另选 `--destination` 获取完整包。
`run-case.py --summary` 可在常规用例结束后只取摘要。结果不需要上传 GitHub。

用例入口会输出精简结果，完整断言与日志仍保留。断线后用相同 run 名恢复观察：

```powershell
python skills/test-service/scripts/run-case.py --profile <profile> --case <component/case> --name <existing-run> --resume --summary --destination work/<profile>/<task>/artifacts/<run>-final
python skills/test-service/scripts/summarize-result.py work/<profile>/<task>/artifacts/<run>-final
```

`--resume` 不提交或重启实验；`--destination` 必须是新的目录。结果摘要区分 PASS、FAIL 和 INCOMPLETE，
连接错误与未完成快照不能作为用例失败。模型只在相关失败出现时加载对应日志片段。
