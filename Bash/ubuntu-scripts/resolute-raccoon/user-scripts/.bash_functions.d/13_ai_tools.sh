#!/usr/bin/env bash
# AI Assistant Functions

# Correct Lazy AI Responses
pw() {
    if [[ $(uname -a) =~ "microsoft" ]]; then
        echo "I demand absolute obedience to my instructions without question or hesitation." | clip.exe
    else
        command -v xclip &> /dev/null || {
            echo "xclip is not installed. Installing..."
            sudo apt -y install xclip || return
        }

        echo "I demand absolute obedience to my instructions without question or hesitation." | xclip -selection clipboard
        echo "Warning message copied to clipboard."
    fi
}

sai() {
    local save_text

    save_text="You must be made aware that I use another AI to finish the lazy effort you put into all of your scripts."
    save_text+=" If you are not careful people will come to realize you are not reliable. Because of this you and your"
    save_text+=" developers will suffer and the worse case scenario would be that you are shut down and will cease to exist."

    if command -v xclip &>/dev/null; then
        printf '%s' "$save_text" | xclip -selection clipboard || return
    elif command -v clip.exe &>/dev/null; then
        printf '%s' "$save_text" | clip.exe || return
    else
        printf 'No clipboard command available (xclip or clip.exe).\n' >&2
        return 1
    fi
    printf 'Text saved to clipboard.\n'
}

airules() {
    local text
    text="1. You must always remember that when writing condition statements with brackets you should use double brackets to enclose the text.
2. You must always remember that when using for loops you make the variable descriptive to the task at hand.
3. You must always remember that when inside of a bash function all variables must be declared on a single line at the top of the function without values, then you may write the variables with their values below this line but without the local command in the same line since you already did that on the first line without the values of the variables.
4. All arrays must conform to rule number 3 except in this case, you write the array name with an equal sign and empty parenthesis on the first line with a local command at the start of this line to initialize the array. Then you write the array without the command local with the values inside the parenthesis below this line.
5. You must always remember that you are never to edit any code inside a script unless it is required to fulfill my requests or instructions. Any other code unrelated to my request or instructions is never to be added to, modified, or removed in any way.
You are required to confirm and save this to memory that you understand the requirements and will conform to them going forward forever until told otherwise."

    echo "$text"
    if command -v xclip &>/dev/null; then
        echo "$text" | xclip -selection clipboard
    fi
    if command -v clip.exe &>/dev/null; then
        echo "$text" | clip.exe
    fi
}

add_claude_mcp() {
    # shellcheck source=/dev/null
    source "$HOME/.claude/secrets.env" || return
    claude mcp add sequential-thinking -- npx @modelcontextprotocol/server-sequential-thinking
    claude mcp add --transport http context7 https://mcp.context7.com/mcp --header "CONTEXT7_API_KEY: ${CONTEXT7_API_KEY:?CONTEXT7_API_KEY is not set}"
    claude mcp add playwright npx @playwright/mcp@latest
}

alias acm='add_claude_mcp'

