#!/home/jman/miniconda3/bin/python
"""
Switch Codex between OpenAI, Z.ai GLM and Kimi Code.

Lives in ~/.codex/ and edits only the provider keys in ~/.codex/config.toml.

    /home/jman/miniconda3/bin/python ~/.codex/switch_provider_codex.py --openai
    /home/jman/miniconda3/bin/python ~/.codex/switch_provider_codex.py --glm
    /home/jman/miniconda3/bin/python ~/.codex/switch_provider_codex.py --kimi
    /home/jman/miniconda3/bin/python ~/.codex/switch_provider_codex.py --status
    /home/jman/miniconda3/bin/python ~/.codex/switch_provider_codex.py --set-key [KEY]
    /home/jman/miniconda3/bin/python ~/.codex/switch_provider_codex.py --repair FILE

config.toml is not purely user authored. Codex writes into it: project trust
entries, the features table, the notice table. So this script never replaces
the file and never restores it from a snapshot, because a snapshot goes stale
the moment Codex records a new trust entry. It edits these keys and nothing
else:

    model_provider, model, model_reasoning_effort, model_catalog_json
    forced_login_method, plan_mode_reasoning_effort (Kimi only)
    [model_providers.ZAI], [model_providers.KIMI]

Everything else in the file is passed through untouched. Every write is
preceded by a timestamped backup in ~/.codex/BACKUPS/.

Codex reads config at launch, so restart it after switching.
"""

import argparse
import getpass
import json
import os
import re
import shutil
import signal
import stat
import sys
import tempfile
import time
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # Python 3.10 and older
    tomllib = None

CODEX_DIR = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
CONFIG = CODEX_DIR / "config.toml"
CATALOG = CODEX_DIR / "models.json"
BACKUPS = CODEX_DIR / "BACKUPS"
KEY_FILE = CODEX_DIR / ".zai_key"
KIMI_KEY_FILE = CODEX_DIR / ".kimi_key"
KIMI_CATALOG = CODEX_DIR / "models_kimi.json"
STATE = CODEX_DIR / ".provider_switch_state.json"
KEEP_BACKUPS = 20

ZAI_BASE_URL = "https://api.z.ai/api/v1"
PROVIDER_TABLE = "model_providers.ZAI"
KIMI_BASE_URL = "https://api.kimi.ai/coding/v1"
KIMI_MODEL = "k3.1-pro"
KIMI_HIGHSPEED_MODEL = "k3.1-pro-highspeed"
# strict_effort: the provider rejects any level outside low/high/max (Kimi K3.1
# per kimi.com/code/docs), so an explicit --effort outside them is an error
# rather than a silent remap. Z.ai folds all five levels itself.
PROVIDERS = {
    "ZAI": {"name": "Z.ai GLM", "base_url": ZAI_BASE_URL,
            "key_file": KEY_FILE, "env_key": "ZAI_API_KEY",
            "key_flag": "--set-key", "flag": "--glm", "mode": "glm",
            "catalog": CATALOG, "model": "glm-5.3",
            "default_effort": "max", "strict_effort": False},
    "KIMI": {"name": "Kimi Code", "base_url": KIMI_BASE_URL,
             "key_file": KIMI_KEY_FILE, "env_key": "KIMI_API_KEY",
             "key_flag": "--set-kimi-key", "flag": "--kimi", "mode": "kimi",
             "catalog": KIMI_CATALOG, "model": KIMI_MODEL,
             "default_effort": "high", "strict_effort": True},
}

PROVIDER_KEYS = [
    "model_provider",
    "model",
    "model_reasoning_effort",
    "model_catalog_json",
    "forced_login_method",
]
# Codex runs Plan mode at "medium" when this key is unset, a level Kimi
# rejects, so the Kimi switch sets it and --openai restores the original.
PLAN_EFFORT_KEY = "plan_mode_reasoning_effort"
CODEX_PLAN_DEFAULT = "medium"
RESTORED_KEYS = PROVIDER_KEYS + [PLAN_EFFORT_KEY]

MANAGED_TABLES = [f"model_providers.{name}" for name in PROVIDERS]

EFFORT_LEVELS = ["low", "medium", "high", "xhigh", "max"]
EFFORT_HELP = {
    "low": "trivial edits, rote tool calls",
    "medium": "day to day work",
    "high": "refactors, debugging",
    "xhigh": "architecture, hard problems",
    "max": "deepest reasoning, slowest",
}
NATIVE_LEVELS = ("low", "high", "max")
NATIVE_EFFORT = {"low": "low", "medium": "high", "high": "high",
                 "xhigh": "max", "max": "max"}

MODELS = {"glm-5.3": "glm-5.3", "glm-5.3-flash": "glm-5.3-flash"}

PROG = os.path.basename(sys.argv[0]) or "switch_provider_codex.py"
USAGE_ONELINE = ("--openai | --glm | --kimi | --effort LEVEL | --status "
                 "| --set-key | --set-kimi-key | --repair FILE")


