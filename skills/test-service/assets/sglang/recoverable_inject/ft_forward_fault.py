"""Inject one coordinated recoverable ModelRunner forward fault."""

import importlib.abc
import os
import sys


ENV_RANKS = "SGLANG_TEST_FT_RECOVERABLE_FAULT_RANK"
ENV_TRIGGER = "SGLANG_TEST_FT_RECOVERABLE_FAULT_FILE"
ENV_DONE = "SGLANG_TEST_FT_RECOVERABLE_FAULT_DONE_FILE"
TARGET_MODULE = "sglang.srt.model_executor.model_runner"


class FaultInjectLoader(importlib.abc.Loader):
    def __init__(self, real_loader):
        self.real_loader = real_loader

    def create_module(self, spec):
        return self.real_loader.create_module(spec)

    def exec_module(self, module):
        self.real_loader.exec_module(module)
        patch_forward(module)


class FaultInjectFinder(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path, target=None):
        if fullname != TARGET_MODULE:
            return None
        for finder in sys.meta_path:
            if finder is self:
                continue
            try:
                spec = finder.find_spec(fullname, path, target)
            except (ImportError, AttributeError):
                continue
            if spec is not None:
                spec.loader = FaultInjectLoader(spec.loader)
                return spec
        return None


def patch_forward(module):
    target_raw = os.environ.get(ENV_RANKS)
    if not target_raw:
        return
    try:
        target_ranks = {
            int(value.strip()) for value in target_raw.split(",") if value.strip()
        }
    except ValueError:
        return

    trigger_file = os.environ.get(ENV_TRIGGER, "")
    done_file = os.environ.get(ENV_DONE, "")
    model_runner = module.ModelRunner
    original_forward = model_runner.forward
    injected = [False]

    def patched_forward(self, forward_batch, **kwargs):
        if injected[0]:
            return original_forward(self, forward_batch, **kwargs)

        rank = self.dp_rank if self.dp_rank is not None else self.tp_rank
        local_trigger = rank in target_ranks and (
            not trigger_file or os.path.exists(trigger_file)
        )

        import torch
        import torch.distributed as dist

        fault_flag = torch.tensor([int(local_trigger)], dtype=torch.int32)
        tp_group = getattr(self, "tp_group", None)
        if tp_group is not None and tp_group.world_size > 1:
            dist.all_reduce(
                fault_flag,
                op=dist.ReduceOp.MAX,
                group=tp_group.cpu_group,
            )
        if not fault_flag.item():
            return original_forward(self, forward_batch, **kwargs)

        injected[0] = True
        if local_trigger and done_file:
            try:
                with open(done_file, "a", encoding="utf-8") as handle:
                    handle.write(
                        f"pid={os.getpid()} rank={rank} "
                        f"forward_pass_id={self.forward_pass_id}\n"
                    )
            except OSError:
                pass
        raise RuntimeError(
            "Injected coordinated recoverable FT forward fault for "
            f"model runner rank(s) {sorted(target_ranks)}"
        )

    model_runner.forward = patched_forward


def install_hook():
    if os.environ.get(ENV_RANKS):
        sys.meta_path.insert(0, FaultInjectFinder())