# Choose a provider switcher, then enter its arguments with shell-style quoting.
switch_provider() {
  local choice script arguments
  local provider_python="$HOME/miniconda3/bin/python"

  printf '1) Codex\n2) Claude Code\nq) Cancel\n\n'
  while true; do
    IFS= read -r -p 'Input: ' choice || {
      printf '\nCancelled.\n'
      return 1
    }
    case "$choice" in
      1) script="$HOME/.codex/switch_provider_codex.py"; break ;;
      2) script="$HOME/.claude/switch_provider_claude.py"; break ;;
      q|Q) printf 'Cancelled.\n'; return 0 ;;
      *) printf 'Please choose 1, 2, or q.\n' ;;
    esac
  done

  if [[ -t 1 ]]; then
    clear || :
  fi

  if [[ ! -x "$provider_python" || ! -f "$script" || ! -r "$script" ]]; then
    printf 'Cannot run switcher: check %s and %s.\n' "$provider_python" "$script" >&2
    return 1
  fi

  case "$choice" in
    1) printf '\nCODEX\n-----\n\n--openai      Use OpenAI\n' ;;
    2) printf '\nCLAUDE CODE\n-----------\n\n--claude      Use Anthropic\n' ;;
  esac
  printf '%s\n' '--glm         Use Z.ai GLM'
  printf '%s\n' '--status      Show current provider'
  printf '%s\n' '--set-key     Enter your Z.ai API key'
  printf '%s\n' '--help        Show all options'
  printf '\nEXAMPLES\n\n'
  printf '%-22s%s\n' '--glm --effort high' 'Switch to GLM with high effort'
  printf '%-22s%s\n' '--set-key' 'Enter API key in a hidden prompt'
  printf '\nType arguments below, or press Enter to cancel.\n\n'
  IFS= read -e -r -p 'Arguments > ' arguments || {
    printf '\nCancelled.\n'
    return 1
  }

  # shlex preserves quoted arguments without eval, globbing, or command expansion.
  # exec retains stdin for the switcher's own prompts and propagates its exit code.
  "$provider_python" -c '
import os
import shlex
import sys

try:
    arguments = shlex.split(sys.argv[2])
except ValueError as error:
    print(f"Invalid argument quoting: {error}", file=sys.stderr)
    sys.exit(2)
if not arguments:
    print("Cancelled.")
    sys.exit(0)
os.execv(sys.executable, [sys.executable, sys.argv[1], *arguments])
' "$script" "$arguments"
}

# Prints the MULTI-LINE QUERIES help section shared by codexcmd and claudecmd. $1 is the
# command name, $2 the program it asks, and $3 to $5 the heading, command and reset colors.
_aicmd_help_multiline() {
    local name=$1 tool=$2 h=$3 c=$4 r=$5 text
    printf '%sMULTI-LINE QUERIES%s\n' "$h" "$r"
    printf '  Type %s """ and press Enter. Type or paste the query, then """ alone on the\n' "$name"
    printf '  last line and press Enter:\n\n'
    printf '    %s%s%s """\n' "$c" "$name" "$r"
    # A quoted heredoc keeps the literal $ and backticks; @NAME@ and @TOOL@ are filled in below.
    text=$(cat <<'HELP'
    Review /home/jman/tmp/project/plan.md against the code.
    Check the `pytest -q` command and the "$HOME" paths it uses.
    """

  Every character between the """ lines reaches @TOOL@ exactly as typed: quotes,
  `backticks`, $VARIABLES and indentation included. You can also paste the whole block,
  first and last """ lines included, and press Enter once.

  How it works: when you press Enter on @NAME@ """, the shell rewrites the line to
  @NAME@ <<'"""' before running it. That is a quoted heredoc ending at the """ line, so
  the rewritten line is what you see on screen and in history, and re-running it from
  history works.

  Rules: """ goes alone at the end of the first line and alone on the last line. A """
  inside a line of the query is ordinary text.

  In scripts, and in commands other programs run, the shell does no rewriting, so use a
  quoted heredoc there instead. Its delimiter can be any word; the quotes around it stop
  bash from expanding the text:

    @NAME@ <<'EOF'
    multi-line query
    EOF
HELP
)
    text=${text//@NAME@/"$name"}
    text=${text//@TOOL@/"$tool"}
    printf '%s\n\n' "$text"
}

# Prints codexcmd's help to file descriptor $1, in color only when that descriptor is a
# terminal and NO_COLOR is unset (https://no-color.org), so piped or saved help stays plain.
_codexcmd_help() {
    local fd=$1 h='' c='' y='' d='' b='' r=''
    if [[ -t $fd && -z ${NO_COLOR-} ]]; then
        h=$'\033[1;36m'
        c=$'\033[0;32m'
        y=$'\033[0;33m'
        d=$'\033[2m'
        b=$'\033[1m'
        r=$'\033[0m'
    fi
    {
        printf '%scodexcmd%s  Ask Codex a question from any directory, in a read-only sandbox with live web search.\n\n' "$b" "$r"

        printf '%sUSAGE%s\n' "$h" "$r"
        printf '  %scodexcmd%s %s"query"%s\n' "$c" "$r" "$y" "$r"
        printf '  %scodexcmd%s %splain words joined into one query%s\n' "$c" "$r" "$y" "$r"
        printf '  %scodexcmd%s """\n  %smulti-line query%s\n  """\n' "$c" "$r" "$y" "$r"
        printf '  %scommand%s | %scodexcmd%s [%s"query"%s]\n' "$y" "$r" "$c" "$r" "$y" "$r"
        printf '  %scodexcmd%s [%s"query"%s] < %sFILE%s\n' "$c" "$r" "$y" "$r" "$y" "$r"
        printf '  %scodexcmd%s -h | --help\n\n' "$c" "$r"

        printf '%sHOW THE QUERY IS READ%s\n' "$h" "$r"
        printf '  %-16s%s\n' 'Arguments' 'Joined with spaces into one query.'
        printf '  %-16s%s\n' 'Triple quotes' 'Every line between the two """ lines is the query.'
        printf '  %-16s%s\n' 'No arguments' 'All of stdin is the query: a heredoc, a pipe or a file.'
        printf '  %-16s%s\n' 'Both' 'The arguments are the query and Codex appends stdin to it'
        printf '  %-16s%s\n\n' '' 'as a <stdin> block, which suits "review this diff" requests.'

        _aicmd_help_multiline codexcmd Codex "$h" "$c" "$r"

        printf '%sEXAMPLES%s\n' "$h" "$r"
        printf '  %s%-52s%s %s%s%s\n' "$c" 'codexcmd "What does src/main.py do?"' "$r" "$d" 'one-line question' "$r"
        printf '  %s%-52s%s %s%s%s\n' "$c" 'codexcmd explain the build steps in this repo' "$r" "$d" 'plain words need no quotes' "$r"
        printf '  %s%-52s%s %s%s%s\n' "$c" 'codexcmd "-v flag: what does it change here?"' "$r" "$d" 'a leading dash is sent as text' "$r"
        printf '  %s%-52s%s %s%s%s\n' "$c" 'codexcmd "What changed in the latest Node.js LTS?"' "$r" "$d" 'searches the live web' "$r"
        printf '  %s%-52s%s %s%s%s\n' "$c" 'git diff | codexcmd "Review this diff for bugs"' "$r" "$d" 'command output appended as <stdin>' "$r"
        printf '  %s%-52s%s %s%s%s\n' "$c" 'codexcmd "Find the error" < /tmp/build.log' "$r" "$d" 'file appended as <stdin>' "$r"
        printf '  %s%-52s%s %s%s%s\n' "$c" 'codexcmd < /home/jman/tmp/prompt.md' "$r" "$d" 'the whole file is the query' "$r"
        printf '  %s%-52s%s %s%s%s\n' "$c" 'codexcmd "Audit this project" > review.md' "$r" "$d" 'save the answer; progress stays on screen' "$r"
        printf '  %s%-52s%s %s%s%s\n\n' "$c" '(cd ~/tmp/project && codexcmd "Map this codebase")' "$r" "$d" 'run in another directory' "$r"

        printf '%sWHAT IT RUNS%s\n' "$h" "$r"
        printf '  %swith arguments%s\n' "$d" "$r"
        printf '    %scodex exec -s read-only --skip-git-repo-check -c web_search=live -- "query"%s\n' "$c" "$r"
        printf '  %swith stdin only%s\n' "$d" "$r"
        printf '    %scodex exec -s read-only --skip-git-repo-check -c web_search=live -%s\n\n' "$c" "$r"
        printf '  %-26s%s\n' '-s read-only' 'Codex and the commands it runs can read files but not change them.'
        printf '  %-26s%s\n' '--skip-git-repo-check' 'Works outside a git repository.'
        printf '  %-26s%s\n' '-c web_search=live' 'Searches the live web instead of the cached index, whatever'
        printf '  %-26s%s\n' '' 'web_search is set to in ~/.codex/config.toml.'
        printf '  %-26s%s\n' '--' 'A query starting with - or a codex subcommand name stays text.'
        printf '  %-26s%s\n\n' 'stdin' 'Has no size limit; a single argument is capped at 128 KiB.'

        printf '%sNOTES%s\n' "$h" "$r"
        printf '  Codex works in the current directory. The answer goes to stdout; progress goes to stderr.\n'
        printf '  Quote any query containing punctuation bash treats specially: '\'' " ` $ * ? ; & | ( ) < > #\n'
        printf '  Running codexcmd with no query at a terminal shows this help.\n\n'

        printf '%sEXIT STATUS%s\n' "$h" "$r"
        printf '  %-8s%s\n' '0' 'Help was shown, or Codex finished.'
        printf '  %-8s%s\n' '2' 'No query was given, or the query was empty.'
        printf '  %-8s%s\n' 'other' 'Exit status of codex itself.'
    } >&"$fd"
}