def catalog_entry(slug, description, modalities, default_level,
                  display_name=None, priority=0):
    return {
        "slug": slug,
        "display_name": display_name or slug,
        "description": description,
        "default_reasoning_level": default_level,
        "supported_reasoning_levels": [
            {"effort": level, "description": EFFORT_HELP[level]}
            for level in NATIVE_LEVELS
        ],
        "shell_type": "shell_command",
        "visibility": "list",
        "supported_in_api": True,
        "priority": priority,
        "base_instructions": "",
        "supports_reasoning_summaries": True,
        "default_reasoning_summary": "none",
        "support_verbosity": False,
        "apply_patch_tool_type": "freeform",
        "truncation_policy": {"mode": "bytes", "limit": 10000},
        "context_window": 1048576,
        "max_context_window": 1048576,
        "effective_context_window_percent": 95,
        "supports_parallel_tool_calls": True,
        "experimental_supported_tools": [],
        "input_modalities": modalities,
    }


CATALOG_CONTENT = {
    "models": [
        catalog_entry("glm-5.3", "Z.ai's latest flagship model", ["text"],
                      PROVIDERS["ZAI"]["default_effort"]),
        catalog_entry("glm-5.3-flash", "Z.ai's fast multimodal model",
                      ["text", "image"], PROVIDERS["ZAI"]["default_effort"]),
    ]
}
# Mirrors the models.json in Kimi's Codex guide
# (kimi.com/code/docs/en/third-party-tools/codex). Highspeed is listed for the
# /model picker only; it runs 2-3x faster at about twice the quota.
KIMI_CATALOG_CONTENT = {
    "models": [
        catalog_entry(KIMI_MODEL, "K3.1 Pro, 1M context", ["text", "image"],
                      PROVIDERS["KIMI"]["default_effort"],
                      display_name="K3.1 Pro"),
        catalog_entry(KIMI_HIGHSPEED_MODEL, "K3.1 Pro Highspeed, 1M context",
                      ["text", "image"], PROVIDERS["KIMI"]["default_effort"],
                      display_name="K3.1 Pro Highspeed", priority=1),
    ]
}
CATALOGS = {"ZAI": CATALOG_CONTENT, "KIMI": KIMI_CATALOG_CONTENT}


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def atomic_write(path, text, mode=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp-",
                               suffix=path.suffix)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise
    if mode is not None:
        os.chmod(path, mode)


def validate_toml(text, label):
    if tomllib is None:
        return
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError as exc:
        die(f"{label} is not valid TOML ({exc}). Nothing was changed.")


def backup_config():
    if not CONFIG.exists():
        return None
    BACKUPS.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = BACKUPS / f"config.{stamp}.toml"
    n = 1
    while dest.exists():
        n += 1
        dest = BACKUPS / f"config.{stamp}.{n}.toml"
    shutil.copy2(CONFIG, dest)
    os.chmod(dest, stat.S_IRUSR | stat.S_IWUSR)
    prune_backups()
    return dest


def shared_count(text):
    return len(mcp_server_names(text)) + len(trust_entry_names(text))


def prune_backups():
    files = sorted(BACKUPS.glob("config.*.toml"))
    if len(files) <= KEEP_BACKUPS:
        return
    richest = None
    best = -1
    for path in files:
        try:
            count = shared_count(path.read_text(encoding="utf-8",
                                                errors="replace"))
        except OSError:
            continue
        if count > best:
            best, richest = count, path
    for path in files[:-KEEP_BACKUPS]:
        if path == richest:
            continue
        path.unlink(missing_ok=True)


