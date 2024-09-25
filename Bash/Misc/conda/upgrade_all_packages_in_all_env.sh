#!/usr/bin/env bash

# Get a list of all conda environments
env_list=$(conda env list | grep -E '^[^#].*/envs/' | awk '{print $1}')

# Loop through each environment
for env in $env_list; do
    printf "%s\n\n" "Upgrading packages in environment: $env"
    
    # Upgrade all packages in the current environment without activating it
    conda update --name "$env" --all -y
    
    echo "Finished upgrading packages in environment: $env"
done

printf "\n%s\n" "All packages in all environments have been upgraded."
