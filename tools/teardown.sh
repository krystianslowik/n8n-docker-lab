#!/usr/bin/env bash
#
# Tears down every Compose project in this lab: the reference stack, all seven
# cases, and the second project bonus-b ships.
#
#   docker compose down -v --remove-orphans
#
# Scoped by Compose project name (every compose.yaml here declares its own
# `name:`), so this touches only this lab's containers, volumes and networks.
#
# There is deliberately NO `docker system prune` here, and there never should
# be. Deleting somebody's unrelated Docker state is not this repo's business.
#
# -v deletes the lab's volumes, so every case comes back cold and re-seeds from
# scratch on the next ./setup.sh. That is the point.
#
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

echo "Tearing down every Compose project in this lab (containers, volumes, networks)."
echo

down() { # $1 = directory, $2... = extra compose args
  local dir=$1; shift
  ( cd "$dir" && docker compose "$@" down -v --remove-orphans ) 2>&1 \
    | grep -E 'Removing|Removed|Warning|error|Error' \
    | sed 's/^/    /'
  return 0
}

# The reference stack.
if [ -f "$ROOT/reference/compose.yaml" ]; then
  echo "reference/"
  down "$ROOT/reference"
fi

# Every case, plus any nested Compose project a case ships (bonus-b's
# metrics-api/ is a second project on purpose: that case IS the second
# project, and `down -v` in the case directory would not touch it).
for dir in "$ROOT"/cases/*/; do
  [ -f "$dir/compose.yaml" ] || continue
  echo "cases/$(basename "$dir")/"

  for nested in "$dir"*/compose.yaml; do
    [ -f "$nested" ] || continue
    rel=${nested#"$dir"}
    echo "  ($rel)"
    down "$dir" -f "$rel"
  done

  down "$dir"
done

# One named network a group can leave behind: bonus-b's documented fix creates a
# shared network that neither project owns once both are down. Nothing else in
# this repo creates a network by an explicit name, so this is the only leftover
# worth naming, and it is removed by name, never by pattern.
if docker network inspect docklab-bonus-b-shared >/dev/null 2>&1; then
  echo "leftover network docklab-bonus-b-shared"
  docker network rm docklab-bonus-b-shared >/dev/null 2>&1 \
    && echo "    Removed" \
    || echo "    still in use by a container, remove that first"
fi

echo
echo "Anything of this lab's still standing? (should be nothing)"
remaining=$(docker ps -a --filter name=docklab --format '{{.Names}} ({{.Status}})')
if [ -n "$remaining" ]; then
  echo "$remaining" | sed 's/^/    /'
else
  echo "    no docklab-* containers"
fi
vols=$(docker volume ls --filter name=docklab --format '{{.Name}}')
if [ -n "$vols" ]; then
  echo "    volumes still present:"
  echo "$vols" | sed 's/^/      /'
  echo "    (a volume Compose no longer references survives \`down -v\`, remove it with"
  echo "     docker volume rm <name>. It is state that outlived its configuration.)"
else
  echo "    no docklab-* volumes"
fi

echo
echo "Done. Your unrelated containers, images and volumes were not touched."
