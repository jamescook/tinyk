# frozen_string_literal: true

module Teek
  module MGBA
    # Shared helpers for child windows (Settings, Save State Picker, ROM Info).
    #
    # Including classes must define a TOP constant and an @app instance variable.
    # Modal windows (grab focus) use show_window/hide_window. Non-modal windows
    # (like ROM Info) use show_window(modal: false)/hide_window(modal: false).
    module ChildWindow
      # Create and configure a toplevel window with standard boilerplate.
      # Hides the window at the end — call show_window to reveal it.
      #
      # @param title [String]
      # @param geometry [String, nil] e.g. '700x390'
      def build_toplevel(title, geometry: nil)
        top = self.class::TOP
        @app.command(:toplevel, top)
        @app.command(:wm, 'title', top, title)
        @app.command(:wm, 'geometry', top, geometry) if geometry
        @app.command(:wm, 'resizable', top, 0, 0)
        @app.command(:wm, 'transient', top, '.')
        @app.command(:wm, 'protocol', top, 'WM_DELETE_WINDOW', proc { hide })
        yield if block_given?
        @app.command(:wm, 'withdraw', top)
      end

      # Position this window to the right of the main application window.
      def position_near_parent
        top = self.class::TOP
        x = @app.command(:winfo, 'rootx', '.').to_i
        y = @app.command(:winfo, 'rooty', '.').to_i
        w = @app.command(:winfo, 'width', '.').to_i
        @app.command(:wm, 'geometry', top, "+#{x + w + 12}+#{y}")
      end

      # Reveal the window, optionally grabbing focus (modal).
      def show_window(modal: true)
        top = self.class::TOP
        position_near_parent
        @app.command(:wm, 'deiconify', top)
        @app.command(:raise, top)
        if modal
          @app.command(:grab, :set, top)
          @app.command(:focus, top)
        end
      end

      # Withdraw the window, release grab if modal, fire on_close callback.
      def hide_window(modal: true)
        top = self.class::TOP
        @app.command(:grab, :release, top) if modal
        @app.command(:wm, 'withdraw', top)
        @callbacks[:on_close]&.call if defined?(@callbacks)
      end
    end
  end
end
