#!/usr/bin/env bash

# set bash options, fail on unset variables, and pipefail
set -uo pipefail

. "${BACKUP_SCRIPT_HOME}/borg-helpers.sh"
. "${BACKUP_SCRIPT_JOBS}/seafile.secrets"
. "${BACKUP_SCRIPT_HOME}/modules/docker-helpers.sh"

require_borg_passphrase

container_name='seafile'
container_root="${DOCKER_ROOT}/containers/${container_name}"
volume_root="${DOCKER_ROOT}/volumes/${container_name}"

docker_down "${container_name}" "${container_root}" || abort_current

info 'Starting backup'

export REPOSITORY_NAME="${container_name}"
capture foreach_backup_host /usr/bin/borg create    \
    --verbose                                       \
    --filter AME                                    \
    --list                                          \
    --stats                                         \
    --compression lz4                               \
    --exclude-caches                                \
    --exclude '*/logs/*'                            \
    --exclude '*/seafile-data/httptmp/*'            \
    --exclude '*/seafile-data/tmpfiles/*'           \
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
    --keep-daily    7                           \
    --keep-weekly   4                           \
    --keep-monthly  6 || {
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

restore_current() {
    docker_up "${container_name}" "${container_root}" || abort_current
}