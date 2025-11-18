#!/usr/bin/env bash

# set bash options, fail on unset variables, and pipefail
set -uo pipefail

this_script_dir="$(/usr/bin/dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"
. "${BACKUP_SCRIPT_HOME}/borg-helpers.sh" || exit 2
. "${this_script_dir}/passbolt.secrets" || abort_current
. "${BACKUP_SCRIPT_HOME}/modules/docker-helpers.sh" || abort_current

require_borg_passphrase

container_name='passbolt'
container_root="${DOCKER_ROOT}/containers/${container_name}"
volume_root="${DOCKER_ROOT}/volumes/${container_name}"

restore_current() {
    unset_borg_passphrase
    docker_up "${container_name}" "${container_root}" || abort_current
}

docker_down "${container_name}" "${container_root}" || abort_current

info 'Starting backup'

export REPOSITORY_NAME="${container_name}"
foreach_backup_host --capture=yes /usr/bin/borg create  \
    --show-rc                                           \
    --stats                                             \
    --compression zlib                                  \
    --exclude-caches                                    \
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
    --keep-daily    30                                  \
    --keep-weekly   24                                  \
    --keep-monthly  48 || {
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
