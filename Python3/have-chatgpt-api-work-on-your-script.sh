#!/usr/bin/env python3

import os
import sys
import click
import openai

# Connect to API key
openai.api_key = os.getenv("OPENAI_API_KEY")

# AI Model Configuration Defaults
DEFAULT_AI_MODEL = "gpt-4-turbo"
BACKUP_AI_MODEL = "gpt-3.5-turbo"  # Backup AI model
DEFAULT_MAX_TOKENS = 4096
DEFAULT_TEMPERATURE = 0.5
DEFAULT_SCRIPT_PATH = "/path/to/script/for/analysis/script.{sh,py,pl,bat,whatever}"

# Default user instructions
DEFAULT_USER_INSTRUCTIONS = """
HI AI AREN'T YOU PRETTY SHNEAT.
DO LIKE ME?
I LIKE YOU SOOOOO SCHWELL
WILL YOU DO MY WORK FOR ME BY MAKING THE ATTACHED SCRIPT SUPER GOOD TIME?
OK GIRL, JUS LET ME KNOW WHAT YA BOY CAN PROVIDE YOU AND WE WILL ROCK THIS JOINT.
"""

@click.command()
@click.option('--path', '-p', 'file_path', default=DEFAULT_SCRIPT_PATH, help='Path to the script for optimization.')
@click.option('--temperature', '-t', default=DEFAULT_TEMPERATURE, help='Set the creativity level of the AI.', type=float)
@click.option('--max-tokens', '-m', default=DEFAULT_MAX_TOKENS, help='Maximum number of tokens for the AI response.', type=int)
@click.option('--model', '-M', default=DEFAULT_AI_MODEL, help='The AI model to use for generating suggestions.')
@click.option('--instructions', '-i', default=DEFAULT_USER_INSTRUCTIONS, help='Specific instructions for the AI.', show_default=False, prompt=True)
@click.option('--verbose', '-v', is_flag=True, help='Enable verbose output for detailed logging.')
@click.option('--output-file', '-o', help='Save the AI suggestions to a specified file.')
@click.help_option('--help', '-h')
def main(file_path, temperature, max_tokens, model, instructions, verbose, output_file):
    """This script enhances script optimization by interfacing with OpenAI's GPT model.
    It allows customization of the AI's behavior and uses user-provided instructions to tailor the AI's analysis.

    Examples:
      python script.py -p /path/to/script.py -M gpt-4-turbo -t 0.2 -m 1200 -i "Optimize this script" -v -o output.txt
      python script.py --help
    """
    if verbose:
        print("Loading script content...")
    script_content = load_script(file_path, verbose)
    
    if verbose:
        print("Fetching AI suggestions...")
    optimization_suggestions = get_optimization_suggestion(script_content, instructions, model, max_tokens, temperature, verbose)
    
    if optimization_suggestions:
        print("AI Optimization Suggestions:")
        print(optimization_suggestions)
        if output_file:
            with open(output_file, 'w') as f:
                f.write(optimization_suggestions)
                if verbose:
                    print(f"Suggestions saved to {output_file}")
    else:
        # Prompt user to try the backup AI model
        try_backup = click.prompt("The AI did not return any suggestions. Would you like to try the backup AI model (yes/no)?", type=str, default="no")
        if try_backup.lower() == "yes":
            optimization_suggestions = get_optimization_suggestion(script_content, instructions, BACKUP_AI_MODEL, max_tokens, temperature, verbose)
            if optimization_suggestions:
                print("AI Optimization Suggestions (Backup Model):")
                print(optimization_suggestions)
            else:
                print("Warning: The backup AI model also did not return any suggestions.")
        else:
            print("Exiting the script.")
            sys.exit(1)

def load_script(file_path, verbose):
    """ Load and return the content of a script file. """
    if verbose:
        print(f"Checking file existence: {file_path}")
    if not os.path.isfile(file_path):
        print(f"Error: The file at '{file_path}' does not exist. Please provide a valid file path.")
        sys.exit(1)

    try:
        with open(file_path, 'r') as file:
            content = file.readlines()
            return ''.join(content)
    except Exception as e:
        print(f"Error: An issue occurred while trying to read the file '{file_path}': {e}")
        sys.exit(1)

def get_optimization_suggestion(script_content, user_instructions, model, max_tokens, temperature, verbose):
    """ Ask the AI for optimization suggestions by combining script content and user instructions. """
    if not script_content:
        print("Error: No content from the script is available to analyze. Please ensure the script contains readable content.")
        sys.exit(1)

    try:
        # Prepare the message content by appending user instructions to script content
        message_content = script_content + "\n" + user_instructions
        if verbose:
            print(f"Sending request to AI model: {model}")
        response = openai.ChatCompletion.create(
            model=model,
            messages=[{"role": "user", "content": message_content.strip()}],
            max_tokens=max_tokens,
            temperature=temperature
        )
        suggestion = response['choices'][0]['message']['content'].strip()
        return suggestion if suggestion else None
    except Exception as e:
        print(f"Error: Failed to obtain optimization suggestions from the AI: {e}")
        return None

if __name__ == '__main__':
    main()
