#!/usr/bin/env ruby
# frozen_string_literal: true

# Theremin — real-time audio synthesis with oscilloscope visualization.
#
# Demonstrates:
#   - Teek::SDL2::AudioStream for push-based PCM audio generation
#   - SDL2 Viewport rendering (draw_line oscilloscope)
#   - Mouse input driving frequency + amplitude in real-time
#   - Tk labels for status display alongside SDL2 rendering
#
# Move the mouse over the SDL2 viewport:
#   X axis → pitch (100 Hz – 2000 Hz, logarithmic)
#   Y axis → volume (loud at top, silent at bottom)
#
# Run: ruby -Ilib -Iteek-sdl2/lib sample/theremin/theremin.rb

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../../teek-sdl2/lib', __dir__)
require 'teek'
require 'teek/sdl2'

FONT_PATH = File.join(__dir__, '..', '..', 'teek-sdl2', 'assets', 'JetBrainsMonoNL-Regular.ttf')

# Note names for display (C4 = 261.63 Hz)
NOTE_NAMES = %w[C C# D D# E F F# G G# A A# B].freeze

class Theremin
  SAMPLE_RATE = 44_100
  CHANNELS    = 1
  WIDTH       = 640
  HEIGHT      = 400

  # Frequency range (logarithmic)
  FREQ_MIN = 100.0
  FREQ_MAX = 2000.0

  # How many samples to generate per tick (~16ms at 60fps)
  SAMPLES_PER_TICK = (SAMPLE_RATE / 60.0).ceil  # ~735

  # Buffer target: keep 2000–4000 samples queued
  BUFFER_LOW  = 2000
  BUFFER_HIGH = 4000

  def initialize
    @app = Teek::App.new(title: 'Theremin')
    @app.show
    @app.set_window_geometry("#{WIDTH}x#{HEIGHT + 60}")

    build_menu

    # SDL2 viewport for oscilloscope
    @viewport = Teek::SDL2::Viewport.new(@app, width: WIDTH, height: HEIGHT)
    @viewport.pack(fill: :both, expand: true)

    # Load font
    @font = @viewport.renderer.load_font(FONT_PATH, 14)
    @font_small = @viewport.renderer.load_font(FONT_PATH, 11)

    # Status bar (Tk label below viewport)
    @status_var = "::theremin_status"
    @app.command(:set, @status_var, "Move mouse over viewport to play")
    status_label = @app.create_widget('ttk::label',
                                      textvariable: @status_var,
                                      font: 'TkFixedFont')
    status_label.pack(fill: :x, padx: 8, pady: 4)

    # Audio stream — mono, 16-bit, 44.1kHz
    @stream = Teek::SDL2::AudioStream.new(
      frequency: SAMPLE_RATE,
      format:    :s16,
      channels:  CHANNELS
    )

    # State
    @frequency = 440.0
    @amplitude = 0.0        # 0.0–1.0
    @phase     = 0.0        # continuous phase (radians)
    @active    = false       # true while mouse is over viewport
    @last_buffer = []       # last generated samples for oscilloscope
    @running = true

    setup_input
    draw_idle_screen
  end

  def run
    @app.mainloop
  ensure
    @stream&.destroy unless @stream&.destroyed?
  end

  private

  def build_menu
    menubar = '.menubar'
    @app.command(:menu, menubar)
    @app.command('.', :configure, menu: menubar)

    # File menu
    @app.command(:menu, "#{menubar}.file", tearoff: 0)
    @app.command(menubar, :add, :cascade, label: 'File', menu: "#{menubar}.file")
    @app.command("#{menubar}.file", :add, :command,
                 label: 'Quit', accelerator: 'Cmd+Q',
                 command: proc { @running = false; @app.command(:destroy, '.') })
  end

  def setup_input
    @viewport.bind('Motion', :x, :y) do |x, y|
      mx = x.to_i.clamp(0, WIDTH - 1)
      my = y.to_i.clamp(0, HEIGHT - 1)
      update_from_mouse(mx, my)
    end

    @viewport.bind('Enter') { start_playing }
    @viewport.bind('Leave') { stop_playing }
  end

  def start_playing
    return if @active

    @active = true
    @amplitude = 0.0
    @phase = 0.0
    @last_buffer = []
    @stream.clear
    @stream.resume
    animate
  end

  def stop_playing
    return unless @active

    @active = false
    @amplitude = 0.0
    @stream.pause
    @stream.clear
    draw_idle_screen
    @app.command(:set, @status_var, "Move mouse over viewport to play")
  end

  def draw_idle_screen
    w, h = @viewport.renderer.output_size
    @viewport.render do |r|
      r.clear(15, 15, 25)
      r.draw_line(0, h / 2, w - 1, h / 2, 40, 40, 50)
      r.draw_text(12, 12, "Move mouse to play",
                  font: @font_small, r: 80, g: 80, b: 80)
    end
  end

  def update_from_mouse(mx, my)
    # X → frequency (logarithmic scale)
    t = mx.to_f / (WIDTH - 1)
    @frequency = FREQ_MIN * (FREQ_MAX / FREQ_MIN)**t

    # Y → amplitude (top = loud, bottom = silent)
    @amplitude = 1.0 - (my.to_f / (HEIGHT - 1))
    @amplitude = @amplitude.clamp(0.0, 1.0)
  end

  def generate_audio
    # Only generate if buffer is running low
    queued = @stream.queued_samples
    return if queued > BUFFER_HIGH

    count = SAMPLES_PER_TICK
    # If buffer is very low, generate more to catch up
    count *= 2 if queued < BUFFER_LOW

    samples = Array.new(count)
    freq = @frequency
    amp = @amplitude
    phase = @phase
    phase_inc = 2.0 * Math::PI * freq / SAMPLE_RATE

    count.times do |i|
      val = Math.sin(phase) * amp * 32000.0
      samples[i] = val.to_i.clamp(-32768, 32767)
      phase += phase_inc
    end

    # Keep phase from growing without bound
    @phase = phase % (2.0 * Math::PI)

    @stream.queue(samples.pack('s*'))
    @last_buffer = samples
  end

  def draw_oscilloscope(r, w, h)
    return if @last_buffer.empty?

    # Draw waveform
    buf = @last_buffer
    step = [buf.length / w.to_f, 1.0].max
    mid_y = h / 2

    prev_x = 0
    prev_y = mid_y

    # Green waveform
    (0...w).each do |x|
      idx = (x * step).to_i
      break if idx >= buf.length

      sample = buf[idx]
      # Map -32768..32767 → 0..h
      y = mid_y - (sample.to_f / 32768.0 * (mid_y - 20)).to_i

      if x > 0
        r.draw_line(prev_x, prev_y, x, y, 0, 255, 100)
      end
      prev_x = x
      prev_y = y
    end

    # Center line (dim)
    r.draw_line(0, mid_y, w - 1, mid_y, 40, 40, 50)
  end

  def note_name(freq)
    # MIDI note number: 69 = A4 = 440Hz
    midi = 69 + 12 * Math.log2(freq / 440.0)
    note_idx = midi.round % 12
    octave = (midi.round / 12) - 1
    "#{NOTE_NAMES[note_idx]}#{octave}"
  end

  def tick
    return unless @active

    generate_audio

    w, h = @viewport.renderer.output_size

    @viewport.render do |r|
      r.clear(15, 15, 25)

      draw_oscilloscope(r, w, h)

      # Frequency / note display
      freq_text = "#{@frequency.round(1)} Hz  #{note_name(@frequency)}"
      r.draw_text(12, 12, freq_text, font: @font, r: 255, g: 255, b: 255)

      amp_text = "vol: #{(@amplitude * 100).round}%"
      r.draw_text(12, 32, amp_text, font: @font_small, r: 180, g: 180, b: 180)

      # Buffer status (bottom-left)
      queued = @stream.queued_samples
      buf_text = "buf: #{queued}"
      color_r = queued < BUFFER_LOW ? 255 : 100
      color_g = queued < BUFFER_LOW ? 100 : 200
      r.draw_text(12, h - 24, buf_text,
                  font: @font_small, r: color_r, g: color_g, b: 100)
    end

    # Update Tk status label
    @app.command(:set, @status_var,
                 format("%.1f Hz  %-4s  vol: %d%%  buf: %d",
                        @frequency, note_name(@frequency),
                        (@amplitude * 100).round,
                        @stream.queued_samples))
  end

  def animate(interval: 16)
    tick
    if @active
      @app.after(interval) { animate(interval: interval) }
    end
  end
end

Theremin.new.run
