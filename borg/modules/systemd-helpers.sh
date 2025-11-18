
# bring systemd service back up
# params:
# 1. service_name - name of the systemd service to start
service_up() {
    if [ $# -ne 1 ]; then
        error "service_up requires 1 parameter: service_name"
        return 1
    fi
    local service_name="${1}"
    if [ -z "${service_name:-}" ]; then
        error "Invalid service_name '${service_name}', cannot start"
        return 1
    fi
    info "Attempting to start '${service_name}' systemd service..."
    capture /usr/bin/systemctl start "${service_name}" || {
        return 1
    }
    info "Successfully started '${service_name}' systemd service"
    return 0
}

# stop systemd service
# params:
# 1. service_name - name of the systemd service to stop
service_down() {
    if [ $# -ne 1 ]; then
        error "service_down requires 1 parameter: service_name"
        return 1
    fi
    local service_name="${1}"
    if [ -z "${service_name:-}" ]; then
        error "Invalid service_name '${service_name}', cannot stop"
        return 1
    fi
    info "Attempting to stop '${service_name}' systemd service..."
    capture /usr/bin/systemctl stop "${service_name}" || {
        return 1
    }
    info "Successfully stopped '${service_name}' systemd service"
    return 0
}
