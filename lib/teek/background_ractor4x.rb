# frozen_string_literal: true

module Teek

  # Ruby 4.x Ractor-based background work for Teek applications.
  # Uses Ractor::Port for streaming and Ractor.shareable_proc for blocks.
  # Uses thread-inside-ractor pattern for non-blocking message handling.
  module BackgroundRactor4x
    # Poll interval when paused (slower to save CPU)
    PAUSED_POLL_MS = 500

    # Why Ractor mode requires Ruby 4.x:
    #
    # Ruby 3.x Ractor support was attempted but abandoned due to fundamental issues:
    #
    # | Aspect                      | 3.x Problem                  | 4.x Solution                  |
    # |-----------------------------|------------------------------|-------------------------------|
    # | Output mechanism            | Ractor.yield BLOCKS caller   | Port.send is non-blocking     |
    # | Block support               | Cannot pass blocks to Ractor | Ractor.shareable_proc works   |
    # | close_incoming after yield  | Bug: doesn't wake threads    | Works correctly               |
    # | Orphaned threads on exit    | Hangs in rb_ractor_terminate | Exits cleanly                 |
    # | Non-blocking receive        | No API exists                | Ractor::Port with select      |
    #
    # What we tried on Ruby 3.x (all failed):
    #
    # 1. Yielder thread pattern: Separate thread does blocking Ractor.yield while
    #    worker pushes to a Queue. Works but adds complexity and has shutdown bugs.
    #
    # 2. Timeout-based polling for messages: Create thread, call Ractor.receive,
    #    join with timeout, kill thread. Very expensive (~10ms per check) and
    #    causes severe performance degradation.
    #
    # 3. Long-lived receiver thread: One thread continuously receives and pushes
    #    to Queue. UI hangs due to thread interaction issues.
    #
    # 4. IO.pipe for signaling: Considered but IO objects aren't Ractor-shareable.
    #
    # The fundamental problem is Ruby 3.x has no non-blocking Ractor.receive,
    # and all workarounds either kill performance or cause hangs/crashes.
    #
    # On Ruby 3.x, use :thread mode instead - it works reliably with the GVL.
    # This 4.x implementation is simpler because Ruby 4.x Ractors just work.

    # Ractor-based background work using Ruby 4.x Ractor::Port for streaming
    # and Ractor.shareable_proc for blocks.
    #
    # @example Block form
    #   work = BackgroundWork.new(app, urls) do |task, data|
    #     data.each { |url| task.yield(fetch(url)) }
    #   end
    #   work.on_progress { |r| update_ui(r) }.on_done { puts "Done!" }
    #
    # @example Worker class form
    #   work = BackgroundWork.new(app, data, worker: MyWorker)
    #   work.on_progress { |r| update_ui(r) }
    class BackgroundWork
      # @param app [Teek::App] the application instance (for +after+ scheduling)
      # @param data [Object] data passed to the worker block/class
      # @param worker [Class, nil] optional worker class (must respond to +#call(task, data)+)
      # @yield [task, data] block executed inside a Ractor
      # @yieldparam task [TaskContext] context for yielding results and checking messages
      # @yieldparam data [Object] the data passed to the constructor
      def initialize(app, data, worker: nil, &block)
        @app = app
        @data = data
        @work_block = block || (worker && proc { |t, d| worker.new.call(t, d) })
        @callbacks = { progress: nil, done: nil, message: nil }
        @started = false
        @done = false
        @paused = false

        # Communication
        @output_queue = Thread::Queue.new
        @control_port = nil  # Set by worker, received back
        @pending_messages = []  # Queued until control_port ready
        @worker_ractor = nil
        @bridge_thread = nil
      end

      # Register a callback for progress updates from the worker.
      # Auto-starts the task if not already started.
      # @yield [value] called on the main thread each time the worker yields a result
      # @return [self]
      def on_progress(&block)
        @callbacks[:progress] = block
        maybe_start
        self
      end

      # Register a callback for when the worker finishes.
      # Auto-starts the task if not already started.
      # @yield called on the main thread when the worker completes
      # @return [self]
      def on_done(&block)
        @callbacks[:done] = block
        maybe_start
        self
      end

      # Register a callback for custom messages sent by the worker via
      # {TaskContext#send_message}.
      # @yield [msg] called on the main thread with the message
      # @return [self]
      def on_message(&block)
        @callbacks[:message] = block
        self
      end

      # Send a message to the worker. The worker can receive it via
      # {TaskContext#check_message} or {TaskContext#wait_message}.
      # Messages are queued if the worker's control port isn't ready yet.
      # @param msg [Object] any Ractor-shareable value
      # @return [self]
      def send_message(msg)
        if @control_port
          begin
            @control_port.send(msg)
          rescue Ractor::ClosedError
            # Port already closed, task is done - ignore
          end
        else
          @pending_messages << msg
        end
        self
      end

      # Pause the worker. The worker will block on the next {TaskContext#yield}
      # or {TaskContext#check_pause} until {#resume} is called.
      # @return [self]
      def pause
        @paused = true
        send_message(:pause)
        self
      end

      # Resume a paused worker.
      # @return [self]
      def resume
        @paused = false
        send_message(:resume)
        self
      end

      # Request the worker to stop. Raises +StopIteration+ inside the worker
      # on the next {TaskContext#check_message} or {TaskContext#yield}.
      # @return [self]
      def stop
        send_message(:stop)
        self
      end

      # Force-close the Ractor and all associated resources.
      # @return [self]
      def close
        @done = true
        # Send stop to let the worker terminate itself — Ruby 4.x doesn't
        # allow closing a Ractor from outside. The message thread will
        # raise StopIteration on the Ractor's main thread, which triggers
        # the rescue block that sends [:done] to the output port and exits
        # the Ractor cleanly.
        begin
          @control_port&.send(:stop)
        rescue Ractor::ClosedError
          # Already closed
        end
        @control_port = nil
        # Wait for the bridge thread to receive [:done] and exit. Without
        # this, the zombie bridge thread blocks subsequent operations on
        # Windows (Ractor::Port#receive holds the GVL).
        @bridge_thread&.join(2)
        self
      end

      # Explicitly start the background work. Called automatically by
      # {#on_progress} and {#on_done}; only needed when using {#on_message}
      # alone.
      # @return [self]
      def start
        return self if @started
        @started = true

        # Wrap in isolated proc for Ractor sharing. The block can only access
        # its parameters (task, data), not outer-scope variables.
        isolation_error = false
        begin
          shareable_block = Ractor.shareable_proc(&@work_block)
        rescue Ractor::IsolationError
          isolation_error = true
        end
        if isolation_error
          raise Ractor::IsolationError,
            "Background work block must not reference outside variables (including `app`). " \
            "Use t.yield() to send results to on_progress, which runs on the main thread."
        end

        start_ractor(shareable_block)
        start_polling
        self
      end

      # @return [Boolean] whether the worker has finished
      def done?
        @done
      end

      # @return [Boolean] whether the worker is paused
      def paused?
        @paused
      end

      private

      def maybe_start
        start unless @started
      end

      def start_ractor(shareable_block)
        data = @data
        output_port = Ractor::Port.new

        @worker_ractor = Ractor.new(data, output_port, shareable_block) do |d, out, blk|
          # Worker creates its own control port for receiving messages
          control_port = Ractor::Port.new
          msg_queue = Thread::Queue.new

          # Send control port back to main thread
          out.send([:control_port, control_port])

          # Background thread receives from control port, forwards to queue.
          # On :stop, interrupts the main Ractor thread with StopIteration
          # (the main block may never call check_message) and signals the
          # bridge thread via [:done] on the output port.
          main_thread = Thread.current
          Thread.new do
            loop do
              begin
                msg = control_port.receive
                msg_queue << msg
                if msg == :stop
                  main_thread.raise(StopIteration)
                  break
                end
              rescue Ractor::ClosedError
                break
              end
            end
          end

          Thread.current[:tk_in_background_work] = true
          task = TaskContext.new(out, msg_queue)
          begin
            blk.call(task, d)
            out.send([:done])
          rescue StopIteration
            out.send([:done])
          rescue => e
            out.send([:error, "#{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"])
            out.send([:done])
          end
        end

        # Bridge thread: Port.receive -> Queue
        @bridge_thread = Thread.new do
          loop do
            begin
              result = output_port.receive
              if result.is_a?(Array) && result[0] == :control_port
                @control_port = result[1]
                @pending_messages.each { |m| @control_port.send(m) }
                @pending_messages.clear
              else
                @output_queue << result
                break if result[0] == :done
              end
            rescue Ractor::ClosedError
              @output_queue << [:done]
              break
            end
          end
        end
      end

      def start_polling
        @dropped_count = 0
        @choke_warned = false

        poll = proc do
          next if @done

          drop_intermediate = Teek::BackgroundWork.drop_intermediate
          # Drain queue. If drop_intermediate, only use LATEST progress value.
          # This prevents UI choking when worker yields faster than UI polls.
          last_progress = nil
          results_this_poll = 0
          until @output_queue.empty?
            msg = @output_queue.pop(true)
            type, value = msg
            case type
            when :done
              @done = true
              @control_port = nil  # Clear to prevent send to closed port
              # Call progress with final value before done callback
              @callbacks[:progress]&.call(last_progress) if last_progress
              last_progress = nil  # Prevent duplicate call after loop
              warn_if_choked
              @callbacks[:done]&.call
              break
            when :result
              results_this_poll += 1
              if drop_intermediate
                last_progress = value  # Keep only latest
              else
                @callbacks[:progress]&.call(value)  # Call for every value
              end
            when :message
              @callbacks[:message]&.call(value)
            when :error
              if Teek::BackgroundWork.abort_on_error
                raise RuntimeError, "[Ractor] Background work error: #{value}"
              else
                warn "[Ractor] Background work error: #{value}"
              end
            end
          end

          # Track dropped messages (all but the last one we processed)
          if drop_intermediate && results_this_poll > 1
            dropped = results_this_poll - 1
            @dropped_count += dropped
            warn_choke_start(dropped) unless @choke_warned
          end

          # Call progress callback once with latest value (only if dropping)
          @callbacks[:progress]&.call(last_progress) if drop_intermediate && last_progress && !@done

          unless @done
            # Use slower polling when paused to save CPU
            interval = @paused ? PAUSED_POLL_MS : Teek::BackgroundWork.poll_ms
            @app.after(interval, &poll)
          end
        end

        @app.after(0, &poll)
      end

      def warn_choke_start(dropped)
        @choke_warned = true
        warn "[Teek::BackgroundWork] UI choking: worker yielding faster than UI can poll. " \
             "#{dropped} progress values dropped this cycle. " \
             "Consider yielding less frequently or increasing Tk.background_work_poll_ms."
      end

      def warn_if_choked
        return unless @dropped_count > 0
        warn "[Teek::BackgroundWork] Total #{@dropped_count} progress values dropped during task. " \
             "Only latest values were shown to UI."
      end

      # Context object passed to the worker block inside the Ractor.
      # Provides methods for yielding results, sending/receiving messages,
      # and responding to pause/stop signals.
      class TaskContext
        # @api private
        def initialize(output_port, msg_queue)
          @output_port = output_port
          @msg_queue = msg_queue
          @paused = false
        end

        # Send a result to the main thread. Blocks while paused.
        # The value arrives in the {BackgroundWork#on_progress} callback.
        # @param value [Object] any Ractor-shareable value
        def yield(value)
          check_pause_loop
          @output_port.send([:result, value])
        end

        # Non-blocking check for a message from the main thread.
        # Handles built-in control messages (+:pause+, +:resume+, +:stop+)
        # automatically; +:stop+ raises +StopIteration+.
        # @return [Object, nil] the message, or +nil+ if none pending
        def check_message
          return nil if @msg_queue.empty?
          msg = @msg_queue.pop(true)
          handle_control_message(msg)
          msg
        rescue ThreadError
          nil
        end

        # Blocking wait for the next message from the main thread.
        # Handles control messages automatically.
        # @return [Object] the message
        def wait_message
          msg = @msg_queue.pop
          handle_control_message(msg)
          msg
        end

        # Send a custom message back to the main thread.
        # Arrives in the {BackgroundWork#on_message} callback.
        # @param msg [Object] any Ractor-shareable value
        def send_message(msg)
          @output_port.send([:message, msg])
        end

        # Block while paused, returning immediately if not paused.
        # Call this periodically in long-running loops to honor pause requests.
        def check_pause
          check_pause_loop
        end

        private

        def handle_control_message(msg)
          case msg
          when :pause
            @paused = true
          when :resume
            @paused = false
          when :stop
            raise StopIteration
          end
        end

        def check_pause_loop
          while @paused
            msg = @msg_queue.pop
            handle_control_message(msg)
          end
        end
      end
    end
  end
end
