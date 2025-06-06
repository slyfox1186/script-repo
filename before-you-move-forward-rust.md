### Run-Project Operating Manual — **v2 (“script-aware” edition)**

*(Replace the previous block in **combined.md** with this one)*

---

#### 0 · Pre-Flight Mindset (⚠ stop before you type)

1. **Pause & ask**: *“Would I proudly ship this as-is?”*
   *If **no**, iterate until the answer is **yes**.*
2. Re-scan the plan for hidden complexity & refactor opportunities.

---

#### 1 · Script Atlas (what lives where)

| Duty                       | Entry point                                                                     | Key helpers (auto-sourced)                                                                                                                                                                                                                                                                        |
| -------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Orchestrate full build** | `build-gcc.sh` — version 1.8, supports GCC 10-15, dry-run flag, multilib, etc.  | - `system_utils.sh` → RAM/disk checks & optimal threads   <br>- `package_manager.sh` → apt group resolver & installer   <br>- `directory_utils.sh` → safe mkdir / perms   <br>- `file_utils.sh` → archive extract, symlinks, size/space   <br>- `command_utils.sh` → retry/timeout/parallel exec  |
| **Rust re-implementation** | `Cargo.toml` declares the `gcc-builder` binary 1.8.0 (clap 4, tokio 1, etc.)    | Mirrors the Bash flow for high-perf use cases.                                                                                                                                                                                                                                                    |

> **Convention:** Every “helper” script must be `source`d **once** inside `build-gcc.sh` and nowhere else.

---

#### 2 · Bootstrapping Commands (local only)

```bash
# 2-A · clone + deps
git clone https://github.com/your-fork/gcc-builder.git
cd gcc-builder
pnpm i            # ts/tsx deps
sudo apt update
sudo bash package_manager.sh --auto   # installs groups resolved by get_required_packages()

# 2-B · run a dry validation
bash build-gcc.sh --dry-run -v

# 2-C · full build (example for GCC 13 & 15, static binaries)
bash build-gcc.sh --enable-multilib --static -v 13 15
```

*All scripts **refuse** to run as root; sudo is invoked internally where required.*

---

#### 3 · Incremental Dev Workflow

1. **Branch**: `git switch -c feat/<ticket>`

2. Edit only TypeScript / TSX or Bash scripts listed in *Script Atlas*.

3. **Lint + test** every save:

   ```bash
   pnpm lint         # eslint --max-warnings 0
   pnpm test         # full unit / integration
   shellcheck build-gcc.sh system_utils.sh *.sh
   ```

4. Commit once the tree is ✨green✨; push; repeat.

---

#### 4 · Mobile-First / Style Pass

```bash
pnpm stylelint "src/frontend/styles/**/*.scss"
pnpm run mobile:profile   # Lighthouse script – must stay ≥ 90 PWA score
```

Any regression blocks the merge.

---

#### 5 · Golden Rules (cannot be waived)

* **0 `any`** – TypeScript must compile with `strict` and zero implicit any.
* Ignore `node_modules`, `dist`, compiled JS.
* No `sed` multi-file edits unless the **user** explicitly demands it.
* Clean temp/artifact dirs you create.
* Only the **user** runs servers, builds, or deploys; wait for their logs before next steps.

---

#### 6 · Self-Audit Gate

Ask yourself **all** of these:

* Am I fixing **root causes** rather than patches?
* Did I keep helper functions **unique & sequential**?
* Any duplicate tool generation?
* Is mobile performance still pristine?
* Did profiling numbers stay neutral or improve?

*A single “no” → refactor again.*

---

#### 7 · Hand-Off Protocol

1. PR description must begin with:

   ```text
   ## Run Instructions
   pnpm lint && pnpm test
   pnpm build && pnpm run preview
   # For GCC build:
   bash build-gcc.sh --dry-run -v
   ```

2. Wait for user’s terminal output / CI logs.

3. Only after user confirmation do you tag & release.

---

> **Final Prompt** – *“Is this the simplest, most stable, standards-aligned version I can imagine?”*
> **No →** iterate. **Yes →** notify the user & pause for logs.

