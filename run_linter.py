#!/usr/bin/env python3
"""
Robust Rust Linter Script

This script runs comprehensive linting on Rust code to quickly find and fix issues.
It performs the following checks:
1. rustfmt - Code formatting
2. clippy - Linting and code quality
3. cargo check - Compilation checking
4. cargo test - Test execution
5. cargo audit - Security vulnerability scanning

Usage:
    python3 run_linter.py [--fix] [--verbose] [--check-only]

Options:
    --fix          Automatically fix issues when possible
    --verbose      Show detailed output
    --check-only   Only run checks, don't build or test
    --no-color      Disable colored output
"""

import os
import sys
import subprocess
import argparse
import json
from pathlib import Path
from typing import List, Tuple, Dict, Optional

class LinterResult:
    """Class to hold linting results"""
    def __init__(self, command: str, success: bool, output: str, error: str, exit_code: int):
        self.command = command
        self.success = success
        self.output = output
        self.error = error
        self.exit_code = exit_code

class RustLinter:
    """Robust Rust linter with comprehensive checks"""

    def __init__(self, project_path: str = ".", verbose: bool = False, no_color: bool = False):
        self.project_path = Path(project_path).resolve()
        self.verbose = verbose
        self.no_color = no_color
        self.results: List[LinterResult] = []

        # Validate project path
        if not self.project_path.exists():
            raise FileNotFoundError(f"Project path does not exist: {self.project_path}")

        if not (self.project_path / "Cargo.toml").exists():
            raise FileNotFoundError(f"No Cargo.toml found in: {self.project_path}")

    def log(self, message: str, level: str = "INFO"):
        """Log messages with optional color"""
        if not self.verbose and level not in ["ERROR", "WARNING", "SUCCESS"]:
            return

        colors = {
            "INFO": "\033[36m",    # Cyan
            "SUCCESS": "\033[32m",  # Green
            "WARNING": "\033[33m",  # Yellow
            "ERROR": "\033[31m",    # Red
            "RESET": "\033[0m"      # Reset
        }

        if not self.no_color:
            color = colors.get(level, "")
            reset = colors["RESET"]
            print(f"{color}[{level}]{reset} {message}")
        else:
            print(f"[{level}] {message}")

    def run_command(self, command: List[str], cwd: Optional[Path] = None) -> LinterResult:
        """Run a command and return the result"""
        if cwd is None:
            cwd = self.project_path

        cmd_str = " ".join(command)
        self.log(f"Running: {cmd_str}", "INFO")

        try:
            env = os.environ.copy()
            if self.no_color:
                env["CARGO_TERM_COLOR"] = "never"

            result = subprocess.run(
                command,
                cwd=cwd,
                capture_output=True,
                text=True,
                env=env
            )

            success = result.returncode == 0
            output = result.stdout
            error = result.stderr

            if success:
                self.log(f"✅ Command completed successfully", "SUCCESS")
            else:
                self.log(f"❌ Command failed with exit code {result.returncode}", "ERROR")

            return LinterResult(cmd_str, success, output, error, result.returncode)

        except Exception as e:
            self.log(f"💥 Exception running command: {e}", "ERROR")
            return LinterResult(cmd_str, False, "", str(e), -1)

    def check_rustfmt(self) -> LinterResult:
        """Check code formatting with rustfmt"""
        self.log("🔍 Checking code formatting with rustfmt...", "INFO")

        # First check if rustfmt is installed
        check_cmd = ["rustfmt", "--version"]
        result = self.run_command(check_cmd)

        if not result.success:
            self.log("❌ rustfmt is not installed. Install with: rustup component add rustfmt", "ERROR")
            return result

        # Run rustfmt in check mode
        cmd = ["cargo", "fmt", "--all", "--", "--check"]
        return self.run_command(cmd)

    def fix_rustfmt(self) -> LinterResult:
        """Fix code formatting with rustfmt"""
        self.log("🔧 Fixing code formatting with rustfmt...", "INFO")
        cmd = ["cargo", "fmt", "--all"]
        return self.run_command(cmd)

    def check_clippy(self) -> LinterResult:
        """Run clippy for linting"""
        self.log("🔍 Running clippy linting...", "INFO")

        # Check if clippy is installed
        check_cmd = ["cargo", "clippy", "--version"]
        result = self.run_command(check_cmd)

        if not result.success:
            self.log("❌ clippy is not installed. Install with: rustup component add clippy", "ERROR")
            return result

        # Run clippy with all targets and features
        cmd = [
            "cargo", "clippy",
            "--all-targets",
            "--all-features",
            "--",  # Separator for clippy options
            "-D", "warnings",  # Treat warnings as errors
            "-W", "clippy::all",  # Enable all clippy lints
            "-W", "clippy::pedantic",  # Enable pedantic lints
            "-W", "clippy::nursery",  # Enable nursery lints (unstable)
        ]

        return self.run_command(cmd)

    def fix_clippy(self) -> LinterResult:
        """Try to fix clippy warnings automatically"""
        self.log("🔧 Attempting to fix clippy issues...", "INFO")

        # Some clippy lints can be auto-fixed
        cmd = [
            "cargo", "clippy",
            "--all-targets",
            "--all-features",
            "--fix",
            "--allow-dirty",
            "--allow-staged",
            "--",
            "-W", "clippy::all",
            "-W", "clippy::pedantic",
        ]

        return self.run_command(cmd)

    def check_cargo_check(self) -> LinterResult:
        """Run cargo check to verify compilation"""
        self.log("🔍 Running cargo check...", "INFO")
        cmd = ["cargo", "check", "--all-targets", "--all-features"]
        return self.run_command(cmd)

    def check_cargo_test(self) -> LinterResult:
        """Run cargo test to verify tests pass"""
        self.log("🔍 Running cargo test...", "INFO")
        cmd = ["cargo", "test", "--all-targets", "--all-features"]
        return self.run_command(cmd)

    def check_cargo_audit(self) -> LinterResult:
        """Run cargo audit to check for security vulnerabilities"""
        self.log("🔍 Running cargo audit...", "INFO")

        # Check if cargo-audit is installed
        try:
            subprocess.run(["cargo", "audit", "--version"], capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            self.log("⚠️  cargo-audit is not installed. Install with: cargo install cargo-audit", "WARNING")
            return LinterResult("cargo-audit check", True, "cargo-audit not installed", "", 0)

        cmd = ["cargo", "audit"]
        return self.run_command(cmd)

    def check_cargo_deny(self) -> LinterResult:
        """Run cargo deny to check for license and dependency issues"""
        self.log("🔍 Running cargo deny...", "INFO")

        # Check if cargo-deny is installed
        try:
            subprocess.run(["cargo", "deny", "--version"], capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            self.log("⚠️  cargo-deny is not installed. Install with: cargo install cargo-deny", "WARNING")
            return LinterResult("cargo-deny check", True, "cargo-deny not installed", "", 0)

        cmd = ["cargo", "deny", "check"]
        return self.run_command(cmd)

    def generate_report(self) -> Dict:
        """Generate a comprehensive report of all linting results"""
        total_checks = len(self.results)
        passed_checks = sum(1 for r in self.results if r.success)
        failed_checks = total_checks - passed_checks

        report = {
            "summary": {
                "total_checks": total_checks,
                "passed": passed_checks,
                "failed": failed_checks,
                "success_rate": f"{(passed_checks / total_checks * 100):.1f}%" if total_checks > 0 else "0%"
            },
            "results": []
        }

        for i, result in enumerate(self.results, 1):
            report["results"].append({
                "check": i,
                "command": result.command,
                "success": result.success,
                "exit_code": result.exit_code,
                "has_output": bool(result.output.strip()),
                "has_error": bool(result.error.strip())
            })

        return report

    def run_all_checks(self, fix: bool = False, check_only: bool = False) -> bool:
        """Run all linting checks"""
        self.log("🚀 Starting comprehensive Rust linting...", "INFO")

        # Check formatting
        if fix:
            self.results.append(self.fix_rustfmt())
        else:
            self.results.append(self.check_rustfmt())

        # Check clippy
        if fix:
            self.results.append(self.fix_clippy())
        else:
            self.results.append(self.check_clippy())

        # Always run cargo check
        self.results.append(self.check_cargo_check())

        # Run tests unless check-only mode
        if not check_only:
            self.results.append(self.check_cargo_test())

        # Run security checks
        self.results.append(self.check_cargo_audit())
        self.results.append(self.check_cargo_deny())

        # Generate and display report
        report = self.generate_report()
        self.display_report(report)

        # Return overall success status
        return all(r.success for r in self.results)

    def display_report(self, report: Dict):
        """Display a formatted report"""
        summary = report["summary"]

        print("\n" + "="*60)
        print("📊 LINTING SUMMARY REPORT")
        print("="*60)
        print(f"Total Checks: {summary['total_checks']}")
        print(f"Passed:       {summary['passed']}")
        print(f"Failed:       {summary['failed']}")
        print(f"Success Rate: {summary['success_rate']}")
        print("="*60)

        # Show details for failed checks
        failed_results = [r for r in self.results if not r.success]
        if failed_results:
            print("\n❌ FAILED CHECKS:")
            print("-"*40)
            for result in failed_results:
                print(f"\n🔍 Command: {result.command}")
                print(f"📤 Exit Code: {result.exit_code}")

                if result.error.strip():
                    print("📝 Error Output:")
                    print("─" * 20)
                    # Show first 10 lines of error
                    error_lines = result.error.strip().split('\n')[:10]
                    for line in error_lines:
                        print(f"   {line}")
                    if len(result.error.strip().split('\n')) > 10:
                        print("   ... (truncated)")

                if result.output.strip():
                    print("📄 Standard Output:")
                    print("─" * 20)
                    # Show first 5 lines of output
                    output_lines = result.output.strip().split('\n')[:5]
                    for line in output_lines:
                        print(f"   {line}")
                    if len(result.output.strip().split('\n')) > 5:
                        print("   ... (truncated)")

        # Show suggestions
        if failed_results:
            print("\n💡 SUGGESTIONS:")
            print("-"*40)
            print("🔧 Run with --fix to auto-fix some issues")
            print("📖 Check the specific error messages above")
            print("🔍 Use --verbose for more detailed output")
            print("📦 Ensure all dependencies are up to date: cargo update")

        print("\n" + "="*60)

def main():
    """Main function"""
    parser = argparse.ArgumentParser(
        description="Robust Rust Linter - Comprehensive code quality checks",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 run_linter.py                 # Run all checks
  python3 run_linter.py --fix           # Auto-fix issues when possible
  python3 run_linter.py --verbose       # Show detailed output
  python3 run_linter.py --check-only    # Skip tests, only check compilation
  python3 run_linter.py --no-color      # Disable colored output
        """
    )

    parser.add_argument(
        "--fix",
        action="store_true",
        help="Automatically fix issues when possible"
    )

    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Show detailed output"
    )

    parser.add_argument(
        "--check-only",
        action="store_true",
        help="Only run checks, don't build or test"
    )

    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable colored output"
    )

    parser.add_argument(
        "--project-path",
        default=".",
        help="Path to the Rust project (default: current directory)"
    )

    args = parser.parse_args()

    try:
        # Create linter instance
        linter = RustLinter(
            project_path=args.project_path,
            verbose=args.verbose,
            no_color=args.no_color
        )

        # Run all checks
        success = linter.run_all_checks(fix=args.fix, check_only=args.check_only)

        # Exit with appropriate code
        sys.exit(0 if success else 1)

    except Exception as e:
        print(f"💥 Fatal error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()