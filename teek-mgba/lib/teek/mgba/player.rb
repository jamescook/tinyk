# frozen_string_literal: true

require 'set'

module Teek
  module MGBA
    # Full-featured GBA frontend powered by teek + teek-sdl2.
    #
    # Renders GBA games at 3x native resolution with audio and
    # keyboard/gamepad input. Uses wall-clock frame pacing with
    # Near/byuu dynamic rate control for audio sync.
    #
    # @example Launch with a ROM
    #   Teek::MGBA::Player.new("pokemon.gba").run
    #
    # @example Launch without a ROM (use File > Open ROM...)
    #   Teek::MGBA::Player.new.run
    class Player
      include Teek::MGBA

      GBA_W  = 240
      GBA_H  = 160
      DEFAULT_SCALE = 3

      # GBA audio: mGBA outputs at 44100 Hz (stereo int16)
      AUDIO_FREQ     = 44100
      GBA_FPS        = 59.7272
      FRAME_PERIOD   = 1.0 / GBA_FPS

      # Dynamic rate control (Near/byuu algorithm adapted for frame timing)
      # Keep audio buffer ~50% full by adjusting frame period ±0.5%.
      AUDIO_BUF_CAPACITY = (AUDIO_FREQ / GBA_FPS * 6).to_i  # ~6 frames (~100ms)
      MAX_DELTA          = 0.005

      # Keyboard → GBA button bitmask
      KEY_MAP = {
        'z'         => KEY_A,
        'x'         => KEY_B,
        'BackSpace' => KEY_SELECT,
        'Return'    => KEY_START,
        'Right'     => KEY_RIGHT,
        'Left'      => KEY_LEFT,
        'Up'        => KEY_UP,
        'Down'      => KEY_DOWN,
        'a'         => KEY_L,
        's'         => KEY_R,
      }.freeze

      # SDL gamepad → GBA button bitmask
      GAMEPAD_MAP = {
        a:             KEY_A,
        b:             KEY_B,
        back:          KEY_SELECT,
        start:         KEY_START,
        dpup:          KEY_UP,
        dpdown:        KEY_DOWN,
        dpleft:        KEY_LEFT,
        dpright:       KEY_RIGHT,
        leftshoulder:  KEY_L,
        rightshoulder: KEY_R,
      }.freeze

      def initialize(rom_path = nil)
        @app = Teek::App.new
        @app.interp.thread_timer_ms = 1  # need fast event dispatch for emulation
        @app.show

        @scale  = DEFAULT_SCALE
        @volume = 1.0
        @muted  = false

        win_w = GBA_W * @scale
        win_h = GBA_H * @scale
        @app.set_window_title("mGBA Player")
        @app.set_window_geometry("#{win_w}x#{win_h}")

        build_menu

        @settings_window = SettingsWindow.new(@app, callbacks: {
          on_scale_change:  method(:apply_scale),
          on_volume_change: method(:apply_volume),
          on_mute_change:   method(:apply_mute),
        })

        @viewport = Teek::SDL2::Viewport.new(@app, width: win_w, height: win_h, vsync: false)
        @viewport.pack(fill: :both, expand: true)

        # Streaming texture at native GBA resolution
        @texture = @viewport.renderer.create_texture(GBA_W, GBA_H, :streaming)

        # Audio stream — stereo int16 at GBA sample rate
        @stream = Teek::SDL2::AudioStream.new(
          frequency: AUDIO_FREQ,
          format:    :s16,
          channels:  2
        )
        @stream.resume

        # Input state
        @keys_held = Set.new
        @gamepad = nil
        @running = true
        @paused = false
        @core = nil
        @rom_path = nil

        setup_input

        load_rom(rom_path) if rom_path

        # Auto-focus viewport for keyboard input
        @app.tcl_eval("focus -force #{@viewport.frame.path}")
        @app.update
      end

      # @return [Integer] current video scale multiplier
      attr_reader :scale

      # @return [Float] current audio volume (0.0-1.0)
      attr_reader :volume

      # @return [Boolean] whether audio is muted
      def muted?
        @muted
      end

      # @return [Teek::MGBA::SettingsWindow]
      attr_reader :settings_window

      def run
        animate
        @app.mainloop
      ensure
        cleanup
      end

      private

      def apply_scale(new_scale)
        @scale = new_scale.clamp(1, 4)
        w = GBA_W * @scale
        h = GBA_H * @scale
        @app.set_window_geometry("#{w}x#{h}")
      end

      def apply_volume(vol)
        @volume = vol.to_f.clamp(0.0, 1.0)
      end

      def apply_mute(muted)
        @muted = !!muted
      end

      def setup_input
        @viewport.bind('KeyPress', :keysym) do |k|
          if k == 'q' || k == 'Escape'
            @running = false
          elsif k == 'p'
            toggle_pause
          else
            @keys_held.add(k)
          end
        end

        @viewport.bind('KeyRelease', :keysym) do |k|
          @keys_held.delete(k)
        end

        @viewport.bind('FocusIn')  { @has_focus = true }
        @viewport.bind('FocusOut') { @has_focus = false }
      end

      def build_menu
        menubar = '.menubar'
        @app.command(:menu, menubar)
        @app.command('.', :configure, menu: menubar)

        # File menu
        @app.command(:menu, "#{menubar}.file", tearoff: 0)
        @app.command(menubar, :add, :cascade, label: 'File', menu: "#{menubar}.file")

        @app.command("#{menubar}.file", :add, :command,
                     label: 'Open ROM...', accelerator: 'Cmd+O',
                     command: proc { open_rom_dialog })
        @app.command("#{menubar}.file", :add, :separator)
        @app.command("#{menubar}.file", :add, :command,
                     label: 'Settings...', accelerator: 'Cmd+,',
                     command: proc { @settings_window.show })
        @app.command("#{menubar}.file", :add, :separator)
        @app.command("#{menubar}.file", :add, :command,
                     label: 'Quit', accelerator: 'Cmd+Q',
                     command: proc { @running = false })

        @app.command(:bind, '.', '<Command-o>', proc { open_rom_dialog })
        @app.command(:bind, '.', '<Command-comma>', proc { @settings_window.show })

        # Emulation menu
        @emu_menu = "#{menubar}.emu"
        @app.command(:menu, @emu_menu, tearoff: 0)
        @app.command(menubar, :add, :cascade, label: 'Emulation', menu: @emu_menu)

        @app.command(@emu_menu, :add, :command,
                     label: 'Pause', accelerator: 'P',
                     command: proc { toggle_pause })
        @app.command(@emu_menu, :add, :command,
                     label: 'Reset', accelerator: 'Cmd+R',
                     command: proc { reset_core })

        @app.command(:bind, '.', '<Command-r>', proc { reset_core })
      end

      def toggle_pause
        return unless @core
        @paused = !@paused
        if @paused
          @stream.pause
          @app.command(@emu_menu, :entryconfigure, 0, label: 'Resume')
        else
          @stream.resume
          @next_frame = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @app.command(@emu_menu, :entryconfigure, 0, label: 'Pause')
        end
      end

      def reset_core
        return unless @rom_path
        load_rom(@rom_path)
      end

      def open_rom_dialog
        filetypes = '{{GBA ROMs} {.gba}} {{GB ROMs} {.gb .gbc}} {{All Files} {*}}'
        path = @app.tcl_eval("tk_getOpenFile -title {Open ROM} -filetypes {#{filetypes}}")
        return if path.empty?

        load_rom(path)
      end

      def load_rom(path)
        if @core && !@core.destroyed?
          @core.destroy
        end
        @stream.clear

        @core = Core.new(path)
        @rom_path = path
        @paused = false
        @stream.resume
        @app.set_window_title("mGBA — #{@core.title}")
        @fps_count = 0
        @fps_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @next_frame = @fps_time
        @audio_samples_produced = 0
      end

      def tick
        unless @core
          @viewport.render { |r| r.clear(0, 0, 0) }
          return
        end

        if @paused
          @viewport.render do |r|
            r.clear(0, 0, 0)
            r.copy(@texture)
          end
          return
        end

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @next_frame ||= now

        # Run as many frames as wall-clock says we owe (cap at 4)
        frames = 0
        while @next_frame <= now && frames < 4
          # 1. Input
          kb_mask = 0
          KEY_MAP.each { |key, bit| kb_mask |= bit if @keys_held.include?(key) }

          gp_mask = 0
          begin
            Teek::SDL2::Gamepad.poll_events
            @gamepad ||= Teek::SDL2::Gamepad.gamepads.first
            if @gamepad && !@gamepad.closed?
              GAMEPAD_MAP.each { |btn, bit| gp_mask |= bit if @gamepad.button?(btn) }
            end
          rescue StandardError
            @gamepad = nil
          end

          @core.set_keys(kb_mask | gp_mask)

          # 2. Emulate one frame
          @core.run_frame

          # 3. Audio — queue and apply dynamic rate control
          pcm = @core.audio_buffer
          unless pcm.empty?
            @audio_samples_produced += pcm.bytesize / 4
            if @muted
              # Drain blip buffer but don't queue — keeps emulation in sync
            elsif @volume < 1.0
              @stream.queue(apply_volume_to_pcm(pcm))
            else
              @stream.queue(pcm)
            end
          end

          # Near/byuu: nudge frame period ±0.5% to keep audio buffer ~50% full
          fill = (@stream.queued_samples.to_f / AUDIO_BUF_CAPACITY).clamp(0.0, 1.0)
          ratio = (1.0 - MAX_DELTA) + 2.0 * fill * MAX_DELTA
          @next_frame += FRAME_PERIOD * ratio
          frames += 1
        end

        # Reset if we fell way behind
        @next_frame = now if now - @next_frame > 0.1

        return if frames == 0

        # 4. Video — render last frame only
        pixels = @core.video_buffer_argb
        @texture.update(pixels)
        @viewport.render do |r|
          r.clear(0, 0, 0)
          r.copy(@texture)
        end

        # 5. FPS
        @fps_count += frames
        elapsed = now - @fps_time
        if elapsed >= 1.0
          fps = @fps_count / elapsed
          actual_rate = (@audio_samples_produced / elapsed).round
          buf_ms = (@stream.queued_samples * 1000.0 / AUDIO_FREQ).round
          @app.set_window_title("mGBA — #{@core.title}  #{fps.round(1)} fps  rate:#{actual_rate}  buf:#{buf_ms}ms")
          @audio_samples_produced = 0
          @fps_count = 0
          @fps_time = now
        end
      end

      def animate
        tick
        if @running
          delay = @core ? 1 : 100
          @app.after(delay) { animate }
        else
          @app.command(:destroy, '.')
        end
      end

      # Apply software volume to int16 stereo PCM data.
      def apply_volume_to_pcm(pcm)
        samples = pcm.unpack('s*')
        gain = @volume
        samples.map! { |s| (s * gain).round.clamp(-32768, 32767) }
        samples.pack('s*')
      end

      def cleanup
        @stream&.pause unless @stream&.destroyed?
        @stream&.destroy unless @stream&.destroyed?
        @texture&.destroy
        @core&.destroy unless @core&.destroyed?
      end
    end
  end
end
