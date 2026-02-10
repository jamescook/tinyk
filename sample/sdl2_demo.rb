#!/usr/bin/env ruby
# frozen_string_literal: true
# teek-record: title=SDL2 Demo

# SDL2 Demo - GPU-accelerated rendering embedded in a Tk frame
#
# Demonstrates:
# - Teek::SDL2::Viewport with animated rectangles
# - Keyboard/mouse input via Tk event bindings
# - SDL2_ttf text rendering
# - Separate Tk event log window proving bidirectional event flow
#
# Run: ruby -Ilib -Iteek-sdl2/lib sample/sdl2_demo.rb

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../teek-sdl2/lib', __dir__)
require 'teek'
require 'teek/sdl2'

FONT_PATH = File.join(__dir__, '..', 'teek-sdl2', 'assets', 'JetBrainsMonoNL-Regular.ttf')

class SDL2Demo
  attr_reader :app

  COLORS = [
    [255, 60, 60],    # red
    [60, 200, 60],    # green
    [60, 100, 255],   # blue
    [255, 200, 40],   # yellow
    [200, 60, 255],   # purple
  ].freeze

  MAX_KEYSTROKES = 8
  MAX_PARTICLES = 60

  def initialize
    @app = Teek::App.new
    @app.show
    @app.set_window_title('SDL2 Demo')
    @app.set_window_geometry('640x520')

    @title = 'SDL2 Demo'

    # SDL2 viewport
    @viewport = Teek::SDL2::Viewport.new(@app, width: 640, height: 480)
    @viewport.pack(fill: :both, expand: true)

    # Load font for text rendering
    @font = @viewport.renderer.load_font(FONT_PATH, 18)
    @font_small = @viewport.renderer.load_font(FONT_PATH, 12)

    # Bouncing boxes
    @boxes = COLORS.each_with_index.map do |color, i|
      {
        x: 40 + i * 100, y: 40 + i * 60,
        w: 60, h: 40,
        dx: 2 + i, dy: 1 + i,
        r: color[0], g: color[1], b: color[2]
      }
    end

    # Input state
    @recent_keys = []     # [{text:, age:}, ...]
    @particles = []       # [{x:, y:, dx:, dy:, age:, r:, g:, b:}, ...]
    @has_focus = false

    # Wire up input
    setup_input
    setup_event_log

    @frame_count = 0
    @fps_frames = 0
    @fps_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @fps_text = '-- fps'
    @running = true
  end

  def setup_input
    # Key events (viewport tracks state internally, we also show them)
    @viewport.bind('KeyPress', :keysym) do |k|
      @recent_keys.unshift({ text: k, age: 0 })
      @recent_keys.pop if @recent_keys.size > MAX_KEYSTROKES
      log_event("KEY DOWN: #{k}")
    end

    @viewport.bind('KeyRelease', :keysym) do |k|
      log_event("KEY UP:   #{k}")
    end

    # Mouse particles
    @viewport.bind('Motion', :x, :y) do |x, y|
      spawn_particle(x.to_i, y.to_i)
      log_event("MOUSE:    #{x},#{y}")
    end

    @viewport.bind('ButtonPress-1', :x, :y) do |x, y|
      5.times { spawn_particle(x.to_i, y.to_i) }
      log_event("CLICK:    #{x},#{y}")
    end

    # Focus tracking
    @viewport.bind('FocusIn') { @has_focus = true }
    @viewport.bind('FocusOut') { @has_focus = false }
  end

  def setup_event_log
    @log_path = '.evlog'
    @app.command(:toplevel, @log_path)
    @app.command(:wm, :title, @log_path, 'Event Log')
    @app.command(:wm, :geometry, @log_path, '300x400+660+0')

    @log_text = @app.create_widget(:text, @log_path + '.log',
      width: 40, height: 25, font: '{TkFixedFont} 10',
      state: :disabled, background: '#1e1e1e', foreground: '#cccccc')
    @log_text.pack(fill: :both, expand: true)

    @app.command(:wm, :protocol, @log_path, 'WM_DELETE_WINDOW',
                 proc { @app.command(:wm, :withdraw, @log_path) })
  end

  def log_event(msg)
    @app.command(@log_text, :configure, state: :normal)
    @app.command(@log_text, :insert, 'end', msg + "\n")
    @app.command(@log_text, :see, 'end')
    @app.command(@log_text, :configure, state: :disabled)

    # Keep last 200 lines
    count = @app.command(@log_text, :count, '-lines', '1.0', 'end').to_i
    if count > 200
      @app.command(@log_text, :configure, state: :normal)
      @app.command(@log_text, :delete, '1.0', "#{count - 200}.0")
      @app.command(@log_text, :configure, state: :disabled)
    end
  end

  def spawn_particle(x, y)
    angle = rand * 2 * Math::PI
    speed = 1 + rand * 3
    color = COLORS.sample
    @particles << {
      x: x.to_f, y: y.to_f,
      dx: Math.cos(angle) * speed, dy: Math.sin(angle) * speed,
      age: 0, r: color[0], g: color[1], b: color[2]
    }
    @particles.shift if @particles.size > MAX_PARTICLES
  end

  def tick
    return unless @running

    w, h = @viewport.renderer.output_size

    # Move boxes
    @boxes.each do |box|
      box[:x] += box[:dx]
      box[:y] += box[:dy]

      if box[:x] <= 0 || box[:x] + box[:w] >= w
        box[:dx] = -box[:dx]
        box[:x] = box[:x].clamp(0, w - box[:w])
      end
      if box[:y] <= 0 || box[:y] + box[:h] >= h
        box[:dy] = -box[:dy]
        box[:y] = box[:y].clamp(0, h - box[:h])
      end
    end

    # Age particles
    @particles.each { |p| p[:age] += 1; p[:x] += p[:dx]; p[:y] += p[:dy] }
    @particles.reject! { |p| p[:age] > 30 }

    # Age keystrokes
    @recent_keys.each { |k| k[:age] += 1 }
    @recent_keys.reject! { |k| k[:age] > 120 }

    # Draw
    @viewport.render do |r|
      r.clear(20, 20, 30)

      # Bouncing boxes
      @boxes.each do |box|
        r.fill_rect(box[:x], box[:y], box[:w], box[:h],
                     box[:r], box[:g], box[:b])
      end

      # Particles
      @particles.each do |p|
        alpha = ((1.0 - p[:age] / 30.0) * 255).to_i
        size = [4 - p[:age] / 10, 1].max
        r.fill_rect(p[:x].to_i, p[:y].to_i, size, size,
                     p[:r], p[:g], p[:b], alpha)
      end

      # Keystrokes in bottom-right
      @recent_keys.each_with_index do |k, i|
        alpha = ((1.0 - k[:age] / 120.0) * 255).to_i
        r.draw_text(w - 150, h - 30 - i * 22, k[:text],
                     font: @font, r: 255, g: 255, b: 255, a: alpha)
      end

      # FPS top-left
      r.draw_text(8, 8, @fps_text, font: @font_small, r: 180, g: 180, b: 180)

      # Focus hint
      unless @has_focus
        r.draw_text(w / 2 - 60, h / 2, "click to focus",
                     font: @font_small, r: 100, g: 100, b: 100)
      end
    end

    @frame_count += 1
    @fps_frames += 1
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed = now - @fps_time
    if elapsed >= 0.5
      @fps_text = "#{(@fps_frames / elapsed).round(1)} fps"
      @fps_frames = 0
      @fps_time = now
    end
  end

  def animate(interval: 16, &on_done)
    tick
    if @running
      @app.after(interval) { animate(interval: interval, &on_done) }
    else
      on_done&.call
    end
  end

  def stop
    @running = false
  end

  def run
    animate
    @app.mainloop
  end
