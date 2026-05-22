#!/bin/bash

cd "$(dirname "$0")"

dockerBin=$(/usr/bin/which docker)
cronMode=false

if [ "$1" == "--cron" ]; then
    cronMode=true
fi

# Pull latest changes to docker-compose.yml and configuration files (manual only)
if [ "$cronMode" = false ]; then
    git pull
fi

# Legacy .env migration: APP_ENV=redis is deprecated, the new convention is
# APP_ENV=prod + USE_REDIS_CACHE=true. The image entrypoint still tolerates
# the old value (with a deprecation warning), but we clean up .env here so
# future updates and tooling see the canonical form.
if [ -f .env ] && grep -q "^APP_ENV=redis" .env; then
    echo "Migrating legacy APP_ENV=redis in .env -> APP_ENV=prod + USE_REDIS_CACHE=true ..."
    sed -i.bak 's/^APP_ENV=redis/APP_ENV=prod/' .env
    if ! grep -q "^USE_REDIS_CACHE=" .env; then
        echo "USE_REDIS_CACHE=true" >> .env
    fi
    rm -f .env.bak
fi

# Pull new images
$dockerBin compose pull

# Start containers. The uploads-migration init container runs first and
# (idempotently) copies legacy feb-data uploads into the new volumes before
# php starts. The php entrypoint then runs Doctrine migrations.
$dockerBin compose stop
$dockerBin compose up --force-recreate -d

if [ "$cronMode" = false ]; then
    # Wait for the php container to become healthy.
    echo "Waiting for fewohbee to be ready ..."
    waited=0
    while true; do
        health=$($dockerBin compose ps --format '{{.Service}} {{.Health}}' 2>/dev/null | grep '^php ' | awk '{print $2}')
        if [ "$health" = "healthy" ]; then
            break
        fi
        if [ $waited -ge 180 ]; then
            echo "Warning: php container did not become healthy within 180s. Continuing anyway."
            break
        fi
        echo "  still waiting ... (${waited}s)"
        sleep 5
        waited=$((waited + 5))
    done

    # Sync new environment variables from the now-running container into .env (manual only)
    echo "Checking for new environment variables ..."
    containerEnvDist=$($dockerBin compose exec --user www-data -T php /bin/sh -c "cat .env.dist" 2>/dev/null)

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
                    if [ -f "$composeFile" ] && grep -q "# new-vars-marker" "$composeFile" \
                        && ! grep -q -- "- ${varName}=" "$composeFile"; then
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
fi

$dockerBin image prune -f
