#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates a minimal valid GBA ROM for testing teek-mgba.
#
# The ROM contains a valid GBA header (entry branch, title, fixed byte,
# complement checksum) and an ARM infinite loop. mGBA will load it,
# emulate frames, and produce video/audio output — enough to exercise
# every Core method without needing a real game.
#
# Usage:
#   ruby teek-mgba/scripts/generate_test_rom.rb
#
# Output:
#   teek-mgba/test/fixtures/test.gba

rom = ("\x00".b) * 512

# ARM entry: branch to 0x08000020 (6 words forward, accounting for PC+8)
rom[0, 4] = [0xEA000006].pack("V")

# Infinite loop at 0x20: ARM `b .` (branch to self)
rom[0x20, 4] = [0xEAFFFFFE].pack("V")

# Game title (12 bytes at 0xA0)
rom[0xA0, 12] = "TEEKTEST".ljust(12, "\x00")

# Fixed value required by GBA header
rom.setbyte(0xB2, 0x96)

# Header complement checksum (sum bytes 0xA0..0xBC)
sum = (0xA0..0xBC).sum { |i| rom.getbyte(i) }
rom.setbyte(0xBD, (-(sum + 0x19)) & 0xFF)

out = File.expand_path("../test/fixtures/test.gba", __dir__)
File.binwrite(out, rom)
puts "Wrote #{rom.bytesize} bytes to #{out}"
