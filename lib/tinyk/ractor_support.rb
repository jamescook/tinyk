# frozen_string_literal: true

# Ractor and background work support for TinyK applications.
#
# This module provides a unified API across Ruby versions:
# - Ruby 4.x: Uses Ractor::Port, Ractor.shareable_proc for true parallelism
# - Ruby 3.x: Ractor mode NOT supported (falls back to thread mode)
# - Thread fallback: Always available, works everywhere
#
# The implementation is selected automatically based on Ruby version.

require_relative 'background_thread'

if Ractor.respond_to?(:shareable_proc)
  require_relative 'background_ractor4x'
end

module TinyK

  # Unified background work API.
  #
  # Creates background work with the specified mode.
  # Mode :ractor uses true parallel execution (Ruby 4.x+ only).
  # Mode :thread uses traditional threading (GVL limited but always works).
  #
  # Configuration (module-level):
  #   TinyK::BackgroundWork.poll_ms = 16          # UI poll interval (default 16ms)
  #   TinyK::BackgroundWork.drop_intermediate = true  # Drop intermediate progress values
  #   TinyK::BackgroundWork.abort_on_error = false    # Raise vs warn on ractor errors
  #
  # Example:
  #   task = TinyK::BackgroundWork.new(app, data, mode: :thread) do |t, d|
  #     d.each { |item| t.yield(process(item)) }
  #   end.on_progress { |r| update_ui(r) }
  #
  class BackgroundWork
    # Configuration
    class << self
      attr_accessor :poll_ms, :drop_intermediate, :abort_on_error
    end
    self.poll_ms = 16
    self.drop_intermediate = true
    self.abort_on_error = false

    # Feature flags
    RACTOR_SUPPORTED = Ractor.respond_to?(:shareable_proc)

    # Registry for background work modes
    @background_modes = {}

    def self.register_background_mode(name, klass)
      @background_modes[name.to_sym] = klass
    end

    def self.background_modes
      @background_modes
    end

    def self.background_mode_class(name)
      @background_modes[name.to_sym]
    end

    # Register built-in modes
    register_background_mode :thread, TinyK::BackgroundThread::BackgroundWork

    # Ractor mode only available on Ruby 4.x+
    if RACTOR_SUPPORTED
      register_background_mode :ractor, TinyK::BackgroundRactor4x::BackgroundWork
    end

    attr_accessor :name

    def initialize(app, data, mode: :thread, worker: nil, &block)
      impl_class = self.class.background_mode_class(mode)
      unless impl_class
        available = self.class.background_modes.keys.join(', ')
        raise ArgumentError, "Unknown mode: #{mode}. Available: #{available}"
      end

      @impl = impl_class.new(app, data, worker: worker, &block)
      @mode = mode
      @name = nil
    end

    def mode
      @mode
    end

    def done?
      @impl.done?
    end

    def paused?
      @impl.paused?
    end

    def on_progress(&block)
      @impl.on_progress(&block)
      self
    end

    def on_done(&block)
      @impl.on_done(&block)
      self
    end

    def on_message(&block)
      @impl.on_message(&block)
      self
    end

    def send_message(msg)
      @impl.send_message(msg)
      self
    end

    def pause
      @impl.pause
      self
    end

    def resume
      @impl.resume
      self
    end

    def stop
      @impl.stop
      self
    end

    def close
      @impl.close if @impl.respond_to?(:close)
      self
    end

    def start
      @impl.start
      self
    end
  end

  # Simple streaming API (no pause support, simpler interface)
  #
  # Example:
  #   TinyK::RactorStream.new(app, files) do |yielder, data|
  #     data.each { |f| yielder.yield(process(f)) }
  #   end.on_progress { |r| update_ui(r) }
  #     .on_done { puts "Done!" }
  #
  class RactorStream
    def initialize(app, data, &block)
      # Ruby 4.x: use Ractor with shareable_proc for true parallelism
      # Ruby 3.x: use threads (Ractor mode not supported)
      if BackgroundWork::RACTOR_SUPPORTED
        shareable_block = Ractor.shareable_proc(&block)
        wrapped_block = Ractor.shareable_proc do |task, d|
          yielder = StreamYielder.new(task)
          shareable_block.call(yielder, d)
        end
        @impl = TinyK::BackgroundRactor4x::BackgroundWork.new(app, data, &wrapped_block)
      else
        wrapped_block = proc do |task, d|
          yielder = StreamYielder.new(task)
          block.call(yielder, d)
        end
        @impl = TinyK::BackgroundThread::BackgroundWork.new(app, data, &wrapped_block)
      end
    end

    def on_progress(&block)
      @impl.on_progress(&block)
      self
    end

    def on_done(&block)
      @impl.on_done(&block)
      self
    end

    def cancel
      @impl.stop
    end

    # Adapter for old yielder API
    class StreamYielder
      def initialize(task)
        @task = task
      end

      def yield(value)
        @task.yield(value)
      end
    end
  end
end
