#!/usr/bin/env ruby
# frozen_string_literal: true
# teek-record: title=Optcarrot NES (Thwaite)

# Optcarrot NES Emulator running on teek-sdl2
#
# Uses teek for the window and teek-sdl2 for GPU-accelerated rendering.
# Optcarrot is installed automatically via bundler/inline.
#
# Usage:
#   ruby -Ilib -Iteek-sdl2/lib sample/optcarrot.rb path/to/rom.nes
#
# Controls:
#   Arrow keys  - D-pad
#   Z           - A button
#   X           - B button
#   Return      - Start
#   Space       - Select
#   Q / Escape  - Quit

FALLBACK_ROMS = [
  File.join(__dir__, 'optcarrot', 'thwaite.nes'),
].freeze

rom_path = ARGV.find { |a| !a.start_with?('--') }
unless rom_path
  rom_path = FALLBACK_ROMS.find { |p| File.exist?(p) }
  unless rom_path
    abort <<~USAGE
      Usage: ruby sample/optcarrot.rb [options] <rom.nes>

      Options are passed through to optcarrot.
      ROM file must be provided — it is not bundled.
      Fallback locations checked:
        #{FALLBACK_ROMS.join("\n    ")}
    USAGE
  end
end

unless File.exist?(rom_path)
  abort "ROM not found: #{rom_path}"
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../teek-sdl2/lib', __dir__)
$LOAD_PATH.unshift File.join(__dir__, 'optcarrot', 'vendor')
require 'teek'
require 'teek/sdl2'
require 'optcarrot'

# --- Video Driver -----------------------------------------------------------

class TeekVideo < Optcarrot::Video
  NES_WIDTH  = 256
  NES_HEIGHT = 224

  def init
    super

    @app = Teek::App.new
    @app.show
    @app.set_window_title('Optcarrot NES — teek-sdl2')
    @app.set_window_geometry("#{NES_WIDTH * 2}x#{NES_HEIGHT * 2}")
    @app.update

    @viewport = Teek::SDL2::Viewport.new(@app, width: NES_WIDTH * 2, height: NES_HEIGHT * 2)
    @viewport.pack(fill: :both, expand: true)

    @texture = @viewport.renderer.create_texture(NES_WIDTH, NES_HEIGHT, :streaming)

    # Build palette: optcarrot palette_rgb is [[r,g,b], ...] → ARGB8888
    @palette = @palette_rgb.map do |r, g, b|
      0xFF000000 | (r << 16) | (g << 8) | b
    end

    # Load font for status overlay
    font_path = File.join(__dir__, '..', 'teek-sdl2', 'assets', 'JetBrainsMonoNL-Regular.ttf')
    @status_font = @viewport.renderer.load_font(font_path, 13)

    # Auto-focus viewport for keyboard input
    @app.tcl_eval("focus -force #{@viewport.frame.path}")
    @app.update

    # FPS tracking
    @fps_count = 0
    @fps_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @frame_num = 0
    @fps_text = '0.0 fps'
  end

  def tick(colors)
    return super if @disposed

    # colors is already palette-mapped uint32 ARGB values from the PPU.
    # Pack to byte string for texture update.
    @texture.update(Teek::SDL2::Pixels.pack_uint32(colors, NES_WIDTH, NES_HEIGHT))

    @viewport.render do |r|
      r.clear(0, 0, 0)
      r.copy(@texture)

      # Status overlay at bottom of game surface (outline + green text)
      right_text = "Hello from Teek!  Ruby #{RUBY_VERSION}"
      lx, ly = 6, NES_HEIGHT * 2 - 18
      rw, = @status_font.measure(right_text)
      rx, ry = NES_WIDTH * 2 - rw - 6, NES_HEIGHT * 2 - 18
      # Black outline (draw offset in 4 directions)
      [[-1,0],[1,0],[0,-1],[0,1]].each do |dx, dy|
        r.draw_text(lx+dx, ly+dy, @fps_text, font: @status_font, r: 0, g: 0, b: 0)
        r.draw_text(rx+dx, ry+dy, right_text, font: @status_font, r: 0, g: 0, b: 0)
      end
      r.draw_text(lx, ly, @fps_text, font: @status_font, r: 0, g: 255, b: 0)
      r.draw_text(rx, ry, right_text, font: @status_font, r: 0, g: 255, b: 0)
    end

    # FPS display
    @fps_count += 1
    @frame_num += 1
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed = now - @fps_time
    if elapsed >= 1.0
      fps = @fps_count / elapsed
      @fps_text = "#{fps.round(1)} fps  |  frame #{@frame_num}"
      @app.set_window_title("Optcarrot — #{fps.round(1)} fps")
      @fps_count = 0
      @fps_time = now
    end

    # Process Tk events so window stays responsive
    @app.update

    super
  end

  def dispose
    @disposed = true
    @texture&.destroy
    @viewport&.destroy
    # Don't destroy app here — TeekDemo.finish needs it for the recording
    # harness signal. Process exit handles cleanup for interactive mode.
  end

  def app
    @app
  end

  def viewport
    @viewport
  end
