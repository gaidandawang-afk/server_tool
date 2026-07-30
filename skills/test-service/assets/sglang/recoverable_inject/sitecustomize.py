import os
import sys


inject_dir = os.environ.get("SGLANG_FT_INJECT_DIR", "")
if inject_dir and inject_dir not in sys.path:
    sys.path.insert(0, inject_dir)

if inject_dir:
    import ft_forward_fault

    ft_forward_fault.install_hook()
