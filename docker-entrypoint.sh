#!/bin/bash
# Start PulseAudio with a null sink for headless audio testing.
# SDL2 can open audio devices against this virtual sink.
pulseaudio --start --daemonize --exit-idle-time=-1 2>/dev/null
pactl load-module module-null-sink sink_name=dummy sink_properties=device.description=Dummy >/dev/null 2>&1

exec "$@"
