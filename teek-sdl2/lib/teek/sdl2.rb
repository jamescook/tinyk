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
require_relative "sdl2/gamepad"

# Tk bridge (embeds SDL2 surface into a Tk frame)
require_relative "sdl2/viewport"
