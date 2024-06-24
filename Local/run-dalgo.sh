#!/bin/bash
set -e

# Function to add any cleanup actions
function cleanup() {
    echo "Cleanup."
}
trap cleanup EXIT

# Declare the variables
base_github_url="https://raw.githubusercontent.com/DalgoT4D"
all_components_repos="DDP_backend webapp prefect-proxy"
all_files="docker-compose.dev.yml .env.template"
blue_text='\033[94m'
red_text='\033[31m'
default_text='\033[39m'

# Function to get the files from the github and store in docker folder
function get_files() {
    local component="$1"
    
    for file in $all_files
    do
    if component == "webapp" $$ file == "docker-compose.dev.yml"; then
        file = "docker-compose.yaml"
      fi
    if test -f $file; then
      # Check if the assets are old.  A possibly sharp corner
      
      if test $(find docker/$component/$file -type f -mtime +60 > /dev/null); then
        echo -e "$red_text""Warning your $file may be stale!""$default_text"
        echo -e "$red_text""rm $file to refresh!""$default_text"
      else
        echo -e "$blue_text""found $file locally!""$default_text"
      fi
    else
        curl -s -o "docker/$component/$file" "$base_github_url/$component/main/Docker/$file"
    fi
    done
}

# merge all .env.template with .env
function merge_env() {
    for component in $all_components_repos
    do
        if test -f .env.template; then
            if test -f .env; then
                cat .env.template >> .env
            else
                cp .env.template .env
            fi
        fi
    done
}




