# frozen_string_literal: true

# Thread-based background work for TinyK applications.
# Always available, works on all Ruby versions.
# Uses GVL so not true parallelism, but keeps UI responsive.

module TinyK
  module BackgroundThread

    # High-level API for background work with messaging support.
    #
    # Example:
    #   task = TinyK::BackgroundThread::BackgroundWork.new(app, data) do |t|
    #     data.each do |item|
    #       break if t.check_message == :stop
    #       t.yield(process(item))
    #     end
    #   end.on_progress { |r| update_ui(r) }
    #     .on_done { puts "Done!" }
    #
    #   task.send_message(:pause)
    #   task.send_message(:resume)
    #   task.stop
    #
    # Poll interval when paused (slower to save CPU)
    PAUSED_POLL_MS = 10000

    class BackgroundWork
      def initialize(app, data, worker: nil, &block)
        # Thread mode supports both block and worker class for API consistency
        @app = app
        @data = data
        @work_block = block || (worker && proc { |t, d| worker.new.call(t, d) })
        @callbacks = { progress: nil, done: nil, message: nil }
        @started = false
        @done = false
        @paused = false

        # Communication channels
        @output_queue = Thread::Queue.new    # Worker -> Main
        @message_queue = Thread::Queue.new   # Main -> Worker
        @worker_thread = nil
      end

      def on_progress(&block)
        @callbacks[:progress] = block
        maybe_start
        self
      end

      def on_done(&block)
        @callbacks[:done] = block
        maybe_start
        self
      end

      # Called when worker sends a non-result message back
      def on_message(&block)
        @callbacks[:message] = block
        self
      end

      # Send a message to the worker (pause, resume, stop, or custom)
      def send_message(msg)
        @message_queue << msg
        self
      end

      # Convenience methods
      def pause
        @paused = true
        send_message(:pause)
        self
      end

      def resume
        @paused = false
        send_message(:resume)
        # Restart polling (was stopped when paused)
        @app.after(0, &@poll_proc) if @poll_proc && !@done
        self
      end

      def stop
        send_message(:stop)
        self
      end

      def close
        @done = true
        @worker_thread&.kill
        self
      end

      def done?
        @done
      end

      def paused?
        @paused
      end

      def start
        return self if @started
        @started = true

        @worker_thread = Thread.new do
          Thread.current[:tk_in_background_work] = true
          task = TaskContext.new(@output_queue, @message_queue)
          begin
            @work_block.call(task, @data)
            @output_queue << [:done]
          rescue StopIteration
            @output_queue << [:done]
          rescue => e
            @output_queue << [:error, "#{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"]
            @output_queue << [:done]
          end
        end

        start_polling
        self
      end

      private

      def maybe_start
        start unless @started
      end

      def start_polling
        @dropped_count = 0
        @choke_warned = false

        @poll_proc = proc do
          next if @done

          drop_intermediate = TinyK::BackgroundWork.drop_intermediate
          # Drain queue. If drop_intermediate, only use LATEST progress value.
          # This prevents UI choking when worker yields faster than UI polls.
          last_progress = nil
          results_this_poll = 0
          begin
            while (msg = @output_queue.pop(true))
              type, value = msg
              case type
              when :done
                @done = true
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
                warn "[Thread] Background work error: #{value}"
              end
            end
          rescue ThreadError
            # Queue empty
          end

          # Track dropped messages (all but the last one we processed)
          if drop_intermediate && results_this_poll > 1
            dropped = results_this_poll - 1
            @dropped_count += dropped
            warn_choke_start(dropped) unless @choke_warned
          end

          # Call progress callback once with latest value (only if dropping)
          @callbacks[:progress]&.call(last_progress) if drop_intermediate && last_progress && !@done

          unless @done || @paused
            @app.after(TinyK::BackgroundWork.poll_ms, &@poll_proc)
          end
        end

        @app.after(0, &@poll_proc)
      end

      def warn_choke_start(dropped)
        @choke_warned = true
        warn "[TinyK::BackgroundWork] UI choking: worker yielding faster than UI can poll. " \
             "#{dropped} progress values dropped this cycle. " \
             "Consider yielding less frequently or increasing Tk.background_work_poll_ms."
      end

      def warn_if_choked
        return unless @dropped_count > 0
        warn "[TinyK::BackgroundWork] Total #{@dropped_count} progress values dropped during task. " \
             "Only latest values were shown to UI."
      end

      # Context passed to the work block
      class TaskContext
        def initialize(output_queue, message_queue)
          @output_queue = output_queue
          @message_queue = message_queue
          @paused = false
        end

        # Yield a result to the main thread.
        # Calls Thread.pass to give main thread a chance to process events.
        def yield(value)
          @output_queue << [:result, value]
          Thread.pass
        end

        # Non-blocking check for messages from main thread.
        # Returns the message or nil if none.
        def check_message
          msg = @message_queue.pop(true)
          handle_control_message(msg)
          msg
        rescue ThreadError
          nil
        end

        # Blocking wait for next message
        def wait_message
          msg = @message_queue.pop
          handle_control_message(msg)
          msg
        end

        # Send a message back to main thread (not a result)
        def send_message(msg)
          @output_queue << [:message, msg]
        end

        # Check pause state, blocking if paused
        def check_pause
          # First drain any pending messages (non-blocking)
          loop do
            msg = @message_queue.pop(true)
            handle_control_message(msg)
          rescue ThreadError
            break  # Queue empty
          end

          # Then block while paused
          while @paused
            msg = @message_queue.pop  # Blocking wait
            handle_control_message(msg)
          end
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
      end
    end
  end
end