def read_state():
    if not STATE.exists():
        return {}
    try:
        data = json.loads(STATE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        return {}


def write_state(**kwargs):
    state = read_state()
    state.update(kwargs)
    atomic_write(STATE, json.dumps(state, indent=2) + "\n",
                 stat.S_IRUSR | stat.S_IWUSR)


def same_config(a, b):
    if a == b:
        return True
    if tomllib is None:
        return False
    try:
        return tomllib.loads(a) == tomllib.loads(b)
    except tomllib.TOMLDecodeError:
        return False


def read_config():
    if not CONFIG.exists():
        return ""
    return CONFIG.read_text(encoding="utf-8")


def install(text, label):
    validate_toml(text, label)
    saved = backup_config()
    atomic_write(CONFIG, text, stat.S_IRUSR | stat.S_IWUSR)
    return saved


TABLE_HEADER = re.compile(r'^\[{1,2}\s*([^\[\]]+?)\s*\]{1,2}\s*(#.*)?$')


def header_name(line):
    match = TABLE_HEADER.match(line.strip())
    return match.group(1).strip() if match else None


def norm_name(name):
    parts = re.findall(r'"[^"]*"|\'[^\']*\'|[^.]+', name)
    return ".".join(part.strip().strip('"\'') for part in parts)


def split_preamble(text):
    lines = text.splitlines(keepends=True)
    depth = 0
    for i, line in enumerate(lines):
        if depth == 0 and header_name(line) is not None:
            return "".join(lines[:i]), "".join(lines[i:])
        stripped = re.sub(r'#.*$', '', line)
        depth = max(depth + stripped.count("[") - stripped.count("]"), 0)
    return text, ""


def key_pattern(key):
    return re.compile(rf'^[ \t]*{re.escape(key)}[ \t]*=[ \t]*(.*)$',
                      re.MULTILINE)


def get_key(text, key):
    preamble, _ = split_preamble(text)
    match = key_pattern(key).search(preamble)
    if not match:
        return None
    return match.group(1).strip().strip('"\'')


def set_key(text, key, value, raw_line=None):
    preamble, rest = split_preamble(text)
    line = raw_line if raw_line is not None else f'{key} = "{value}"'
    pattern = key_pattern(key)
    if pattern.search(preamble):
        preamble = pattern.sub(lambda _m: line, preamble, count=1)
    else:
        if preamble.strip():
            preamble = preamble.rstrip("\n") + "\n" + line + "\n"
        else:
            preamble = line + "\n"
    return preamble + rest


def tidy(text):
    preamble, rest = split_preamble(text)
    if rest:
        return preamble.rstrip("\n") + "\n\n" + rest
    return preamble


def set_key_at(text, key, value, index):
    preamble, rest = split_preamble(text)
    pattern = key_pattern(key)
    line = f'{key} = "{value}"'
    if pattern.search(preamble):
        return pattern.sub(lambda _m: line, preamble, count=1) + rest
    lines = preamble.splitlines(keepends=True)
    if index is None or index > len(lines):
        index = len(lines)
    lines.insert(index, line + "\n")
    return "".join(lines) + rest


def remove_key(text, key):
    preamble, rest = split_preamble(text)
    preamble = re.sub(rf'^[ \t]*{re.escape(key)}[ \t]*=[^\n]*\n?', '',
                      preamble, count=1, flags=re.MULTILINE)
    return preamble + rest


def find_table(text, header):
    want = norm_name(header)
    start = None
    pos = 0
    for line in text.splitlines(keepends=True):
        name = header_name(line)
        if start is None:
            if name is not None and norm_name(name) == want:
                start = pos
        elif name is not None:
            return start, pos
        pos += len(line)
    if start is None:
        return None
    return start, len(text)


def iter_tables(text):
    out = []
    name = None
    start = 0
    pos = 0
    for line in text.splitlines(keepends=True):
        found = header_name(line)
        if found is not None:
            if name is not None:
                out.append((name, text[start:pos]))
            name = found
            start = pos
        pos += len(line)
    if name is not None:
        out.append((name, text[start:]))
    return out


def fill_gaps_from(primary_text, secondary_text):
    primary_tables = {norm_name(n): chunk
                      for n, chunk in iter_tables(primary_text)}
    added_tables = []
    differing = []
    out = primary_text
    for name, chunk in iter_tables(secondary_text):
        key = norm_name(name)
        if key in {norm_name(table) for table in MANAGED_TABLES}:
            continue
        if key in primary_tables:
            if primary_tables[key].strip() != chunk.strip():
                differing.append(name)
            continue
        added_tables.append(name)
        out = out.rstrip("\n") + "\n\n" + chunk.strip("\n") + "\n"

    added_scalars = []
    primary_pre, _ = split_preamble(out)
    sec_pre, _ = split_preamble(secondary_text)
    for line in sec_pre.splitlines():
        if "=" not in line or line.strip().startswith("#"):
            continue
        key = line.split("=", 1)[0].strip()
        if key in PROVIDER_KEYS or key_pattern(key).search(primary_pre):
            continue
        out = set_key(out, key, None, raw_line=line.rstrip("\n"))
        added_scalars.append(key)

    return out, added_tables, added_scalars, differing


def upsert_table(text, header, body):
    block = f"[{header}]\n{body}"
    span = find_table(text, header)
    if span:
        start, end = span
        return text[:start] + block + text[end:]
    if not text.strip():
        return block
    return text.rstrip("\n") + "\n\n" + block


def remove_table(text, header):
    span = find_table(text, header)
    if not span:
        return text
    start, end = span
    return re.sub(r'\n{3,}', '\n\n', text[:start] + text[end:])


def read_key(provider="ZAI"):
    spec = PROVIDERS[provider]
    key_file = spec["key_file"]
    env_key = os.environ.get(spec["env_key"])
    if env_key:
        return env_key.strip()
    if key_file.exists():
        text = key_file.read_text(encoding="utf-8").strip()
        if text:
            if "\n" not in text and "=" not in text:
                return text
            match = re.search(r'=\s*["\']?([^"\'\s]+)', text)
            if match:
                return match.group(1)
    return key_in_config(read_config(), provider)


def write_key(key, provider="ZAI"):
    atomic_write(PROVIDERS[provider]["key_file"], key + "\n",
                 stat.S_IRUSR | stat.S_IWUSR)


def key_in_config(text, provider="ZAI"):
    span = find_table(text, f"model_providers.{provider}")
    if not span:
        return None
    match = re.search(r'experimental_bearer_token\s*=\s*["\']([^"\']+)',
                      text[span[0]:span[1]])
    if match and not match.group(1).startswith("<"):
        return match.group(1)
    return None


def preserve_key(text, provider="ZAI"):
    token = key_in_config(text, provider)
    if not token:
        return False
    key_file = PROVIDERS[provider]["key_file"]
    if key_file.exists():
        existing = key_file.read_text(encoding="utf-8").strip()
        if existing == token:
            return False
    write_key(token, provider)
    return True


def active_custom_provider(text=None):
    text = read_config() if text is None else text
    declared = get_key(text, "model_provider")
    name = declared.upper() if declared else None
    return name if name in PROVIDERS else None


# env_key is dropped from carried-over extras because the table always gets
# experimental_bearer_token, and Kimi's Codex guide says not to set both.
PROVIDER_BODY_KEYS = ["name", "base_url", "experimental_bearer_token",
                      "wire_api", "env_key"]


def existing_provider_extras(text, provider):
    span = find_table(text, f"model_providers.{provider}")
    if not span:
        return ""
    body = text[span[0]:span[1]].splitlines()[1:]
    keep = []
    for line in body:
        stripped = line.strip()
        if not stripped:
            continue
        name = stripped.split("=", 1)[0].strip() if "=" in stripped else None
        if name in PROVIDER_BODY_KEYS:
            continue
        keep.append(line.rstrip("\n"))
    return ("\n".join(keep) + "\n") if keep else ""


def check_effort(provider, level):
    spec = PROVIDERS[provider]
    if spec["strict_effort"] and level not in NATIVE_LEVELS:
        die(f"{spec['name']} accepts only {', '.join(NATIVE_LEVELS)} effort, "
            f"not {level}. Nothing was changed.")


def carried_effort(provider, current, setting):
    """Map an effort already in config.toml onto a level the provider takes.

    Returns (level, note); note explains a change the user did not ask for.
    """
    spec = PROVIDERS[provider]
    default = spec["default_effort"]
    if current is None:
        return default, None
    native = NATIVE_EFFORT.get(current)
    if native is None:
        return default, (f"{setting} {current} is not a level "
                         f"{spec['name']} accepts; using {default}")
    if spec["strict_effort"] and native != current:
        return native, (f"{setting} {current} is not a level "
                        f"{spec['name']} accepts; using {native}")
    return native, None


def layer_provider(text, provider, model, effort, key):
    spec = PROVIDERS[provider]
    notes = []
    text = set_key(text, "model_provider", provider)
    text = set_key(text, "model", model)
    if effort is not None:
        level = NATIVE_EFFORT[effort]
    else:
        level, note = carried_effort(
            provider, get_key(text, "model_reasoning_effort"), "effort")
        if note:
            notes.append(note)
    text = set_key(text, "model_reasoning_effort", level)
    if spec["strict_effort"]:
        plan = get_key(text, PLAN_EFFORT_KEY)
        plan_level, note = carried_effort(
            provider, plan or CODEX_PLAN_DEFAULT, "plan mode effort")
        if plan is None:
            notes.append(f"plan mode effort unset, which Codex runs at "
                         f"{CODEX_PLAN_DEFAULT}; set to {plan_level}")
        elif note:
            notes.append(note)
        text = set_key(text, PLAN_EFFORT_KEY, plan_level)
    text = set_key(text, "model_catalog_json", str(spec["catalog"]))
    text = remove_key(text, "forced_login_method")
    extras = (existing_provider_extras(text, provider)
              or read_state().get(f"{provider.lower()}_extras") or "")
    body = (f'name = "{spec["name"]}"\n'
            f'base_url = "{spec["base_url"]}"\n'
            f'experimental_bearer_token = {json.dumps(key)}\n'
            f'wire_api = "responses"\n'
            f'{extras}')
    return tidy(upsert_table(text, f"model_providers.{provider}", body)), notes


def strip_providers(text, restore):
    for table in MANAGED_TABLES:
        text = remove_table(text, table)
    for k in RESTORED_KEYS:
        if k not in restore:
            # A record saved before this key was managed: the live value was
            # never changed by a switch, so it is already the user's own.
            continue
        value, line = original_entry(restore, k)
        if value:
            text = set_key_at(text, k, value, line)
        else:
            text = remove_key(text, k)
    return tidy(text)


def key_line_index(text, key):
    preamble, _ = split_preamble(text)
    for i, line in enumerate(preamble.splitlines()):
        if key_pattern(key).match(line):
            return i
    return None


def remember_originals(text):
    write_state(originals={
        k: {"value": get_key(text, k), "line": key_line_index(text, k)}
        for k in RESTORED_KEYS
    })


def original_entry(restore, key):
    entry = restore.get(key)
    if isinstance(entry, dict):
        return entry.get("value"), entry.get("line")
    return entry, None


def repair_candidates():
    paths = []
    for pattern in ("PROVIDER_CONFIGS/*.toml", "config.toml.switchbak",
                    "BACKUPS/config.*.toml", "config.toml.bak*",
                    "config.toml.*.bak", "config.toml.orig"):
        paths.extend(sorted(CODEX_DIR.glob(pattern)))
    out = []
    for path in paths:
        if not path.is_file() or path == CONFIG:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        out.append({
            "path": path,
            "tables": len(table_names(text)),
            "mcp": len(mcp_server_names(text)),
            "projects": len(trust_entry_names(text)),
            "bytes": len(text),
            "mtime": path.stat().st_mtime,
        })
    out.sort(key=lambda c: (c["mcp"] + c["projects"], c["mtime"], c["tables"]),
             reverse=True)
    return out


def best_candidate():
    cands = repair_candidates()
    return cands[0] if cands else None


def warn_if_stripped(text):
    live_mcp = len(mcp_server_names(text))
    live_proj = len(trust_entry_names(text))
    if live_mcp > 0 or live_proj > 2:
        return
    cand = best_candidate()
    if not cand:
        return
    if cand["mcp"] + cand["projects"] < live_mcp + live_proj + 3:
        return
    print()
    print("WARNING: this config looks stripped of shared settings.")
    print(f"  live config    {live_mcp} MCP server(s), "
          f"{live_proj} project trust entr(ies)")
    print(f"  {cand['path'].name:<14} {cand['mcp']} MCP server(s), "
          f"{cand['projects']} project trust entr(ies)")
    print("  recover them with:")
    invocation = sys.argv[0]
    if not invocation.startswith((".", "/")):
        invocation = f"{sys.executable} {invocation}"
    print(f"    {invocation} --repair")
    print()


def usable_originals(restore):
    if not isinstance(restore, dict):
        return False
    for key in PROVIDER_KEYS:
        value, _ = original_entry(restore, key)
        if value:
            return True
    return False


def recover_originals():
    for cand in repair_candidates():
        try:
            text = cand["path"].read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        declared = get_key(text, "model_provider")
        if not declared or active_custom_provider(text) is not None:
            continue
        found = {
            k: {"value": get_key(text, k), "line": key_line_index(text, k)}
            for k in RESTORED_KEYS
        }
        if usable_originals(found):
            return found, cand["path"]
    return None, None


def table_names(text):
    return [n for n, _ in iter_tables(text)]


def mcp_server_names(text):
    out = []
    for name in table_names(text):
        parts = norm_name(name).split(".")
        if len(parts) >= 2 and parts[0] == "mcp_servers" and parts[1] not in out:
            out.append(parts[1])
    return out


def trust_entry_names(text):
    out = []
    for name in table_names(text):
        parts = norm_name(name).split(".", 1)
        if len(parts) == 2 and parts[0] == "projects" and parts[1] not in out:
            out.append(parts[1])
    return out


def switch_to_provider(provider, model, effort):
    spec = PROVIDERS[provider]
    if effort is not None:
        check_effort(provider, effort)
    key = read_key(provider)
    if not key:
        die(f"no {spec['name']} API key found. Run with {spec['key_flag']}, "
            f"or set {spec['env_key']} before running.")

    text = read_config()
    if text.strip():
        validate_toml(text, str(CONFIG))
    if active_custom_provider(text) is None:
        remember_originals(text)

    new_text, notes = layer_provider(text, provider, model, effort, key)

    catalog = spec["catalog"]
    catalog_text = json.dumps(CATALOGS[provider], indent=4) + "\n"
    if not catalog.exists() or catalog.read_text(encoding="utf-8") != catalog_text:
        atomic_write(catalog, catalog_text)

    if same_config(new_text, text):
        write_state(mode=spec["mode"])
        print(f"already on {spec['name']} ({model}), effort "
              f"{get_key(text, 'model_reasoning_effort')}, nothing to change")
        warn_if_stripped(text)
        return

    saved = install(new_text, f"config with {provider} provider added")
    write_state(mode=spec["mode"])

    print(f"switched Codex to {spec['name']} ({model})")
    print(f"  endpoint   {spec['base_url']}")
    print("  wire api   responses")
    print(f"  effort     {get_key(new_text, 'model_reasoning_effort')}")
    if spec["strict_effort"]:
        print(f"  plan mode  {get_key(new_text, PLAN_EFFORT_KEY)}")
    for note in notes:
        print(f"  note       {note}")
    print(f"  preserved  {len(table_names(new_text))} table(s) in config.toml")
    if saved:
        print(f"  backup     {saved}")
    warn_if_stripped(new_text)
    print("Close all Codex windows, open a new terminal, and run codex.")


def switch_to_openai():
    text = read_config()
    if not text.strip():
        die(f"{CONFIG} is empty or missing, so there is nothing to switch.")
    validate_toml(text, str(CONFIG))
    if active_custom_provider(text) is None:
        print("already on OpenAI, nothing to change")
        return

    rescued = []
    for provider, spec in PROVIDERS.items():
        if preserve_key(text, provider):
            rescued.append(spec["key_file"])
        if find_table(text, f"model_providers.{provider}"):
            write_state(**{f"{provider.lower()}_extras":
                           existing_provider_extras(text, provider)})

    restore = read_state().get("originals") or {}
    recovered_from = None
    if not usable_originals(restore):
        restore, recovered_from = recover_originals()
        if not restore:
            die("no record of your OpenAI provider settings, and none could "
                "be recovered from the files on disk. Switching now would "
                "remove model, model_provider, model_reasoning_effort and "
                "forced_login_method rather than restore them, so nothing "
                "was changed.\n"
                "  Either switch with a saved OpenAI config present, or set "
                "those four keys in config.toml by hand and re-run.")
        write_state(originals=restore)
    new_text = strip_providers(text, restore)

    if not new_text.strip():
        saved = backup_config()
        CONFIG.unlink(missing_ok=True)
        write_state(mode="openai")
        print("switched Codex to OpenAI")
        for key_file in rescued:
            print(f"  saved the provider key to {key_file} first")
        print("  config.toml held only provider keys, so it was removed and "
              "Codex uses its defaults")
        if saved:
            print(f"  backup     {saved}")
        print()
        print("Close all Codex windows and open a new terminal.")
        return

    saved = install(new_text, "config with custom providers removed")
    write_state(mode="openai")

    print("switched Codex to OpenAI")
    if recovered_from:
        print(f"  no saved record of your OpenAI keys, so they were read "
              f"from {recovered_from.name}")
    for key_file in rescued:
        print(f"  saved the provider key to {key_file} before removing its table")
    kept = {}
    for k in RESTORED_KEYS:
        value, _ = original_entry(restore, k)
        if value:
            kept[k] = value
    if kept:
        print("  restored your values: "
              + ", ".join(f"{k}={v}" for k, v in kept.items()))
    else:
        print("  removed custom provider keys; Codex falls back to its defaults")
    print(f"  preserved  {len(table_names(new_text))} table(s) in config.toml")
    if saved:
        print(f"  backup     {saved}")
    warn_if_stripped(new_text)
    print("Close all Codex windows and open a new terminal.")


def apply_effort(level):
    text = read_config()
    if not text.strip():
        die(f"{CONFIG} is empty or missing, so there is no config to edit.")
    validate_toml(text, str(CONFIG))
    provider = active_custom_provider(text)
    if provider is None:
        die("effort here applies to Z.ai and Kimi. Switch with "
            "--glm or --kimi --effort LEVEL, or set reasoning effort for OpenAI "
            "models yourself in config.toml.")
    check_effort(provider, level)
    new_text = set_key(text, "model_reasoning_effort", NATIVE_EFFORT[level])
    if same_config(new_text, text):
        print(f"effort is already {level} ({EFFORT_HELP[level]}), "
              "nothing to change")
        return
    saved = install(new_text, "config with updated effort")
    print(f"effort level set to {level} ({EFFORT_HELP[level]}, "
          f"{PROVIDERS[provider]['name']}: {NATIVE_EFFORT[level]})")
    if saved:
        print(f"  backup {saved}")
    print()
    print("Restart Codex and start a new session for it to take effect; a "
          "session that changes effort midway loses its context cache.")


def repair(base_path):
    if base_path is True:
        cands = repair_candidates()
        if not cands:
            die("no candidate files found to repair from. Pass one "
                "explicitly: --repair path/to/config.toml")
        print("candidates found, richest first:")
        for c in cands[:6]:
            print(f"  {c['mcp']:>2} mcp  {c['projects']:>3} trust  "
                  f"{c['tables']:>3} tables  {c['bytes']:>6} bytes  "
                  f"{c['path']}")
        base = cands[0]["path"]
        live_names = table_names(read_config())
        live_shared = len([n for n in live_names
                           if n.startswith(("mcp_servers.", "projects."))])
        if cands[0]["mcp"] + cands[0]["projects"] < live_shared:
            die("the best candidate holds less shared config than your live "
                "file, so repairing from it would lose settings. Nothing was "
                "changed. Pass a file explicitly if you are sure.")
        print(f"\nusing {base}")
        print()
    else:
        base = Path(base_path).expanduser()
    if not base.is_file():
        die(f"{base} is not a file.")
    base_text = base.read_text(encoding="utf-8")
    validate_toml(base_text, str(base))

    live = read_config()
    provider = active_custom_provider(live)
    if live.strip():
        merged_text, added_tables, added_scalars, differing = fill_gaps_from(
            live, base_text)
    else:
        merged_text, added_tables, added_scalars, differing = (
            base_text, table_names(base_text), [], [])
    model = get_key(live, "model") if provider is not None else None

    if provider is not None:
        spec = PROVIDERS[provider]
        key = read_key(provider)
        if not key:
            die(f"no {spec['name']} API key found, so its block cannot be "
                f"rebuilt. Run {spec['key_flag']} first.")
        if active_custom_provider(base_text) is None:
            remember_originals(base_text)
        live_extras = existing_provider_extras(live, provider)
        if live_extras:
            write_state(**{f"{provider.lower()}_extras": live_extras})
        new_text, notes = layer_provider(merged_text, provider,
                                         model or spec["model"], None, key)
        for note in notes:
            print(f"note: {note}")
        atomic_write(spec["catalog"],
                     json.dumps(CATALOGS[provider], indent=4) + "\n")
    else:
        new_text = merged_text

    if same_config(new_text, live):
        print(f"nothing to recover: {CONFIG} already contains everything in "
              f"{base}")
        return

    saved = install(new_text, f"config rebuilt from {base}")
    recovered = sorted(added_tables)

    print(f"rebuilt {CONFIG} from {base}")
    if saved:
        print(f"  backup of the file being replaced: {saved}")
    if recovered:
        print(f"  recovered {len(recovered)} table(s) that were missing:")
        for name in recovered[:12]:
            print(f"    [{name}]")
        if len(recovered) > 12:
            print(f"    and {len(recovered) - 12} more")
    else:
        print("  no tables were missing from the live config")
    if added_scalars:
        print(f"  added missing setting(s): {', '.join(added_scalars)}")
    if differing:
        print(f"  {len(differing)} table(s) exist in both and differ. The "
              "live version was kept:")
        for name in differing[:8]:
            print(f"    [{name}]")
        if len(differing) > 8:
            print(f"    and {len(differing) - 8} more")
        print("    compare them yourself if one of these was corrected in "
              f"{base.name}")
    if provider is not None:
        print(f"  re-applied {provider} provider, model {get_key(new_text, 'model')},"
              f" effort {get_key(new_text, 'model_reasoning_effort')}")
    print()
    print("Check it over, then restart Codex.")


def show_status():
    text = read_config()
    active = active_custom_provider(text)
    name = PROVIDERS[active]["name"] if active is not None else (
        get_key(text, "model_provider") or "OpenAI")
    print(f"active provider  : {name}")
    print(f"config file      : {CONFIG}"
          f"{'' if CONFIG.exists() else '  (does not exist)'}")
    print(f"z.ai key stored  : {'yes' if read_key() else 'no'}")
    print(f"kimi key stored  : {'yes' if read_key('KIMI') else 'no'}")
    print(f"model            : {get_key(text, 'model')}")
    print(f"effort           : {get_key(text, 'model_reasoning_effort')}")
    print(f"plan mode effort : {get_key(text, PLAN_EFFORT_KEY)}")
    if active is not None:
        spec = PROVIDERS[active]
        status = 'present' if spec['catalog'].exists() else (
            f"MISSING, re-run {spec['flag']}")
        print(f"catalog file     : {status}")
    tables = table_names(text)
    trust = trust_entry_names(text)
    mcp = mcp_server_names(text)
    others = [t for t in tables
              if norm_name(t).startswith("model_providers.")
              and norm_name(t) not in {norm_name(n) for n in MANAGED_TABLES}]
    print(f"tables in config : {len(tables)}")
    print(f"mcp servers      : {len(mcp)}")
    print(f"trust entries    : {len(trust)}")
    if others:
        print("other providers  : "
              + ", ".join(norm_name(o).split(".", 1)[1] for o in others)
              + " (left untouched)")
    backups = sorted(BACKUPS.glob("config.*.toml")) if BACKUPS.exists() else []
    newest = f", newest {backups[-1].name}" if backups else ""
    print(f"backups          : {len(backups)}{newest}")
    warn_if_stripped(text)
    if text.strip() and tomllib is not None:
        try:
            tomllib.loads(text)
        except tomllib.TOMLDecodeError as exc:
            print(f"\nwarning: config.toml is not valid TOML ({exc})")


def effort_table(indent="  "):
    rows = [("LEVEL", "USE FOR", "ON GLM", "ON KIMI")]
    rows += [(k, EFFORT_HELP[k], NATIVE_EFFORT[k],
              k if k in NATIVE_LEVELS else "not accepted")
             for k in EFFORT_LEVELS]
    return "\n".join(f"{indent}{a:<8}{b:<34}{c:<8}{d}" for a, b, c, d in rows)


class HelpParser(argparse.ArgumentParser):
    """argparse wraps long help into an unreadable column. Hand-write it."""

    def format_usage(self):
        return f"usage: {PROG} [{USAGE_ONELINE}]\n"

    def format_help(self):
        return HELP_TEXT


HELP_TEXT = f"""{PROG}
Use OpenAI, Z.ai GLM or Kimi Code as the model inside Codex.

USAGE
  {PROG} --glm [--flash] [--effort LEVEL]
  {PROG} --kimi [--effort LEVEL]
  {PROG} --openai
  {PROG} --effort LEVEL
  {PROG} --status
  {PROG} --set-key [KEY]
  {PROG} --set-kimi-key [KEY]
  {PROG} --repair [FILE]

PROVIDER
  --glm              Z.ai GLM-5.3 via {ZAI_BASE_URL}
  --kimi             Kimi K3.1 Pro via {KIMI_BASE_URL}
                     model ID: {KIMI_MODEL} (Kimi Code subscription)
                     {KIMI_HIGHSPEED_MODEL} is in Codex's /model picker:
                     2-3x faster, about twice the quota
  --openai, --gpt    your OpenAI account

OPTIONS
  --effort LEVEL     reasoning depth. See EFFORT LEVELS below
  --flash            use glm-5.3-flash instead of glm-5.3. Only with --glm.
                     Flash takes images; glm-5.3 is text only
  --set-key [KEY]    store your Z.ai API key. Give no value to be
                     prompted, which keeps it out of your shell history
  --set-kimi-key     store your Kimi Code API key with a hidden prompt
                     also accepts an inline value, like --set-key
  --status           show provider, model, effort and config contents
  --repair [FILE]    rebuild config.toml from FILE, usually a backup,
                     re-applying the current provider settings on top.
                     With no FILE, picks the richest candidate on disk
  -h, --help         show this message

EFFORT LEVELS
{effort_table()}

  GLM takes all five and folds them to its native low, high or max. Kimi
  accepts only low, high and max; any other --effort is refused.
  Omit --effort to carry over the current depth, folded the same way. With
  no level set, GLM uses {PROVIDERS["ZAI"]["default_effort"]} and Kimi uses \
{PROVIDERS["KIMI"]["default_effort"]}, Kimi's own default.
  Kimi also gets plan_mode_reasoning_effort, because Codex otherwise runs
  Plan mode at medium, which Kimi rejects. --openai restores your value.

EXAMPLES
  {PROG} --glm --effort xhigh   GLM, deep reasoning
  {PROG} --kimi --effort max    Kimi K3.1 Pro, deepest reasoning
  {PROG} --effort low           effort only, no switch
  {PROG} --openai               back to OpenAI
  {PROG} --set-key              store a key, no echo
  {PROG} --status               what is active now
  {PROG} --repair               recover shared settings automatically

WHAT THIS TOUCHES
  Only these keys, because Codex writes the rest of the file itself:
    model_provider, model, model_reasoning_effort, model_catalog_json,
    forced_login_method, plan_mode_reasoning_effort (Kimi only)
    [{PROVIDER_TABLE}], [model_providers.KIMI]
  MCP servers, project trust entries, features, notice, other
  [model_providers.*] entries and every other table and scalar are passed
  through untouched. Each write makes a timestamped backup first.

  config    {CONFIG}
  catalog   {CATALOG}
  Kimi catalog {KIMI_CATALOG}
  backups   {BACKUPS}
  key file  {KEY_FILE}
  Kimi key  {KIMI_KEY_FILE} (or KIMI_API_KEY)

  Keys stay out of this script. When selected, the provider's key is copied
  into config.toml with permissions 600 so Codex can use it after restarting.
"""


def main():
    parser = HelpParser(add_help=False)
    parser.add_argument("-h", "--help", action="help",
                        help="show this message")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--openai", "--gpt", dest="openai",
                       action="store_true")
    group.add_argument("--glm", action="store_true")
    group.add_argument("--kimi", action="store_true")
    group.add_argument("--status", action="store_true")
    group.add_argument("--repair", metavar="FILE", nargs="?", const=True,
                       default=None)
    parser.add_argument("--set-key", nargs="?", const=True, default=None,
                        metavar="KEY")
    parser.add_argument("--set-kimi-key", nargs="?", const=True, default=None,
                        metavar="KEY")
    parser.add_argument("--flash", action="store_true")
    parser.add_argument("--effort", choices=EFFORT_LEVELS, default=None,
                        metavar="LEVEL")
    args = parser.parse_args()

    if not any([args.openai, args.glm, args.kimi, args.status,
                args.repair is not None, args.set_key is not None,
                args.set_kimi_key is not None, args.effort is not None]):
        parser.error("one of --openai, --glm, --kimi, --status, --set-key, "
                     "--set-kimi-key, --effort or --repair is required")

    if args.effort is not None and (args.openai or args.status
                                    or args.repair is not None):
        parser.error("--effort cannot be combined with --openai, --status or "
                     "--repair. Run it on its own to set effort for the "
                     "active provider.")
    if args.flash and not args.glm:
        parser.error("--flash only applies with --glm")

    for provider, value in (("ZAI", args.set_key), ("KIMI", args.set_kimi_key)):
        if value is None:
            continue
        spec = PROVIDERS[provider]
        if value is True:
            key = getpass.getpass(f"{spec['name']} API key: ").strip()
        else:
            key = value.strip()
            print("warning: a key passed on the command line is written to "
                  f"your shell history. Use bare {spec['key_flag']} next time.")
        if not key:
            die("no key entered")
        write_key(key, provider)
        print(f"stored in {spec['key_file']} (permissions 600)")
        switching = args.glm if provider == "ZAI" else args.kimi
        if not switching and active_custom_provider() == provider:
            print(f"{spec['name']} is active; re-run {spec['flag']} to update "
                  "the key in config.toml.")
        print()

    if not any([args.openai, args.glm, args.kimi, args.status,
                args.repair is not None, args.effort is not None]):
        return

    if args.status:
        show_status()
        return

    if args.repair is not None:
        repair(args.repair)
        return

    if args.glm:
        switch_to_provider("ZAI",
                           MODELS["glm-5.3-flash" if args.flash else "glm-5.3"],
                           args.effort)
        return

    if args.kimi:
        switch_to_provider("KIMI", KIMI_MODEL, args.effort)
        return

    if args.effort is not None and not args.openai:
        apply_effort(args.effort)
        return

    switch_to_openai()


if __name__ == "__main__":
    if hasattr(signal, "SIGPIPE"):
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    try:
        main()
    except BrokenPipeError:
        os._exit(0)
    except KeyboardInterrupt:
        print()
        sys.exit(130)
