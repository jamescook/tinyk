#!/usr/bin/env ruby
# frozen_string_literal: true

# mGBA Player — GBA frontend powered by teek + teek-sdl2
#
# Usage:
#   ruby -Ilib -Iteek-sdl2/lib -Iteek-mgba/lib sample/mgba_player/mgba_player.rb [rom.gba]
#
# Controls:
#   Arrow keys  — D-pad
#   Z           — A
#   X           — B
#   Return      — Start
#   Backspace   — Select
#   A           — L shoulder
#   S           — R shoulder
#   P           — Pause/Resume
#   Q / Escape  — Quit

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../../teek-sdl2/lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../../teek-mgba/lib', __dir__)
require 'teek/mgba'

rom_path = ARGV.find { |a| !a.start_with?('--') }
Teek::MGBA::Player.new(rom_path).run
