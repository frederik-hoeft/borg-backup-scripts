#!/usr/bin/env bash

# set bash options, fail on unset variables, and pipefail
set -uo pipefail
shopt -s nullglob

declare -r service_name='smbd.service'
this_script_dir="$(/usr/bin/dirname "$(/usr/bin/realpath "${BASH_SOURCE[0]}")")"

. "${BACKUP_SCRIPT_HOME}/borg-helpers.sh" || exit 2
. "${BACKUP_SCRIPT_HOME}/modules/systemd-helpers.sh" || abort_current

restore_current() {
    unset_borg_passphrase
    service_up "${service_name}" || abort_current
}
require_smb_variables() {
    if [[ -z "${SMB_REPOSITORY_NAME:-}" || -z "${SMB_ROOT:-}" ]]; then
        error 'One or more required SMB variables are not set. Aborting.'
        restore_current
        abort_current
    fi
}

# iterate over all secrets files in smb-targets
secret_dir="${this_script_dir}/smb-targets"
secret_files=("${secret_dir}"/*.secrets)

# if no secrets files, warn and exit gracefully (nullglob set)
if [ ${#secret_files[@]} -eq 0 ]; then
    warn "No secrets files found in ${secret_dir}; nothing to back up."
    exit 0
fi

# stop service once before processing any targets
service_down "${service_name}" || abort_current

for secret_file in "${secret_files[@]}"; do
    [ -f "${secret_file}" ] || continue
    info "Processing SMB target secrets file: $(basename "${secret_file}")"
    # clear per-target variables to avoid bleed-over
    unset SMB_REPOSITORY_NAME SMB_ROOT REPOSITORY_NAME BORG_PASSPHRASE
    . "${secret_file}" || {
        restore_current
        abort_current
    }
    require_smb_variables
    require_borg_passphrase --soft-fail || {
        restore_current
        abort_current
    }

    # check if SMB_ROOT exists, skip if not
    if [ ! -d "${SMB_ROOT}" ]; then
        warn "SMB root directory '${SMB_ROOT}' does not exist; nothing to back up. Skipping."
        continue
    fi

    info 'Starting backup'

    export REPOSITORY_NAME="${SMB_REPOSITORY_NAME}"
    foreach_backup_host --capture=yes /usr/bin/borg create \
        --show-rc                                          \
        --stats                                            \
        --compression zlib                                 \
        --exclude-caches                                   \
                                                           \
        ::"${SMB_REPOSITORY_NAME}-{now}"                 \
        "${SMB_ROOT}" || {
            restore_current
            abort_current
        }

    info 'Pruning repository'

    foreach_backup_host --capture=yes /usr/bin/borg prune \
        --list                                             \
        --glob-archives "${SMB_REPOSITORY_NAME}-*"        \
        --show-rc                                          \
        --keep-daily    30                                 \
        --keep-weekly   24                                 \
        --keep-monthly  24 || {
            restore_current
            abort_current
        }

    info 'Compacting repository'

    foreach_backup_host --capture=yes /usr/bin/borg compact --show-rc || {
        restore_current
        abort_current
    }
done

# bring service back up after all targets processed
restore_current