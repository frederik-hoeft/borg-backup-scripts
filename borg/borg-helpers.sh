falsish=('No' 'NO' 'no' 'N' 'n' '0')
truish=('Yes' 'YES' 'yes' 'Y' 'y' '1')

# formats a message into a log entry
# parameters:
#   $1: log level
#   $2: message
# returns:
#   formatted log message
create_log_entry() {
    local message="${1}: $(date) ${2}"
    echo "${message}"
}

# writes a message to the log file and, if verbose, to stdout
# parameters:
#   $1: log level
#   $2: message
write_log() {
    local message=$(create_log_entry "${1}" "${2}")
    echo "${message}" | tee -a "${BACKUP_LOG_FILE}" >> "${BACKUP_LOG_FILE_TEMP}"
    # if verbose, write to stdout, always write errors
    if [ -n "${BACKUP_LOG_VERBOSE}" ] || [ "${1}" = 'ERROR' ]; then
        echo "${message}"
    fi
}

# write an info message to the log
# parameters:
#   $*: message
info() {
    write_log 'INFO' "$*"
}

# write a warning message to the log
# parameters:
#   $*: message
warn() { 
    write_log 'WARN' "$*"
}

# write an error message to the log and to stdout
# parameters:
#   $*: message
error() { 
    write_log 'ERROR' "$*"
}

# exit the current backup script only, allowing the next script to run
# parameters: None
# returns: exits with code 1
abort_current() {
    local message=$(create_log_entry 'ABORT' "aborting current backup script due to script failure in ${BASH_SOURCE[1]}")
    echo "${message}" | /usr/bin/tee -a "${BACKUP_LOG_FILE}"
    exit 1
}

# exit the current backup script and stop the backup process
# parameters: None
# returns: exits with code 2
abort_all() {
    local message=$(create_log_entry 'ABORT' "aborting all backups immediately due to script failure in ${BASH_SOURCE[1]}")
    echo "${message}" | /usr/bin/tee -a "${BACKUP_LOG_FILE}"
    exit 2
}

# ensure that BORG_PASSPHRASE is set, otherwise abort current script
# parameters: None
# returns: exits with code 1 if BORG_PASSPHRASE is not set
require_borg_passphrase() {
    if [ -z "${BORG_PASSPHRASE:-}" ]; then
        error 'required variable BORG_PASSPHRASE is not set'
        abort_current
    fi
}

