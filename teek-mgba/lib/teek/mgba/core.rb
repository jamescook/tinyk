# frozen_string_literal: true

module Teek
  module MGBA
    # GBA emulator core wrapping libmgba's mCore API.
    #
    # Core loads a GBA ROM, emulates one frame at a time, and provides
    # access to the video and audio output buffers. Pair with
    # {Teek::SDL2::Renderer} for display and {Teek::SDL2::AudioStream}
    # for sound.
    #
    # @example Run a frame and grab pixels
    #   core = Teek::MGBA::Core.new("game.gba")
    #   core.run_frame
    #   pixels = core.video_buffer   # 240*160*4 bytes RGBA
    #   core.destroy
    class Core

      # @!method initialize(rom_path, save_dir = nil)
      #   Load a GBA ROM and initialize the emulator core.
      #   Detects the platform (GBA/GB/GBC) from the file extension,
      #   allocates video and audio buffers, resets the CPU, and autoloads
      #   the battery save file (.sav).
      #
      #   @param rom_path [String] path to the ROM file (.gba, .gb, .gbc)
      #   @param save_dir [String, nil] directory for .sav files.
      #     When +nil+, saves are stored alongside the ROM.
      #   @raise [ArgumentError] if the ROM format is unrecognized or the file cannot be opened
      #   @raise [RuntimeError] if core initialization or ROM loading fails

      # @!method run_frame
      #   Advance the emulation by one video frame (~16.7 ms of GBA time).
      #   Releases the GVL so other Ruby threads can run during emulation.
      #   After this call, {#video_buffer} and {#audio_buffer} contain
      #   the new frame's output.
      #   @return [nil]

      # @!method video_buffer
      #   Raw pixel data for the current frame.
      #   Returns a binary String of +width * height * 4+ bytes in mGBA's
      #   native color format (ABGR8888 — R in low bits of each uint32).
      #   @return [String] binary pixel data
      #   @see #video_buffer_argb

      # @!method video_buffer_argb
      #   Pixel data converted to ARGB8888 for SDL2 textures.
      #   Same dimensions as {#video_buffer} but with R and B channels
      #   swapped so the data can be passed directly to
      #   {Teek::SDL2::Texture#update}.
      #   @return [String] binary pixel data in ARGB8888 format

      # @!method audio_buffer
      #   Drain the audio output for the most recent frame(s).
      #   Returns interleaved stereo signed 16-bit PCM samples (L R L R ...).
      #   The number of samples varies per frame (~548 at 32768 Hz).
      #   @return [String] binary PCM data (packed int16, little-endian)

      # @!method set_keys(bitmask)
      #   Set the currently pressed buttons as a bitmask.
      #   Combine key constants with bitwise OR:
      #     +core.set_keys(Teek::MGBA::KEY_A | Teek::MGBA::KEY_START)+
      #   Pass +0+ to release all buttons.
      #   @param bitmask [Integer] bitwise OR of +KEY_*+ constants
      #   @return [nil]

      # @!method width
      #   Video output width in pixels (240 for GBA).
      #   @return [Integer]

      # @!method height
      #   Video output height in pixels (160 for GBA).
      #   @return [Integer]

      # @!method title
      #   Internal ROM title (up to 12 characters for GBA).
      #   @return [String]

      # @!method game_code
      #   Game code from the ROM header, prefixed with platform
      #   (e.g. "AGB-BTKE" for GBA, "CGB-XXXX" for GBC).
      #   @return [String]

      # @!method maker_code
      #   2-character maker/publisher code from the GBA ROM header
      #   at offset 0xB0 (e.g. "01" for Nintendo).
      #   Returns empty string for non-GBA ROMs.
      #   @return [String]

      # @!method checksum
      #   CRC32 checksum of the loaded ROM.
      #   @return [Integer]

      # @!method platform
      #   Platform string: "GBA", "GB", or "Unknown".
      #   @return [String]

      # @!method rom_size
      #   Size of the loaded ROM in bytes.
      #   @return [Integer]

      # @!method save_state_to_file(path)
      #   Save the complete emulator state (CPU, memory, audio, video) to a file.
      #   Includes battery save data and RTC state.
      #   @param path [String] destination file path
      #   @return [Boolean] true on success
      #   @raise [RuntimeError] if the file cannot be opened for writing

      # @!method load_state_from_file(path)
      #   Restore emulator state from a previously saved state file.
      #   @param path [String] state file path
      #   @return [Boolean] true on success, false if file doesn't exist or is invalid

      # @!method destroy
      #   Shut down the emulator core and free all resources.
      #   Further method calls will raise.
      #   @return [nil]

      # @!method destroyed?
      #   Whether the core has been destroyed.
      #   @return [Boolean]
    end
  end
end
