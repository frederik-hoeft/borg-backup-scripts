#!/usr/bin/env bash

# set bash options, fail on unset variables, and pipefail
set -uo pipefail

. "${BACKUP_SCRIPT_HOME}/borg-helpers.sh"
. "${BACKUP_SCRIPT_JOBS}/passbolt.secrets"
. "${BACKUP_SCRIPT_HOME}/modules/docker-helpers.sh"

require_borg_passphrase

container_name='passbolt'
container_root="${DOCKER_ROOT}/containers/${container_name}"
volume_root="${DOCKER_ROOT}/volumes/${container_name}"

restore_current() {
    docker_up "${container_name}" "${container_root}" || abort_current
}

docker_down "${container_name}" "${container_root}" || abort_current

info 'Starting backup'

export REPOSITORY_NAME="${container_name}"
capture foreach_backup_host /usr/bin/borg create    \
    --verbose                                       \
    --filter AME                                    \
    --list                                          \
    --stats                                         \
    --compression zlib                              \
    --exclude-caches                                \
                                                    \
    ::"${container_name}-{now}"                     \
    "${volume_root}" || {
        restore_current
        abort_current
    }

info 'Pruning repository'

capture foreach_backup_host /usr/bin/borg prune \
    --list                                      \
    --glob-archives "${container_name}-*"       \
    --show-rc                                   \
    --keep-daily    30                          \
    --keep-weekly   24                          \
    --keep-monthly  24 || {
        restore_current
        abort_current
    }

# actually free repo disk space by compacting segments
info 'Compacting repository'

capture foreach_backup_host /usr/bin/borg compact || {
    restore_current
    abort_current
}

restore_current