# shutdown any backup hosts that were woken up for the backup
# parameters: None
borg_cleanup() {
    if [ -z "${BACKUP_WOL_STATE_DIR}" ]; then
        warn "BACKUP_WOL_STATE_DIR not set, skipping cleanup"
        return 0
    fi
    
    if [ ! -d "${BACKUP_WOL_STATE_DIR}" ]; then
        warn "WOL state directory '${BACKUP_WOL_STATE_DIR}' not found, skipping cleanup"
        return 0
    fi
    
    # iterate through all wol-state files and shutdown hosts that were woken up
    for wol_state_file in "${BACKUP_WOL_STATE_DIR}"/*.wol-state; do
        # skip if no files match the pattern
        [ -f "${wol_state_file}" ] || continue
        
        # extract hostname from filename
        local hostname
        hostname=$(basename "${wol_state_file}" .wol-state)
        
        # read the WOL state
        local wol_state
        if [ -f "${wol_state_file}" ]; then
            wol_state=$(cat "${wol_state_file}")
        else
            warn "WOL state file '${wol_state_file}' not found for host ${hostname}"
            continue
        fi
        
        if [ "${wol_state}" = "1" ]; then
            info "${hostname} was not running before backup. Triggering shutdown..."
            # shutdown is the only command we are allowed to run (configure in authorized_keys on backup host)
            # we use sshpass to provide the password non-interactively (look for ([Pp])assphrase prompt)
            capture /usr/bin/sshpass -f/root/.ssh/pass -P assphrase /usr/bin/ssh "root@${hostname}" '/usr/bin/shutdown -h now' || {
                error "Failed to shutdown ${hostname}"
                continue
            }
        else
            info "${hostname} was running before backup. Not stopping it."
        fi
        
        # clean up the state file after processing
        rm -f "${wol_state_file}"
    done
}

# runs cleanup tasks and exits with an error
# parameters: 
#   $1: the last exit code
# returns: exits with code 1
try_panic() {
    local message=$(create_log_entry 'PANIC' "an unhandled error occurred in ${BASH_SOURCE[1]}")
    echo "${message}" | /usr/bin/tee -a "${BACKUP_LOG_FILE}"
    # TODO: send an email
    # if the last exit code was higher than 1, we need to abort the backup
    if [ "${1:-0}" -gt 1 ]; then
        create_log_entry 'FATAL' 'cleaning up and aborting backup' | /usr/bin/tee -a "${BACKUP_LOG_FILE}"
        borg_cleanup
        exit 1
    fi
    # otherwise, we can continue with the next backup script
}

# capture the output of a command, log it, capture stdout, and check for errors
# parameters:
#   $*: command to run
# returns:
#   exit code of the command
capture() {
    local command_log_entry=$(create_log_entry 'EXEC' "$*")
    echo "${command_log_entry}" | tee -a "${BACKUP_LOG_FILE}" >> "${BACKUP_LOG_FILE_TEMP}"
    if [ -n "${BACKUP_LOG_VERBOSE}" ]; then
        echo "${command_log_entry}"
    fi
    # define local first. doing it inline will cause the exit code to be lost
    local output
    output="$("$@" 2>&1)"
    local rc=$?
    echo "${output}" | tee -a "${BACKUP_LOG_FILE}" >> "${BACKUP_LOG_FILE_TEMP}"
    if [ -n "${BACKUP_LOG_VERBOSE}" ]; then
        echo "${output}"
    fi
    if [ ${rc} -ne 0 ]; then
        local error="ERROR: Previous command failed with exit code ${rc}."
        echo "${error}" | tee -a "${BACKUP_LOG_FILE}" >> "${BACKUP_LOG_FILE_TEMP}"
        if [ -n "${BACKUP_LOG_VERBOSE}" ]; then
            echo "${error}"
        else
            # dump the log file to stdout if we are not verbose (for cron)
            cat "${BACKUP_LOG_FILE_TEMP}"
        fi
    fi
    # don't hard-exit here, let the caller decide (for cleanup)
    return "${rc}"
}

# ensure remote host is up and reachable
# requires static ARP entry for routing when target host is offline
borg_poke_backup_host() {
    if [ -z "${BACKUP_HOST:-}" ] || [ -z "${BACKUP_PORT:-}" ] || [ -z "${BACKUP_MAC:-}" ]; then
        error "BACKUP_HOST, BACKUP_PORT, and BACKUP_MAC must be set. borg_poke_backup_host requires these to be defined."
        exit 1
    fi
    info "Checking if ${BACKUP_HOST} is up..."
    local wake_on_lan=0

    if ! /usr/bin/ping -c 1 -W 10 "${BACKUP_HOST}" > /dev/null; then
        warn "${BACKUP_HOST} is unreachable! Attempting Wake on LAN."
        local backup_host_ip
        local rc
        backup_host_ip=$(/usr/bin/getent hosts "${BACKUP_HOST}" | /usr/bin/awk '{ print $1 }')
        rc=$?
        if [ ${rc} -ne 0 ] || [ -z "${backup_host_ip}" ]; then
            error "Unable to resolve hostname ${BACKUP_HOST} to an IP address"
            exit 1
        fi
        info "DNS reports ${BACKUP_HOST} at ${backup_host_ip}"
        capture /usr/bin/wakeonlan -i "${backup_host_ip}" "${BACKUP_MAC}" || exit 1
        # give it some time to boot up...
        if [ -n "${BACKUP_LOG_VERBOSE}" ]; then
            printf 'Waiting for host to come online...'
        fi
        local attempt=0
        local max_attempts=120
        until /usr/bin/nc -w 3 -z "${BACKUP_HOST}" "${BACKUP_PORT}"; do
            if [ ${attempt} -eq ${max_attempts} ]; then
                printf '\n'
                error "Failed to wake up ${BACKUP_HOST}."
                exit 2
            fi
            if [ -n "${BACKUP_LOG_VERBOSE}" ]; then
                printf '.'
            fi
            attempt=$((attempt + 1))
            sleep 2
        done
        if [ -n "${BACKUP_LOG_VERBOSE}" ]; then
            printf '\n'
        fi
    
        info "${BACKUP_HOST} is now awake!"
        wake_on_lan=1
    fi
    
    # verify ssh connectivity
    if ! /usr/bin/nc -w 3 -z "${BACKUP_HOST}" "${BACKUP_PORT}"; then
        error "${BACKUP_HOST} is unreachable via ssh"
        exit 3
    fi
    local wol_state_file="${BACKUP_WOL_STATE_DIR}/${BACKUP_HOST}.wol-state"
    info "${BACKUP_HOST} is reachable on port ${BACKUP_PORT}."
    echo "${wake_on_lan}" > "${wol_state_file}"
    info "${wol_state_file} --> ${wake_on_lan}"
}

# helper function to extract a field from JSON host configuration
# parameters:
#   $1: JSON data
#   $2: host index
#   $3: field name
# returns:
#   extracted field value or exits with error
_extract_host_field() {
    local json_data="$1"
    local host_index="$2"
    local field_name="$3"
    
    local value
    value=$(echo "${json_data}" | /usr/bin/jq -r ".[$host_index].$field_name") || {
        error "foreach_backup_host: failed to extract $field_name for host $host_index"
        return 1
    }
    
    if [ "${value}" = "null" ]; then
        error "foreach_backup_host: $field_name is null for host $host_index"
        return 1
    fi
    
    echo "${value}"
}

# validates if a value is in the truish array
# parameters:
#   $1: value to check
# returns:
#   0 if value is truish, 1 otherwise
_is_truish() {
    local value="$1"
    local item
    for item in "${truish[@]}"; do
        if [ "$item" = "$value" ]; then
            return 0
        fi
    done
    return 1
}

# validates if a value is in the falsish array
# parameters:
#   $1: value to check
# returns:
#   0 if value is falsish, 1 otherwise
_is_falsish() {
    local value="$1"
    local item
    for item in "${falsish[@]}"; do
        if [ "$item" = "$value" ]; then
            return 0
        fi
    done
    return 1
}

# validates and parses the --capture parameter
# parameters:
#   $1: the --capture=value argument
# returns:
#   0 if valid, 1 otherwise, and sets CAPTURE_ENABLED variable
_parse_capture_param() {
    local capture_arg="$1"
    
    # check if argument starts with --capture=
    if [[ ! "$capture_arg" =~ ^--capture=.+ ]]; then
        error "foreach_backup_host: first argument must be --capture=value"
        return 1
    fi
    
    # extract the value after =
    local capture_value="${capture_arg#--capture=}"
    
    if [ -z "$capture_value" ]; then
        error "foreach_backup_host: --capture= requires a value"
        return 1
    fi
    
    # validate the capture value
    if _is_truish "$capture_value"; then
        CAPTURE_ENABLED=1
    elif _is_falsish "$capture_value"; then
        CAPTURE_ENABLED=0
    else
        error "foreach_backup_host: invalid --capture value '$capture_value'. Must be one of: ${TRUISH[*]} ${falsish[*]}"
        return 1
    fi
    
    return 0
}

# executes the supplied command for each borg backup host defined in the borg host config json file
# parameters:
#   $1: --capture=value (mandatory, where value is from TRUISH or FALSISH arrays)
#   $2: command to execute
#   $@: additional arguments to pass to the command
# environment variables:
#   BORG_HOST_CONFIG: path to the JSON config file (required)
#   REPOSITORY_NAME: optional repository name to construct BORG_REPO
# injects for each host:
#   BACKUP_HOST, BACKUP_PORT, BACKUP_MAC, BORG_RSH, BACKUP_REPO_ROOT, BORG_REPO (if REPOSITORY_NAME is set)
# returns:
#   exit code of the first failed command, or 0 if all succeed
foreach_backup_host() {
    if [ $# -eq 0 ]; then
        error 'foreach_backup_host: no arguments specified'
        return 1
    fi
    
    # parse and validate the mandatory --capture parameter
    local CAPTURE_ENABLED
    if ! _parse_capture_param "$1"; then
        return 1
    fi
    shift
    
    if [ $# -eq 0 ]; then
        error 'foreach_backup_host: no command specified after --capture parameter'
        return 1
    fi
    
    if [ -z "${BORG_HOST_CONFIG}" ]; then
        error 'foreach_backup_host: BORG_HOST_CONFIG environment variable is not set'
        return 1
    fi
    
    if [ ! -f "${BORG_HOST_CONFIG}" ]; then
        error "foreach_backup_host: config file '${BORG_HOST_CONFIG}' not found"
        return 1
    fi
    
    # check if jq is available
    if ! command -v /usr/bin/jq > /dev/null 2>&1; then
        error 'foreach_backup_host: jq is required but not installed'
        return 1
    fi
    
    local cmd="$1"
    shift
    local args=("$@")
    
    # read the JSON config and process each host
    local hosts_json
    hosts_json=$(/usr/bin/cat "${BORG_HOST_CONFIG}") || {
        error "foreach_backup_host: failed to read config file '${BORG_HOST_CONFIG}'"
        return 1
    }
    
    local host_count
    host_count=$(echo "${hosts_json}" | /usr/bin/jq '. | length') || {
        error 'foreach_backup_host: failed to parse JSON config file'
        return 1
    }
    
    # Validate that host_count is a non-empty integer
    if ! [[ "$host_count" =~ ^[0-9]+$ ]]; then
        error "foreach_backup_host: host_count ('${host_count}') is not a valid integer"
        return 1
    fi
    
    info "foreach_backup_host: processing ${host_count} backup hosts"
    
    local i=0
    while [ "$i" -lt "$host_count" ]; do
        # extract host configuration
        local hostname port wake_on_lan_mac borg_rsh borg_repo_root
        
        hostname=$(_extract_host_field "${hosts_json}" "$i" 'hostname') || return 1
        port=$(_extract_host_field "${hosts_json}" "$i" 'port') || return 1
        wake_on_lan_mac=$(_extract_host_field "${hosts_json}" "$i" 'wake_on_lan_mac') || return 1
        borg_rsh=$(_extract_host_field "${hosts_json}" "$i" 'borg_rsh') || return 1
        borg_repo_root=$(_extract_host_field "${hosts_json}" "$i" 'borg_repo_root') || return 1
        
        info "foreach_backup_host: executing command for host ${hostname}:${port}"
        
        # set up environment variables for this host
        export BACKUP_HOST="${hostname}"
        export BACKUP_PORT="${port}"
        export BACKUP_MAC="${wake_on_lan_mac}"
        export BORG_RSH="${borg_rsh}"
        export BACKUP_REPO_ROOT="${borg_repo_root}"
        
        # construct BORG_REPO if REPOSITORY_NAME is set
        if [ -n "${REPOSITORY_NAME:-}" ]; then
            export BORG_REPO="ssh://borg@${hostname}:${port}${borg_repo_root}/${REPOSITORY_NAME}"
        fi
        
        # execute the command
        if [ "${CAPTURE_ENABLED}" -eq 1 ]; then
            # use capture function for output logging
            if [ ${#args[@]} -gt 0 ]; then
                capture "${cmd}" "${args[@]}"
            else
                capture "${cmd}"
            fi
        else
            # execute directly without capture
            if [ ${#args[@]} -gt 0 ]; then
                "${cmd}" "${args[@]}"
            else
                "${cmd}"
            fi
        fi
        local rc=$?
        
        # clean up environment variables
        unset BACKUP_HOST BACKUP_PORT BACKUP_MAC BORG_RSH BACKUP_REPO_ROOT
        if [ -n "${REPOSITORY_NAME:-}" ]; then
            unset BORG_REPO
        fi
        
        # stop on first failure
        if [ ${rc} -ne 0 ]; then
            error "foreach_backup_host: command failed with exit code ${rc} for host ${hostname}"
            return ${rc}
        fi
        
        i=$((i + 1))
    done
    
    info "foreach_backup_host: completed successfully for all ${host_count} hosts"
    return 0
}

# global error handling
trap 'error Backup interrupted >&2; exit 2' INT TERM