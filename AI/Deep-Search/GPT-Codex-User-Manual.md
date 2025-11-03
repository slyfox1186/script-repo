The OpenAI Codex CLI: A Technical User Manual for Ubuntu Environments
Part 1: Introduction and Core Concepts
1.1 Disambiguating "Codex": From Model to Agent
A common point of confusion when discussing OpenAI's coding tools is the term "Codex." It is essential to understand the distinction between its past and present implementations.
 * Legacy Codex (2021-2023): This term referred to a family of AI models (e.g., code-davinci-002) based on GPT-3 and fine-tuned on public code repositories. These models powered the original GitHub Copilot and were available via a specific "Codex API". This model family and its corresponding API endpoints were deprecated in March 2023.
 * Modern Codex (2025): The contemporary "Codex" is not a model but an agentic engineering assistant. This agent is a comprehensive system that can be accessed through multiple interfaces, including a web UI (Codex Cloud), an IDE extension, a Slack integration, and the command-line interface (CLI).
This modern agent is powered by OpenAI's latest-generation models, including GPT-5 and a specialized, highly optimized variant, GPT-5-Codex. This new model is purpose-built for agentic coding tasks, capable of complex reasoning, iterating on code, and even running for hours to complete a task. This manual focuses exclusively on the modern Codex CLI available for Ubuntu.
1.2 The Dual-Mode Authentication Model
The Codex CLI operates on a hybrid authentication and billing model, and the choice of which to use is the first and most critical step in its setup.
 * ChatGPT Subscription (Recommended): The primary method for using the Codex CLI is by linking it to an active ChatGPT subscription (e.g., Plus, Pro, Team, or Enterprise). Usage in this mode is debited against the message limits associated with that plan. For example, a Plus plan may allow 30-150 local messages every 5 hours, while a Pro plan offers significantly more.
 * OpenAI API Key (Pay-as-You-Go): Alternatively, users can configure the CLI to use a standard OpenAI API key. In this mode, usage is not subject to ChatGPT plan limits but is instead billed on a pay-as-you-go basis at standard API rates. This method is ideal for high-volume use, automated scripts, or CI/CD pipelines where the fixed limits of a subscription plan are too restrictive.
This dual system allows a developer to use their included subscription for day-to-day interactive work and seamlessly switch to API billing for heavy-duty, automated tasks.
## Part 2: Installation and Authentication on Ubuntu
2.1 Prerequisites
Before installing the Codex CLI on an Ubuntu system, two prerequisites are required:
 * Node.js: Version 14 or later.
 * npm: The Node Package Manager, which is typically bundled with Node.js.
These can be installed from the official NodeSource repository or via a version manager.
2.2 CLI Installation
With the prerequisites in place, the Codex CLI is installed globally via npm:
$ npm install -g @openai/codex

This command downloads the @openai/codex package and makes the codex executable available system-wide.
Note on Permissions: If this command fails with an EACCES error, it indicates a permissions issue with the default global npm directory. The recommended solution is to configure npm to use a user-owned directory, not to run the command with sudo.
# 1. Create a directory for global user packages
$ mkdir -p ~/.npm-global

# 2. Tell npm to use this new directory
$ npm config set prefix '~/.npm-global'

# 3. Add this directory to your PATH in ~/.bashrc
$ echo 'export PATH="~/.npm-global/bin:$PATH"' >> ~/.bashrc

# 4. Refresh your shell
$ source ~/.bashrc

# 5. Re-run the install command
$ npm install -g @openai/codex

2.3 First-Time Authentication
The first time the codex command is run, it will initiate the authentication process.
$ codex

The CLI will present a choice to "Sign in with ChatGPT" or "Use API key."
 * Method 1: Sign in with ChatGPT (Recommended)
   * Select "Sign in with ChatGPT".
   * The CLI will display a URL and prompt the user to open it in a browser.
   * This will lead to a standard OpenAI login and an authorization request, linking the CLI to the active ChatGPT subscription. This is the simplest method and enables the use of subscription plan limits.
 * Method 2: Use API Key
   * This method requires an OpenAI API key.
   * The key must be set as an environment variable in the Ubuntu terminal, typically by adding it to the ~/.bashrc file for persistence.
   # Add to ~/.bashrc
