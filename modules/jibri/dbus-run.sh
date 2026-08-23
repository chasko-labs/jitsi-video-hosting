#!/usr/bin/with-contenv bash
# Start dbus system bus — required by Chrome 143+ inside containers.
# Without this, Chrome hangs indefinitely waiting for dbus socket.
mkdir -p /run/dbus
exec dbus-daemon --system --nofork
