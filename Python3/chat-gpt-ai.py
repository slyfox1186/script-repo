#!/usr/bin/env python3

import os
import sys
import click
import openai
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Connect to API key
openai.api_key = os.getenv("OPENAI_API_KEY")

# AI Model Configuration Defaults
DEFAULT_AI_MODEL = "gpt-4-turbo"
BACKUP_AI_MODEL = "gpt-3.5-turbo-0125"
DEFAULT_MAX_TOKENS = 4096
DEFAULT_TEMPERATURE = 0.3 # Higher numbers are more creative responses up to a max of 1.0
DEFAULT_SCRIPT_PATH = ""

# Default user instructions
DEFAULT_USER_INSTRUCTIONS = """
Please optimize this python script so it uses the least amount of resources and over head available to perform its functions. However, do not remove any code other than to optimize the script so it runs as fast as possible.
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
      python script.py -p /path/to/script.py -M gpt-4 -t 0.2 -m 1200 -i "Optimize this script" -v -o output.txt
      python script.py --help
    """
    if verbose:
        logger.setLevel(logging.DEBUG)

    logger.info("Loading script content...")
    script_content = load_script(file_path)
    
    logger.info("Fetching AI suggestions...")
    optimization_suggestions = get_optimization_suggestion(script_content, instructions, model, max_tokens, temperature)
    
    if optimization_suggestions:
        logger.info("AI Optimization Suggestions:")
        logger.info(optimization_suggestions)
        if output_file:
            save_suggestions(optimization_suggestions, output_file)
    else:
        # Prompt user to try the backup AI model
        try_backup = click.prompt("The AI did not return any suggestions. Would you like to try the backup AI model (yes/no)?", type=str, default="no")
        if try_backup.lower() == "yes":
            logger.info("Trying backup AI model...")
            optimization_suggestions = get_optimization_suggestion(script_content, instructions, BACKUP_AI_MODEL, max_tokens, temperature)
            if optimization_suggestions:
                logger.info("AI Optimization Suggestions (Backup Model):")
                logger.info(optimization_suggestions)
            else:
                logger.warning("The backup AI model also did not return any suggestions.")
        else:
            logger.info("Exiting the script.")
            sys.exit(0)

def load_script(file_path):
    """ Load and return the content of a script file. """
    logger.debug(f"Checking file existence: {file_path}")
    if not os.path.isfile(file_path):
        logger.error(f"The file at '{file_path}' does not exist. Please provide a valid file path.")
        sys.exit(1)

    try:
        with open(file_path, 'r') as file:
            content = file.read()
            return content
    except Exception as e:
        logger.exception(f"An issue occurred while trying to read the file '{file_path}': {e}")
        sys.exit(1)

def get_optimization_suggestion(script_content, user_instructions, model, max_tokens, temperature):
    """ Ask the AI for optimization suggestions by combining script content and user instructions. """
    if not script_content:
        logger.error("No content from the script is available to analyze. Please ensure the script contains readable content.")
        sys.exit(1)

    try:
        # Prepare the message content by appending user instructions to script content
        message_content = script_content + "\n" + user_instructions
        logger.debug(f"Sending request to AI model: {model}")
        response = openai.ChatCompletion.create(
            model=model,
            messages=[{"role": "user", "content": message_content.strip()}],
            max_tokens=max_tokens,
            temperature=temperature
        )
        suggestion = response['choices'][0]['message']['content'].strip()
        return suggestion if suggestion else None
    except Exception as e:
        logger.exception(f"Failed to obtain optimization suggestions from the AI: {e}")
        return None

def save_suggestions(suggestions, output_file):
    """ Save the AI suggestions to a specified file. """
    try:
        with open(output_file, 'w') as f:
            f.write(suggestions)
            logger.debug(f"Suggestions saved to {output_file}")
    except Exception as e:
        logger.exception(f"Failed to save suggestions to {output_file}: {e}")

if __name__ == '__main__':
    main()