export OPENAI_API_KEY="your-api-key-here"

   * After refreshing the shell (source ~/.bashrc), the CLI will detect and use this key for all authentications.
It is possible to switch between these methods later using the codex logout command or by modifying the config.toml file.
Part 3: Core CLI Usage (Interactive TUI)
3.1 Launching the Interactive Session
The primary mode of interaction is the Terminal User Interface (TUI). It is launched by running codex within a project's root directory.
$ # Navigate to your project directory
$ cd /path/to/my-project

$ # Ensure the project is a Git repository (recommended)
$ git init

$ # Launch Codex
$ codex

The CLI performs best when initiated from the root of a Git repository, as it uses the repository context to inform its actions.
3.2 TUI Basics and Slash Commands
The TUI functions as a conversational chat interface, similar to ChatGPT, but with a focus on file system operations and code execution. In addition to natural language prompts, the TUI supports several "slash commands" for meta-level control.
 * /status: Displays the current configuration, including the active model, sandbox settings, approval policy, and (if applicable) remaining usage limits for the subscription plan.
 * /model: Used to switch the active AI model (e.g., /model gpt-5-codex or /model gpt-5).
 * /mcp: Lists the currently connected Model Context Protocol (MCP) servers, which are the "tools" or "plugins" Codex can use.
 * /clear: Resets the current conversation history. This is useful for starting a new task without the context of the previous one, which can also help manage token usage.
3.3 Enabling and Disabling Internet Access
The user query regarding "Internet on and off" is handled through two distinct mechanisms: explicit web search and general network sandboxing.
 * Enabling Web Search (The "--search" Flag):
   By default, Codex does not have access to live web search. To enable this, the interactive session must be launched with the --search flag.
   $ codex --search

   This grants the agent permission to use the web_search tool, allowing it to look up documentation, package versions, or recent information.
 * Controlling General Network Access (Sandboxing):
   "Internet off" is the default state for most operations. The Codex CLI operates in a sandbox that, by default, restricts network access during command execution. This is a security feature to prevent the AI from running unauthorized commands (e.g., curl or wget). Full network access can only be granted by explicitly changing the sandbox policy, which is covered in the Security section of this manual.
3.4 Managing Chat State and History
As of the current version, the Codex CLI does not automatically save interactive chat history between sessions. If the user quits and restarts the codex TUI, the previous conversation is lost.
To manage this, users must either:
 * Restart Manually: Exit the TUI and relaunch codex to begin a fresh, un-contexted session.
 * Use /clear: Use the /clear command to wipe the current conversation's context within a running session.
Community requests exist for persistent history features (e.g., --save-history and --load-history), but these are not yet implemented in the main release.
Part 4: Automation and Scripting with codex exec
4.1 Non-Interactive Execution
Beyond the TUI, the Codex CLI provides a non-interactive exec command (short-form e) for automation and scripting. This allows Codex to be used as a standard command-line tool.
The basic syntax is codex exec "PROMPT":
$ codex exec "Refactor all.js files in./src to use arrow functions"

This command runs the task in "automation mode" without launching the TUI.
4.2 Piping and Standard Input
A powerful feature for Ubuntu users is the exec command's ability to read a prompt from stdin by using - as the prompt. This allows it to be seamlessly integrated into Unix pipelines.
Example 1: Analyzing a log file
$ cat /var/log/syslog | codex exec - "Summarize the critical errors from this log"

Example 2: Reviewing Git changes
$ git diff HEAD~1 | codex exec - "Create a bullet-point summary of these code changes"

Example 3: Analyzing a file
$ cat README.md | codex exec - "Check this markdown file for broken links"

4.3 Use Case: CI/CD and Automated Reports
The exec command is designed for automated environments. When combined with specific flags, it can run unattended tasks.
 * --full-auto: This flag applies a low-friction automation preset. It sets the sandbox to workspace-write (allowing file edits in the project) and the approval policy to on-failure (it will only ask for help if a command fails).
 * --dangerou[span_66](start_span)[span_66](end_span)sly-bypass-approvals-and-sandbox (or --yolo): For fully automated, trusted environments (like a Docker container in a CI runner), this flag removes all safety guards.
