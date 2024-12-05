#!/bin/bash

# Create necessary directories if they don't exist
create_dirs() {
    mkdir -p data/{rootfs,kernel,logs}
    mkdir -p shared
}

# Initialize the environment
init() {
    create_dirs
    echo "Environment initialized. Directory structure created."
}

case "$1" in
    "init")
        init
        ;;
    "build")
        create_dirs
        docker-compose build
        ;;
    "start")
        create_dirs
        docker-compose up
        ;;
    "stop")
        docker-compose down
        ;;
    "clean")
        docker-compose down
        rm -rf data/* shared/*
        echo "Environment cleaned."
        ;;
    "ssh")
        ssh -p 2023 ubuntu@localhost
        ;;
    "shell")
        docker-compose exec qemu-cxl /bin/bash
        ;;
    "logs")
        if [ -z "$2" ]; then
            echo "Recent logs:"
            ls -lht data/logs/ | head -n 5
            echo "Use './manage.sh logs <filename>' to view a specific log"
        else
            less "data/logs/$2"
        fi
        ;;
    *)
        echo "Usage: $0 {init|build|start|stop|clean|ssh|shell|logs}"
        echo "  init:  Initialize the environment"
        echo "  build: Build the Docker image"
        echo "  start: Start the environment"
        echo "  stop:  Stop the environment"
        echo "  clean: Clean up all generated files"
        echo "  ssh:   Connect to the VM via SSH"
        echo "  shell: Get a shell inside the container"
        echo "  logs:  View logs (use 'logs <filename>' to view specific log)"
        exit 1
        ;;
esac 