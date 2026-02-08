# frozen_string_literal: true
#
# TeekDemo - Helper module for automated sample testing and recording
#
# Two independent modes:
#   - Test mode (TK_READY_PORT): Quick verification that sample loads/runs
#   - Record mode (TK_RECORD): Video capture with longer delays
#
# Usage:
#   require_relative '../lib/teek/demo_support'
#
#   app = Teek::App.new
#   TeekDemo.app = app
#
#   if TeekDemo.active?
#     TeekDemo.on_visible {
#       do_something
#       app.after(TeekDemo.delay(test: 200, record: 500)) {
#         TeekDemo.finish
#       }
#     }
#   end
#
require 'socket'

module TeekDemo
  class << self
    attr_accessor :app

    def testing?
      !!ENV['TK_READY_PORT']
    end

    def recording?
      !!ENV['TK_RECORD']
    end

    def active?
      testing? || recording?
    end

    # Get appropriate delay for current mode
    def delay(test: 100, record: 1000)
      recording? ? record : test
    end

    # Run block once when window becomes visible.
    # @param window [String] Tcl path of the window to watch (default: ".")
    def on_visible(window: '.', timeout: 60, &block)
      return unless active?
      raise ArgumentError, "block required" unless block
      raise "TeekDemo.app not set" unless app

      @demo_started = false
      app.bind(window, 'Visibility') do
        next if @demo_started
        @demo_started = true

        signal_recording_ready(window: window) if recording?

        # Safety timeout
        app.after(timeout * 1000) { finish }

        app.after(50) { block.call }
      end
    end

    # Run block once when event loop is idle.
    # Use when window is already created before binding can be set up.
    def after_idle(timeout: 60, &block)
      return unless active?
      raise ArgumentError, "block required" unless block
      raise "TeekDemo.app not set" unless app

      @demo_started = false
      app.after_idle {
        next if @demo_started
        @demo_started = true

        signal_recording_ready if recording?

        app.after(timeout * 1000) { finish }

        block.call
      }
    end

    # Signal recording harness that window is visible and ready to record.
    # Polls until geometry is valid, then signals via TCP.
    def signal_recording_ready(window: '.')
      return unless (port = ENV['TK_STOP_PORT'])
      return if @_recording_ready_sent

      try_signal = proc do
        app.tcl_eval('update idletasks')
        width = app.tcl_eval("winfo width #{window}").to_i
        height = app.tcl_eval("winfo height #{window}").to_i

        if width >= 10 && height >= 10
          @_recording_ready_sent = true
          @_initial_geometry = [width, height]

          begin
            sock = TCPSocket.new('127.0.0.1', port.to_i)
            sock.write("R:#{width}x#{height}")
            sock.close
          rescue StandardError => e
            $stderr.puts "TeekDemo: signal error: #{e.message}"
          end
        else
          app.after(10) { try_signal.call }
        end
      end

      try_signal.call
    end

    # Signal test harness that sample is ready (without exiting)
    def signal_ready
      $stdout.flush
      if (port = ENV.delete('TK_READY_PORT'))
        begin
          TCPSocket.new('127.0.0.1', port.to_i).close
        rescue StandardError
        end
      end
    end

    # Signal completion and exit cleanly.
    # Handles TK_READY_PORT (test) and TK_STOP_PORT (record).
    def finish
      signal_ready

      if (port = ENV['TK_STOP_PORT'])
        Thread.new do
          begin
            sock = TCPSocket.new('127.0.0.1', port.to_i)
            sock.read(1)  # Block until harness sends byte or closes
            sock.close
          rescue StandardError
          end
          app.after(0) { app.tcl_eval('destroy .') }
        end
      else
        app.after(0) { app.tcl_eval('destroy .') }
      end
    end
  end
end
