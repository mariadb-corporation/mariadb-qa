#!/bin/bash
# Container entry point. Starts as root to align the box user with the host
# user, wires the framework into /test and /data, then runs the command as the
# box user.

set -u

BOX_USER="${BOX_USER:-qa}"
BOX_HOME="/home/${BOX_USER}"
QA_DIR="${BOX_HOME}/mariadb-qa"

# Match the host user, so files written into the mapped /test and /data belong
# to the engineer on the host. -o allows an id that another account already uses
CUR_UID="$(id -u "${BOX_USER}")"
CUR_GID="$(id -g "${BOX_USER}")"
CHANGED=0
if [ -n "${HOST_GID:-}" ] && [ "${HOST_GID}" != "${CUR_GID}" ]; then
  groupmod -o -g "${HOST_GID}" "${BOX_USER}" && CHANGED=1
fi
if [ -n "${HOST_UID:-}" ] && [ "${HOST_UID}" != "${CUR_UID}" ]; then
  usermod -o -u "${HOST_UID}" "${BOX_USER}" && CHANGED=1
fi
if [ "${CHANGED}" = "1" ]; then
  chown -R "${BOX_USER}:${BOX_USER}" "${BOX_HOME}" /MSAN_libs 2> /dev/null
fi

# The two mapped directories. Only the top level is touched, so a large tree is
# not walked on every start
for D in /test /data; do
  [ -d "${D}" ] || mkdir -p "${D}"
  if [ "$(stat -c %u "${D}")" != "$(id -u "${BOX_USER}")" ]; then
    chown "${BOX_USER}:${BOX_USER}" "${D}"
  fi
done

runuser -u "${BOX_USER}" -- /usr/local/bin/box-setup.sh

# linkit creates every /test, /data and home directory helper, links the Claude
# Code skills, and writes the alias list to /tmp/.bashrc. It is safe to re-run,
# and it must run here because the two mapped directories are empty at build time
# The log name differs from the one qa-update uses, because this file belongs to
# root and the box user has to be able to write its own
if ! runuser -u "${BOX_USER}" -- "${QA_DIR}/linkit" > /tmp/linkit-start.log 2>&1; then
  echo "warning: linkit reported a problem, see /tmp/linkit-start.log"
fi
runuser -u "${BOX_USER}" -- bash -c '
  if [ -r /tmp/.bashrc ] && ! grep -qs "^alias anc=" "${HOME}/.bashrc"; then
    cat /tmp/.bashrc >> "${HOME}/.bashrc"
  fi'

BASEDIRS="$( (cd /test && ./gendirs.sh ALLALL) 2> /dev/null | wc -l)"
# git as the owner of the clone, because git rejects another user's repository
QA_REV="$(runuser -u "${BOX_USER}" -- git -C "${QA_DIR}" log -1 --format='%h %cd' --date=short 2> /dev/null)"
cat << EOF

  MariaDB QA Framework Container
  ------------------------------
  framework  ${QA_REV}
  compiler   $(clang --version | head -1)
  /dev/shm   $(df -h /dev/shm | awk 'NR==2 {print $2}')
  /test      ${BASEDIRS} server build(s)

  Check the box       qa-check
  Read the guide      qa-guide
  Clone and build     cb        and cb-san, cb-msan, cb-tsan, cb-val
  Update the box      qa-update and qa-upgrade

EOF

exec runuser -u "${BOX_USER}" -- "$@"
