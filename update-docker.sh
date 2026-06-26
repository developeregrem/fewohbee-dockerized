#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

dockerBin=$(command -v docker)
cronMode=false

if [ "${1:-}" == "--cron" ]; then
    cronMode=true
fi

syncEnvFromDist() {
    local addedVars
    local commentBuffer
    local line
    local varName

    if [ ! -f .env.dist ]; then
        echo "Warning: .env.dist not found. Skipping env sync."
        return
    fi

    if [ ! -f .env ]; then
        echo "Warning: .env not found. Skipping env sync."
        return
    fi

    echo "Checking for new environment variables ..."

    addedVars=0
    commentBuffer=""

    while IFS= read -r line || [ -n "$line" ]; do
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

        # Some variables are intentionally NOT synced into dockerized .env:
        #   DB_SERVER_VERSION - pinned in docker-compose.yml
        #   APP_ENV / APP_DEBUG / USE_REDIS_CACHE - baked into the image
        #     (choice via FEWOHBEE_VERSION tag prod vs -debug); syncing them
        #     would let users accidentally override the image identity and
        #     mismatch cache/vendor configuration.
        case "$varName" in
            DB_SERVER_VERSION|APP_ENV|APP_DEBUG|USE_REDIS_CACHE)
                commentBuffer=""
                continue
                ;;
        esac

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

            echo "  Added: $varName"
            addedVars=$((addedVars + 1))
        fi

        # Reset comment buffer after each variable (whether added or already present)
        commentBuffer=""
    done < .env.dist

    if [ $addedVars -gt 0 ]; then
        echo "$addedVars new variable(s) added to .env."
        echo "Please review the new variables in .env and adjust values if needed."
    else
        echo "No new environment variables found."
    fi
}

# Pull latest changes to docker-compose.yml and configuration files (manual only)
if [ "$cronMode" = false ]; then
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "Update aborted: local changes in tracked files would make git pull unsafe."
        echo "Please commit, stash, or revert these changes before running update-docker.sh again."
        git status --short --untracked-files=no
        exit 1
    fi

    oldHead=$(git rev-parse HEAD)
    if ! git pull --ff-only; then
        echo "Update aborted: could not fast-forward the repository."
        echo "Please resolve local repository state manually before running update-docker.sh again."
        exit 1
    fi
    newHead=$(git rev-parse HEAD)

    if ! git diff --quiet "$oldHead" "$newHead" -- update-docker.sh; then
        echo "update-docker.sh was updated. Restarting with the new script ..."
        exec "$BASH" "$0" "$@"
    fi
fi

# Legacy .env cleanup: APP_ENV is baked into the selected image tag in the
# dockerized setup and should no longer be overridden from .env.
if [ -f .env ] && grep -q "^APP_ENV=redis" .env; then
    echo "Removing legacy APP_ENV=redis from .env ..."
    sed -i.bak '/^APP_ENV=redis$/d' .env
    rm -f .env.bak
fi

if [ "$cronMode" = false ]; then
    syncEnvFromDist
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
        health=$($dockerBin compose ps --format '{{.Service}} {{.Health}}' 2>/dev/null | awk '$1 == "php" { print $2; exit }' || true)
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
fi

$dockerBin image prune -f
