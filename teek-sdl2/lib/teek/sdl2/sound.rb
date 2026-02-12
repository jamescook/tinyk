# frozen_string_literal: true

module Teek
  module SDL2
    # A short audio sample loaded from a WAV file.
    #
    # Sound wraps SDL2_mixer's Mix_Chunk for fire-and-forget playback
    # of sound effects. The audio mixer is initialized automatically
    # on first use.
    #
    # @example
    #   sound = Teek::SDL2::Sound.new("click.wav")
    #   sound.play
    #   sound.play(volume: 64)   # half volume
    #   sound.destroy
    class Sound

      # @!method initialize(path)
      #   Load a sound effect from a file. Initializes the audio mixer automatically.
      #   @param path [String] path to a WAV, OGG, or other supported audio file

      # @!method play(volume: nil, loops: 0, fade_ms: 0)
      #   Play the sound on the next available channel.
      #   @param volume [Integer, nil] playback volume (0–128, nil = current)
      #   @param loops [Integer] 0 = play once, N = play N extra times, -1 = loop forever
      #   @param fade_ms [Integer] fade-in duration in milliseconds (0 = no fade)
      #   @return [Integer] channel number used (pass to {SDL2.halt} to stop)

      # @!method volume
      #   Current volume for this sound.
      #   @return [Integer] 0–128

      # @!method volume=(vol)
      #   Set the volume for this sound.
      #   @param vol [Integer] 0–128
      #   @return [Integer]

      # @!method destroy
      #   Free the underlying audio data. Further method calls will raise.
      #   @return [nil]

      # @!method destroyed?
      #   Whether the sound has been destroyed.
      #   @return [Boolean]
    end
  end
end
