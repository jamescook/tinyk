# frozen_string_literal: true

require 'fileutils'
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
      TOAST_DURATION     = 1.5 # seconds (fallback; overridden by config)
      SAVE_STATE_DEBOUNCE_DEFAULT = 3.0 # seconds; overridden by config
      SAVE_STATE_SLOTS    = 10

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
        @quick_save_slot = @config.quick_save_slot
        @save_state_backup = @config.save_state_backup?
        @last_save_time = 0
        @state_dir = nil  # set when ROM loaded
        load_keyboard_config

        win_w = GBA_W * @scale
        win_h = GBA_H * @scale
        @app.set_window_title("mGBA Player")
        @app.set_window_geometry("#{win_w}x#{win_h}")

        build_menu

        @rom_info_window = RomInfoWindow.new(@app, callbacks: {
          on_close: method(:on_child_window_close),
        })
        @state_picker = SaveStatePicker.new(@app, callbacks: {
          on_save: method(:save_state),
          on_load: method(:load_state),
          on_close: method(:on_child_window_close),
        })

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
          on_toast_duration_change: method(:apply_toast_duration),
          on_quick_slot_change:   method(:apply_quick_slot),
          on_backup_change:       method(:apply_backup),
          on_close:               method(:on_child_window_close),
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
        toast_label = "#{@config.toast_duration}s"
        @app.set_variable(SettingsWindow::VAR_TOAST_DURATION, toast_label)
        @app.set_variable(SettingsWindow::VAR_QUICK_SLOT, @quick_save_slot.to_s)
        @app.set_variable(SettingsWindow::VAR_SS_BACKUP, @save_state_backup ? '1' : '0')

        # Input/emulation state (initialized before SDL2)
        @keys_held = Set.new
        @gamepad = nil
        @running = true
        @paused = false
        @core = nil
        @rom_path = nil
        @initial_rom = rom_path
        @modal_child = nil  # tracks which child window is open

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
        # Crop height for inverse-blend overlays: ascent covers glyphs above
        # baseline, plus a few pixels for common descenders (p, g, y).
        # This excludes the very bottom rows where TTF AA residue causes
        # artifacts under inverse blending.
        if @overlay_font
          ascent = @overlay_font.ascent
          full_h = @overlay_font.measure('p')[1]
          @overlay_crop_h = [ascent + (full_h - ascent) / 2, full_h - 1].min
        end
        @ff_label_tex = nil
        @fps_tex = nil
        @fps_shadow_tex = nil
        @toast_tex = nil
        @toast_expires = 0

        # Custom blend mode: white text inverts the background behind it.
        # dstRGB = (1 - dstRGB) * srcRGB + dstRGB * (1 - srcA)
        # Where srcA=1 (opaque text): result = 1 - dst  (inverted)
        # Where srcA=0 (transparent): result = dst      (unchanged)
        @inverse_blend = Teek::SDL2.compose_blend_mode(
          :one_minus_dst_color, :one_minus_src_alpha, :add,
          :zero, :one, :add
        )

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

      def show_rom_info
        return unless @core && !@core.destroyed?
        return bell if @modal_child
        @modal_child = :rom_info
        enter_modal
        saves = @config.saves_dir
        sav_name = File.basename(@rom_path, File.extname(@rom_path)) + '.sav'
        sav_path = File.join(saves, sav_name)
        @rom_info_window.show(@core, rom_path: @rom_path, save_path: sav_path)
      end

      # -- Save states ---------------------------------------------------------

      # Build per-ROM state directory path using game code + CRC32.
      # e.g. states/AGB-BTKE-A1B2C3D4/
      def state_dir_for_rom(core)
        code = core.game_code.gsub(/[^a-zA-Z0-9_.-]/, '_')
        crc  = format('%08X', core.checksum)
        File.join(@config.states_dir, "#{code}-#{crc}")
      end

      def state_path(slot)
        File.join(@state_dir, "state#{slot}.ss")
      end

      def screenshot_path(slot)
        File.join(@state_dir, "state#{slot}.png")
      end

      def save_state(slot)
        return unless @core && !@core.destroyed?

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if now - @last_save_time < @config.save_state_debounce
          show_toast("Save blocked (too fast)")
          return
        end

        FileUtils.mkdir_p(@state_dir) unless File.directory?(@state_dir)

        # Backup rotation: existing files → .bak (if enabled)
        ss = state_path(slot)
        png = screenshot_path(slot)
        if @save_state_backup
          File.rename(ss, "#{ss}.bak") if File.exist?(ss)
          File.rename(png, "#{png}.bak") if File.exist?(png)
        end

        if @core.save_state_to_file(ss)
          @last_save_time = now
          save_screenshot(png)
          show_toast("State saved to slot #{slot}")
        else
          show_toast("Failed to save state")
        end
      end

      def load_state(slot)
        return unless @core && !@core.destroyed?

        ss = state_path(slot)
        unless File.exist?(ss)
          show_toast("No state in slot #{slot}")
          return
        end

        if @core.load_state_from_file(ss)
          show_toast("State loaded from slot #{slot}")
        else
          show_toast("Failed to load state")
        end
      end

      # Save a PNG screenshot of the current frame via Tk photo image.
      # Creates a temporary photo, writes ARGB pixels via C, then
      # uses Tk's built-in PNG format handler to write the file.
      def save_screenshot(path)
        return unless @core && !@core.destroyed?

        pixels = @core.video_buffer_argb
        photo_name = "__teek_ss_#{object_id}"

        @app.tcl_eval("image create photo #{photo_name} -width #{GBA_W} -height #{GBA_H}")
        @app.interp.photo_put_block(photo_name, pixels, GBA_W, GBA_H, format: :argb)
        @app.tcl_eval("#{photo_name} write {#{path}} -format png")
        @app.tcl_eval("image delete #{photo_name}")
      rescue StandardError
        # Screenshot is optional — don't fail the save state
        @app.tcl_eval("image delete #{photo_name}") rescue nil
      end

      def quick_save
        save_state(@quick_save_slot)
      end

      def quick_load
        load_state(@quick_save_slot)
      end

      MODAL_LABELS = {
        settings: 'Settings',
        picker: 'Save States',
        rom_info: 'ROM Info',
      }.freeze

      def show_settings(tab: nil)
        return bell if @modal_child
        @modal_child = :settings
        enter_modal
        @settings_window.show(tab: tab)
      end

      def show_state_picker
        return unless @core && !@core.destroyed? && @state_dir
        return bell if @modal_child
        @modal_child = :picker
        enter_modal
        @state_picker.show(state_dir: @state_dir, quick_slot: @quick_save_slot)
      end

      def on_child_window_close
        destroy_toast
        toggle_pause if @core && !@was_paused_before_modal
        @modal_child = nil
      end

      def enter_modal
        @was_paused_before_modal = @paused
        toggle_fast_forward if @fast_forward
        toggle_pause if @core && !@paused
        label = MODAL_LABELS[@modal_child] || @modal_child.to_s
        show_toast("Waiting for #{label}\u2026", permanent: true)
      end

      def bell
        @app.command(:bell)
      end

      def save_config
        @config.scale = @scale
        @config.volume = (@volume * 100).round
        @config.muted = @muted
        @config.turbo_speed = @turbo_speed
        @config.keep_aspect_ratio = @keep_aspect_ratio
        @config.show_fps = @show_fps
        @config.quick_save_slot = @quick_save_slot
        @config.save_state_backup = @save_state_backup

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
          elsif k == 'F5'
            quick_save
          elsif k == 'F6'
            show_state_picker
          elsif k == 'F8'
            quick_load
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
                     label: 'Quit', accelerator: 'Cmd+Q',
                     command: proc { @running = false })

        @app.command(:bind, '.', '<Command-o>', proc { open_rom_dialog })
        @app.command(:bind, '.', '<Command-comma>', proc { show_settings })

        # Settings menu — one entry per settings tab
        settings_menu = "#{menubar}.settings"
        @app.command(:menu, settings_menu, tearoff: 0)
        @app.command(menubar, :add, :cascade, label: 'Settings', menu: settings_menu)

        SettingsWindow::TABS.each do |label, tab_path|
          accel = label == 'Video' ? 'Cmd+,' : nil
          opts = { label: "#{label}...", command: proc { show_settings(tab: tab_path) } }
          opts[:accelerator] = accel if accel
          @app.command(settings_menu, :add, :command, **opts)
        end

        # View menu
        view_menu = "#{menubar}.view"
        @app.command(:menu, view_menu, tearoff: 0)
        @app.command(menubar, :add, :cascade, label: 'View', menu: view_menu)

        @app.command(view_menu, :add, :command,
                     label: 'Fullscreen', accelerator: 'F11',
                     command: proc { toggle_fullscreen })
        @app.command(view_menu, :add, :command,
                     label: 'ROM Info...', state: :disabled,
                     command: proc { show_rom_info })
        @view_menu = view_menu

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
        @app.command(@emu_menu, :add, :separator)
        @app.command(@emu_menu, :add, :command,
                     label: 'Quick Save', accelerator: 'F5', state: :disabled,
                     command: proc { quick_save })
        @app.command(@emu_menu, :add, :command,
                     label: 'Quick Load', accelerator: 'F8', state: :disabled,
                     command: proc { quick_load })
        @app.command(@emu_menu, :add, :separator)
        @app.command(@emu_menu, :add, :command,
                     label: 'Save States...', accelerator: 'F6', state: :disabled,
                     command: proc { show_state_picker })

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

      def apply_toast_duration(secs)
        @config.toast_duration = secs
      end

      def apply_quick_slot(slot)
        @quick_save_slot = slot.to_i.clamp(1, 10)
      end

      def apply_backup(enabled)
        @save_state_backup = !!enabled
      end

      def toggle_show_fps
        @show_fps = !@show_fps
        destroy_fps_overlay unless @show_fps
        @app.set_variable(SettingsWindow::VAR_SHOW_FPS, @show_fps ? '1' : '0')
      end

      # Build an inverse-blend overlay texture from text. White source
      # pixels invert the destination, transparent regions pass through.
      def build_inverse_tex(text)
        return nil unless @overlay_font
        tex = @overlay_font.render_text(text, 255, 255, 255)
        tex.blend_mode = @inverse_blend
        tex
      end

      # Draw an inverse overlay texture at (x, y), cropping to the font's
      # ascent height (excludes descender area which has alpha artifacts
      # visible under inverse blending).
      def draw_inverse_tex(r, tex, x, y)
        return unless tex
        tw = tex.width
        th = @overlay_crop_h || tex.height
        r.copy(tex, [0, 0, tw, th], [x, y, tw, th])
      end

      # -- Toast notifications --------------------------------------------------

      TOAST_PAD_X = 14
      TOAST_PAD_Y = 8
      TOAST_RADIUS = 8

      # Show a GBA-style dialog box notification at the bottom of the
      # game viewport. One toast at a time; new toasts replace the old one.
      # The background is pre-rendered in C with anti-aliased rounded corners.
      #
      # @param message [String]
      # @param duration [Float, nil] seconds to display; nil = use config default
      # @param permanent [Boolean] if true, stays until explicitly destroyed
      def show_toast(message, duration: nil, permanent: false)
        destroy_toast
        return unless @overlay_font

        @toast_text_tex = @overlay_font.render_text(message, 255, 255, 255)
        tw = @toast_text_tex.width
        th = @overlay_crop_h || @toast_text_tex.height

        box_w = tw + TOAST_PAD_X * 2
        box_h = th + TOAST_PAD_Y * 2

        # Generate AA rounded-rect background as ARGB pixels in C
        bg_pixels = Teek::MGBA.toast_background(box_w, box_h, TOAST_RADIUS)
        @toast_bg_tex = @viewport.renderer.create_texture(box_w, box_h, :streaming)
        @toast_bg_tex.update(bg_pixels)
        @toast_bg_tex.blend_mode = :blend

        @toast_box_w = box_w
        @toast_box_h = box_h
        @toast_text_w = tw
        @toast_text_h = th
        @toast_permanent = permanent
        @toast_expires = permanent ? nil : Process.clock_gettime(Process::CLOCK_MONOTONIC) + (duration || @config.toast_duration)
      end

      # Draw the current toast centered at the bottom of the game area.
      def draw_toast(r, dest)
        return unless @toast_bg_tex
        unless @toast_permanent
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if now >= @toast_expires
            destroy_toast
            return
          end
        end

        # Position: bottom-center of game area, 12px from bottom
        if dest
          cx = dest[0] + dest[2] / 2
          by = dest[1] + dest[3] - 12 - @toast_box_h
        else
          out_w, out_h = r.output_size
          cx = out_w / 2
          by = out_h - 12 - @toast_box_h
        end
        bx = cx - @toast_box_w / 2

        # Background (pre-rendered with AA rounded corners)
        r.copy(@toast_bg_tex, nil, [bx, by, @toast_box_w, @toast_box_h])
        # White text centered in the box
        tx = bx + (@toast_box_w - @toast_text_w) / 2
        ty = by + (@toast_box_h - @toast_text_h) / 2
        r.copy(@toast_text_tex, [0, 0, @toast_text_w, @toast_text_h],
               [tx, ty, @toast_text_w, @toast_text_h])
      end

      def destroy_toast
        @toast_bg_tex&.destroy
        @toast_bg_tex = nil
        @toast_text_tex&.destroy
        @toast_text_tex = nil
      end

      # -----------------------------------------------------------------------

      def rebuild_fps_overlay(text)
        destroy_fps_overlay
        @fps_tex = build_inverse_tex(text)
      end

      def destroy_fps_overlay
        @fps_tex&.destroy
        @fps_tex = nil
      end

      def rebuild_ff_label
        destroy_ff_label
        label = @turbo_speed == 0 ? '>> MAX' : ">> #{@turbo_speed}x"
        @ff_label_tex = build_inverse_tex(label)
      end

      def destroy_ff_label
        @ff_label_tex&.destroy
        @ff_label_tex = nil
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

        saves = @config.saves_dir
        FileUtils.mkdir_p(saves) unless File.directory?(saves)
        @core = Core.new(path, saves)
        @rom_path = path
        @state_dir = state_dir_for_rom(@core)
        @paused = false
        @stream.resume
        @app.command(:place, :forget, @status_label) rescue nil
        @app.set_window_title("mGBA \u2014 #{@core.title}")
        @app.command(@view_menu, :entryconfigure, 1, state: :normal)
        # Enable save state menu entries (Quick Save=3, Quick Load=4, Save States=6)
        [3, 4, 6].each { |i| @app.command(@emu_menu, :entryconfigure, i, state: :normal) }
        @fps_count = 0
        @fps_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @next_frame = @fps_time
        @audio_samples_produced = 0

        @config.add_recent_rom(path)
        @config.save!
        rebuild_recent_menu

        sav_name = File.basename(path, File.extname(path)) + '.sav'
        sav_path = File.join(saves, sav_name)
        if File.exist?(sav_path)
          show_toast("Loaded #{sav_name}")
        else
          show_toast("Created #{sav_name}")
        end
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
            draw_toast(r, dest)
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
          ox = dest ? dest[0] : 0
          oy = dest ? dest[1] : 0
          draw_inverse_tex(r, @ff_label_tex, ox + 4, oy + 4) if ff_indicator
          draw_fps_overlay(r, dest)
          draw_toast(r, dest)
        end
      end

      def draw_fps_overlay(r, dest)
        return unless @show_fps && @fps_tex
        fx = (dest ? dest[0] + dest[2] : r.output_size[0]) - @fps_tex.width - 6
        fy = (dest ? dest[1] : 0) + 4
        draw_inverse_tex(r, @fps_tex, fx, fy)
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
        destroy_toast
        @overlay_font&.destroy unless @overlay_font&.destroyed?
        @stream&.destroy unless @stream&.destroyed?
        @texture&.destroy unless @texture&.destroyed?
        @core&.destroy unless @core&.destroyed?
      end
    end
  end
end
