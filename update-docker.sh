#!/bin/bash

cd "$(dirname "$0")"

dockerBin=$(/usr/bin/which docker)

# Pull latest changes to docker-compose.yml and configuration files
#git pull

# Pull and build new images
$dockerBin compose pull
$dockerBin compose build --force-rm --pull

# Start containers. The php entrypoint will clone/update fewohbee via git.
$dockerBin compose stop
$dockerBin compose up --force-recreate -d

# Wait for fewohbee to finish setup (git clone/pull + composer + migrations)
echo "Waiting for fewohbee to finish setup ..."
until [ "$($dockerBin compose exec -T php /bin/sh -c 'cat /firstrun' 2>/dev/null)" == "1" ]; do
    echo "  still waiting ..."
    sleep 10
done

# Sync new environment variables from the now-running container into .env
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

        # Add if not already present in .env
        if ! grep -q "^${varName}=" .env; then
            if [ $addedVars -eq 0 ]; then
                printf "\n# Variables added by update-docker.sh on %s\n" "$(date '+%Y-%m-%d')" >> .env
            fi
            # Write accumulated comments first, then the variable
            if [ -n "$commentBuffer" ]; then
                printf "\n%s\n" "$commentBuffer" >> .env
            fi
            printf "%s\n" "$line" >> .env

            # Also add the variable to the environment: sections in both compose files
            # (inserted before the # new-vars-marker comment, which appears in php and cron services)
            for composeFile in docker-compose.yml docker-compose.no-ssl.yml; do
                if [ -f "$composeFile" ] && grep -q "# new-vars-marker" "$composeFile"; then
                    tmpfile=$(mktemp)
                    awk -v varline="            - ${varName}=\${${varName}}" \
                        '/# new-vars-marker/ { print varline } { print }' \
                        "$composeFile" > "$tmpfile" && mv "$tmpfile" "$composeFile"
                fi
            done

            echo "  Added: $varName"
            addedVars=$((addedVars + 1))
        fi

        # Reset comment buffer after each variable (whether added or already present)
        commentBuffer=""
    done <<< "$containerEnvDist"

    if [ $addedVars -gt 0 ]; then
        echo "$addedVars new variable(s) added to .env and docker-compose.yml / docker-compose.no-ssl.yml."
        echo "Please review the new variables in .env and adjust values if needed."
        echo "Restarting php and cron containers to apply new environment variables ..."
        $dockerBin compose up --force-recreate -d php cron
    else
        echo "No new environment variables found."
    fi
fi

docker image prune -f
