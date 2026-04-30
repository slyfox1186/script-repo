#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$EUID" -eq 0 ]]; then
    echo "Error: Do not run this script as root or with sudo." >&2
    exit 1
fi

umask 077

FAQ_USER=""
FAQ_PASS=""
COOKIES_OUT=""
LOGIN_URL=""
HEADLESS=0

usage() {
    local prog
    prog="$(basename "$0")"
    cat <<EOF
$prog — log in to a website and export its cookies for aria2/curl/wget

  >>> IMPORTANT: the URL you pass with -w MUST load the login page    <<<
  >>> directly (the page that has the username + password fields).    <<<
  >>> Do NOT pass the homepage / root domain — pre-fill will fail and <<<
  >>> the script will sit waiting for a login that never happens.     <<<

WHAT IT DOES
  1. Opens a real Chromium window pointed at the login URL you give it.
  2. Pre-fills the username and password fields for you.
  3. You solve the CAPTCHA (if any) and click LOGIN.
  4. Once the page redirects away from the login URL, it grabs every
     cookie set for that site and saves them to your output file in
     Netscape "cookies.txt" format (the format aria2/curl/wget expect).
  5. The output directory and file are created if they don't exist.

USAGE
  $prog -u USER -p PASS -o PATH -w URL [--headless]

REQUIRED ARGUMENTS
  -u, --user   USER     Your login username.
  -p, --pass   PASS     Your login password.
                        Tip: quote it if it contains shell-special chars.
  -o, --output PATH     Where to write the cookies file. Parent dir is
                        created (mode 700); file is created (mode 600).
                        Example: ~/.aria2/cookies.txt
  -w, --url    URL      Full URL of the LOGIN PAGE — the exact page that
                        shows the username and password fields. NOT the
                        homepage, NOT just the domain. Must start with
                        http:// or https://.
                          GOOD: http://www.example.com/login.php
                          GOOD: https://site.tld/account/signin
                          BAD : http://www.example.com/   (homepage)
                          BAD : example.com               (no scheme)

OPTIONAL ARGUMENTS
      --headless        Run Chromium with no visible window. Only useful
                        if the site has NO captcha. The browser will be
                        invisible, so you cannot interact with it.
  -h, --help            Show this help text and exit.

EXAMPLES
  Typical use (headed browser, you solve the CAPTCHA):
    $prog \\
      -u myuser \\
      -p 'my-secret-pw' \\
      -o ~/.aria2/cookies.txt \\
      -w http://www.example.com/login.php

  No CAPTCHA, no GUI:
    $prog -u myuser -p mypass \\
          -o ./cookies.txt \\
          -w https://site.tld/login \\
          --headless

EXIT CODES
  0   Cookies were captured and written successfully.
  2   Bad / missing arguments, OR no cookies could be captured
      (login was not completed within the 5-minute window).

NOTES
  • The first run takes ~30s to set up a Python venv and install
    Playwright. Subsequent runs are fast.
  • You have up to 5 minutes after the browser opens to log in.
  • Cookies for the site's root domain (and its subdomains) are saved.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--user)    FAQ_USER="${2-}"; shift 2;;
        -p|--pass)    FAQ_PASS="${2-}"; shift 2;;
        -o|--output)  COOKIES_OUT="${2-}"; shift 2;;
        -w|--url)     LOGIN_URL="${2-}"; shift 2;;
        --headless)   HEADLESS=1; shift;;
        -h|--help)    usage; exit 0;;
        *)            echo "Unknown argument: $1" >&2; usage >&2; exit 2;;
    esac
done

