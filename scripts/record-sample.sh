#!/bin/bash
#
# Record a Tk sample to video (Linux, used inside Docker)
# Requires: xvfb-run (or DISPLAY set), ffmpeg, xrandr, gtf
#
# The sample must handle TK_RECORD=1 for auto-start and auto-exit.
# Window geometry is queried dynamically from the demo via TeekDemo.signal_recording_ready.
# The Xvfb display is resized to match using xrandr (RandR extension).
#
# Usage:
#   ./scripts/record-sample.sh sample/goldberg.rb [output.webm]
#
#   Custom settings:
#     CODEC=x264 ./scripts/record-sample.sh sample/foo.rb  # h264, larger files
#
set -e

SAMPLE="${1:?Usage: $0 <sample.rb> [output]}"
FRAMERATE="${FRAMERATE:-30}"
CODEC="${CODEC:-x264}"  # x264 (default), vp9 (alternative)

# Output filename and codec settings
# Use NAME env var if provided, otherwise derive from sample path
if [ -n "$NAME" ]; then
    BASENAME="$NAME"
else
    BASENAME="${SAMPLE##*/}"
    BASENAME="${BASENAME%.rb}"
fi

case "$CODEC" in
    vp9)
        EXT="webm"
        CODEC_OPTS="-c:v libvpx-vp9 -crf 30 -b:v 0"
        ;;
    x264|h264)
        EXT="mp4"
        CODEC_OPTS="-c:v libx264 -preset fast -crf 23"
        ;;
    *)
        echo "Error: Unknown codec '$CODEC' (use vp9 or x264)"
        exit 1
        ;;
esac

OUTPUT="${2:-${BASENAME}.${EXT}}"

[ -f "$SAMPLE" ] || { echo "Error: $SAMPLE not found"; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo "Error: ffmpeg not installed"; exit 1; }

# Use bundle exec if Gemfile present (Docker), otherwise plain ruby
if [ -f Gemfile ]; then
    RUBY_CMD="bundle exec ruby -Ilib"
else
    RUBY_CMD="ruby -Ilib"
fi

# If no DISPLAY, re-exec under xvfb-run with RandR extension enabled
# Start with large default screen; we'll resize dynamically after getting window geometry
if [ -z "$DISPLAY" ]; then
    command -v xvfb-run >/dev/null 2>&1 || { echo "Error: xvfb-run not installed and DISPLAY not set"; exit 1; }
    exec xvfb-run -a -s "-screen 0 1920x1080x24 +extension RANDR" "$0" "$@"
fi

# Only print if not called from docker-record.sh
[ -z "$DOCKER_RECORD" ] && echo "Recording ${SAMPLE} to ${OUTPUT} (${CODEC})..."

# Find a free port for stop signal
find_free_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null || \
    ruby -e 'require "socket"; s=TCPServer.new("127.0.0.1",0); puts s.addr[1]; s.close' 2>/dev/null || \
    echo "9999"
}
STOP_PORT=$(find_free_port)

# Thumbnail path (same name as output, .png extension)
THUMBNAIL="${OUTPUT%.*}.png"

# Start nc listener, capture output to temp file
echo "Waiting for ready signal on port $STOP_PORT..."
READY_FILE=$(mktemp)
nc -l -p "$STOP_PORT" > "$READY_FILE" &
NC_PID=$!

# Poll until nc is actually listening
while ! ss -tln | grep -q ":$STOP_PORT "; do sleep 0.01; done

# Now start the app
TK_RECORD=1 TK_STOP_PORT="$STOP_PORT" TK_THUMBNAIL_PATH="$THUMBNAIL" $RUBY_CMD "$SAMPLE" &
APP_PID=$!

# Wait for nc to finish (client connected and disconnected)
wait $NC_PID 2>/dev/null
READY_DATA=$(head -c20 "$READY_FILE")
rm -f "$READY_FILE"
echo "DEBUG: READY_DATA='$READY_DATA'"
if [[ "$READY_DATA" =~ R:([0-9]+)x([0-9]+) ]]; then
    WIN_WIDTH="${BASH_REMATCH[1]}"
    WIN_HEIGHT="${BASH_REMATCH[2]}"
    echo "Window geometry: ${WIN_WIDTH}x${WIN_HEIGHT}"
else
    echo "Error: Demo did not send geometry. Update demo to use TeekDemo.signal_recording_ready"
    exit 1
fi

# Resize Xvfb display to match window geometry using RandR
# This ensures pixel-perfect capture without needing per-sample screen_size config
if command -v xrandr >/dev/null 2>&1 && command -v gtf >/dev/null 2>&1; then
    MODE_NAME="${WIN_WIDTH}x${WIN_HEIGHT}_60"
    # Generate CVT timing values using gtf
    MODELINE=$(gtf "$WIN_WIDTH" "$WIN_HEIGHT" 60 | grep Modeline | sed 's/.*Modeline //' | sed 's/"//g')
    if [ -n "$MODELINE" ]; then
        echo "Resizing display to ${WIN_WIDTH}x${WIN_HEIGHT}..."
        # Add new mode and switch to it (ignore errors if mode exists)
        xrandr --newmode $MODELINE 2>/dev/null || true
        xrandr --addmode screen "$MODE_NAME" 2>/dev/null || true
        xrandr -s "$MODE_NAME" 2>/dev/null || true
        sleep 0.1  # Brief settle time after resize
    fi
fi

# Position window at 0,0 for consistent capture
WINDOW_ID=$(xdotool search --onlyvisible --name "" 2>/dev/null | head -1)
if [ -n "$WINDOW_ID" ]; then
    echo "Window detected (id: $WINDOW_ID), moving to 0,0..."
    xdotool windowmove "$WINDOW_ID" 0 0
fi
sleep 0.1  # Brief settle time

# Capture using window geometry (x11grab captures screen region at 0,0)
ffmpeg -y -f x11grab -video_size "${WIN_WIDTH}x${WIN_HEIGHT}" \
    -framerate ${FRAMERATE} -i "${DISPLAY}+0,0" \
    ${CODEC_OPTS} \
    "${OUTPUT}" 2>/dev/null &
FFMPEG_PID=$!

# Wait for "done" signal (demo connects and waits for ack)
# Use a simple Ruby one-liner for reliable socket handling
echo "Recording..."
ruby -rsocket -e '
  server = TCPServer.new("127.0.0.1", ARGV[0].to_i)
  client = server.accept  # Connection itself is the "done" signal
  STDERR.puts "Got done signal"
  Process.kill("INT", ARGV[1].to_i) rescue nil
  sleep 0.5
  client.write("x")  # Send ack so demo can exit
  client.close
  server.close
' "$STOP_PORT" "$FFMPEG_PID" 2>&1 &
WAIT_PID=$!

# Wait for either: done signal handled, app exit, or timeout
timeout 120 tail --pid=$WAIT_PID -f /dev/null 2>/dev/null || true

kill $FFMPEG_PID 2>/dev/null || true
wait $FFMPEG_PID 2>/dev/null || true
kill $WAIT_PID 2>/dev/null || true
wait $APP_PID 2>/dev/null || true

echo "Done: ${OUTPUT}"