end

# --- Input Driver ------------------------------------------------------------

class TeekInput < Optcarrot::Input
  KEY_MAP = {
    'left'   => :left,
    'right'  => :right,
    'up'     => :up,
    'down'   => :down,
    'z'      => :a,
    'x'      => :b,
    'return' => :start,
    'space'  => :select,
  }.freeze

  # Demo script: [{frame:, button:, action: :keydown/:keyup}, ...]
  # Thwaite (missile command): title → 1 player → shoot missiles
  DEMO_SCRIPT = [
    # Title screen — mash Start quickly
    { frame: 60, button: :start, action: :keydown },
    { frame: 65, button: :start, action: :keyup },
    # 1 player select — A
    { frame: 80, button: :a, action: :keydown },
    { frame: 85, button: :a, action: :keyup },
    # Skip any text — A again
    { frame: 100, button: :a, action: :keydown },
    { frame: 105, button: :a, action: :keyup },
    { frame: 120, button: :a, action: :keydown },
    { frame: 125, button: :a, action: :keyup },
    # Dismiss text screens
    { frame: 185, button: :a, action: :keydown },
    { frame: 190, button: :a, action: :keyup },
    { frame: 230, button: :a, action: :keydown },
    { frame: 235, button: :a, action: :keyup },
    # Game should be starting — move and shoot aggressively
    # Move crosshair right+up, shoot
    { frame: 250, button: :right, action: :keydown },
    { frame: 250, button: :up, action: :keydown },
    { frame: 280, button: :up, action: :keyup },
    { frame: 290, button: :right, action: :keyup },
    { frame: 295, button: :b, action: :keydown },
    { frame: 300, button: :b, action: :keyup },
    # Sweep left, shoot
    { frame: 320, button: :left, action: :keydown },
    { frame: 320, button: :up, action: :keydown },
    { frame: 350, button: :up, action: :keyup },
    { frame: 380, button: :left, action: :keyup },
    { frame: 385, button: :b, action: :keydown },
    { frame: 390, button: :b, action: :keyup },
    # Sweep right+down, shoot
    { frame: 410, button: :right, action: :keydown },
    { frame: 410, button: :down, action: :keydown },
    { frame: 440, button: :down, action: :keyup },
    { frame: 470, button: :right, action: :keyup },
    { frame: 475, button: :b, action: :keydown },
    { frame: 480, button: :b, action: :keyup },
    # Quick left, shoot
    { frame: 500, button: :left, action: :keydown },
    { frame: 530, button: :left, action: :keyup },
    { frame: 535, button: :b, action: :keydown },
    { frame: 540, button: :b, action: :keyup },
    # Up+right, shoot
    { frame: 560, button: :right, action: :keydown },
    { frame: 560, button: :up, action: :keydown },
    { frame: 590, button: :up, action: :keyup },
    { frame: 600, button: :right, action: :keyup },
    { frame: 605, button: :b, action: :keydown },
    { frame: 610, button: :b, action: :keyup },
    # Sweep left, shoot twice
    { frame: 630, button: :left, action: :keydown },
    { frame: 680, button: :left, action: :keyup },
    { frame: 685, button: :b, action: :keydown },
    { frame: 690, button: :b, action: :keyup },
    { frame: 710, button: :up, action: :keydown },
    { frame: 730, button: :up, action: :keyup },
    { frame: 735, button: :b, action: :keydown },
    { frame: 740, button: :b, action: :keyup },
    # Down+right, shoot
    { frame: 760, button: :right, action: :keydown },
    { frame: 760, button: :down, action: :keydown },
    { frame: 790, button: :down, action: :keyup },
    { frame: 810, button: :right, action: :keyup },
    { frame: 815, button: :b, action: :keydown },
    { frame: 820, button: :b, action: :keyup },
    # Final flurry — left, shoot, right, shoot
    { frame: 840, button: :left, action: :keydown },
    { frame: 870, button: :left, action: :keyup },
    { frame: 875, button: :b, action: :keydown },
    { frame: 880, button: :b, action: :keyup },
    { frame: 900, button: :right, action: :keydown },
    { frame: 900, button: :up, action: :keydown },
    { frame: 925, button: :up, action: :keyup },
    { frame: 940, button: :right, action: :keyup },
    { frame: 945, button: :b, action: :keydown },
    { frame: 950, button: :b, action: :keyup },
  ].freeze

  def init
    @viewport = @video.viewport
    @prev_state = {}
    @demo_mode = defined?(TeekDemo) && TeekDemo.active?
    @demo_idx = 0
  end

  def tick(frame, pads)
    # Real keyboard input
    KEY_MAP.each do |key, button|
      down = @viewport.key_down?(key)
      was_down = @prev_state[key]

      if down && !was_down
        event(pads, :keydown, button, 0)
      elsif !down && was_down
        event(pads, :keyup, button, 0)
      end

      @prev_state[key] = down
    end

    # Demo script — virtual button presses by frame count
    if @demo_mode
      while @demo_idx < DEMO_SCRIPT.size && DEMO_SCRIPT[@demo_idx][:frame] <= frame
        cmd = DEMO_SCRIPT[@demo_idx]
        event(pads, cmd[:action], cmd[:button], 0)
        @demo_idx += 1
      end
    end

    # Quit on Q or Escape
    if @viewport.key_down?('q') || @viewport.key_down?('escape')
      throw :quit_nes
    end
  end

  def dispose
  end
