# frozen_string_literal: true

# Persistent Tk worker process for fast test execution.
#
# Instead of spawning a new Ruby process for each test this class keeps a single Tk interpreter
# alive and resets state between tests. Trad-off is dealing with tests/code that mutate
# global state.
#
# Uses pipe-based IPC (no threads) to avoid Tk threading issues.
#
# Usage:
#   TinyK::TestWorker.start
#   result = TinyK::TestWorker.run_test("label = TkLabel.new(root); ...")
#   TinyK::TestWorker.stop

require 'stringio'
require 'fileutils'
require 'tmpdir'
require 'json'
require 'open3'

module TinyK; end
class TinyK::TestWorker
  SOCKET_DIR = File.join(Dir.tmpdir, 'tinyk_test_worker')
  PID_FILE = File.join(SOCKET_DIR, 'worker.pid')
  READY_FILE = File.join(SOCKET_DIR, 'ready')

  class << self
    def start
      return if running?

      FileUtils.mkdir_p(SOCKET_DIR)
      cleanup_stale_files

      # Build load path args
      load_paths = $LOAD_PATH.select { |p| p.include?(File.dirname(File.dirname(__FILE__))) }
      load_path_args = load_paths.flat_map { |p| ["-I", p] }

      # Spawn worker with pipes
      @stdin_w, @stdout_r, @stderr_r, @wait_thread = Open3.popen3(
        RbConfig.ruby, *load_path_args, __FILE__, 'server'
      )

      File.write(PID_FILE, @wait_thread.pid.to_s)

      # Wait for ready signal
      wait_for_ready
    end

    def stop
      return unless running?

      begin
        send_command('shutdown')
      rescue
        # Already dead
      end

      @stdin_w&.close
      @stdout_r&.close
      @stderr_r&.close
      @wait_thread&.value rescue nil

      @stdin_w = @stdout_r = @stderr_r = @wait_thread = nil
      cleanup_stale_files
    end

    # Default timeout for test execution (can be overridden via TK_TEST_TIMEOUT env var)
    DEFAULT_TIMEOUT = 60

    def run_test(code, pipe_capture: false, timeout: nil)
      start unless running?
      timeout ||= Integer(ENV['TK_TEST_TIMEOUT'] || DEFAULT_TIMEOUT)
      send_command('run', { code: code, pipe_capture: pipe_capture }, timeout: timeout)
    end

    def running?
      @wait_thread&.alive? && @stdin_w && !@stdin_w.closed?
    end

    private

    def send_command(cmd, data = nil, timeout: nil)
      msg = JSON.generate({ cmd: cmd, data: data })
      @stdin_w.puts(msg)
      @stdin_w.flush

      # Wait for response with timeout
      if timeout
        ready = IO.select([@stdout_r], nil, nil, timeout)
        unless ready
          # Kill the worker on timeout
          Process.kill('KILL', @wait_thread.pid) rescue nil
          raise "Test timed out after #{timeout}s"
        end
      end

      response = @stdout_r.gets
      unless response
        # Try to get error info
        err = @stderr_r.read_nonblock(4096) rescue "[no output]"
        err_text = "Worker died: #{err}"

        raise err_text
      end

      JSON.parse(response, symbolize_names: true)
    end

    def wait_for_ready(timeout: 10)
      deadline = Time.now + timeout

      until File.exist?(READY_FILE)
        raise "TinyK::TestWorker failed to start within #{timeout}s" if Time.now > deadline
        sleep 0.05
      end
    end

    def cleanup_stale_files
      File.unlink(PID_FILE) if File.exist?(PID_FILE)
      File.unlink(READY_FILE) if File.exist?(READY_FILE)
    end
  end

  # Server-side: runs in subprocess
  class Server
    def initialize
      require 'tinyk'
      @app = TinyK::App.new
      @test_count = 0
    end

    def run
      # Signal ready
      File.write(READY_FILE, '')

      # Main loop - read commands from stdin
      while (line = $stdin.gets)
        msg = JSON.parse(line, symbolize_names: true)

        result = case msg[:cmd]
        when 'run'
          data = msg[:data]
          run_test(data[:code], pipe_capture: data[:pipe_capture])
        when 'shutdown'
          # Write coverage BEFORE responding (parent closes pipes after response)
          # This must happen here, not in at_exit, because the parent process
          # closes pipes immediately after receiving the response.
          SimpleCov.result if ENV['COVERAGE'] && defined?(SimpleCov)
          shutdown
          break
        when 'ping'
          { pong: true }
        else
          { error: "Unknown command: #{msg[:cmd]}" }
        end

        $stdout.puts(JSON.generate(result))
        $stdout.flush
      end
    end

    def run_test(code, pipe_capture: false)
      @test_count += 1
      # Use instance variable to avoid shadowing by test code's local variables
      @_test_result = { success: true, stdout: "", stderr: "", test_number: @test_count }

      # Pipe-based capture is needed for Ractor tests (StringIO isn't thread-safe)
      @pipe_capture = pipe_capture

      begin
        # Capture stdout/stderr
        old_stdout, old_stderr = $stdout, $stderr
        if pipe_capture
          @out_r, out_w = IO.pipe
          @err_r, err_w = IO.pipe
          out_w.sync = true
          err_w.sync = true
          $stdout = out_w
          $stderr = err_w
        else
          captured_out = StringIO.new
          captured_err = StringIO.new
          $stdout = captured_out
          $stderr = captured_err
        end

        # Make interp available to the test code
        b = binding
        b.local_variable_set(:app, @app)

        # Helper for display-dependent checks that may need time to settle
        # Retries until expected value is returned or timeout
        wait_for_display = ->(expected, timeout: 1.0, &block) {
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          result = nil
          while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
            @app.tcl_eval('update')
            result = block.call
            break if result.to_s == expected
            sleep 0.02
          end
          result
        }
        b.local_variable_set(:wait_for_display, wait_for_display)

        # Helper that waits until block returns truthy or timeout
        # Returns the truthy value or nil on timeout
        wait_until = ->(timeout: 1.0, &block) {
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          result = nil
          while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
            @app.tcl_eval('update')
            result = block.call
            break if result
            sleep 0.02
          end
          result
        }
        b.local_variable_set(:wait_until, wait_until)

        # TODO: Not yet working in TinyK — needs tkextlib/tkimg ported
        # Helper to capture screenshots for debugging test failures
        # Usage: capture_screenshot("my_test") or capture_screenshot("step1", window: some_widget)
        screenshot_dir = File.expand_path('../../screenshots/test', __FILE__)
        test_root = @app # TODO: screenshot helper needs rework for TinyK
        test_count = @test_count
        capture_screenshot = ->(name, window: nil) {
          begin
            win = window || test_root
            unless win
              STDERR.puts "Screenshot failed: no root window available"
              return
            end

            require 'tkextlib/tkimg/window'
            require 'tkextlib/tkimg/png'

            FileUtils.mkdir_p(screenshot_dir)
            @app.tcl_eval('update')

            path = File.join(screenshot_dir, "#{name}_#{test_count}.png")
            img = TkPhotoImage.new(:format => 'window', :data => win.path)
            img.write(path, :format => 'png')
            STDERR.puts "Screenshot saved: #{path}"
          rescue => e
            STDERR.puts "Screenshot failed: #{e.message}"
          end
        }
        b.local_variable_set(:capture_screenshot, capture_screenshot)

        # Execute the test code
        eval(code, b, "(test)", 1)

        if @pipe_capture
          $stdout.close
          $stderr.close
          @_test_result[:stdout] = @out_r.read
          @_test_result[:stderr] = @err_r.read
        else
          @_test_result[:stdout] = captured_out.string
          @_test_result[:stderr] = captured_err.string
        end
      rescue Exception => e
        @_test_result[:success] = false
        @_test_result[:error_class] = e.class.name
        @_test_result[:error_message] = e.message
        @_test_result[:backtrace] = e.backtrace || []
        if @pipe_capture
          $stdout.close rescue nil
          $stderr.close rescue nil
          @_test_result[:stdout] = @out_r.read rescue ""
          @_test_result[:stderr] = @err_r.read rescue ""
        else
          @_test_result[:stdout] = captured_out.string if captured_out
          @_test_result[:stderr] = captured_err.string if captured_err
        end

        # Extract code context if error is in eval'd code
        if e.backtrace&.first&.start_with?('(test):')
          line_match = e.backtrace.first.match(/\(test\):(\d+)/)
          if line_match
            line_num = line_match[1].to_i
            code_lines = code.lines
            start_line = [line_num - 3, 0].max
            end_line = [line_num + 1, code_lines.size - 1].min
            context_lines = (start_line..end_line).map do |i|
              prefix = (i + 1 == line_num) ? ">>>" : "   "
              "#{prefix} #{i + 1}: #{code_lines[i]}"
            end
            @_test_result[:code_context] = context_lines.join
          end
        end
      ensure
        $stdout, $stderr = old_stdout, old_stderr
        if @pipe_capture
          @out_r&.close rescue nil
          @err_r&.close rescue nil
        end
        reset_tk_state!
      end

      @_test_result
    end

    def shutdown
      @app.tcl_eval('destroy .') rescue nil
      { shutdown: true }
    end

    private

    def reset_tk_state!
      # Destroy all children of root, then withdraw
      children = @app.tcl_eval('winfo children .').split
      children.each do |child|
        @app.tcl_eval("destroy #{child}") rescue nil
      end
      @app.tcl_eval('wm withdraw .')

      # Reset WM properties (these persist between tests)
      @app.tcl_eval('wm minsize . 1 1')
      @app.tcl_eval('wm maxsize . 0 0') rescue nil
      @app.tcl_eval('wm geometry . ""')

      reset_grid_config!
    end

    # Reset grid geometry manager state for a widget.
    # Column/row weights, minsize, pad, uniform settings persist after
    # children are removed, so we must explicitly clear them.
    def reset_grid_config!(path = '.')
      result = @app.tcl_eval("grid size #{path}")
      cols, rows = result.to_s.split.map(&:to_i)
      return if cols == 0 && rows == 0

      @app.tcl_eval("grid anchor #{path} nw")
      @app.tcl_eval("grid propagate #{path} 1")

      cols.times do |c|
        @app.tcl_eval("grid columnconfigure #{path} #{c} -weight 0 -minsize 0 -pad 0 -uniform {}")
      end

      rows.times do |r|
        @app.tcl_eval("grid rowconfigure #{path} #{r} -weight 0 -minsize 0 -pad 0 -uniform {}")
      end
    end
  end
end

# Run as server if executed with 'server' argument
if ARGV[0] == 'server'
  require 'open3'

  # Set up SimpleCov for coverage collection in the worker process
  if ENV['COVERAGE']
    require 'simplecov'
    require_relative 'simplecov_config'

    coverage_name = ENV['COVERAGE_NAME'] || 'default'
    SimpleCov.coverage_dir "#{SimpleCovConfig::PROJECT_ROOT}/coverage/results/#{coverage_name}_worker_#{Process.pid}"
    SimpleCov.command_name "tk_worker:#{coverage_name}:#{Process.pid}"
    SimpleCov.print_error_status = false
    SimpleCov.formatter SimpleCov::Formatter::SimpleFormatter

    SimpleCov.start do
      SimpleCovConfig.apply_filters(self)
      track_files "#{SimpleCovConfig::PROJECT_ROOT}/lib/**/*.rb"
    end
  end

  FileUtils.mkdir_p(TinyK::TestWorker::SOCKET_DIR)
  TinyK::TestWorker::Server.new.run
end
