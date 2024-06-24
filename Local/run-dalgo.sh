#!/bin/bash
set -e

# Function to add any cleanup actions
function cleanup() {
    echo "Cleanup."
}
trap cleanup EXIT

# Declare the variables
base_github_url="https://raw.githubusercontent.com/DalgoT4D"
all_components_repos="webapp"  #"DDP_backend webapp prefect-proxy"
all_files="docker-compose.dev.yml .env.template"
blue_text='\033[94m'
red_text='\033[31m'
default_text='\033[39m'
PROJECT_NAME="dalgo"

# Function to get the files from the github and store in docker folder
function get_files() {
    local component="$1"
    local file_url=""
    echo -e "$blue_text""Getting files for $component""$default_text"
    for file in $all_files
    do
    
    if test -e Docker/$component/$file; then
      # Check if the assets are old.  A possibly sharp corner
      echo -e "$blue_text""Checking if $file is stale""$default_text"
      # Check if folder exists and cretate it if it does not
        if [ ! -d Docker/$component ]; then
            mkdir -p Docker/$component
        fi
        if test $(find Docker/$component -type f -name $file -mtime +60 > /dev/null); then
            echo -e "$red_text""Warning your $file may be stale!""$default_text"
            echo -e "$red_text""rm $file to refresh!""$default_text"
        else
            echo -e "$blue_text""found $file locally!""$default_text"
        fi
    else
        echo -e "$blue_text""Downloading $file""$default_text"
        if [ ! -d Docker/$component ]; then
            mkdir -p Docker/$component
        fi
        if [ $component == "webapp" ] && [ $file == "docker-compose.dev.yml" ]; then
            file_temp="docker-compose.yaml"
            file_url="$base_github_url/$component/main/Docker/$file_temp"
        else
            file_url="$base_github_url/$component/main/Docker/$file"
        fi
        # check if file exists in the github
        if [ $file == ".env.template" ]; then
            if [ $component == "webapp" ]; then
                file_temp=".env.example"
            else
                file_temp=$file
            fi
            file_url="$base_github_url/$component/main/$file_temp"
        fi
        echo -e "$blue_text""Checking if $file exists in $file_url""$default_text"
        http_status=$(curl -o /dev/null --silent --head --write-out '%{http_code}' "$file_url")
        if [ "$http_status" -eq 200 ]; then
            curl -L -s -o Docker/$component/$file $file_url
            echo -e "$blue_text""Downloaded $file""$default_text"
        else
            echo -e "$red_text""Failed to download $file. File does not exist""$default_text"
            exit 1;
        fi
        
    fi
    done
}

# merge all .env.template with .env
function merge_env() {
    for component in $all_components_repos
    do
        if test -f Docker/$component/.env.template; then
            if test -f Docker/.env; then
                cat Docker/$component/.env.template >> Docker/.env
            else
                cp Docker/$component/.env.template Docker/.env
            fi
        fi
    done
}

# Run docker compose
function run_docker_compose() {
    # Check if the docker-compose.yaml for each component exists
    # aggregate all the docker-compose.yaml files
    dockerfiles=""
    for component in $all_components_repos
    do
        if test -f docker/$component/docker-compose.dev.yml; then
            echo -e "$blue_text""Appending docker compose for $component""$default_text"
            dockerfiles+="$dockerfiles -f Docker/$component/docker-compose.dev.yml"
        else
            echo -e "$red_text""Docker/$component/docker-compose.dev.yml does not exist!""$default_text"
            exit 1;
        fi
    done
    set -a
    source Docker/.env
    set +a
    echo -e "$blue_text""Running docker compose for $dockerfiles""$default_text"
    echo -e "$blue_text""docker-compose ${dockerfiles}up""$default_text"
    eval "docker-compose $dockerfiles up"
}

# stop the docker containers
function stop() {
    echo "Stopping the docker containers"
    dockerfiles=""
    for component in $all_components_repos
    do
        if test -f docker/$component/docker-compose.dev.yml; then
            echo -e "$blue_text""Appending docker compose for $component""$default_text"
            dockerfiles+="$dockerfiles -f Docker/$component/docker-compose.dev.yml"
        else
            echo -e "$red_text""Docker/$component/docker-compose.dev.yml does not exist!""$default_text"
            exit 1;
        fi
    done
    eval "docker-compose $dockerfiles down"
}

# Combine all the functions
function start() {
    for component in $all_components_repos
    do
        get_files $component
    done
    merge_env
    run_docker_compose
}

arg="$1"
case $arg in
    start)
        start
        ;;
 
    stop)
        echo "Stopping the docker containers"
        stop
        ;;
       *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac

