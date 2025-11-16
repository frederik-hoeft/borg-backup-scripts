
# restore docker container
# requires DOCKER_USER to be set
# params:
# 1. container_name - common name of the container
# 2. container_root - root path of the container (where docker-compose.yml is located)
docker_up() {
    if [ $# -ne 2 ]; then
        error "docker_up requires 2 parameters: container_name, container_root"
        return 1
    fi
    local container_name="${1}"
    local container_root="${2}"
    if [ -z "${DOCKER_USER:-}" ]; then
        error "DOCKER_USER is not set, cannot restore docker container '${container_name}'"
        return 1
    fi
    if [ -z "${container_root:-}" ] || [ ! -f "${container_root}/docker-compose.yml" ]; then
        error "Invalid container_root '${container_root}' for docker container '${container_name}', cannot restore"
        return 1
    fi
    info "Attempting to restore '${container_name}' docker container..."
    capture /usr/bin/su -c "/usr/bin/docker compose -f ${container_root}/docker-compose.yml up -d" "${DOCKER_USER}"
    info "Successfully restored '${container_name}' docker container"
    return 0
}

# stop docker container
# requires DOCKER_USER to be set
# params:
# 1. container_name - common name of the container
# 2. container_root - root path of the container (where docker-compose.yml is located)
docker_down() {
    if [ $# -ne 2 ]; then
        error "docker_down requires 2 parameters: container_name, container_root"
        return 1
    fi
    local container_name="${1}"
    local container_root="${2}"
    if [ -z "${DOCKER_USER:-}" ]; then
        error "DOCKER_USER is not set, cannot stop docker container '${container_name}'"
        return 1
    fi
    if [ -z "${container_root:-}" ] || [ ! -f "${container_root}/docker-compose.yml" ]; then
        error "Invalid container_root '${container_root}' for docker container '${container_name}', cannot stop"
        return 1
    fi
    info "Attempting to stop '${container_name}' docker container..."
    capture /usr/bin/su -c "/usr/bin/docker compose -f ${container_root}/docker-compose.yml down" "${DOCKER_USER}"
    return 0
}