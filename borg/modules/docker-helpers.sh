
# bring docker container group back up
# requires DOCKER_USER to be set
# params:
# 1. container_name - common name of the container group
# 2. container_root - root path of the container group (where docker-compose.yml is located)
docker_up() {
    if [ $# -ne 2 ]; then
        error "docker_up requires 2 parameters: container_name, container_root"
        return 1
    fi
    local container_name="${1}"
    local container_root="${2}"
    if [ -z "${DOCKER_USER:-}" ]; then
        error "DOCKER_USER is not set, cannot start docker container group '${container_name}'"
        return 1
    fi
    if [ -z "${container_root:-}" ] || [ ! -f "${container_root}/docker-compose.yml" ]; then
        error "Invalid container_root '${container_root}' for docker container group '${container_name}', cannot start"
        return 1
    fi
    info "Attempting to start '${container_name}' docker container group..."
    capture /usr/bin/su -c "/usr/bin/docker compose -f '${container_root}/docker-compose.yml' up -d" "${DOCKER_USER}" || {
        return 1
    }
    info "Successfully started '${container_name}' docker container group"
    return 0
}

# stop docker container group
# requires DOCKER_USER to be set
# params:
# 1. container_name - common name of the container group
# 2. container_root - root path of the container group (where docker-compose.yml is located)
docker_down() {
    if [ $# -ne 2 ]; then
        error "docker_down requires 2 parameters: container_name, container_root"
        return 1
    fi
    local container_name="${1}"
    local container_root="${2}"
    if [ -z "${DOCKER_USER:-}" ]; then
        error "DOCKER_USER is not set, cannot stop docker container group '${container_name}'"
        return 1
    fi
    if [ -z "${container_root:-}" ] || [ ! -f "${container_root}/docker-compose.yml" ]; then
        error "Invalid container_root '${container_root}' for docker container group '${container_name}', cannot stop"
        return 1
    fi
    info "Attempting to stop '${container_name}' docker container group..."
    capture /usr/bin/su -c "/usr/bin/docker compose -f '${container_root}/docker-compose.yml' down" "${DOCKER_USER}" || {
        return 1
    }
    info "Successfully stopped '${container_name}' docker container group"
    return 0
}