Example git[span_67](start_span)[span_67](end_span)lab-ci.yml job:
run_codex_review:
  stage: test
  image: node:latest
  script:
    - npm install -g @openai/codex
    - export OPENAI_API_KEY=$CODEX_API_KEY # API key needed for CI
    # Run Codex in full-auto mode to generate a report
    - codex exec --full-auto "Scan all changed files for potential bugs and write a report to codex_report.md"
  artifacts:
    paths:
      - codex_report.md

This demonstrates how codex exec can be integrated into a pipeline to perform automated code quality checks.
Part 5: Best Practices for Security and Project Context
5.1 Understanding Sandboxing and Approval Policies
The most critical "best practice" for using the Codex CLI is understanding its security model. Because the agent can execute commands, it operates within a sandbox with a specific approval policy. These are highly configurable.
A user can set these policies via command-line flags (e.g., codex --sandbox read-only) or permanently in the config.toml file.
The two main settings are sandbox_mode and approval_policy.
Sandbox Modes
| sandbox_mode | Description |
|---|---|
| read-only | The agent can only read files. It cannot write, edit, or run any commands. This is the safest mode. |
| workspace-write | The agent can read and edit files within the current directory and write to temporary directories (like /tmp). |
| danger-full-access | No sandbox. The agent has full, unrestricted access to the filesystem and network. |
Approval Policies
| approval_policy | Description |
| :--- | :--- |
| untrusted | The agent must ask for user approval before every command it runs. This is secure but creates high friction. |
| on-request | This is the recommended default. The agent runs safe commands (like ls or cat) but will ask for approval before running potentially risky commands (like rm, curl, or writing outside the workspace). |
| on-failure | The agent will try to run commands in its sandbox. If a command fails (e.g., due to a sandbox restriction), it will then ask the user for approval to run it again without restrictions. |
| never | The agent will never ask for approval. If a command fails, it will try to find another way. This is intended for fully automated (non-interactive) runs. |
The "YOLO" Flag:
The CLI provides a "panic-button" flag for full automation:
--dangerously-bypass-approvals-and-sandbox (or its alias, --yolo).
This flag is simply a shortcut for setting sandbox_mode = "danger-full-access" and approval_policy = "never".
Warning: This flag gives the AI complete, un-prompted control over the machine, including network and file system access. It should only be used in secure, isolated environments, such as a disposable Docker container, or on non-sensitive, fully version-controlled projects.
5.2 Proactive Context: The AGENTS.md File
The second most critical "best practice" is managing the quality of the AI's output. A common workflow is to prompt the AI, receive incorrect code, and then correct it (e.g., "No, we use npm test, not pytest").
The AGENTS.md file is designed to solve this problem proactively. It is a README.md file for the AI.
When the Codex agent starts, it searches the repository for an AGENTS.md file. This file provides the agent with essential, project-specific context, such as:
 * How to build, test, and run the project.
 * Architectural patterns and conventions.
 * Domain-specific vocabulary.
 * Security requirements (e.g., "All database queries must be parameterized").
By providing this information upfront, the agent's "first attempt" at a solution is far more accurate and aligned with the project's standards, drastically reducing the need for correction and review.
Example AGENTS.md:
AGENTS.md
Architecture Overview
This is a Node.js Express app with a PostgreSQL database.
 * /controllers contains business logic.
 * /routes defines API endpoints.
 * All database queries must use the db.query helper to ensure parameterization.
Setup and Test Commands
 * Install dependencies: npm install
 * Start dev server: npm run dev
 * Run tests: npm test
Conventions & Patterns
 * Use TypeScript.
 * Commit messages must follow the Conventional Commits specification.
 * All new features require a corresponding test file.
Security
 * Any database query must use parameterized SQL to prevent injection attacks.
 * Environment variables are loaded from .env via dotenv.
