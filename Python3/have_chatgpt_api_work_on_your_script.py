#!/usr/bin/env python3

"""Send a script's contents plus user instructions to OpenAI for analysis."""

import os
import sys
from pathlib import Path

import click
from openai import OpenAI, OpenAIError

DEFAULT_AI_MODEL = "gpt-4o"
BACKUP_AI_MODEL = "gpt-4-turbo"
DEFAULT_MAX_TOKENS = 4096
DEFAULT_TEMPERATURE = 0.5
DEFAULT_SCRIPT_PATH = "/path/to/script/for/analysis/file.{sh,py,pl,bat,whatever}"

DEFAULT_USER_INSTRUCTIONS = (
    "Please analyze the script above and suggest concrete, code-level "
    "improvements: bugs, performance issues, idiomatic refactors, and any "
    "missing edge-case handling. Reply with a short summary followed by "
    "specific change suggestions."
)


def load_script(path: Path, verbose: bool) -> str:
    if verbose:
        click.echo(f"Reading {path}")
    if not path.is_file():
        raise click.ClickException(f"File does not exist: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def get_optimization_suggestion(
    client: OpenAI,
    script_content: str,
    user_instructions: str,
    model: str,
    max_tokens: int,
    temperature: float,
    verbose: bool,
) -> str | None:
    if not script_content.strip():
        raise click.ClickException("The script file is empty.")

    message_content = f"{script_content}\n\n{user_instructions}".strip()
    if verbose:
        click.echo(f"Requesting completion from model: {model}")

    try:
        response = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": message_content}],
            max_tokens=max_tokens,
            temperature=temperature,
        )
    except OpenAIError as exc:
        click.echo(f"OpenAI API error: {exc}", err=True)
        return None

    suggestion = (response.choices[0].message.content or "").strip()
    return suggestion or None


@click.command()
@click.option("--path", "-p", "file_path", default=DEFAULT_SCRIPT_PATH,
              type=click.Path(path_type=Path), help="Path to the script for analysis.")
@click.option("--temperature", "-t", default=DEFAULT_TEMPERATURE, type=float,
              help="Sampling temperature.")
@click.option("--max-tokens", "-m", default=DEFAULT_MAX_TOKENS, type=int,
              help="Maximum response tokens.")
@click.option("--model", "-M", default=DEFAULT_AI_MODEL,
              help="Primary OpenAI model to use.")
@click.option("--instructions", "-i", default=DEFAULT_USER_INSTRUCTIONS,
              help="Instructions appended after the script content.")
@click.option("--verbose", "-v", is_flag=True, help="Verbose progress output.")
@click.option("--output-file", "-o", type=click.Path(path_type=Path),
              help="Optional file to save suggestions to.")
@click.help_option("--help", "-h")
def main(
    file_path: Path,
    temperature: float,
    max_tokens: int,
    model: str,
    instructions: str,
    verbose: bool,
    output_file: Path | None,
) -> None:
    """Send a script through OpenAI's chat completions API and print suggestions."""
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise click.ClickException("OPENAI_API_KEY is not set in the environment.")
    client = OpenAI(api_key=api_key)

    script_content = load_script(file_path, verbose)
    suggestions = get_optimization_suggestion(
        client, script_content, instructions, model, max_tokens, temperature, verbose
    )

    if not suggestions:
        if click.confirm(
            "Primary model returned nothing. Try the backup model?", default=False
        ):
            suggestions = get_optimization_suggestion(
                client,
                script_content,
                instructions,
                BACKUP_AI_MODEL,
                max_tokens,
                temperature,
                verbose,
            )
        if not suggestions:
            click.echo("No suggestions returned by either model.", err=True)
            sys.exit(1)

    click.echo("AI Optimization Suggestions:")
    click.echo(suggestions)
    if output_file:
        output_file.write_text(suggestions, encoding="utf-8")
        if verbose:
            click.echo(f"Suggestions saved to {output_file}")


if __name__ == "__main__":
    main()
