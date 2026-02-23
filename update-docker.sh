#!/bin/bash

cd "$(dirname "$0")"

dockerBin=$(/usr/bin/which docker)

# Pull and build new images
$dockerBin compose pull
$dockerBin compose build --force-rm --pull

# Migrate existing .env to .env + .env.app if .env.app does not exist yet.
# This must happen before "docker compose up" since docker-compose.yml requires
# .env.app to exist via the env_file directive.
if [ ! -f ".env.app" ]; then
    if grep -q "^# FewohBee Settings" .env 2>/dev/null; then
        echo "Migrating FewohBee settings from .env to .env.app ..."
        sed -n '/^# FewohBee Settings/,$p' .env > .env.app
        chmod 0600 .env.app
        echo "Created .env.app from .env."
        echo "Please review .env.app and remove the FewohBee Settings section from .env manually."
    else
        echo "Warning: .env.app does not exist and no migration source found in .env."
        echo "Please create .env.app from .env.app.dist manually."
        exit 1
    fi
fi

# Start containers. The php entrypoint will clone/update fewohbee via git.
$dockerBin compose stop
$dockerBin compose up --force-recreate -d

# Wait for fewohbee to finish setup (git clone/pull + composer + migrations)
echo "Waiting for fewohbee to finish setup ..."
until [ "$($dockerBin compose exec -T php /bin/sh -c 'cat /firstrun' 2>/dev/null)" == "1" ]; do
    echo "  still waiting ..."
    sleep 10
done

# Sync new environment variables from the now-running container into .env.app
echo "Checking for new environment variables ..."
containerEnvDist=$($dockerBin compose exec --user www-data -T php /bin/sh -c "cat fewohbee/.env.dist" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$containerEnvDist" ]; then
    echo "Warning: Could not read .env.dist from container. Skipping env sync."
else
    addedVars=0
    commentBuffer=""

    while IFS= read -r line; do
        # Accumulate comments and empty lines to carry them along with their variable
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
            [ -n "$commentBuffer" ] && commentBuffer+=$'\n'
            commentBuffer+="$line"
            continue
        fi

        # Extract variable name (everything before the first =)
        varName="${line%%=*}"
        if [[ -z "$varName" ]]; then
            commentBuffer=""
            continue
        fi

        # DB_SERVER_VERSION is hardcoded in docker-compose.yml, skip it
        if [[ "$varName" == "DB_SERVER_VERSION" ]]; then
            commentBuffer=""
            continue
        fi

        # Add if not already present in .env.app
        if ! grep -q "^${varName}=" .env.app; then
            if [ $addedVars -eq 0 ]; then
                printf "\n# Variables added by update-docker.sh on %s\n" "$(date '+%Y-%m-%d')" >> .env.app
            fi
            # Write accumulated comments first, then the variable
            if [ -n "$commentBuffer" ]; then
                printf "\n%s\n" "$commentBuffer" >> .env.app
            fi
            printf "%s\n" "$line" >> .env.app
            echo "  Added: $varName"
            addedVars=$((addedVars + 1))
        fi

        # Reset comment buffer after each variable (whether added or already present)
        commentBuffer=""
    done <<< "$containerEnvDist"

    if [ $addedVars -gt 0 ]; then
        echo "$addedVars new variable(s) added to .env.app."
        echo "Please review the new variables and adjust values if needed."
        echo "Restarting php and cron containers to apply new environment variables ..."
        $dockerBin compose up --force-recreate -d php cron
    else
        echo "No new environment variables found."
    fi
fi

docker image prune -f