missing=()
[[ -z "$FAQ_USER"    ]] && missing+=("-u/--user")
[[ -z "$FAQ_PASS"    ]] && missing+=("-p/--pass")
[[ -z "$COOKIES_OUT" ]] && missing+=("-o/--output")
[[ -z "$LOGIN_URL"   ]] && missing+=("-w/--url")
if (( ${#missing[@]} > 0 )); then
    echo "Error: missing required argument(s): ${missing[*]}" >&2
    echo >&2
    usage >&2
    exit 2
fi

if [[ ! "$LOGIN_URL" =~ ^https?:// ]]; then
    echo "Error: -w/--url must start with http:// or https:// (got: $LOGIN_URL)" >&2
    exit 2
fi

cat >&2 <<EOF
============================================================
 Reminder: -w must point at the LOGIN PAGE (not the homepage)
   You passed: $LOGIN_URL
 If this URL does not show username/password fields, the
 script cannot pre-fill the form and the login will fail.
============================================================
EOF

cookies_dir="$(dirname -- "$COOKIES_OUT")"
if [[ -e "$cookies_dir" && ! -d "$cookies_dir" ]]; then
    echo "Error: $cookies_dir exists but is not a directory." >&2
    exit 1
fi
if [[ ! -d "$cookies_dir" ]]; then
    mkdir -p -- "$cookies_dir"
    chmod 700 -- "$cookies_dir"
fi

if [[ ! -e "$COOKIES_OUT" ]]; then
    touch -- "$COOKIES_OUT"
    chmod 600 -- "$COOKIES_OUT"
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required." >&2
    exit 1
fi

VENV_DIR="${SOURCE_COOKIES_VENV:-$HOME/.cache/source_cookies/venv}"
mkdir -p -- "$(dirname -- "$VENV_DIR")"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "[+] Creating Python venv at $VENV_DIR"
    python3 -m venv -- "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

if ! python -c 'import playwright' >/dev/null 2>&1; then
    echo "[+] Installing playwright into venv"
    pip install --quiet --upgrade pip
    pip install --quiet playwright
fi

export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"

# Idempotent — skips download if matching browser is already cached.
echo "[+] Ensuring Chromium is installed (this is a no-op if already cached)"
python -m playwright install chromium >/dev/null

echo "[+] Cookies will be written to: $COOKIES_OUT"

FAQ_USER="$FAQ_USER" FAQ_PASS="$FAQ_PASS" COOKIES_OUT="$COOKIES_OUT" \
LOGIN_URL="$LOGIN_URL" HEADLESS="$HEADLESS" \
python - <<'PYEOF'
import os
import sys
import time
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

USER = os.environ["FAQ_USER"]
PASS = os.environ["FAQ_PASS"]
OUT  = Path(os.environ["COOKIES_OUT"])
LOGIN_URL = os.environ["LOGIN_URL"]
HEADLESS = os.environ.get("HEADLESS", "0") not in ("0", "", "false", "False")

HOSTNAME = (urlparse(LOGIN_URL).hostname or "").lower()
ROOT_DOMAIN = ".".join(HOSTNAME.split(".")[-2:]) if HOSTNAME.count(".") >= 1 else HOSTNAME

UA = "Mozilla/5.0 (X11; Linux x86_64; rv:150.0) Gecko/20100101 Firefox/150.0"

def to_netscape(cookies):
    """Render a list of Playwright cookies in Netscape cookies.txt format."""
    lines = [
        "# Netscape HTTP Cookie File",
        "# Generated by source_cookies.sh",
        "",
    ]
    for c in cookies:
        domain = c.get("domain", "")
        include_subdomains = "TRUE" if domain.startswith(".") else "FALSE"
        path = c.get("path", "/") or "/"
        secure = "TRUE" if c.get("secure") else "FALSE"
        expires = int(c.get("expires", -1) or -1)
        if expires < 0:
            expires = 0
        name = c.get("name", "")
        value = c.get("value", "")
        lines.append("\t".join([
            domain, include_subdomains, path, secure, str(expires), name, value
        ]))
    return "\n".join(lines) + "\n"

with sync_playwright() as p:
    browser = p.chromium.launch(headless=HEADLESS)
    ctx = browser.new_context(user_agent=UA)
    page = ctx.new_page()

    print(f"[+] Navigating to {LOGIN_URL}")
    page.goto(LOGIN_URL, wait_until="domcontentloaded")

    try:
        page.fill('input[name="username"]', USER)
        page.fill('input[name="pass"]', PASS)
        try:
            page.focus('input[name="code"]')
        except Exception:
            pass
        print("[+] Username/password pre-filled.")
    except Exception as e:
        print(f"[!] Could not pre-fill credentials: {e}", file=sys.stderr)

    if HEADLESS:
        print("[!] HEADLESS=1 — submitting blindly. CAPTCHA likely to fail.",
              file=sys.stderr)
        try:
            page.click('input[type="submit"]')
        except Exception:
            pass
    else:
        print("[+] Solve the CAPTCHA (if any) in the browser window and click LOGIN.")
        print(f"[+] Waiting up to 5 minutes for redirect away from {LOGIN_URL} ...")

    success = False
    deadline = time.time() + (5 * 60)
    while time.time() < deadline:
        try:
            page.wait_for_url(
                lambda u: u.rstrip("/") != LOGIN_URL.rstrip("/"),
                timeout=3000,
            )
            success = True
            break
        except PWTimeout:
            if page.is_closed():
                print("[!] Browser window was closed before login completed.",
                      file=sys.stderr)
                break

    if not success:
        print(f"[!] Did not detect successful login (no redirect away from {LOGIN_URL}).",
              file=sys.stderr)
        print("[!] Saving any cookies that were obtained anyway.", file=sys.stderr)

    cookies = ctx.cookies()
    try:
        browser.close()
    except Exception:
        pass

site_cookies = [
    c for c in cookies
    if ROOT_DOMAIN and ROOT_DOMAIN in (c.get("domain", "") or "").lower()
]

if not site_cookies:
    print(f"[X] No cookies for {ROOT_DOMAIN!r} were captured. Login likely failed.",
          file=sys.stderr)
    sys.exit(2)

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(to_netscape(site_cookies))
try:
    os.chmod(OUT, 0o600)
except OSError:
    pass

print(f"[+] Wrote {len(site_cookies)} cookie(s) to {OUT}")
for c in site_cookies:
    print(f"    - {c.get('domain')}  {c.get('name')}")
PYEOF

echo "[+] Done."