end

demo = SDL2Demo.new

# Automated demo support (testing and recording)
require_relative '../lib/teek/demo_support'
TeekDemo.app = demo.app

if TeekDemo.recording?
  demo.app.set_window_geometry('+0+0')
  demo.app.tcl_eval('. configure -cursor none')
  TeekDemo.signal_recording_ready
end

if TeekDemo.active?
  vp = demo.instance_variable_get(:@viewport)
  fp = vp.frame.path

  TeekDemo.after_idle do
    d = TeekDemo.method(:delay)
    app = demo.app
    gen = proc { |ev, **opts|
      args = opts.map { |k, v| "-#{k} #{v}" }.join(' ')
      app.tcl_eval("event generate #{fp} <#{ev}> #{args}")
    }

    demo.animate

    # Give focus (-force needed on X11/xvfb for event generate to deliver key events)
    app.after(d.call(test: 1, record: 300)) { app.tcl_eval("focus -force #{fp}") }

    # Click around to show particles
    clicks = [[200, 150], [400, 300], [100, 350], [500, 200], [300, 100]]
    clicks.each_with_index do |(x, y), i|
      t = d.call(test: 1, record: 600) * (i + 1) + d.call(test: 1, record: 500)
      app.after(t) {
        gen.call('ButtonPress-1', x: x, y: y)
        app.after(50) { gen.call('ButtonRelease-1', x: x, y: y) }
      }
    end

    # Type some keys (overlaps with clicks)
    keys = %w[H e l l o space S D L 2]
    base = d.call(test: 1, record: 2000)
    keys.each_with_index do |k, i|
      t = base + d.call(test: 1, record: 150) * (i + 1)
      app.after(t) {
        gen.call('KeyPress', keysym: k)
        app.after(80) { gen.call('KeyRelease', keysym: k) }
      }
    end

    # Finish after ~5s recording / immediately in test
    app.after(d.call(test: 50, record: 5000)) {
      demo.stop
      TeekDemo.finish
    }
  end
else
  demo.animate
end

demo.app.mainloop