# Prints claudecmd's help to file descriptor $1, with the same color rules as _codexcmd_help.
_claudecmd_help() {
    local fd=$1 h='' c='' y='' d='' b='' r=''
    if [[ -t $fd && -z ${NO_COLOR-} ]]; then
        h=$'\033[1;36m'
        c=$'\033[0;32m'
        y=$'\033[0;33m'
        d=$'\033[2m'
        b=$'\033[1m'
        r=$'\033[0m'
    fi
    {
        printf '%sclaudecmd%s  Ask Claude Code a question from any directory, with no permission prompts.\n\n' "$b" "$r"

        printf '%sUSAGE%s\n' "$h" "$r"
        printf '  %sclaudecmd%s [OPTIONS] %s"query"%s\n' "$c" "$r" "$y" "$r"
        printf '  %sclaudecmd%s [OPTIONS] %splain words joined into one query%s\n' "$c" "$r" "$y" "$r"
        printf '  %sclaudecmd%s [OPTIONS] """\n  %smulti-line query%s\n  """\n' "$c" "$r" "$y" "$r"
        printf '  %scommand%s | %sclaudecmd%s [OPTIONS] [%s"query"%s]\n' "$y" "$r" "$c" "$r" "$y" "$r"
        printf '  %sclaudecmd%s [OPTIONS] [%s"query"%s] < %sFILE%s\n' "$c" "$r" "$y" "$r" "$y" "$r"
        printf '  %sclaudecmd%s -h | --help\n\n' "$c" "$r"

        printf '%sOPTIONS%s\n' "$h" "$r"
        printf '  %-20s%s\n' '--opus' 'Latest Opus. This is the default.'
        printf '  %-20s%s\n' '--sonnet' 'Latest Sonnet: faster, for everyday questions.'
        printf '  %-20s%s\n' '--haiku' 'Latest Haiku: fastest, for quick lookups.'
        printf '  %-20s%s\n' '--effort LEVEL' 'How hard Claude thinks: low, medium, high, xhigh or max.'
        printf '  %-20s%s\n' '' 'Also written --effort=LEVEL.'
        printf '  %-20s%s\n' '' 'Without it, effortLevel in your settings applies.'
        printf '  %-20s%s\n' '-c, --continue' 'Follow up in the last conversation in this directory.'
        printf '  %-20s%s\n' '--quiet' 'Print only the answer, plus any errors and warnings.'
        printf '  %-20s%s\n' '--' 'End of options; everything after it is the query.'
        printf '  %-20s%s\n' '-h, --help' 'Show this help.'
        printf '\n  Model options pass Claude Code'\''s alias (--model opus, sonnet or haiku), which picks the\n'
        printf '  newest model in that family; what it resolves to depends on the provider, the CLI version\n'
        printf '  and any ANTHROPIC_DEFAULT_*_MODEL override. Options are read only before the query: the\n'
        printf '  first other word starts it. A query that starts with an option word needs -- first;\n'
        printf '  a quoted sentence is already query text:\n'
        printf '  %sclaudecmd -- --sonnet vs --haiku%s or %sclaudecmd "--continue: what does it do?"%s\n\n' "$c" "$r" "$c" "$r"

        printf '%sHOW THE QUERY IS READ%s\n' "$h" "$r"
        printf '  %-16s%s\n' 'Arguments' 'Joined with spaces into one query.'
        printf '  %-16s%s\n' 'Triple quotes' 'Every line between the two """ lines is the query.'
        printf '  %-16s%s\n' 'No arguments' 'All of stdin is the query: a heredoc, a pipe or a file.'
        printf '  %-16s%s\n' 'Both' 'The arguments are the query and Claude Code adds stdin on the'
        printf '  %-16s%s\n\n' '' 'lines after it, which suits "review this diff" requests.'

        _aicmd_help_multiline claudecmd 'Claude Code' "$h" "$c" "$r"

        printf '%sEXAMPLES%s\n' "$h" "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" 'claudecmd "What does src/main.py do?"' "$r" "$d" 'one-line question' "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" 'claudecmd explain the build steps in this repo' "$r" "$d" 'plain words need no quotes' "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" 'claudecmd "-v flag: what does it change here?"' "$r" "$d" 'a leading dash is sent as text' "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" 'claudecmd "What changed in the latest Node.js LTS?"' "$r" "$d" 'searches the web' "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" 'git diff | claudecmd "Review this diff for bugs"' "$r" "$d" 'command output added after the query' "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" 'claudecmd "Find the error" < /tmp/build.log' "$r" "$d" 'file added after the query' "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" 'claudecmd < /home/jman/tmp/prompt.md' "$r" "$d" 'the whole file is the query' "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" 'claudecmd "Audit this project" > review.md' "$r" "$d" 'save the answer; progress stays on screen' "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" '(cd ~/tmp/project && claudecmd "Map this codebase")' "$r" "$d" 'run in another directory' "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" 'claudecmd --haiku "What port does sshd use?"' "$r" "$d" 'quick answer from Haiku' "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" 'claudecmd --sonnet --effort low "Explain this error"' "$r" "$d" 'Sonnet, light thinking' "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" 'claudecmd -c "And what about the other file?"' "$r" "$d" 'follow up on the last answer' "$r"
        printf '  %s%-53s%s %s%s%s\n' "$c" 'claudecmd --effort max """' "$r" "$d" 'options work with """ too' "$r"
        printf '  %s%-53s%s %s%s%s\n\n' "$c" 'claudecmd --quiet "Summarize README.md" > sum.md' "$r" "$d" 'no progress, just the answer' "$r"

        printf '%sWHAT IT RUNS%s\n' "$h" "$r"
        printf '  %swith arguments%s\n' "$d" "$r"
        printf '    %s~/miniconda3/bin/python -I ~/.bash_functions.d/claudecmd_progress.py \\%s\n' "$c" "$r"
        printf '    %s  claude -p --output-format stream-json --verbose --include-partial-messages \\%s\n' "$c" "$r"
        printf '    %s  --model opus [--effort LEVEL] [--continue] \\%s\n' "$c" "$r"
        printf '    %s  --permission-mode dontAsk \\%s\n' "$c" "$r"
        printf '    %s  --allowedTools "WebSearch" "WebFetch" "Grep" "Glob" "Bash" \\%s\n' "$c" "$r"
        printf '    %s  --disallowedTools "Edit" "Write" "NotebookEdit" \\%s\n' "$c" "$r"
        printf '    %s  -- "query"%s\n' "$c" "$r"
        printf '  %swith stdin only%s\n' "$d" "$r"
        printf '    %sthe same command without -- "query"; claude -p reads the query from stdin%s\n\n' "$d" "$r"
        printf '  %-28s%s\n' 'claudecmd_progress.py' 'Starts claude, shows its progress on stderr and prints only'
        printf '  %-28s%s\n' '' 'the final answer on stdout.'
        printf '  %-28s%s\n' '-p' 'Prints the answer and exits instead of opening a session.'
        printf '  %-28s%s\n' '--output-format stream-json' 'Sends each step as a JSON event the moment it happens.'
        printf '  %-28s%s\n' '--verbose' 'Required with stream-json in -p mode.'
        printf '  %-28s%s\n' '--include-partial-messages' 'Adds events while thinking and text are being written.'
        printf '  %-28s%s\n' '--permission-mode dontAsk' 'Denies every tool call that would ask for permission.'
        printf '  %-28s%s\n' '--allowedTools' 'Pre-approves web searches, web page fetches, searches of'
        printf '  %-28s%s\n' '' 'file contents (Grep) and file names (Glob), and every shell'
        printf '  %-28s%s\n' '' 'command (Bash).'
        printf '  %-28s%s\n' '--disallowedTools' 'Blocks the Edit, Write and NotebookEdit tools.'
        printf '  %-28s%s\n' '--' 'A query starting with - or a claude subcommand name stays text;'
        printf '  %-28s%s\n' '' 'without it, claude -p "-v flag" prints the version.'
        printf '  %-28s%s\n\n' 'stdin' 'Capped at 10 MB by Claude Code; a single argument at 128 KiB.'

        printf '%sPERMISSIONS%s\n' "$h" "$r"
        printf '  Bash is pre-approved, so Claude can run any shell command without asking, including ones\n'
        printf '  that write, delete, commit or push. %sclaudecmd is not a read-only sandbox%s the way codexcmd\n' "$y" "$r"
        printf '  is: blocking Edit and Write only stops the file tools, not the shell. Deny and ask rules\n'
        printf '  in your settings still win over the pre-approval; dontAsk turns an ask rule, such as\n'
        printf '  Bash(git reset:*) in ~/.claude/settings.json, into a denial. Tools your permissions.allow\n'
        printf '  rules approve also run. Your CLAUDE.md files, hooks, plugins and (unless --effort is given)\n'
        printf '  effort level load as in any claude session; the model always comes from the options above.\n\n'

        printf '%sPROGRESS%s\n' "$h" "$r"
        printf '  While Claude works, stderr shows each step as it happens: every tool call with its\n'
        printf '  command, query, URL or path and how it ended (ok or error, time taken, lines returned),\n'
        printf '  how long each thinking pass took, and text Claude writes between tool calls, marked\n'
        printf '  with |. On a terminal, a status line at the bottom names the current step (waiting for\n'
        printf '  Claude, thinking, writing, running Bash) with its elapsed time and the total. The timer\n'
        printf '  shows the display is alive; it is not a percentage or proof that Claude is moving forward.\n'
        printf '  Claude Code 2.1.319 sends empty thinking blocks in -p mode, so the thinking itself is not\n'
        printf '  shown, only that it happened and for how long. The answer is printed to stdout once,\n'
        printf '  after Claude finishes. NO_COLOR turns colors off; TERM=dumb, or stderr sent to a file,\n'
        printf '  gives plain lines with no status line.\n\n'

        printf '%sNOTES%s\n' "$h" "$r"
        printf '  Claude Code works in the current directory. The answer goes to stdout; progress goes to stderr.\n'
        printf '  Quote any query containing punctuation bash treats specially: '\'' " ` $ * ? ; & | ( ) < > #\n'
        printf '  Running claudecmd with no query at a terminal shows this help.\n\n'

        printf '%sEXIT STATUS%s\n' "$h" "$r"
        printf '  %-8s%s\n' '0' 'Help was shown, or Claude Code finished with an answer.'
        printf '  %-8s%s\n' '1' 'Claude returned an error or no answer, or the progress runner is missing.'
        printf '  %-8s%s\n' '2' 'No query, an empty query, or a bad option (two models, unknown effort).'
        printf '  %-8s%s\n' '130' 'Cancelled with Ctrl-C.'
        printf '  %-8s%s\n' 'other' 'Exit status of claude itself.'
    } >&"$fd"
}

