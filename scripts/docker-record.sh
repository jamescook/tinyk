#!/bin/bash
#
# Record a Teek sample inside Docker and save to recordings/
#
# Usage:
#   ./scripts/docker-record.sh sample/goldberg.rb
#
#   Options:
#     TCL_VERSION=8.6 ./scripts/docker-record.sh ...  # Use Tcl 8.6
#     CODEC=vp9 ./scripts/docker-record.sh ...        # Use vp9 (.webm)
#
set -e

SAMPLE="${1:?Usage: $0 <sample.rb>}"
TCL_VERSION="${TCL_VERSION:-9}"
RUBY_VERSION="${RUBY_VERSION:-3.4}"
CODEC="${CODEC:-x264}"

# Build image name matching Rakefile convention
if [ "$TCL_VERSION" = "8.6" ] || [ "$TCL_VERSION" = "8" ]; then
    BASE="teek-ci-test-8"
else
    BASE="teek-ci-test-9"
fi
if [ "$RUBY_VERSION" = "3.4" ]; then
    IMAGE="$BASE"
else
    IMAGE="${BASE}-ruby${RUBY_VERSION}"
fi

[ -f "$SAMPLE" ] || { echo "Error: $SAMPLE not found"; exit 1; }

# Output filename with correct extension
if [ -n "$NAME" ]; then
    BASENAME="$NAME"
else
    BASENAME="${SAMPLE##*/}"
    BASENAME="${BASENAME%.rb}"
fi
case "$CODEC" in
    vp9) EXT="webm" ;;
    x264|h264) EXT="mp4" ;;
    *) EXT="webm" ;;
esac
OUTPUT="${BASENAME}.${EXT}"

mkdir -p recordings

echo "Recording ${SAMPLE} with ${IMAGE} (${CODEC})..."

docker run --rm \
    -e "FRAMERATE=${FRAMERATE:-30}" \
    -e "CODEC=${CODEC}" \
    -e "NAME=${NAME}" \
    -e "DOCKER_RECORD=1" \
    -v "$(pwd)/scripts:/app/scripts:ro" \
    -v "$(pwd)/sample:/app/sample:ro" \
    -v "$(pwd)/recordings:/app/recordings" \
    "${IMAGE}" \
    bash -c "./scripts/record-sample.sh '${SAMPLE}' && mv '${OUTPUT}' recordings/ && mv '${BASENAME}.png' recordings/ 2>/dev/null || true"

echo "Done: recordings/${OUTPUT}"
