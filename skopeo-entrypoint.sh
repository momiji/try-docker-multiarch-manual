#!/bin/sh
set -e

groupadd docker$DOCKER_GID -g $DOCKER_GID -o
useradd skopeo$USER_UID -u $USER_UID -g $DOCKER_GID -M -N -o -d /

exec sudo -i -u skopeo$USER_UID skopeo "$@"
