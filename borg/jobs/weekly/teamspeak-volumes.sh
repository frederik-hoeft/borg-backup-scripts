#!/usr/bin/env bash

# set bash options, fail on unset variables, and pipefail
set -uo pipefail

restore_current() {
    info "Attempting to restore '${container_name}' docker container..."
    capture /usr/bin/su -c "/usr/bin/docker compose -f ${container_root}/docker-compose.yml up -d" "${DOCKER_USER}" || abort_current
    info "Successfully restored '${container_name}' docker container"
}

. "${BACKUP_SCRIPT_HOME}/borg.helpers"
. "${BACKUP_SCRIPT_JOBS}/teamspeak.secrets"

container_name='teamspeak'
container_root="${DOCKER_ROOT}/containers/${container_name}"
volume_root="${DOCKER_ROOT}/volumes/${container_name}"

# verify required variables are set
if [ -z "${BORG_PASSPHRASE}" ]; then
    error 'required variable BORG_PASSPHRASE is not set'
    abort_current
fi

info "Attempting to stop '${container_name}' docker container..."

# bring down container
capture /usr/bin/su -c "/usr/bin/docker compose -f ${container_root}/docker-compose.yml down" "${DOCKER_USER}" || abort_current

info "Starting backup"

export REPOSITORY_NAME="${container_name}"
capture foreach_backup_host /usr/bin/borg create    \
    --verbose                                       \
    --filter AME                                    \
    --list                                          \
    --stats                                         \
    --compression lz4                               \
    --exclude-caches                                \
    --exclude '*teamspeak/logs/*'                   \
                                                    \
    ::"${container_name}-{now}"                     \
    ${volume_root} || {
        restore_current
        abort_current
    }

info "Pruning repository"

capture foreach_backup_host /usr/bin/borg prune \
    --list                                      \
    --glob-archives "${container_name}-*"       \
    --show-rc                                   \
    --keep-weekly   7                           \
    --keep-monthly  12 || {
        restore_current
        abort_current
    }

# actually free repo disk space by compacting segments
info "Compacting repository"

capture foreach_backup_host /usr/bin/borg compact || {
    restore_current
    abort_current
}

info "Running 'docker compose up -d' on '${container_name}'..."

# restart container
restore_current