5.3 Git Integration Workflows
The Codex agent is designed to work with Git.
 * Locally: The CLI uses the Git repository context to understand the project structure and file history.
 * Remotely (Codex Cloud): The agent integrates directly with GitHub. By commenting @codex review on a pull request, a developer can trigger a Codex Cloud agent to perform a code review. The agent will analyze the diff and leave comments on the PR, and it will use the nearest AGENTS.md file as its guide for review standards.
Part 6: Best Practices for Cost and Model Management
6.1 Managing Subscription Usage Limits
When using a ChatGPT subscription, the Codex CLI is subject to usage limits (e.g., 30-150 messages per 5 hours for Plus).
 * A "message" is not a single prompt; its "cost" depends on the complexity and token count of the task.
 * Warning: Using high-reasoning models, such as gpt-5-codex high, will consume these limits dramatically faster. In one report, a Pro user exhausted their limit in 30 minutes on this setting. It is recommended to use "medium" reasoning for most tasks.
 * The /status command in the TUI will display current limit status.
 * When a limit is hit, the user has three options :
   * Wait for the 5-hour window to reset.
   * Purchase additional "on-demand" credits.
   * Switch to API key-based billing (see Part 7.2).
6.2 Cost-Saving with Local Models (Ollama)
For users concerned with cost, privacy, or who wish to work offline, the Codex CLI supports using local, open-source models through providers like Ollama.
This allows the user to bypass OpenAI's models and billing entirely.
 * Prerequisite: A local model server like Ollama must be installed and running.
 * Easy Mode: The --oss flag is a shortcut that tells Codex to find and use a running Ollama instance.
   $ codex --oss

 * Config Mode: A more robust method is to define Ollama as a "model provider" in the configuration file.
6.3 Example: config.[span_68](start_span)[span_68](end_span)toml for Ollama
The following block can be added to ~/.codex/config.toml to configure Ollama and create a profile to use it.

# ~/.codex/config.toml

# 1. Define the Ollama provider
[model_providers.ollama]
name = "Ollama"
# This is the default API endpoint for Ollama
base_url = "http://localhost:11434/v1"
wire_api = "chat"

# 2. (Optional) Create a profile to easily switch to a local model
#    (Assumes "llama3" has been pulled via "ollama pull llama3")
[profiles.local-llama]
model_provider = "ollama"
model = "llama3:latest"

The user can then invoke this profile with codex --profile local-llama.
Part 7: Advanced Configuration Reference
All advanced customization is handled in the central configuration file, located at ~/.codex/config.toml.
7.1 Key config.toml Settings
This file allows a user to set the default behavior of the CLI.
# ~/.codex/config.toml

# Set the default model to use
model = "gpt-5-codex" 

# Set the default security policies
approval_policy = "on-request" 
sandbox_mode = "workspace-write" 

# Set the default authentication method ("chatgpt" or "apikey")
preferr[span_78](start_span)[span_78](end_span)ed_auth_method = "chatgpt" [span_130](start_span)[span_130](end_span)[span_132](start_span)[span_132](end_span)

7.2 Using Configuration Profiles (--profile)
Profiles are the most powerful customization feature. They are named groups of settings defined in config.toml that can be invoked at launch with the --profile <name> (or -p <name>) flag.
This allows a user to manage the "tri-modal" operation of the CLI—switching between subscription, API billing, and local models—without editing the file each time.
Example config.toml with Profiles:
# De[span_69](start_span)[span_69](end_span)fault settings (for subscription use)
model = "gpt-5-codex"
model_provider = "openai"
approval_policy = "on-request"

# Profile for high-capacity API billing
[profiles.api-heavy]
preferred_auth_method = "apikey"
model = "gpt-5-codex"
# Use a higher reasoning level, which is better for API billing
model_reasoning_effort = "high" [span_134](start_span)[span_134](end_span)

# Profile for cost-free, private local use
[profiles.local-safe]
model_provider = "ollama"
model = "llama3:latest"
sandbox_mode = "read-only"
approval_policy = "untrusted"

# Profile for dangerous, automated CI jobs
[profiles.ci-yolo]
preferred_auth_method = "apikey"
approval_policy = "never"
sandbox_mode = "danger-full-access"

Usage:
 * codex (Uses default subscription settings)
 * codex --profile api-heavy (Switches to API key and high reasoning)
 * codex --profile local-safe (Switches to Ollama in read-only mode)