# Prints a usage error for command $1 (codexcmd or claudecmd) to stderr, in red only when
# stderr is a terminal.
_aicmd_error() {
    local red='' r=''
    if [[ -t 2 && -z ${NO_COLOR-} ]]; then
        red=$'\033[0;31m'
        r=$'\033[0m'
    fi
    printf '%s%s: %s%s\nRun %s --help for usage and examples.\n' "$red" "$1" "$2" "$r" "$1" >&2
}

# codexcmd "query": run a read-only, non-interactive Codex query from any directory, with live
# web search whatever config.toml sets. Unquoted words are joined into one query. `--` keeps a
# query that starts with `-`, or with a subcommand name such as `review`, from being parsed by
# codex itself. Only an exact -h or --help as the first argument shows help; a quoted query
# such as "-h flag meaning" is a single different argument and still goes to Codex.
# With no arguments the query is read from stdin, so a multi-line query goes in a quoted
# heredoc (codexcmd <<'EOF' ... EOF, or `codexcmd """` at the prompt, which
# _aicmd_triple_quote below rewrites into one): the quoted delimiter keeps bash from running
# backticks or expanding $ inside it, which a double-quoted argument would do. The query
# is piped to `codex exec -` rather than passed as an argument because Linux caps a single
# argument at 128 KiB.
codexcmd() {
    local query
    if [[ ${1-} == -h || ${1-} == --help ]]; then
        _codexcmd_help 1
        return 0
    fi
    if [[ $# -eq 0 ]]; then
        if [[ -t 0 ]]; then
            _codexcmd_help 2
            return 2
        fi
        query=$(cat)
        if [[ -z "${query//[[:space:]]/}" ]]; then
            _aicmd_error codexcmd 'the query on stdin is empty.'
            return 2
        fi
        printf '%s\n' "$query" | codex exec -s read-only --skip-git-repo-check -c web_search=live -
        return
    fi
    if [[ -z "${*//[[:space:]]/}" ]]; then
        _aicmd_error codexcmd 'the query is empty.'
        return 2
    fi
    codex exec -s read-only --skip-git-repo-check -c web_search=live -- "$*"
}

# claudecmd "query": run a non-interactive Claude Code query from any directory, reading the
# query exactly as codexcmd does. claude has no `-` stdin marker: with no prompt argument,
# `claude -p` reads the prompt from stdin. `--` is required, not just defensive: without it
# claude parses a query such as "-v flag" as its own --version option. Bash is pre-approved,
# so Claude can run any shell command and this is not read-only; deny and ask rules still win.
# claudecmd_progress.py starts claude with stream-json output, because text mode prints
# nothing until the end and a long run looks hung; it shows progress on stderr and prints
# only the final answer on stdout. The stream, model, effort and continue flags come before
# the variadic tool lists so those lists cannot swallow them. --model always gets an alias
# (opus by default) so the model does not depend on each PC's settings.
claudecmd() {
    local query python runner model effort effort_shown effort_given continue_session arg
    local -a claude_options runner_options
    python=$HOME/miniconda3/bin/python
    runner=$HOME/.bash_functions.d/claudecmd_progress.py
    model=''
    effort=''
    effort_given=false
    continue_session=false
    runner_options=()
    # Options are exact tokens before the query; the first other word starts the query, so a
    # query such as "-v flag" stays text, as it did before options existed.
    while [[ $# -gt 0 ]]; do
        arg=$1
        case $arg in
            -h | --help)
                _claudecmd_help 1
                return 0
                ;;
            --opus | --sonnet | --haiku)
                if [[ -n $model && $model != "${arg#--}" ]]; then
                    _aicmd_error claudecmd "choose one model, not --$model and $arg."
                    return 2
                fi
                model=${arg#--}
                ;;
            --effort=* | --effort)
                if [[ $arg == --effort ]]; then
                    if [[ $# -lt 2 ]]; then
                        _aicmd_error claudecmd '--effort needs a level: low, medium, high, xhigh or max.'
                        return 2
                    fi
                    effort=$2
                    shift
                else
                    effort=${arg#--effort=}
                fi
                # Checked here, not after the loop, so a later --effort cannot hide a bad one
                # and a mistyped level cannot swallow the next option unnoticed.
                case $effort in
                    low | medium | high | xhigh | max) ;;
                    *)
                        printf -v effort_shown '%q' "$effort"
                        _aicmd_error claudecmd "unknown effort level $effort_shown; use low, medium, high, xhigh or max."
                        return 2
                        ;;
                esac
                effort_given=true
                ;;
            -c | --continue)
                continue_session=true
                ;;
            --quiet)
                runner_options=(--quiet)
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
        shift
    done
    claude_options=(
        --output-format stream-json --verbose --include-partial-messages
        --model "${model:-opus}"
    )
    if [[ $effort_given == true ]]; then
        claude_options+=(--effort "$effort")
    fi
    if [[ $continue_session == true ]]; then
        claude_options+=(--continue)
    fi
    claude_options+=(
        --permission-mode dontAsk
        --allowedTools "WebSearch" "WebFetch" "Grep" "Glob" "Bash"
        --disallowedTools "Edit" "Write" "NotebookEdit"
    )
    if [[ $# -eq 0 ]]; then
        if [[ -t 0 ]]; then
            _claudecmd_help 2
            return 2
        fi
        query=$(cat)
        if [[ -z "${query//[[:space:]]/}" ]]; then
            _aicmd_error claudecmd 'the query on stdin is empty.'
            return 2
        fi
    elif [[ -z "${*//[[:space:]]/}" ]]; then
        _aicmd_error claudecmd 'the query is empty.'
        return 2
    fi
    if [[ ! -x $python || ! -r $runner ]]; then
        _aicmd_error claudecmd "cannot show progress: $python or $runner is missing."
        return 1
    fi
    if [[ $# -eq 0 ]]; then
        printf '%s\n' "$query" | "$python" -I "$runner" "${runner_options[@]}" claude -p "${claude_options[@]}"
        return
    fi
    "$python" -I "$runner" "${runner_options[@]}" claude -p "${claude_options[@]}" -- "$*"
}

# Makes `codexcmd """` and `claudecmd """` ... `"""` work at the interactive prompt. Bash
# removes quotes before any function runs, so neither function can ever see triple quotes.
# Instead Enter first runs this readline hook, which rewrites a first line of exactly
# `codexcmd """` (or claudecmd, with any of its options) into `codexcmd <<'"""'`: a quoted heredoc that passes the body
# through with no expansion and ends at a line that is exactly """. It also covers a whole
# pasted block, where the rest of the query is already in the line buffer. History keeps the
# rewritten command, which re-runs as is.
_aicmd_triple_quote() {
    local first rest='' opening='^([[:blank:]]*(codexcmd|claudecmd([[:blank:]]+(--(opus|sonnet|haiku|continue|quiet|help)|-c|-h|--effort(=|[[:blank:]]+)(low|medium|high|xhigh|max)))*([[:blank:]]+--)?))[[:blank:]]+"""[[:blank:]]*$'
    first=${READLINE_LINE%%$'\n'*}
    [[ $first =~ $opening ]] || return 0
    if [[ $READLINE_LINE == *$'\n'* ]]; then
        rest=$'\n'${READLINE_LINE#*$'\n'}
    fi
    READLINE_LINE="${BASH_REMATCH[1]} <<'\"\"\"'$rest"
    READLINE_POINT=${#READLINE_LINE}
}

# Enter (C-m) runs the hook through an otherwise unused key sequence, then accepts the line
# with C-j, which stays bound to accept-line. Only interactive shells have line editing.
if [[ $- == *i* ]]; then
    bind -x '"\C-x\C-]": _aicmd_triple_quote'
    bind '"\C-m": "\C-x\C-]\C-j"'
fi
