# frozen_string_literal: true

module Teek
  module SDL2
    # Streaming music playback for longer audio files (MP3, OGG, WAV).
    #
    # Only one Music track can play at a time (SDL2_mixer limitation).
    # For short sound effects that can overlap, use {Sound} instead.
    #
    # @example
    #   music = Teek::SDL2::Music.new("background.mp3")
    #   music.play              # loops forever by default
    #   music.volume = 64       # half volume
    #   music.pause
    #   music.resume
    #   music.stop
    #   music.destroy
    class Music

      # @!method initialize(path)
      #   Load a music file (MP3, OGG, WAV). Initializes the mixer automatically.
      #   @param path [String] path to the music file

      # @!method play(loops: -1, fade_ms: 0)
      #   Start playing the music. Only one music track plays at a time.
      #   @param loops [Integer] -1 = loop forever (default), 0 = play once, N = play N extra times
      #   @param fade_ms [Integer] fade-in duration in milliseconds (0 = no fade)
      #   @return [nil]

      # @!method stop
      #   Stop music playback.
      #   @return [nil]

      # @!method pause
      #   Pause music playback.
      #   @return [nil]

      # @!method resume
      #   Resume paused music.
      #   @return [nil]

      # @!method playing?
      #   Whether music is currently playing.
      #   @return [Boolean]

      # @!method paused?
      #   Whether music is currently paused.
      #   @return [Boolean]

      # @!method volume
      #   Current music volume.
      #   @return [Integer] 0–128

      # @!method volume=(vol)
      #   Set the music volume.
      #   @param vol [Integer] 0–128
      #   @return [Integer]

      # @!method destroy
      #   Free the underlying music data. Stops playback if playing.
      #   @return [nil]

      # @!method destroyed?
      #   Whether the music has been destroyed.
      #   @return [Boolean]
    end
  end
end