end

# --- Register drivers and run ------------------------------------------------

# Inject our drivers into optcarrot's driver database
Optcarrot::Driver::DRIVER_DB[:video][:teek] = :TeekVideo
Optcarrot::Driver::DRIVER_DB[:input][:teek] = :TeekInput
Optcarrot.const_set(:TeekVideo, TeekVideo)
Optcarrot.const_set(:TeekInput, TeekInput)

# Prevent Driver.load_each from trying to require_relative our inline drivers
original_load_each = Optcarrot::Driver.method(:load_each)
Optcarrot::Driver.define_singleton_method(:load_each) do |conf, type, name|
  if name == :teek
    klass_name = Optcarrot::Driver::DRIVER_DB[type][name]
    return Optcarrot.const_get(klass_name)
  end
  original_load_each.call(conf, type, name)
end

# Patch Config's option candidates to accept our driver names
# (candidates are snapshot at class load from DRIVER_DB.keys)
Optcarrot::Config.const_get(:OPTIONS).each do |_section, opts|
  opts.each do |_id, opt|
    next unless opt[:type] == :driver && opt[:candidates]
    opt[:candidates] << :teek unless opt[:candidates].include?(:teek)
  end
end

# Automated demo support (testing and recording)
require_relative '../lib/teek/demo_support'

# Build argv for optcarrot
optcarrot_argv = ['--video=teek', '--input=teek']

if TeekDemo.active?
  # Run for ~960 frames (~16s) in demo mode
  optcarrot_argv << '--frames=960'
end

ARGV.each { |a| optcarrot_argv << a if a.start_with?('--') }
optcarrot_argv << rom_path

nes = Optcarrot::NES.new(optcarrot_argv)
video = nes.instance_variable_get(:@video)
TeekDemo.app = video.app

if TeekDemo.recording?
  video.app.set_window_geometry('+0+0')
  video.app.tcl_eval('. configure -cursor none')
  TeekDemo.signal_recording_ready
end

catch(:quit_nes) { nes.run }

if TeekDemo.active?
  # Signal recording harness directly (can't use TeekDemo.finish because
  # there's no Tk event loop running after the NES exits)
  if (port = ENV['TK_STOP_PORT'])
    begin
      sock = TCPSocket.new('127.0.0.1', port.to_i)
      sock.read(1) # wait for harness to stop ffmpeg
      sock.close
    rescue StandardError
    end
  end
  video.app.destroy('.') rescue nil
end
