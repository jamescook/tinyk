# frozen_string_literal: true

require 'set'

module Teek
  module SDL2
    # An SDL2-accelerated rendering surface embedded in a Tk frame.
    #
    # Viewport creates a Tk frame, obtains its native window handle via
    # the Tk C API, then embeds an SDL2 renderer inside it using
    # +SDL_CreateWindowFrom+. All drawing goes through SDL2 with GPU
    # acceleration — no Tk involvement in the rendering path.
    #
    # Keyboard input is tracked automatically via Tk bindings so you can
    # poll key state with {#key_down?} in a game loop.
    #
    # @example Create a viewport and draw a red rectangle
    #   viewport = Teek::SDL2::Viewport.new(app, width: 800, height: 600)
    #   viewport.pack(fill: :both, expand: true)
    #
    #   viewport.render do |r|
    #     r.clear(0, 0, 0)
    #     r.fill_rect(10, 10, 100, 50, 255, 0, 0)
    #   end
    #
    # @example Poll keyboard input
    #   if viewport.key_down?('left')
    #     player_x -= speed
    #   end
    #
    # @see Renderer
    class Viewport
      # @return [Teek::App] the Teek application
      attr_reader :app

      # @return [Teek::Widget] the underlying Tk frame
      attr_reader :frame

      # @return [Teek::SDL2::Renderer] the SDL2 renderer
      attr_reader :renderer

      # @return [Set<String>] currently held key names (lowercase keysyms)
      attr_reader :keys_down

      # @param app [Teek::App] the Teek application
      # @param parent [Teek::Widget, String, nil] parent widget (nil for root)
      # @param width [Integer] initial width in pixels
      # @param height [Integer] initial height in pixels
      # @param vsync [Boolean] enable VSync (default: true). Disable for
      #   applications that manage their own frame pacing (e.g. emulators).
      def initialize(app, parent: nil, width: 640, height: 480, vsync: true)
        @app = app
        @destroyed = false

        # Create a Tk frame to host the SDL2 window
        @frame = app.create_widget('frame', parent: parent,
                                   width: width, height: height)

        # Pack with fixed size so the frame is managed, then force a
        # full update. On X11, update_idletasks alone isn't enough —
        # the window must process MapNotify to be usable by SDL2.
        @frame.pack
        app.tcl_eval('update')

        # Get platform-native window handle via Tk C API
        # (macOS: NSWindow*, X11: Window ID, Windows: HWND)
        #
        # NOTE: On macOS, Tk_MacOSXGetNSWindowForDrawable returns the NSWindow
        # for the entire Tk toplevel, not just this frame. SDL_CreateWindowFrom
        # therefore creates a renderer that covers the whole window. Tk widgets
        # packed alongside the viewport will be painted over by SDL2 rendering.
        # On X11 each frame has its own X Window, so embedding is frame-scoped.
        # Workaround on macOS: use SDL2_ttf to draw overlay text on the surface
        # rather than Tk widgets.
        handle = app.interp.native_window_handle(@frame.path)

        # Create SDL2 renderer embedded in the frame (Layer 2 → Layer 1)
        @renderer = Teek::SDL2.create_renderer_from_handle(handle, vsync)

        # Register SDL2 event source if this is the first viewport
        Teek::SDL2.register_event_source

        # Key state tracking for game-loop polling
        @keys_down = Set.new
        @frame.bind('KeyPress', :keysym) { |k| @keys_down.add(k.downcase) }
        @frame.bind('KeyRelease', :keysym) { |k| @keys_down.delete(k.downcase) }

        # Click-to-focus: Tk frames must have focus to receive key events
        @frame.bind('ButtonPress-1') { focus }

        # Bind cleanup on frame destroy
        @frame.bind('<Destroy>') { _on_destroy }

        # Track viewport count for event source lifecycle
        Teek::SDL2._viewports << self
      end

      # Draw with the renderer in a block, auto-presenting at the end.
      #
      # @yield [renderer] the SDL2 renderer for this viewport
      # @yieldparam renderer [Teek::SDL2::Renderer]
      # @return [self]
      # @raise [Teek::SDL2::Error] if the viewport has been destroyed
      #
      # @example
      #   viewport.render do |r|
      #     r.clear(0, 0, 0)
      #     r.fill_rect(10, 10, 100, 50, 255, 0, 0)
      #   end
      def render(&block)
        raise Teek::SDL2::Error, "viewport has been destroyed" if @destroyed
        @renderer.render(&block)
      end

      # Pack the viewport into its parent using Tk's pack geometry manager.
      #
      # @param kwargs options passed to the Tk +pack+ command
      # @return [self]
      def pack(**kwargs)
        @frame.pack(**kwargs)
        self
      end

      # Grid the viewport into its parent using Tk's grid geometry manager.
      #
      # @param kwargs options passed to the Tk +grid+ command
      # @return [self]
      def grid(**kwargs)
        @frame.grid(**kwargs)
        self
      end

      # Check if a key is currently held down. Uses Tk keysym names (lowercase).
      #
      # @param keysym [String, Symbol] Tk keysym name (e.g. +'left'+, +'space'+, +'a'+)
      # @return [Boolean]
      #
      # @example
      #   viewport.key_down?('left')   # arrow key
      #   viewport.key_down?('space')  # spacebar
      #   viewport.key_down?('a')      # letter key
      def key_down?(keysym)
        @keys_down.include?(keysym.to_s.downcase)
      end

      # Give this viewport keyboard focus so it receives key events.
      #
      # @return [void]
      def focus
        @app.tcl_eval("focus #{@frame.path}")
      end

      # Bind a Tk event on the viewport frame.
      #
      # Automatically chains with internal behavior (key tracking,
      # click-to-focus) so user callbacks don't clobber {#key_down?}.
      #
      # @param event [String] Tk event name (e.g. +'KeyPress'+, +'ButtonPress-1'+)
      # @param subs [Array<Symbol, String>] Tk substitution codes
      # @yield called when the event fires
      # @return [void]
      def bind(event, *subs, &block)
        case event.to_s
        when 'KeyPress'
          @frame.bind(event, *subs) do |*args|
            @keys_down.add(args.first.to_s.downcase) if args.first
            block&.call(*args)
          end
        when 'KeyRelease'
          @frame.bind(event, *subs) do |*args|
            @keys_down.delete(args.first.to_s.downcase) if args.first
            block&.call(*args)
          end
        when /ButtonPress/
          @frame.bind(event, *subs) do |*args|
            focus
            block&.call(*args)
          end
        else
          @frame.bind(event, *subs, &block)
        end
      end

      # Destroy the viewport, its SDL2 renderer, and the Tk frame.
      #
      # @return [void]
      def destroy
        return if @destroyed
        @renderer.destroy unless @renderer.destroyed?
        @frame.destroy if @frame.exist?
        _cleanup
      end

      # @return [Boolean] whether this viewport has been destroyed
      def destroyed?
        @destroyed
      end

      def inspect
        "#<Teek::SDL2::Viewport #{@frame.path} #{destroyed? ? 'DESTROYED' : 'active'}>"
      end

      private

      def _on_destroy
        return if @destroyed
        @renderer.destroy unless @renderer.destroyed?
        _cleanup
      end

      def _cleanup
        @destroyed = true
        Teek::SDL2._viewports.delete(self)

        # Unregister event source when last viewport is gone
        if Teek::SDL2._viewports.empty?
          Teek::SDL2.unregister_event_source
        end
      end
    end

    # Internal viewport tracking for event source lifecycle
    @_viewports = []

    class << self
      # @api private
      def _viewports
        @_viewports
      end
    end
  end
end
