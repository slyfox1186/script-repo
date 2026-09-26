"""Shared helpers for the regression tests.

The repository holds standalone scripts rather than an importable package, so
tests load each script by path.  Nothing here touches the network, root-owned
paths, the user's home, or any real conda environment.
"""

import importlib.util
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def load_script_module(relative_path, module_name):
    """Import a repository script as a module without running its __main__ block."""
    path = REPO_ROOT / relative_path
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module
