# frozen_string_literal: true

module Teek
  module SDL2
    # Push-based real-time PCM audio output.
    #
    # AudioStream wraps an SDL2 audio device for streaming raw PCM
    # samples. Unlike {Sound} and {Music} (which play from files),
    # AudioStream lets you generate or decode audio in real-time and
    # push it directly to the speakers.
    #
    # The stream starts paused. Queue some initial data, then call
    # {#resume} to begin playback. Use {#queued_samples} to monitor
    # the buffer level and pace your audio generation.
    #
    # @example Play a 440 Hz sine wave for 1 second
    #   stream = Teek::SDL2::AudioStream.new(frequency: 44100, format: :s16, channels: 1)
    #   samples = (0...44100).map { |i| (Math.sin(2 * Math::PI * 440 * i / 44100.0) * 32000).to_i }
    #   stream.queue(samples.pack('s*'))
    #   stream.resume
    #   sleep 1
    #   stream.destroy
    class AudioStream

      # @!method initialize(frequency: 44100, format: :s16, channels: 2)
      #   Open a push-based audio output device.
      #   The stream starts paused — call {#resume} after queuing initial data.
      #   @param frequency [Integer] sample rate in Hz (default: 44100)
      #   @param format [Symbol] sample format — +:s16+ (signed 16-bit),
      #     +:f32+ (32-bit float), or +:u8+ (unsigned 8-bit)
      #   @param channels [Integer] 1 for mono, 2 for stereo (default: 2)

      # @!method queue(data)
      #   Push raw PCM data to the audio device.
      #   The data must be a binary String whose format matches the stream's
      #   +format+ and +channels+ (e.g. packed signed 16-bit integers for +:s16+).
      #   @param data [String] raw PCM samples (binary encoding)
      #   @return [nil]

      # @!method queued_bytes
      #   Bytes of audio data currently queued for playback.
      #   @return [Integer]

      # @!method queued_samples
      #   Number of audio sample frames currently queued.
      #   One sample frame = one value per channel.
      #   Useful for pacing audio generation (e.g. keep 2000–4000 samples buffered).
      #   @return [Integer]

      # @!method resume
      #   Start or unpause audio playback.
      #   @return [nil]

      # @!method pause
      #   Pause audio playback. Queued data is preserved.
      #   @return [nil]

      # @!method playing?
      #   Whether the audio device is currently playing (not paused).
      #   @return [Boolean]

      # @!method clear
      #   Flush all queued audio data.
      #   @return [nil]

      # @!method frequency
      #   Sample rate in Hz.
      #   @return [Integer]

      # @!method channels
      #   Number of audio channels (1 = mono, 2 = stereo).
      #   @return [Integer]

      # @!method format
      #   Audio sample format.
      #   @return [Symbol] +:s16+, +:f32+, or +:u8+

      # @!method destroy
      #   Close the audio device. Further method calls will raise.
      #   @return [nil]

      # @!method destroyed?
      #   Whether the audio stream has been destroyed.
      #   @return [Boolean]

      # @!method self.available?
      #   Whether at least one audio output device is available.
      #   @return [Boolean]

      # @!method self.device_count
      #   Number of audio output devices detected by SDL2.
      #   @return [Integer]

      # @!method self.driver_name
      #   Name of the current SDL2 audio driver (e.g. "wasapi", "dummy").
      #   @return [String, nil]
    end

    # Null-object stand-in for {AudioStream} when no audio device is
    # available.  Every method is a silent no-op, so the rest of the
    # application can call the same API without nil guards.
    class NullAudioStream
      def queue(_data)    = nil
      def queued_bytes    = 0
      def queued_samples  = 0
      def resume          = nil
      def pause           = nil
      def playing?        = false
      def clear           = nil
      def frequency       = 0
      def channels        = 0
      def format          = :s16
      def destroy         = nil
      def destroyed?      = true
    end
  end
end
