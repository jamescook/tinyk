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
      FF_MAX_FRAMES      = 10  # cap for uncapped turbo to avoid locking event loop

      # Default keyboard → GBA button bitmask (Tk keysym → bitmask)
      DEFAULT_KEY_MAP = {
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

      # Default SDL gamepad → GBA button bitmask
      DEFAULT_GAMEPAD_MAP = {
        a:              KEY_A,
        b:              KEY_B,
        back:           KEY_SELECT,
        start:          KEY_START,
        dpad_up:        KEY_UP,
        dpad_down:      KEY_DOWN,
        dpad_left:      KEY_LEFT,
        dpad_right:     KEY_RIGHT,
        left_shoulder:  KEY_L,
        right_shoulder: KEY_R,
      }.freeze

      # GBA button label → bitmask (for remapping)
      GBA_BTN_BITS = {
        a: KEY_A, b: KEY_B,
        l: KEY_L, r: KEY_R,
        up: KEY_UP, down: KEY_DOWN,
        left: KEY_LEFT, right: KEY_RIGHT,
        start: KEY_START, select: KEY_SELECT,
      }.freeze


      def initialize(rom_path = nil)
        @app = Teek::App.new
        @app.interp.thread_timer_ms = 1  # need fast event dispatch for emulation
        @app.show

        @config = Teek::MGBA.user_config
        @scale  = @config.scale
        @volume = @config.volume / 100.0
        @muted  = @config.muted?
        @key_map = DEFAULT_KEY_MAP.dup
        @gamepad_map = DEFAULT_GAMEPAD_MAP.dup
        @dead_zone = Teek::SDL2::Gamepad::DEAD_ZONE
        @turbo_speed = @config.turbo_speed
        @turbo_volume = @config.turbo_volume_pct / 100.0
        @keep_aspect_ratio = @config.keep_aspect_ratio?
        @show_fps = @config.show_fps?
        @fast_forward = false
        @fullscreen = false
        load_keyboard_config

        win_w = GBA_W * @scale
        win_h = GBA_H * @scale
        @app.set_window_title("mGBA Player")
        @app.set_window_geometry("#{win_w}x#{win_h}")

        build_menu

        @settings_window = SettingsWindow.new(@app, callbacks: {
          on_scale_change:        method(:apply_scale),
          on_volume_change:       method(:apply_volume),
          on_mute_change:         method(:apply_mute),
          on_gamepad_map_change:  method(:apply_gamepad_mapping),
          on_keyboard_map_change: method(:apply_keyboard_mapping),
          on_deadzone_change:     method(:apply_deadzone),
          on_gamepad_reset:       method(:apply_gamepad_reset),
          on_keyboard_reset:      method(:apply_keyboard_reset),
          on_undo_gamepad:        method(:undo_mappings),
          on_turbo_speed_change:  method(:apply_turbo_speed),
          on_aspect_ratio_change: method(:apply_aspect_ratio),
          on_show_fps_change:     method(:apply_show_fps),
          on_close:               method(:on_settings_close),
          on_save:                method(:save_config),
        })

        # Push loaded config into the settings UI
        @settings_window.refresh_gamepad(build_kb_labels, 0)
        turbo_label = @turbo_speed == 0 ? 'Uncapped' : "#{@turbo_speed}x"
        @app.set_variable(SettingsWindow::VAR_TURBO, turbo_label)
        scale_label = "#{@scale}x"
        @app.set_variable(SettingsWindow::VAR_SCALE, scale_label)
        @app.set_variable(SettingsWindow::VAR_ASPECT_RATIO, @keep_aspect_ratio ? '1' : '0')
        @app.set_variable(SettingsWindow::VAR_SHOW_FPS, @show_fps ? '1' : '0')

        # Input/emulation state (initialized before SDL2)
        @keys_held = Set.new
        @gamepad = nil
        @running = true
        @paused = false
        @core = nil
        @rom_path = nil
        @initial_rom = rom_path

        # Block interaction until SDL2 is ready
        @app.command('tk', 'busy', '.')
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

      # @return [Hash] current keyboard keysym → GBA button mapping
      attr_reader :key_map

      # @return [Hash] current gamepad → GBA button mapping
      attr_reader :gamepad_map

      # @return [Integer] current analog stick dead zone threshold
      attr_reader :dead_zone

      def run
        @app.after(1) { init_sdl2 }
        @app.mainloop
      ensure
        cleanup
      end

      private

      # Deferred SDL2 initialization — runs inside the event loop so the
      # window is already painted and responsive. Without this, the heavy
      # SDL2 C calls (renderer, audio device, gamepad IOKit) block the
      # main thread before macOS has a chance to display the window,
      # causing a brief spinning beach ball.
      def init_sdl2
        win_w = GBA_W * @scale
        win_h = GBA_H * @scale

        @viewport = Teek::SDL2::Viewport.new(@app, width: win_w, height: win_h, vsync: false)
        @viewport.pack(fill: :both, expand: true)

        # Status label overlaid on viewport (shown when no ROM loaded)
        @status_label = '.status_overlay'
        @app.command(:label, @status_label,
          text: 'File > Open ROM...',
          fg: '#888888', bg: '#000000',
          font: '{TkDefaultFont} 11')
        @app.command(:place, @status_label,
          in: @viewport.frame.path,
          relx: 0.5, rely: 0.85, anchor: :center)

        # Streaming texture at native GBA resolution
        @texture = @viewport.renderer.create_texture(GBA_W, GBA_H, :streaming)

        # Font for on-screen indicators (fast-forward, etc.)
        font_path = File.expand_path('../../../assets/JetBrainsMonoNL-Regular.ttf', __dir__)
        @overlay_font = File.exist?(font_path) ? @viewport.renderer.load_font(font_path, 14) : nil
        @ff_label_tex = nil
        @fps_tex = nil
        @fps_shadow_tex = nil

        # Audio stream — stereo int16 at GBA sample rate
        @stream = Teek::SDL2::AudioStream.new(
          frequency: AUDIO_FREQ,
          format:    :s16,
          channels:  2
        )
        @stream.resume

        # Initialize gamepad subsystem for hot-plug detection
        Teek::SDL2::Gamepad.init_subsystem
        Teek::SDL2::Gamepad.on_added { |_| refresh_gamepads }
        Teek::SDL2::Gamepad.on_removed { |_| @gamepad = nil; refresh_gamepads }
        refresh_gamepads
        start_gamepad_probe

        setup_input

        load_rom(@initial_rom) if @initial_rom

        # Unblock interaction now that SDL2 is ready
        @app.command('tk', 'busy', 'forget', '.')

        # Auto-focus viewport for keyboard input
        @app.tcl_eval("focus -force #{@viewport.frame.path}")
        @app.update

        animate
      end

      def show_settings
        @was_paused_before_settings = @paused
        toggle_fast_forward if @fast_forward
        toggle_pause if @core && !@paused
        @settings_window.show
      end

      def on_settings_close
        toggle_pause if @core && !@was_paused_before_settings
      end

      def save_config
        @config.scale = @scale
        @config.volume = (@volume * 100).round
        @config.muted = @muted
        @config.turbo_speed = @turbo_speed
        @config.keep_aspect_ratio = @keep_aspect_ratio
        @config.show_fps = @show_fps

        # Save keyboard mappings under sentinel GUID
        @key_map.each do |keysym, bit|
          gba_btn = GBA_BTN_BITS.key(bit)
          @config.set_mapping(Config::KEYBOARD_GUID, gba_btn, keysym) if gba_btn
        end

        # Save gamepad mappings under real GUID
        if (guid = current_gamepad_guid)
          @config.gamepad(guid, name: @gamepad.name)
          pct = (@dead_zone.to_f / 32767 * 100).round
          @config.set_dead_zone(guid, pct)
          @gamepad_map.each do |gp_btn, bit|
            gba_btn = GBA_BTN_BITS.key(bit)
            @config.set_mapping(guid, gba_btn, gp_btn) if gba_btn
          end
        end
        @config.save!
      end

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

      def apply_gamepad_mapping(gba_btn, gp_btn)
        bit = GBA_BTN_BITS[gba_btn] or return
        @gamepad_map.delete_if { |_, v| v == bit }
        @gamepad_map[gp_btn] = bit
      end

      def apply_deadzone(threshold)
        @dead_zone = threshold.to_i
      end

      def apply_gamepad_reset
        @gamepad_map = DEFAULT_GAMEPAD_MAP.dup
        @dead_zone = Teek::SDL2::Gamepad::DEAD_ZONE
      end

      def apply_keyboard_mapping(gba_btn, keysym)
        bit = GBA_BTN_BITS[gba_btn] or return
        @key_map.delete_if { |_, v| v == bit }
        @key_map[keysym.to_s] = bit
      end

      def apply_keyboard_reset
        @key_map = DEFAULT_KEY_MAP.dup
      end

      # Undo: reload mappings from disk for the current settings mode
      def undo_mappings
        @config.reload!
        if @settings_window.keyboard_mode?
          load_keyboard_config
          labels = build_kb_labels
          @settings_window.refresh_gamepad(labels, 0)
        else
          load_gamepad_config if @gamepad
          labels = build_gp_labels
          pct = (@dead_zone.to_f / 32767 * 100).round
          @settings_window.refresh_gamepad(labels, pct)
        end
      end

      def current_gamepad_guid
        @gamepad&.guid rescue nil
      end

      # Load stored keyboard config from the sentinel GUID
      def load_keyboard_config
        kb_cfg = @config.mappings(Config::KEYBOARD_GUID)
        @key_map = {}
        kb_cfg.each do |gba_str, keysym|
          bit = GBA_BTN_BITS[gba_str.to_sym]
          next unless bit
          @key_map[keysym] = bit
        end
      end

      # Load stored gamepad config for the current controller
      def load_gamepad_config
        return unless @gamepad
        guid = @gamepad.guid rescue return
        gp_cfg = @config.gamepad(guid, name: @gamepad.name)

        # Apply stored mappings
        @gamepad_map = {}
        gp_cfg['mappings'].each do |gba_str, gp_str|
          bit = GBA_BTN_BITS[gba_str.to_sym]
          next unless bit
          @gamepad_map[gp_str.to_sym] = bit
        end

        # Apply stored dead zone
        pct = gp_cfg['dead_zone']
        @dead_zone = (pct / 100.0 * 32767).round
      end

      # Build label hash from current @key_map (for settings window refresh)
      def build_kb_labels
        labels = {}
        @key_map.each do |keysym, bit|
          gba_btn = GBA_BTN_BITS.key(bit)
          labels[gba_btn] = keysym if gba_btn
        end
        labels
      end

      # Build label hash from current @gamepad_map (for settings window refresh)
      def build_gp_labels
        labels = {}
        @gamepad_map.each do |gp_btn, bit|
          gba_btn = GBA_BTN_BITS.key(bit)
          labels[gba_btn] = gp_btn.to_s if gba_btn
        end
        labels
      end

      GAMEPAD_PROBE_MS  = 2000
      GAMEPAD_LISTEN_MS = 50

      def start_gamepad_probe
        @app.after(GAMEPAD_PROBE_MS) { gamepad_probe_tick }
      end

      def gamepad_probe_tick
        return unless @running
        has_gp = @gamepad && !@gamepad.closed?
        settings_visible = @app.command(:wm, 'state', SettingsWindow::TOP) != 'withdrawn' rescue false

        # When settings is visible, use update_state (SDL_GameControllerUpdate)
        # instead of poll_events (SDL_PollEvent) to avoid pumping the Cocoa
        # run loop, which steals events from Tk's native widgets.
        # Background events hint ensures update_state gets fresh data even
        # when the SDL window doesn't have focus.
        if settings_visible && has_gp
          Teek::SDL2::Gamepad.update_state

          # Listen mode: capture first pressed button for remap
          if @settings_window.listening_for
            Teek::SDL2::Gamepad.buttons.each do |btn|
              if @gamepad.button?(btn)
                @settings_window.capture_mapping(btn)
                break
              end
            end
          end

          @app.after(GAMEPAD_LISTEN_MS) { gamepad_probe_tick }
          return
        end

        # Settings closed: use poll_events for hot-plug callbacks
        unless @core
          Teek::SDL2::Gamepad.poll_events rescue nil
        end
        @app.after(GAMEPAD_PROBE_MS) { gamepad_probe_tick }
      end

      def refresh_gamepads
        names = ['Keyboard Only']
        prev_gp = @gamepad
        8.times do |i|
          gp = begin; Teek::SDL2::Gamepad.open(i); rescue; nil; end
          next unless gp
          names << gp.name
          @gamepad ||= gp
          gp.close unless gp == @gamepad
        end
        @settings_window&.update_gamepad_list(names)
        update_status_label
        load_gamepad_config if @gamepad && @gamepad != prev_gp
      end

      def update_status_label
        return if @core # hidden during gameplay
        gp_text = @gamepad ? @gamepad.name : 'No gamepad detected'
        @app.command(@status_label, :configure,
          text: "File > Open ROM...\n#{gp_text}")
      end

      def setup_input
        @viewport.bind('KeyPress', :keysym) do |k|
          if k == 'q'
            @running = false
          elsif k == 'Escape'
            @fullscreen ? toggle_fullscreen : (@running = false)
          elsif k == 'p'
            toggle_pause
          elsif k == 'Tab'
            toggle_fast_forward
          elsif k == 'F11'
            toggle_fullscreen
          elsif k == 'F3'
            toggle_show_fps
          else
            @keys_held.add(k)
          end
        end

        @viewport.bind('KeyRelease', :keysym) do |k|
          @keys_held.delete(k)
        end

        @viewport.bind('FocusIn')  { @has_focus = true }
        @viewport.bind('FocusOut') { @has_focus = false }

        # Alt+Return fullscreen toggle (emulator convention)
        @app.command(:bind, @viewport.frame.path, '<Alt-Return>', proc { toggle_fullscreen })
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

        # Recent ROMs submenu
        @recent_menu = "#{menubar}.file.recent"
        @app.command(:menu, @recent_menu, tearoff: 0)
        @app.command("#{menubar}.file", :add, :cascade,
                     label: 'Recent', menu: @recent_menu)
        rebuild_recent_menu

        @app.command("#{menubar}.file", :add, :separator)
        @app.command("#{menubar}.file", :add, :command,
                     label: 'Settings...', accelerator: 'Cmd+,',
                     command: proc { show_settings })
        @app.command("#{menubar}.file", :add, :separator)
        @app.command("#{menubar}.file", :add, :command,
                     label: 'Quit', accelerator: 'Cmd+Q',
                     command: proc { @running = false })

        @app.command(:bind, '.', '<Command-o>', proc { open_rom_dialog })
        @app.command(:bind, '.', '<Command-comma>', proc { show_settings })

        # View menu
        view_menu = "#{menubar}.view"
        @app.command(:menu, view_menu, tearoff: 0)
        @app.command(menubar, :add, :cascade, label: 'View', menu: view_menu)

        @app.command(view_menu, :add, :command,
                     label: 'Fullscreen', accelerator: 'F11',
                     command: proc { toggle_fullscreen })

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

      def toggle_fast_forward
        return unless @core
        @fast_forward = !@fast_forward
        if @fast_forward
          rebuild_ff_label
        else
          destroy_ff_label
          @next_frame = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @stream.clear
        end
      end

      def apply_turbo_speed(speed)
        @turbo_speed = speed
        rebuild_ff_label if @fast_forward
      end

      def apply_aspect_ratio(keep)
        @keep_aspect_ratio = keep
      end

      def toggle_fullscreen
        @fullscreen = !@fullscreen
        @app.command(:wm, 'attributes', '.', '-fullscreen', @fullscreen ? 1 : 0)
      end

      def apply_show_fps(show)
        @show_fps = show
        destroy_fps_overlay unless @show_fps
      end

      def toggle_show_fps
        @show_fps = !@show_fps
        destroy_fps_overlay unless @show_fps
        @app.set_variable(SettingsWindow::VAR_SHOW_FPS, @show_fps ? '1' : '0')
      end

      def rebuild_fps_overlay(text)
        destroy_fps_overlay
        return unless @overlay_font
        @fps_tex = @overlay_font.render_text(text, 0, 255, 0)
        @fps_shadow_tex = @overlay_font.render_text(text, 0, 0, 0)
      end

      def destroy_fps_overlay
        @fps_tex&.destroy
        @fps_tex = nil
        @fps_shadow_tex&.destroy
        @fps_shadow_tex = nil
      end

      def rebuild_ff_label
        destroy_ff_label
        label = @turbo_speed == 0 ? '>> MAX' : ">> #{@turbo_speed}x"
        @ff_label_tex = @overlay_font.render_text(label, 255, 255, 0)
      end

      def destroy_ff_label
        if @ff_label_tex
          @ff_label_tex.destroy
          @ff_label_tex = nil
        end
      end

      def reset_core
        return unless @rom_path
        load_rom(@rom_path)
      end

      def confirm_rom_change(new_path)
        return true unless @core && !@core.destroyed?

        name = File.basename(new_path)
        result = @app.command('tk_messageBox',
          parent: '.',
          title: 'Game Running',
          message: "Another game is running. Switch to #{name}?",
          type: :okcancel,
          icon: :warning)
        result == 'ok'
      end

      def open_rom_dialog
        filetypes = '{{GBA ROMs} {.gba}} {{GB ROMs} {.gb .gbc}} {{All Files} {*}}'
        path = @app.tcl_eval("tk_getOpenFile -title {Open ROM} -filetypes {#{filetypes}}")
        return if path.empty?
        return unless confirm_rom_change(path)

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
        @app.command(:place, :forget, @status_label) rescue nil
        @app.set_window_title("mGBA — #{@core.title}")
        @fps_count = 0
        @fps_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @next_frame = @fps_time
        @audio_samples_produced = 0

        @config.add_recent_rom(path)
        @config.save!
        rebuild_recent_menu
      end

      def open_recent_rom(path)
        unless File.exist?(path)
          @app.command('tk_messageBox',
            parent: '.',
            title: 'ROM Not Found',
            message: "The ROM file no longer exists:\n#{path}",
            type: :ok,
            icon: :error)
          @config.remove_recent_rom(path)
          @config.save!
          rebuild_recent_menu
          return
        end
        return unless confirm_rom_change(path)

        load_rom(path)
      end

      def rebuild_recent_menu
        # Clear all existing entries
        @app.command(@recent_menu, :delete, 0, :end) rescue nil

        roms = @config.recent_roms
        if roms.empty?
          @app.command(@recent_menu, :add, :command,
                       label: '(none)', state: :disabled)
        else
          roms.each do |rom_path|
            label = File.basename(rom_path)
            @app.command(@recent_menu, :add, :command,
                         label: label,
                         command: proc { open_recent_rom(rom_path) })
          end
          @app.command(@recent_menu, :add, :separator)
          @app.command(@recent_menu, :add, :command,
                       label: 'Clear',
                       command: proc { clear_recent_roms })
        end
      end

      def clear_recent_roms
        @config.clear_recent_roms
        @config.save!
        rebuild_recent_menu
      end

      def tick
        unless @core
          @viewport.render { |r| r.clear(0, 0, 0) }
          return
        end

        if @paused
          dest = compute_dest_rect
          @viewport.render do |r|
            r.clear(0, 0, 0)
            r.copy(@texture, nil, dest)
            draw_fps_overlay(r, dest)
          end
          return
        end

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @next_frame ||= now

        if @fast_forward
          tick_fast_forward(now)
        else
          tick_normal(now)
        end
      end

      def tick_normal(now)
        frames = 0
        while @next_frame <= now && frames < 4
          run_one_frame
          queue_audio

          # Near/byuu: nudge frame period ±0.5% to keep audio buffer ~50% full
          fill = (@stream.queued_samples.to_f / AUDIO_BUF_CAPACITY).clamp(0.0, 1.0)
          ratio = (1.0 - MAX_DELTA) + 2.0 * fill * MAX_DELTA
          @next_frame += FRAME_PERIOD * ratio
          frames += 1
        end

        @next_frame = now if now - @next_frame > 0.1
        return if frames == 0

        render_frame
        update_fps(frames, now)
      end

      def tick_fast_forward(now)
        if @turbo_speed == 0
          # Uncapped: poll input once per tick to avoid flooding the Cocoa
          # event loop (SDL_PollEvent pumps it), then blast through frames.
          keys = poll_input
          FF_MAX_FRAMES.times do |i|
            @core.set_keys(keys)
            @core.run_frame
            i == 0 ? queue_audio(volume_override: @turbo_volume) : @core.audio_buffer
          end
          @next_frame = now
          render_frame(ff_indicator: true)
          update_fps(FF_MAX_FRAMES, now)
          return
        end

        # Paced turbo (2x, 3x, 4x): run @turbo_speed frames per FRAME_PERIOD.
        # Same timing gate as tick_normal so 2x ≈ 120 fps, not 2000 fps.
        frames = 0
        while @next_frame <= now && frames < @turbo_speed * 4
          @turbo_speed.times do
            run_one_frame
            frames == 0 ? queue_audio(volume_override: @turbo_volume) : @core.audio_buffer
            frames += 1
          end
          @next_frame += FRAME_PERIOD
        end
        @next_frame = now if now - @next_frame > 0.1
        return if frames == 0

        render_frame(ff_indicator: true)
        update_fps(frames, now)
      end

      # Read keyboard + gamepad state, return combined bitmask.
      # Uses SDL_GameControllerUpdate (not SDL_PollEvent) to read gamepad
      # state without pumping the Cocoa event loop on macOS — SDL_PollEvent
      # steals NSKeyDown events from Tk, making quit/escape unresponsive.
      # Hot-plug detection is handled separately by start_gamepad_probe.
      def poll_input
        kb_mask = 0
        @key_map.each { |key, bit| kb_mask |= bit if @keys_held.include?(key) }

        gp_mask = 0
        begin
          Teek::SDL2::Gamepad.update_state
          if @gamepad && !@gamepad.closed?
            @gamepad_map.each { |btn, bit| gp_mask |= bit if @gamepad.button?(btn) }
          end
        rescue StandardError
          @gamepad = nil
        end

        kb_mask | gp_mask
      end

      def run_one_frame
        @core.set_keys(poll_input)
        @core.run_frame
      end

      def queue_audio(volume_override: nil)
        pcm = @core.audio_buffer
        return if pcm.empty?

        @audio_samples_produced += pcm.bytesize / 4
        if @muted
          # Drain blip buffer but don't queue — keeps emulation in sync
        else
          vol = volume_override || @volume
          if vol < 1.0
            @stream.queue(apply_volume_to_pcm(pcm, vol))
          else
            @stream.queue(pcm)
          end
        end
      end

      def render_frame(ff_indicator: false)
        pixels = @core.video_buffer_argb
        @texture.update(pixels)
        dest = compute_dest_rect
        @viewport.render do |r|
          r.clear(0, 0, 0)
          r.copy(@texture, nil, dest)
          if ff_indicator && @ff_label_tex
            ox = dest ? dest[0] : 0
            oy = dest ? dest[1] : 0
            r.copy(@ff_label_tex, nil, [ox + 4, oy + 4, @ff_label_tex.width, @ff_label_tex.height])
          end
          draw_fps_overlay(r, dest)
        end
      end

      # Draw FPS counter in top-right of game area with thick black outline
      # for contrast — readable against any background. Uses 2px offsets in
      # 8 directions so the outline is visible on HiDPI/Retina displays.
      OUTLINE_OFFSETS = [[-2,0],[2,0],[0,-2],[0,2],[-1,-1],[-1,1],[1,-1],[1,1]].freeze

      def draw_fps_overlay(r, dest)
        return unless @show_fps && @fps_tex
        fx = (dest ? dest[0] + dest[2] : r.output_size[0]) - @fps_tex.width - 6
        fy = (dest ? dest[1] : 0) + 4
        sw = @fps_shadow_tex.width
        sh = @fps_shadow_tex.height
        OUTLINE_OFFSETS.each { |dx, dy| r.copy(@fps_shadow_tex, nil, [fx + dx, fy + dy, sw, sh]) }
        r.copy(@fps_tex, nil, [fx, fy, @fps_tex.width, @fps_tex.height])
      end

      # Calculate a centered destination rectangle that preserves the GBA's 3:2
      # aspect ratio within the current renderer output. Returns nil when
      # stretching is preferred (keep_aspect_ratio off).
      #
      # Example — fullscreen on a 1920x1080 (16:9) monitor:
      #   scale_x = 1920 / 240 = 8.0
      #   scale_y = 1080 / 160 = 6.75
      #   scale   = min(8.0, 6.75) = 6.75   (height is the constraint)
      #   dest    = [150, 0, 1620, 1080]     (pillarboxed: 150px black bars L+R)
      #
      # Example — fullscreen on a 2560x1600 (16:10) monitor:
      #   scale_x = 2560 / 240 ≈ 10.67
      #   scale_y = 1600 / 160 = 10.0
      #   scale   = 10.0
      #   dest    = [80, 0, 2400, 1600]      (pillarboxed: 80px bars L+R)
      def compute_dest_rect
        return nil unless @keep_aspect_ratio

        out_w, out_h = @viewport.renderer.output_size
        scale_x = out_w.to_f / GBA_W
        scale_y = out_h.to_f / GBA_H
        scale = [scale_x, scale_y].min

        dest_w = (GBA_W * scale).to_i
        dest_h = (GBA_H * scale).to_i
        dest_x = (out_w - dest_w) / 2
        dest_y = (out_h - dest_h) / 2

        [dest_x, dest_y, dest_w, dest_h]
      end

      def update_fps(frames, now)
        @fps_count += frames
        elapsed = now - @fps_time
        if elapsed >= 1.0
          fps = (@fps_count / elapsed).round(1)
          rebuild_fps_overlay("#{fps} fps") if @show_fps
          @audio_samples_produced = 0
          @fps_count = 0
          @fps_time = now
        end
      end

      def animate
        if @running
          tick
          delay = (@core && !@paused) ? 1 : 100
          @app.after(delay) { animate }
        else
          cleanup
          @app.command(:destroy, '.')
        end
      end

      # Apply software volume to int16 stereo PCM data.
      def apply_volume_to_pcm(pcm, gain = @volume)
        samples = pcm.unpack('s*')
        samples.map! { |s| (s * gain).round.clamp(-32768, 32767) }
        samples.pack('s*')
      end

      def cleanup
        return if @cleaned_up
        @cleaned_up = true

        @stream&.pause unless @stream&.destroyed?
        destroy_ff_label
        destroy_fps_overlay
        @overlay_font&.destroy unless @overlay_font&.destroyed?
        @stream&.destroy unless @stream&.destroyed?
        @texture&.destroy unless @texture&.destroyed?
        @core&.destroy unless @core&.destroyed?
      end
    end
  end
end
