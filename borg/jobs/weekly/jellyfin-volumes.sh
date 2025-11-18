#!/usr/bin/env bash

# set bash options, fail on unset variables, and pipefail
set -uo pipefail

this_script_dir="$(/usr/bin/dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"
. "${BACKUP_SCRIPT_HOME}/borg-helpers.sh" || exit 2
. "${this_script_dir}/jellyfin.secrets" || abort_current
. "${BACKUP_SCRIPT_HOME}/modules/docker-helpers.sh" || abort_current

require_borg_passphrase

container_name='jellyfin'
container_root="${DOCKER_ROOT}/containers/${container_name}"
volume_root="${DOCKER_ROOT}/volumes/${container_name}"

restore_current() {
    docker_up "${container_name}" "${container_root}" || abort_current
}

docker_down "${container_name}" "${container_root}" || abort_current

info 'Starting backup'

export REPOSITORY_NAME="${container_name}"
foreach_backup_host --capture=yes /usr/bin/borg create  \
    --show-rc                                           \
    --filter AME                                        \
    --stats                                             \
    --compression lz4                                   \
    --exclude-caches                                    \
    --exclude '*/logs/*'                                \
    --exclude '*/log/*'                                 \
    --exclude '*/temp/*'                                \
                                                        \
    ::"${container_name}-{now}"                         \
    "${volume_root}" || {
        restore_current
        abort_current
    }

info 'Pruning repository'

foreach_backup_host --capture=yes /usr/bin/borg prune   \
    --list                                              \
    --glob-archives "${container_name}-*"               \
    --show-rc                                           \
    --keep-weekly   12                                  \
    --keep-monthly  12 || {
        restore_current
        abort_current
    }

# actually free repo disk space by compacting segments
info 'Compacting repository'

foreach_backup_host --capture=yes /usr/bin/borg compact --show-rc || {
    restore_current
    abort_current
}

restore_current
