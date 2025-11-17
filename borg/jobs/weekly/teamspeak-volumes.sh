#!/usr/bin/env bash

# set bash options, fail on unset variables, and pipefail
set -uo pipefail

this_script_dir="$(/usr/bin/realpath "$(/usr/bin/dirname "${BASH_SOURCE[0]}")")"
. "${BACKUP_SCRIPT_HOME}/borg-helpers.sh" || exit 2
. "${this_script_dir}/teamspeak.secrets" || abort_current
. "${BACKUP_SCRIPT_HOME}/modules/docker-helpers.sh" || abort_current

require_borg_passphrase

container_name='teamspeak'
container_root="${DOCKER_ROOT}/containers/${container_name}"
volume_root="${DOCKER_ROOT}/volumes/${container_name}"

restore_current() {
    docker_up "${container_name}" "${container_root}" || abort_current
}

docker_down "${container_name}" "${container_root}" || abort_current

info 'Starting backup'

export REPOSITORY_NAME="${container_name}"
foreach_backup_host /usr/bin/borg create        \
    --verbose                                   \
    --filter AME                                \
    --list                                      \
    --stats                                     \
    --compression lz4                           \
    --exclude-caches                            \
    --exclude '*teamspeak/logs/*'               \
                                                \
    ::"${container_name}-{now}"                 \
    "${volume_root}" || {
        restore_current
        abort_current
    }

info 'Pruning repository'

foreach_backup_host /usr/bin/borg prune         \
    --list                                      \
    --glob-archives "${container_name}-*"       \
    --show-rc                                   \
    --keep-weekly   7                           \
    --keep-monthly  12 || {
        restore_current
        abort_current
    }

# actually free repo disk space by compacting segments
info 'Compacting repository'

foreach_backup_host /usr/bin/borg compact || {
    restore_current
    abort_current
}

restore_current
