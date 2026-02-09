#!/usr/bin/env ruby
# frozen_string_literal: true
# teek-record: title=Concurrency Demo - File Hasher

# Concurrency Demo - File Hasher
#
# Compares concurrency modes:
# - None: Direct execution, UI frozen. Shows what happens without background work.
# - None+update: Synchronous but with forced UI updates so progress is visible.
# - Thread: Background thread with GVL overhead. Enables Pause, UI stays responsive.
# - Ractor: True parallelism (separate GVL). Best throughput. (Ruby 4.x+ only)

require 'teek'
require 'teek/background_none'
require 'digest'
require 'tmpdir'

# Register :none mode for demo
Teek::BackgroundWork.register_background_mode(:none, Teek::BackgroundNone::BackgroundWork)

RACTOR_AVAILABLE = Teek::BackgroundWork::RACTOR_SUPPORTED

class ThreadingDemo
  attr_reader :app

  ALGORITHMS = %w[SHA256 SHA512 SHA384 SHA1 MD5].freeze

  MODES = if RACTOR_AVAILABLE
    ['None', 'None+update', 'Thread', 'Ractor'].freeze
  else
    ['None', 'None+update', 'Thread'].freeze
  end

  def initialize
    @app = Teek::App.new
    @running = false
    @paused = false
    @stop_requested = false
    @background_task = nil

    build_ui
    collect_files

    @app.update
    w = @app.command(:winfo, 'width', '.')
    h = @app.command(:winfo, 'height', '.')
    @app.set_window_geometry("#{w}x#{h}+0+0")
    @app.set_window_resizable(true, true)

    close_proc = proc { |*|
      @background_task&.close
      @app.destroy('.')
    }
    @app.command(:wm, 'protocol', '.', 'WM_DELETE_WINDOW', close_proc)
  end

  def build_ui
    @app.show
    @app.set_window_title('Concurrency Demo - File Hasher')
    @app.command(:wm, 'minsize', '.', 600, 400)

    # Tcl variables for widget bindings
    @app.set_variable('::chunk_size', 3)
    @app.set_variable('::algorithm', 'SHA256')
    @app.set_variable('::mode', 'Thread')
    @app.set_variable('::allow_pause', 0)
    @app.set_variable('::progress', 0)

    ractor_note = RACTOR_AVAILABLE ? "Ractor: true parallel." : "(Ractor available on Ruby 4.x+)"
    @app.create_widget('ttk::label',
      text: "File hasher demo - compares concurrency modes.\n" \
            "None: UI frozen. None+update: progress visible, pause works. " \
            "Thread: responsive, GVL shared. #{ractor_note}",
      justify: :left).pack(fill: :x, padx: 10, pady: 10)

    build_controls
    build_statusbar
    build_log
  end

  def build_controls
    ctrl = @app.create_widget('ttk::frame')
    ctrl.pack(fill: :x, padx: 10, pady: 5)

    @start_btn = @app.create_widget('ttk::button', parent: ctrl,
      text: 'Start', command: proc { |*| start_hashing })
    @start_btn.pack(side: :left)

    @pause_btn = @app.create_widget('ttk::button', parent: ctrl,
      text: 'Pause', state: :disabled, command: proc { |*| toggle_pause })
    @pause_btn.pack(side: :left, padx: 5)

    @app.create_widget('ttk::button', parent: ctrl,
      text: 'Reset', command: proc { |*| reset }).pack(side: :left)

    @app.create_widget('ttk::label', parent: ctrl,
      text: 'Algorithm:').pack(side: :left, padx: 10)

    @algo_combo = @app.create_widget('ttk::combobox', parent: ctrl,
      textvariable: '::algorithm',
      values: Teek.make_list(*ALGORITHMS),
      width: 8,
      state: :readonly)
    @algo_combo.pack(side: :left)

    @app.create_widget('ttk::label', parent: ctrl,
      text: 'Batch:').pack(side: :left, padx: 10)

    @batch_val = @app.create_widget('ttk::label', parent: ctrl, text: '3', width: 3)
    @batch_val.pack(side: :left)

    @app.create_widget('ttk::scale', parent: ctrl,
      orient: :horizontal,
      from: 1,
      to: 100,
      length: 100,
      variable: '::chunk_size',
      command: proc { |v, *| @batch_val.command(:configure, text: v.to_f.round.to_s) })
      .pack(side: :left, padx: 5)

    @app.create_widget('ttk::label', parent: ctrl,
      text: 'Mode:').pack(side: :left, padx: 10)

    @mode_combo = @app.create_widget('ttk::combobox', parent: ctrl,
      textvariable: '::mode',
      values: Teek.make_list(*MODES),
      width: 10,
      state: :readonly)
    @mode_combo.pack(side: :left)

    @app.create_widget('ttk::checkbutton', parent: ctrl,
      text: 'Allow Pause',
      variable: '::allow_pause').pack(side: :left, padx: 10)
  end

  def build_statusbar
    status = @app.create_widget('ttk::frame')
    status.pack(side: :bottom, fill: :x, padx: 5, pady: 5)

    # Progress section (left)
    progress_frame = @app.create_widget('ttk::frame', parent: status,
      relief: :sunken, borderwidth: 2)
    progress_frame.pack(side: :left, fill: :x, expand: 1, padx: 2)

    @app.create_widget('ttk::progressbar', parent: progress_frame,
      orient: :horizontal,
      length: 200,
      mode: :determinate,
      variable: '::progress',
      maximum: 100).pack(side: :left, padx: 5, pady: 4)

    @status_label = @app.create_widget('ttk::label', parent: progress_frame,
      text: 'Ready', width: 20, anchor: :w)
    @status_label.pack(side: :left, padx: 10)

    @file_label = @app.create_widget('ttk::label', parent: progress_frame,
      text: '', width: 28, anchor: :w)
    @file_label.pack(side: :left, padx: 5)

    # Info section (right)
    info_frame = @app.create_widget('ttk::frame', parent: status,
      relief: :sunken, borderwidth: 2)
    info_frame.pack(side: :right, padx: 2)

    @files_label = @app.create_widget('ttk::label', parent: info_frame,
      text: '', width: 12, anchor: :e)
    @files_label.pack(side: :left, padx: 8, pady: 4)

    @app.create_widget('ttk::separator', parent: info_frame,
      orient: :vertical).pack(side: :left, fill: :y, pady: 4)

    @app.create_widget('ttk::label', parent: info_frame,
      text: "Ruby #{RUBY_VERSION}", anchor: :e).pack(side: :left, padx: 8, pady: 4)
  end

  def build_log
    log = @app.create_widget('ttk::labelframe', text: 'Output')
    log.pack(fill: :both, expand: 1, padx: 10, pady: 5)

    log_frame = @app.create_widget('ttk::frame', parent: log)
    log_frame.pack(fill: :both, expand: 1, padx: 5, pady: 5)
    @app.command(:pack, 'propagate', log_frame, 0)

    @log_text = @app.create_widget(:text, parent: log_frame,
      width: 80, height: 15, wrap: :none)
    @log_text.pack(side: :left, fill: :both, expand: 1)

    vsb = @app.create_widget('ttk::scrollbar', parent: log_frame,
      orient: :vertical, command: "#{@log_text} yview")
    @log_text.command(:configure, yscrollcommand: "#{vsb} set")
    vsb.pack(side: :right, fill: :y)
  end

  def collect_files
    base = File.exist?('/app') ? '/app' : Dir.pwd
    @files = Dir.glob("#{base}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) }
    @files.reject! { |f| f.include?('/.git/') }
    @files.sort!

    max_files = ARGV.find { |a| a.start_with?('--max-files=') }&.split('=')&.last&.to_i
    max_files ||= ENV['DEMO_MAX_FILES']&.to_i
    max_files ||= 5 if ENV['TK_READY_PORT'] # test mode -- don't hash 200+ files
    @files = @files.first(max_files) if max_files && max_files > 0

    @files_label.command(:configure, text: "#{@files.size} files")
  end

  def current_mode
    @app.get_variable('::mode')
  end

  def set_combo_enabled(widget)
    # ttk state: must clear disabled AND set readonly in one call
    @app.tcl_eval("#{widget} state {!disabled readonly}")
  end

  def start_hashing
    @running = true
    @paused = false
    @stop_requested = false

    @start_btn.command(:state, 'disabled')
    @algo_combo.command(:state, 'disabled')
    @mode_combo.command(:state, 'disabled')
    @log_text.command(:delete, '1.0', 'end')
    @app.set_variable('::progress', 0)
    @status_label.command(:configure, text: 'Hashing...')

    if @app.get_variable('::allow_pause').to_i == 1
      @pause_btn.command(:state, '!disabled')
    else
      @pause_btn.command(:state, 'disabled')
    end

    @app.set_window_resizable(false, false) unless current_mode == 'Ractor'

    @metrics = {
      start_time: Process.clock_gettime(Process::CLOCK_MONOTONIC),
      ui_update_count: 0,
      ui_update_total_ms: 0.0,
      total: @files.size,
      files_done: 0,
      mode: current_mode
    }

    mode_sym = case current_mode
      when 'None', 'None+update' then :none
      else current_mode.downcase.to_sym
    end
    start_background_work(mode_sym)
  end

  def toggle_pause
    @paused = !@paused
    @pause_btn.command(:configure, text: @paused ? 'Resume' : 'Pause')
    @status_label.command(:configure, text: @paused ? 'Paused' : 'Hashing...')
    @app.set_window_resizable(@paused, @paused)
    if @paused
      set_combo_enabled(@mode_combo)
    else
      @mode_combo.command(:state, 'disabled')
    end

    if @background_task
      @paused ? @background_task.pause : @background_task.resume
    end

    write_metrics("PAUSED") if @paused && @metrics
  end

  def reset
    @stop_requested = true
    @paused = false
    @running = false

    @background_task&.stop
    @background_task = nil

    @start_btn.command(:state, '!disabled')
    @pause_btn.command(:state, 'disabled')
    @pause_btn.command(:configure, text: 'Pause')
    set_combo_enabled(@algo_combo)
    set_combo_enabled(@mode_combo)
    @app.set_window_resizable(true, true)
    @log_text.command(:delete, '1.0', 'end')
    @app.set_variable('::progress', 0)
    @status_label.command(:configure, text: 'Ready')
    @file_label.command(:configure, text: '')

    @app.set_variable('::mode', 'Thread')
    @app.set_variable('::algorithm', 'SHA256')
    @app.set_variable('::chunk_size', 3)
    @batch_val.command(:configure, text: '3')
    @app.set_variable('::allow_pause', 0)
  end

  def write_metrics(status = "DONE")
    return unless @metrics
    m = @metrics
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - m[:start_time]
    dir = File.writable?(__dir__) ? __dir__ : Dir.tmpdir
    File.open(File.join(dir, 'threading_demo_metrics.log'), 'a') do |f|
      f.puts "=" * 60
      f.puts "Status: #{status} at #{Time.now}"
      f.puts "Mode: #{m[:mode]}"
      f.puts "Algorithm: #{@app.get_variable('::algorithm')}"
      f.puts "Files processed: #{m[:files_done]}/#{m[:total]}"
      chunk = [@app.get_variable('::chunk_size').to_f.round, 1].max
      f.puts "Batch size: #{chunk}"
      f.puts "-" * 40
      f.puts "Elapsed: #{elapsed.round(3)}s"
      f.puts "UI updates: #{m[:ui_update_count]}"
      f.puts "UI update total: #{m[:ui_update_total_ms].round(1)}ms" if m[:ui_update_total_ms]
      f.puts "UI update avg: #{(m[:ui_update_total_ms] / m[:ui_update_count]).round(2)}ms" if m[:ui_update_count] > 0 && m[:ui_update_total_ms]
      f.puts "Files/sec: #{(m[:files_done] / elapsed).round(1)}" if elapsed > 0
      f.puts
    end
  end

  def finish_hashing
    write_metrics("DONE") unless @stop_requested
    return if @stop_requested

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @metrics[:start_time]
    files_per_sec = (@metrics[:files_done] / elapsed).round(1)
    @status_label.command(:configure,
      text: "Done #{elapsed.round(2)}s (#{files_per_sec}/s)")
    @file_label.command(:configure, text: '')
    @start_btn.command(:state, '!disabled')
    @pause_btn.command(:state, 'disabled')
    set_combo_enabled(@algo_combo)
    set_combo_enabled(@mode_combo)
    @app.set_window_resizable(true, true)
    @running = false
  end

  # ─────────────────────────────────────────────────────────────
  # All modes use unified Teek::BackgroundWork API
  # ─────────────────────────────────────────────────────────────

  def start_background_work(mode)
    ui_mode = current_mode

    files = @files.dup
    algo_name = @app.get_variable('::algorithm')
    chunk_size = [@app.get_variable('::chunk_size').to_f.round, 1].max
    base_dir = Dir.pwd
    allow_pause = @app.get_variable('::allow_pause').to_i == 1

    work_data = {
      files: files,
      algo_name: algo_name,
      chunk_size: chunk_size,
      base_dir: base_dir,
      allow_pause: allow_pause
    }

    if mode == :ractor
      work_data = Ractor.make_shareable({
        files: Ractor.make_shareable(files.freeze),
        algo_name: algo_name.freeze,
        chunk_size: chunk_size,
        base_dir: base_dir.freeze,
        allow_pause: allow_pause
      })
    end

    # Each progress value has unique log text — don't drop any
    Teek::BackgroundWork.drop_intermediate = false

    @background_task = Teek::BackgroundWork.new(@app, work_data, mode: mode) do |task, data|
      algo_class = Digest.const_get(data[:algo_name])
      total = data[:files].size
      pending = []

      data[:files].each_with_index do |path, index|
        if data[:allow_pause] && pending.empty?
          task.check_pause
        end

        begin
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          hash = algo_class.file(path).hexdigest
          dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
          short_path = path.sub(%r{^/app/}, '').sub(data[:base_dir] + '/', '')
          pending << "#{short_path}: #{hash} #{dt < 0.01 ? format('%.5fs', dt) : format('%.2fs', dt)}\n"
        rescue StandardError => e
          short_path = path.sub(%r{^/app/}, '').sub(data[:base_dir] + '/', '')
          pending << "#{short_path}: ERROR - #{e.message}\n"
        end

        is_last = index == total - 1
        if pending.size >= data[:chunk_size] || is_last
          task.yield({
            index: index,
            total: total,
            updates: pending.join
          })
          pending = []
        end
      end
    end

    @background_task.on_progress do |msg|
      ui_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      @log_text.command(:insert, 'end', msg[:updates])
      @log_text.command(:see, 'end')
      pct = ((msg[:index] + 1).to_f / msg[:total] * 100).round
      @app.set_variable('::progress', pct)
      @status_label.command(:configure,
        text: "Hashing... #{msg[:index] + 1}/#{msg[:total]}")

      @metrics[:ui_update_count] += 1
      @metrics[:ui_update_total_ms] += (Process.clock_gettime(Process::CLOCK_MONOTONIC) - ui_start) * 1000
      @metrics[:files_done] = msg[:index] + 1

      @app.update if ui_mode == 'None+update'
    end.on_done do
      @background_task = nil
      finish_hashing
    end
  end

  def run
    @app.mainloop
  end
end

demo = ThreadingDemo.new

# Automated demo support (testing and recording)
require_relative '../lib/teek/demo_support'
TeekDemo.app = demo.app

if TeekDemo.recording?
  demo.app.set_window_geometry('+0+0')
  demo.app.tcl_eval('. configure -cursor none')
  TeekDemo.signal_recording_ready
end

if TeekDemo.active?
  TeekDemo.after_idle {
    demo.app.after(100) {
      app = demo.app

      # Set batch size high for fast processing
      app.set_variable('::chunk_size', 100)

      # Test matrix: [mode, pause_enabled]
      tests = [['None', false], ['None+update', false], ['Thread', false]]
      tests << ['Ractor', false] if RACTOR_AVAILABLE
      # Quick mode for smoke tests
      tests = [['Thread', false]] if ARGV.include?('--quick') || TeekDemo.testing?

      test_index = 0

      run_next_test = proc do
        if test_index < tests.size
          mode, pause = tests[test_index]

          # Configure mode and pause
          app.set_variable('::mode', mode)
          app.set_variable('::allow_pause', pause ? 1 : 0)

          # Start hashing
          app.after(100) { demo.start_hashing }

          # Wait for completion
          check_done = proc do
            if demo.instance_variable_get(:@running)
              app.after(200, &check_done)
            else
              test_index += 1
              if test_index < tests.size
                app.after(200) {
                  demo.reset
                  app.after(200, &run_next_test)
                }
              else
                app.after(200) { TeekDemo.finish }
              end
            end
          end
          app.after(500, &check_done)
        end
      end

      run_next_test.call
    }
  }
end

demo.run
