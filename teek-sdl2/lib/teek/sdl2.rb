# frozen_string_literal: true

require "teek"
require_relative "sdl2/version"
require "teek_sdl2"

module Teek
  # GPU-accelerated 2D rendering via SDL2, embedded inside Tk windows.
  #
  # Teek::SDL2 lets you drop an SDL2 hardware-accelerated surface into any
  # Tk application. The surface lives inside a Tk frame so it coexists with
  # normal Tk widgets (buttons, labels, menus) while all pixel work is
  # GPU-driven.
  #
  # The main entry point is {Viewport}, which creates a Tk frame, obtains
  # its native window handle, and hands it to SDL2 for rendering.
  #
  # @example Basic usage
  #   require 'teek'
  #   require 'teek/sdl2'
  #
  #   app = Teek::App.new
  #   vp  = Teek::SDL2::Viewport.new(app, width: 800, height: 600)
  #   vp.render do |r|
  #     r.clear(0, 0, 0)
  #     r.fill_rect(10, 10, 100, 50, 255, 0, 0)
  #   end
  #   app.mainloop
  #
  # @see Viewport
  # @see Renderer
  # @see Texture
  # @see Font
  module SDL2
    # @!group Audio (C-defined module functions)

    # @!method self.open_audio
    #   Explicitly initialize the audio mixer. Safe to call multiple times.
    #   Called automatically by {Sound} and {Music} constructors.
    #   @return [nil]

    # @!method self.close_audio
    #   Shut down the audio mixer and free resources.
    #   @return [nil]

    # @!method self.halt(channel)
    #   Immediately stop playback on a channel.
    #   @param channel [Integer] channel number (returned by {Sound#play})
    #   @return [nil]

    # @!method self.playing?(channel)
    #   Whether the given channel is currently playing.
    #   @param channel [Integer]
    #   @return [Boolean]

    # @!method self.channel_paused?(channel)
    #   Whether the given channel is paused.
    #   @param channel [Integer]
    #   @return [Boolean]

    # @!method self.pause_channel(channel)
    #   Pause playback on a channel.
    #   @param channel [Integer]
    #   @return [nil]

    # @!method self.resume_channel(channel)
    #   Resume a paused channel.
    #   @param channel [Integer]
    #   @return [nil]

    # @!method self.channel_volume(channel, vol = -1)
    #   Set or query volume for a channel.
    #   @param channel [Integer]
    #   @param vol [Integer] 0–128, or -1 to query without changing
    #   @return [Integer] current volume

    # @!method self.fade_out_music(ms)
    #   Gradually fade out the currently playing music.
    #   @param ms [Integer] fade duration in milliseconds
    #   @return [nil]

    # @!method self.fade_out_channel(channel, ms)
    #   Gradually fade out a channel.
    #   @param channel [Integer]
    #   @param ms [Integer] fade duration in milliseconds
    #   @return [nil]

    # @!method self.master_volume
    #   Current master volume (requires SDL2_mixer >= 2.6).
    #   @return [Integer] 0–128
    #   @raise [NotImplementedError] if SDL2_mixer < 2.6

    # @!method self.master_volume=(vol)
    #   Set the master volume (requires SDL2_mixer >= 2.6).
    #   @param vol [Integer] 0–128
    #   @return [Integer] previous volume
    #   @raise [NotImplementedError] if SDL2_mixer < 2.6

    # @!method self.start_audio_capture(path)
    #   Begin recording mixed audio output to a WAV file.
    #   Everything that plays through the mixer (sounds, music) is captured.
    #   @param path [String] output WAV file path
    #   @return [nil]
    #   @raise [RuntimeError] if capture is already in progress
    #   @see .stop_audio_capture

    # @!method self.stop_audio_capture
    #   Stop recording and finalize the WAV file.
    #   Safe to call even if no capture is in progress.
    #   @return [nil]
    #   @see .start_audio_capture

    # @!endgroup

    # @!group Blending (C-defined module functions)

    # @!method self.compose_blend_mode(src_color_factor, dst_color_factor, color_op, src_alpha_factor, dst_alpha_factor, alpha_op)
    #   Create a custom blend mode for use with {Texture#blend_mode=}.
    #
    #   The blend equations are:
    #     dstRGB = color_op(srcRGB * src_color_factor, dstRGB * dst_color_factor)
    #     dstA   = alpha_op(srcA   * src_alpha_factor, dstA   * dst_alpha_factor)
    #
    #   Factors (Symbol):
    #   - +:zero+, +:one+
    #   - +:src_color+, +:one_minus_src_color+
    #   - +:src_alpha+, +:one_minus_src_alpha+
    #   - +:dst_color+, +:one_minus_dst_color+
    #   - +:dst_alpha+, +:one_minus_dst_alpha+
    #
    #   Operations (Symbol):
    #   - +:add+ — +src + dst+ (all renderers)
    #   - +:subtract+ — +src - dst+
    #   - +:rev_subtract+ — +dst - src+
    #   - +:minimum+ — +min(src, dst)+
    #   - +:maximum+ — +max(src, dst)+
    #
    #   @param src_color_factor [Symbol] multiplier for source RGB
    #   @param dst_color_factor [Symbol] multiplier for destination RGB
    #   @param color_op [Symbol] operation combining color components
    #   @param src_alpha_factor [Symbol] multiplier for source alpha
    #   @param dst_alpha_factor [Symbol] multiplier for destination alpha
    #   @param alpha_op [Symbol] operation combining alpha components
    #   @return [Integer] opaque blend mode ID for {Texture#blend_mode=}
    #   @see https://wiki.libsdl.org/SDL2/SDL_ComposeCustomBlendMode SDL_ComposeCustomBlendMode
    #   @see https://wiki.libsdl.org/SDL2/SDL_BlendFactor SDL_BlendFactor
    #   @see https://wiki.libsdl.org/SDL2/SDL_BlendOperation SDL_BlendOperation
    #
    #   @example Inverse/invert effect (text shows opposite of background)
    #     inverse = Teek::SDL2.compose_blend_mode(
    #       :one_minus_dst_color, :one_minus_src_alpha, :add,
    #       :zero, :one, :add
    #     )
    #     white_text = font.render_text("Hello", 255, 255, 255)
    #     white_text.blend_mode = inverse

    # @!endgroup

    @event_source = nil

    # Register SDL2 as a Tcl event source. Called automatically when the
    # first {Viewport} is created. Uses a C function pointer for the hot
    # path — no Ruby in the poll loop.
    #
    # @param interval_ms [Integer] polling interval in milliseconds
    # @return [void]
    # @api private
    def self.register_event_source(interval_ms: 16)
      return if @event_source&.registered?

      fn_ptr = _event_check_fn_ptr   # C function address from sdl2bridge.c
      @event_source = Teek._register_event_source(fn_ptr, 0, interval_ms)
    end

    # Remove SDL2 from Tcl's event loop. Called automatically when the last
    # {Viewport} is destroyed.
    #
    # @return [void]
    # @api private
    def self.unregister_event_source
      @event_source&.unregister
      @event_source = nil
    end
  end
end

# Ruby convenience layers (reopen C-defined classes)
require_relative "sdl2/renderer"
require_relative "sdl2/texture"
require_relative "sdl2/font"
require_relative "sdl2/sound"
require_relative "sdl2/music"
require_relative "sdl2/audio_stream"
require_relative "sdl2/gamepad"

# Tk bridge (embeds SDL2 surface into a Tk frame)
require_relative "sdl2/viewport"
