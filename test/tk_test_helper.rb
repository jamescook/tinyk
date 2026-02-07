# frozen_string_literal: true

require 'method_source'
require 'socket'
require_relative 'simplecov_config'

# Helper for running Tk tests in isolated subprocesses.
#
# Why subprocesses? Tk's interpreter is a singleton - once you call
# root.destroy, the Tk application is terminated and cannot be recreated
# in the same process. This is by design in Tcl/Tk:
#
#   - Tk_Init can only be called once per interpreter
#   - Destroying "." terminates the Tk application
#   - There's no Tk_Reinit or way to recreate the main window
#
# See: https://www.tcl-lang.org/man/tcl8.5/TkLib/Tk_Init.htm
#      https://www.tcl-lang.org/man/tcl8.6/TkCmd/destroy.htm
#
# We spawn a fresh Ruby process for each test to get a clean Tk interpreter.

require 'open3'
require 'timeout'

module TinyKTestHelper
  # Project root for absolute paths in subprocesses
  PROJECT_ROOT = SimpleCovConfig::PROJECT_ROOT

  # SimpleCov preamble injected into subprocess code for coverage merging
  # Only runs if ENV['COVERAGE'] is set
  #
  # Each subprocess writes to its own directory to avoid race conditions.
  # Directory is named <COVERAGE_NAME>_sub_<PID> so collation can find them all.
  def self.simplecov_preamble
    SimpleCovConfig.subprocess_preamble
  end

  # Runs Ruby code in a separate process with fresh Tk interpreter.
  # Returns [success, stdout, stderr, status]
  #
  # Example:
  #   success, out, err, status = tk_subprocess(<<~RUBY)
  #     require 'tk'
  #     root = TkRoot.new { withdraw }
  #     puts "it works"
  #     root.destroy
  #   RUBY
  #
  # Default timeout for subprocess tests (can be overridden via TK_TEST_TIMEOUT env var)
  DEFAULT_SUBPROCESS_TIMEOUT = 60

  def tk_subprocess(code, coverage: true, timeout: nil)
    timeout ||= Integer(ENV['TK_TEST_TIMEOUT'] || DEFAULT_SUBPROCESS_TIMEOUT)

    # Build load path from current process
    load_paths = $LOAD_PATH.select { |p| p.include?(File.dirname(__dir__)) }
    load_path_args = load_paths.flat_map { |p| ["-I", p] }

    # Prepend SimpleCov setup for coverage merging
    full_code = coverage ? "#{TinyKTestHelper.simplecov_preamble}\n#{code}" : code

    # Pass env vars to subprocess
    env = {}
    env['VISUAL'] = '1' if ENV['VISUAL']
    env['COVERAGE'] = '1' if ENV['COVERAGE']

    stdin, stdout, stderr, wait_thr = Open3.popen3(
      env, RbConfig.ruby, *load_path_args, "-e", full_code
    )
    stdin.close

    pid = wait_thr.pid
    deadline = Time.now + timeout
    status = nil

    # Poll for completion with timeout
    while Time.now < deadline
      if wait_thr.join(0.1)
        status = wait_thr.value
        break
      end
    end

    unless status
      # Timed out - kill the process
      Process.kill('KILL', pid) rescue nil
      wait_thr.join
      stdout.close
      stderr.close
      return [false, "", "Test timed out after #{timeout}s", nil]
    end

    out = stdout.read
    err = stderr.read
    stdout.close
    stderr.close

    [status.success?, out, err, status]
  end

  # Assertion wrapper for tk_subprocess.
  # Fails the test with captured output if the subprocess fails.
  #
  # The block should return a string of Ruby code to execute.
  #
  # Example:
  #   def test_something
  #     assert_tk_subprocess("should do the thing") do
  #       <<~RUBY
  #         require 'tk'
  #         root = TkRoot.new { withdraw }
  #         # test code...
  #         root.destroy
  #       RUBY
  #     end
  #   end
  #
  @_subprocess_warned = false

  def assert_tk_subprocess(message = "Tk subprocess test failed")
    unless TinyKTestHelper.instance_variable_get(:@_subprocess_warned)
      TinyKTestHelper.instance_variable_set(:@_subprocess_warned, true)
      warn "Note: assert_tk_subprocess spawns a new process per test (slow). " \
           "Use assert_tk_app for most tests."
    end

    code = yield
    success, stdout, stderr, status = tk_subprocess(code)

    output = []
    output << "STDOUT:\n#{stdout}" unless stdout.empty?
    output << "STDERR:\n#{stderr}" unless stderr.empty?
    output << "Exit status: #{status.exitstatus}"

    assert success, "#{message}\n#{output.join("\n")}"
  end

  # DEPRECATED: Use assert_tk_app instead (uses persistent TinyK::TestWorker)
  # This spawns a new subprocess for each test - slower but supports VISUAL mode.
  def assert_tk_app_subprocess(message, app_method)
    # Extract method body (skip def line and closing end)
    source_lines = app_method.source.lines
    body = source_lines[1..-2].join

    # Prepend visual mode helper (defines tk_end)
    full_body = "#{TinyKTestHelper.visual_mode_preamble}\n#{body}"

    success, stdout, stderr, status = tk_subprocess(full_body)

    output = []
    output << "STDOUT:\n#{stdout}" unless stdout.empty?
    output << "STDERR:\n#{stderr}" unless stderr.empty?
    output << "Exit status: #{status.exitstatus}"

    assert success, "#{message}\n#{output.join("\n")}"
  end

  # Smoke test a sample file - checks it loads without crashing.
  #
  # Spawns the sample with TK_READY_PORT env var pointing to a TCP port.
  # Sample uses TkDemo.finish (from tk/demo_support) to signal completion.
  # Parent waits for connection, then terminates the process for clean shutdown.
  #
  # Returns [success, stdout, stderr]
  #
  # Options:
  #   :timeout - max seconds to wait for ready signal (default: 10)
  #
  def smoke_test_sample(sample_path, timeout: 10, args: [])
    sample_path = File.expand_path(sample_path)
    raise ArgumentError, "Sample not found: #{sample_path}" unless File.exist?(sample_path)

    load_paths = $LOAD_PATH.select { |p| p.include?(File.dirname(__dir__)) }
    load_path_args = load_paths.flat_map { |p| ["-I", p] }

    # Create TCP server for ready signal (cross-platform)
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]

    stdout_r, stdout_w = IO.pipe
    stderr_r, stderr_w = IO.pipe

    pid = Process.spawn(
      { 'TK_READY_PORT' => port.to_s },
      RbConfig.ruby, *load_path_args, sample_path, *args,
      in: :close,
      out: stdout_w,
      err: stderr_w
    )

    # Parent closes write ends
    stdout_w.close
    stderr_w.close

    success = false
    stdout = ""
    stderr = ""

    # Hard timeout wrapper - ensures we never hang forever
    hard_timeout = timeout + 5

    begin
      Timeout.timeout(hard_timeout) do
        # Wait for ready signal (TCP connection) or timeout
        timed_out = false
        if IO.select([server], nil, nil, timeout)
          client = server.accept
          client.close  # Got ready signal - UI is up
          success = true
        else
          timed_out = true
        end
        server.close

        # Terminate the process
        terminate_process(pid)

        stdout = stdout_r.read
        stderr = stderr_r.read
        if timed_out
          stderr = "TIMEOUT: Sample did not signal ready within #{timeout}s\n#{stderr}"
        end
      end
    rescue Timeout::Error
      # Hard timeout hit - force kill and fail
      kill_process(pid)
      stdout = stdout_r.read rescue ""
      stderr = "HARD TIMEOUT: Sample did not respond within #{hard_timeout}s\n#{stderr_r.read rescue ""}"
      success = false
    ensure
      server.close unless server.closed?
      stdout_r.close unless stdout_r.closed?
      stderr_r.close unless stderr_r.closed?
    end

    [success, stdout, stderr]
  end

  # Platform-aware process termination
  # Tries graceful shutdown first, then force kill
  def terminate_process(pid)
    return unless process_alive?(pid)

    if Gem.win_platform?
      # Windows: no SIGTERM, just kill
      Process.kill("KILL", pid)
      Process.wait(pid)
    else
      # Unix: try SIGTERM first for graceful shutdown
      Process.kill("TERM", pid)
      begin
        Timeout.timeout(2) { Process.wait(pid) }
      rescue Timeout::Error
        Process.kill("KILL", pid)
        Process.wait(pid)
      end
    end
  rescue Errno::ESRCH, Errno::ECHILD
    # Process already gone
  end

  # Force kill a process
  def kill_process(pid)
    Process.kill("KILL", pid) rescue nil
    Process.wait(pid) rescue nil
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  # Run test using persistent TinyK::TestWorker (fast, no subprocess spawn per test).
  #
  # The test code has access to `root` (a withdrawn TkRoot instance).
  # Do NOT create your own TkRoot or call root.destroy - worker manages this.
  #
  # Example:
  #   def test_something
  #     assert_tk_app("should work", method(:my_app))
  #   end
  #
  #   def my_app
  #     require 'tk'
  #     label = TkLabel.new(root) { text "Hello" }
  #     raise "wrong" unless label.cget(:text) == "Hello"
  #   end
  #
  def assert_tk_app(message, app_method, pipe_capture: false, timeout: nil)
    require_relative 'tinyk_test_worker'

    # Extract method body (skip def line and closing end)
    source_lines = app_method.source.lines
    body = source_lines[1..-2].join

    result = TinyK::TestWorker.run_test(body, pipe_capture: pipe_capture, timeout: timeout)

    # Show warnings (interpreter cleanup, etc.) even on success
    if result[:warnings]&.any?
      warn "TinyK::TestWorker warnings: #{result[:warnings].join('; ')}"
    end

    unless result[:success]
      output = []
      output << "Error: #{result[:error_class]}: #{result[:error_message]}"
      output << "Code:\n#{result[:code_context]}" if result[:code_context]
      output << "Backtrace:\n  #{result[:backtrace].join("\n  ")}" if result[:backtrace]
      output << "STDOUT:\n#{result[:stdout]}" unless result[:stdout].to_s.empty?
      output << "STDERR:\n#{result[:stderr]}" unless result[:stderr].to_s.empty?
      output << "Warnings:\n#{result[:warnings].join("\n")}" if result[:warnings]&.any?

      flunk "#{message}\n#{output.join("\n")}"
    end

    assert true  # Explicit pass
  end

  # Assertion wrapper for smoke_test_sample
  def assert_sample_loads(sample_path, message: nil, timeout: 10)
    sample_name = File.basename(sample_path)
    message ||= "Sample #{sample_name} should load without crashing"

    success, stdout, stderr = smoke_test_sample(sample_path, timeout: timeout)

    output = []
    output << "STDOUT:\n#{stdout}" unless stdout.empty?
    output << "STDERR:\n#{stderr}" unless stderr.empty?

    assert success, "#{message}\n#{output.join("\n")}"
  end
end