7.3 Creating Custom Prompts
Codex supports reusable, user-defined prompts.
 * Create a markdown file in ~/.codex/prompts/ (e.g., test.md).
 * Write the prompt in the file, using $1, $2, etc., as positional arguments.
Example ~/.codex/prompts/test.md:
Write a comprehensive unit test for the function in $1.
Use the Jest testing framework.
Ensure all edge cases are covered.
Usage in TUI:
> /test src/utils/myFunction.js

7.4 Extending Codex with MCP (Model Context Protocol)
MCP is the "plugin" system for Codex, allowing it to connect to other tools and data sources. These are configured in config.toml or added via the codex mcp add command.
Example 1: Add a Documentation Server (Context7)
This command adds an MCP server that gives the agent access to developer documentation.
$ codex mcp add context7 -- npx -y @upstash/context7-mcp

Example 2: Add a Read-Only PostgreSQL Database
By adding this to confi[span_57](start_span)[span_57](end_span)g.toml, the agent gains the ability to query a database.
[mcp_servers.postgres]
command = "npx"
args =
stdio = true

The agent can then be prompted with "Use the postgres MCP tool to list all tables in the 'users' schema."
Part 8: The Broader Codex Ecosystem
A truly effective user understands that the Codex CLI is just one "surface" for a single, powerful agentic brain. The "best practice" is to use the right tool for the right job.
 * Codex Cloud (Web UI): Accessed at chatgpt.com/codex. This is used for delegating large, long-running, asynchronous tasks. A user can ask Codex Cloud to "refactor the entire repository," and it will work in the background in a sandboxed container, eventually generating a pull request for review.
 * Codex SDK: A programmatic library (primarily TypeScript) for building Codex into custom applications or CI/CD pipelines. This is more advanced than codex exec and is used for creating new, custom agentic workflows.
 * Integrations (Slack & GitHub): These are entry points to Codex Cloud.
   * Slack: Add the "Codex for Slack" app. Tagging @Codex in a channel will cause the agent to read the thread's context and initiate a Codex Cloud task.
   * GitHub: As noted earlier, commenting @codex review in a PR initiates a Codex Cloud code review task.
Part 9: Conclusions and Recommendations
The OpenAI Codex CLI is a powerful, multi-faceted engineering agent. To use it safely, effectively, and efficiently on Ubuntu, users should adhere to the following best practices.
 * Prioritize Security Configuration: Before performing any complex task, understand the security model.
   * Default: Use the default approval_policy = "on-request" and sandbox_mode = "workspace-write" for interactive work.
   * Automation: Only use --dangerously-bypass-approvals-and-sandbox (or --yolo) in fully isolated and trusted environments like Docker containers.
   * Verification: Use the /status command to verify active security settings.
 * Invest in Proactive Context: The single most effective way to improve the quality of the agent's output is to create and maintain a comprehensive AGENTS.md file. This pre-loads the agent with project-specific rules, preventing common errors and reducing the need for iterative correction.
3.  Master the "Tri-Modal" Configuration: Use configuration profiles in ~/.codex/config.toml to manage the three primary operational modes:
  *   Mode 1 (Default): Use the standard ChatGPT subscription for daily tasks. Be mindful of usage limits, especially when using "high" reasoning models.
*   Mode 2 (Pro/CI): Use a profile that sets preferred_auth_method = "apikey" for heavy-duty automation or when subscription limits are hit.
*   Mode 3 (Private/Offline): Use a profile that sets model_provider = "ollama" to run on local models, ensuring privacy and eliminating costs.
 * Use the Right Surface for the Task: Do not force the CLI to perform tasks better suited for other interfaces.
   * Codex CLI: Use for interactive, in-terminal development and scripting.
   * IDE Extension: Use for in-editor, file-aware refactoring.
   * Codex Cloud (Web/Slack/GitHub): Use for large, asynchronous tasks (e.g., "refactor the entire repo") where the agent can work for hours and deliver a pull request.
   * Codex SDK: Use for building custom, programmatic, and automated agentic workflows into a CI/CD pipeline.
