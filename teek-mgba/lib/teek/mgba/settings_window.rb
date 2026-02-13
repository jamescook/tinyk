# frozen_string_literal: true

module Teek
  module MGBA
    # Settings window for the mGBA Player.
    #
    # Opens a Toplevel with a ttk::notebook containing Video, Audio, and
    # Gamepad tabs. Closing the window hides it (withdraw) rather than
    # destroying it.
    #
    # Widget paths and Tcl variable names are exposed as constants so tests
    # can interact with the UI the same way a user would (set variable,
    # generate event, assert result).
    class SettingsWindow
      TOP = ".mgba_settings"
      NB  = "#{TOP}.nb"

      # Widget paths for test interaction
      SCALE_COMBO = "#{NB}.video.scale_row.scale_combo"
      TURBO_COMBO = "#{NB}.video.turbo_row.turbo_combo"
      VOLUME_SCALE = "#{NB}.audio.vol_row.vol_scale"
      MUTE_CHECK = "#{NB}.audio.mute_row.mute"

      # Gamepad tab widget paths
      GAMEPAD_TAB   = "#{NB}.gamepad"
      GAMEPAD_COMBO = "#{GAMEPAD_TAB}.gp_row.gp_combo"
      DEADZONE_SCALE = "#{GAMEPAD_TAB}.dz_row.dz_scale"
      GP_RESET_BTN   = "#{GAMEPAD_TAB}.btn_bar.reset_btn"
      GP_UNDO_BTN    = "#{GAMEPAD_TAB}.btn_bar.undo_btn"

      # GBA button widget paths (for remapping)
      GP_BTN_A      = "#{GAMEPAD_TAB}.buttons.right.btn_a"
      GP_BTN_B      = "#{GAMEPAD_TAB}.buttons.right.btn_b"
      GP_BTN_L      = "#{GAMEPAD_TAB}.buttons.shoulders.btn_l"
      GP_BTN_R      = "#{GAMEPAD_TAB}.buttons.shoulders.btn_r"
      GP_BTN_UP     = "#{GAMEPAD_TAB}.buttons.left.btn_up"
      GP_BTN_DOWN   = "#{GAMEPAD_TAB}.buttons.left.btn_down"
      GP_BTN_LEFT   = "#{GAMEPAD_TAB}.buttons.left.btn_left"
      GP_BTN_RIGHT  = "#{GAMEPAD_TAB}.buttons.left.btn_right"
      GP_BTN_START  = "#{GAMEPAD_TAB}.buttons.center.btn_start"
      GP_BTN_SELECT = "#{GAMEPAD_TAB}.buttons.center.btn_select"

      # Bottom bar
      SAVE_BTN = "#{TOP}.save_btn"

      # Tcl variable names
      VAR_SCALE    = '::mgba_scale'
      VAR_TURBO    = '::mgba_turbo'
      VAR_VOLUME   = '::mgba_volume'
      VAR_MUTE     = '::mgba_mute'
      VAR_GAMEPAD  = '::mgba_gamepad'
      VAR_DEADZONE = '::mgba_deadzone'

      # GBA button → widget path mapping
      GBA_BUTTONS = {
        a: GP_BTN_A, b: GP_BTN_B,
        l: GP_BTN_L, r: GP_BTN_R,
        up: GP_BTN_UP, down: GP_BTN_DOWN,
        left: GP_BTN_LEFT, right: GP_BTN_RIGHT,
        start: GP_BTN_START, select: GP_BTN_SELECT,
      }.freeze

      # Default GBA → SDL gamepad mappings (display names)
      DEFAULT_GP_LABELS = {
        a: 'a', b: 'b',
        l: 'left_shoulder', r: 'right_shoulder',
        up: 'dpad_up', down: 'dpad_down',
        left: 'dpad_left', right: 'dpad_right',
        start: 'start', select: 'back',
      }.freeze

      # Default GBA → Tk keysym mappings (keyboard mode display names)
      DEFAULT_KB_LABELS = {
        a: 'z', b: 'x',
        l: 'a', r: 's',
        up: 'Up', down: 'Down',
        left: 'Left', right: 'Right',
        start: 'Return', select: 'BackSpace',
      }.freeze

      # @param app [Teek::App]
      # @param callbacks [Hash] :on_scale_change, :on_volume_change, :on_mute_change,
      #   :on_gamepad_map_change, :on_deadzone_change
      def initialize(app, callbacks: {})
        @app = app
        @callbacks = callbacks
        @listening_for = nil
        @listen_timer = nil
        @keyboard_mode = true
        @gp_labels = DEFAULT_KB_LABELS.dup

        app.command(:toplevel, TOP)
        app.command(:wm, 'title', TOP, 'Settings')
        app.command(:wm, 'geometry', TOP, '700x360')
        app.command(:wm, 'resizable', TOP, 0, 0)
        app.command(:wm, 'transient', TOP, '.')  # child of main window

        # Hide on close, don't destroy
        close_proc = proc { |*| hide }
        app.command(:wm, 'protocol', TOP, 'WM_DELETE_WINDOW', close_proc)

        setup_ui

        # Start hidden
        app.command(:wm, 'withdraw', TOP)
      end

      # @return [Symbol, nil] the GBA button currently listening for remap, or nil
      attr_reader :listening_for

      # @return [Boolean] true when editing keyboard bindings, false for gamepad
      def keyboard_mode?
        @keyboard_mode
      end

      def show
        @app.command(:wm, 'deiconify', TOP)
        @app.command(:raise, TOP)
        @app.command(:grab, :set, TOP)
        @app.command(:focus, TOP)
      end

      def hide
        @app.command(:grab, :release, TOP)
        @app.command(:wm, 'withdraw', TOP)
        @callbacks[:on_close]&.call
      end

      def update_gamepad_list(names)
        @app.command(GAMEPAD_COMBO, 'configure',
          values: Teek.make_list(*names))
        current = @app.get_variable(VAR_GAMEPAD)
        unless names.include?(current)
          @app.set_variable(VAR_GAMEPAD, names.first)
        end
      end

      # Enable the Save button (called when any setting changes)
      def mark_dirty
        @app.command(SAVE_BTN, 'configure', state: :normal)
      end

      private

      def do_save
        @callbacks[:on_save]&.call
        @app.command(SAVE_BTN, 'configure', state: :disabled)
      end

      def setup_ui
        @app.command('ttk::notebook', NB)
        @app.command(:pack, NB, fill: :both, expand: 1, padx: 5, pady: [5, 0])

        setup_video_tab
        setup_audio_tab
        setup_gamepad_tab

        # Save button — disabled until a setting changes
        @app.command('ttk::button', SAVE_BTN, text: 'Save', state: :disabled,
          command: proc { do_save })
        @app.command(:pack, SAVE_BTN, side: :bottom, pady: [0, 8])
      end

      def setup_video_tab
        frame = "#{NB}.video"
        @app.command('ttk::frame', frame)
        @app.command(NB, 'add', frame, text: 'Video')

        # Window Scale
        row = "#{frame}.scale_row"
        @app.command('ttk::frame', row)
        @app.command(:pack, row, fill: :x, padx: 10, pady: [15, 5])

        @app.command('ttk::label', "#{row}.lbl", text: 'Window Scale:')
        @app.command(:pack, "#{row}.lbl", side: :left)

        @app.set_variable(VAR_SCALE, '3x')
        @app.command('ttk::combobox', SCALE_COMBO,
          textvariable: VAR_SCALE,
          values: Teek.make_list('1x', '2x', '3x', '4x'),
          state: :readonly,
          width: 5)
        @app.command(:pack, SCALE_COMBO, side: :right)

        @app.command(:bind, SCALE_COMBO, '<<ComboboxSelected>>',
          proc { |*|
            val = @app.get_variable(VAR_SCALE)
            scale = val.to_i
            if scale > 0
              @callbacks[:on_scale_change]&.call(scale)
              mark_dirty
            end
          })

        # Turbo Speed
        turbo_row = "#{frame}.turbo_row"
        @app.command('ttk::frame', turbo_row)
        @app.command(:pack, turbo_row, fill: :x, padx: 10, pady: 5)

        @app.command('ttk::label', "#{turbo_row}.lbl", text: 'Turbo Speed:')
        @app.command(:pack, "#{turbo_row}.lbl", side: :left)

        @app.set_variable(VAR_TURBO, '2x')
        @app.command('ttk::combobox', TURBO_COMBO,
          textvariable: VAR_TURBO,
          values: Teek.make_list('2x', '3x', '4x', 'Uncapped'),
          state: :readonly,
          width: 10)
        @app.command(:pack, TURBO_COMBO, side: :right)

        @app.command(:bind, TURBO_COMBO, '<<ComboboxSelected>>',
          proc { |*|
            val = @app.get_variable(VAR_TURBO)
            speed = val == 'Uncapped' ? 0 : val.to_i
            @callbacks[:on_turbo_speed_change]&.call(speed)
            mark_dirty
          })
      end

      def setup_audio_tab
        frame = "#{NB}.audio"
        @app.command('ttk::frame', frame)
        @app.command(NB, 'add', frame, text: 'Audio')

        # Volume slider
        vol_row = "#{frame}.vol_row"
        @app.command('ttk::frame', vol_row)
        @app.command(:pack, vol_row, fill: :x, padx: 10, pady: [15, 5])

        @app.command('ttk::label', "#{vol_row}.lbl", text: 'Volume:')
        @app.command(:pack, "#{vol_row}.lbl", side: :left)

        @vol_val_label = "#{vol_row}.vol_label"
        @app.command('ttk::label', @vol_val_label, text: '100%', width: 5)
        @app.command(:pack, @vol_val_label, side: :right)

        @app.set_variable(VAR_VOLUME, '100')
        @app.command('ttk::scale', VOLUME_SCALE,
          orient: :horizontal,
          from: 0,
          to: 100,
          length: 150,
          variable: VAR_VOLUME,
          command: proc { |v, *|
            pct = v.to_f.round
            @app.command(@vol_val_label, 'configure', text: "#{pct}%")
            @callbacks[:on_volume_change]&.call(pct / 100.0)
            mark_dirty
          })
        @app.command(:pack, VOLUME_SCALE, side: :right, padx: [5, 5])

        # Mute checkbox
        mute_row = "#{frame}.mute_row"
        @app.command('ttk::frame', mute_row)
        @app.command(:pack, mute_row, fill: :x, padx: 10, pady: 5)

        @app.set_variable(VAR_MUTE, '0')
        @app.command('ttk::checkbutton', MUTE_CHECK,
          text: 'Mute',
          variable: VAR_MUTE,
          command: proc { |*|
            muted = @app.get_variable(VAR_MUTE) == '1'
            @callbacks[:on_mute_change]&.call(muted)
            mark_dirty
          })
        @app.command(:pack, MUTE_CHECK, side: :left)
      end
      def setup_gamepad_tab
        frame = GAMEPAD_TAB
        @app.command('ttk::frame', frame)
        @app.command(NB, 'add', frame, text: 'Gamepad')

        # Gamepad selector row
        gp_row = "#{frame}.gp_row"
        @app.command('ttk::frame', gp_row)
        @app.command(:pack, gp_row, fill: :x, padx: 10, pady: [8, 4])

        @app.command('ttk::label', "#{gp_row}.lbl", text: 'Gamepad:')
        @app.command(:pack, "#{gp_row}.lbl", side: :left)

        @app.set_variable(VAR_GAMEPAD, 'Keyboard Only')
        @app.command('ttk::combobox', GAMEPAD_COMBO,
          textvariable: VAR_GAMEPAD, state: :readonly, width: 20)
        @app.command(:pack, GAMEPAD_COMBO, side: :left, padx: 4)
        @app.command(GAMEPAD_COMBO, 'configure',
          values: Teek.make_list('Keyboard Only'))

        @app.command(:bind, GAMEPAD_COMBO, '<<ComboboxSelected>>',
          proc { |*| switch_input_mode })

        # GBA button layout
        buttons_frame = "#{frame}.buttons"
        @app.command('ttk::frame', buttons_frame)
        @app.command(:pack, buttons_frame, fill: :both, expand: 1, padx: 10, pady: 4)

        # Shoulders: L and R at top
        shoulders = "#{buttons_frame}.shoulders"
        @app.command('ttk::frame', shoulders)
        @app.command(:pack, shoulders, fill: :x, pady: [0, 8])
        make_gba_button(GP_BTN_L, shoulders, :l, side: :left)
        make_gba_button(GP_BTN_R, shoulders, :r, side: :right)

        # Middle: three columns — D-pad | Select/Start | A/B
        mid = "#{buttons_frame}.mid"
        @app.command('ttk::frame', mid)
        @app.command(:pack, mid, fill: :both, expand: 1)

        # D-pad (left column)
        left = "#{buttons_frame}.left"
        @app.command('ttk::frame', left)
        @app.command(:pack, left, side: :left, padx: [0, 20])
        dpad_top = "#{left}.top"
        @app.command('ttk::frame', dpad_top)
        @app.command(:pack, dpad_top)
        make_gba_button(GP_BTN_UP, dpad_top, :up, side: :top)
        dpad_mid = "#{left}.mid"
        @app.command('ttk::frame', dpad_mid)
        @app.command(:pack, dpad_mid)
        make_gba_button(GP_BTN_LEFT, dpad_mid, :left, side: :left)
        make_gba_button(GP_BTN_RIGHT, dpad_mid, :right, side: :left)
        dpad_bot = "#{left}.bot"
        @app.command('ttk::frame', dpad_bot)
        @app.command(:pack, dpad_bot)
        make_gba_button(GP_BTN_DOWN, dpad_bot, :down, side: :top)

        # A/B (right column)
        right = "#{buttons_frame}.right"
        @app.command('ttk::frame', right)
        @app.command(:pack, right, side: :right, padx: [20, 0], pady: [15, 0])
        make_gba_button(GP_BTN_B, right, :b, side: :left)
        make_gba_button(GP_BTN_A, right, :a, side: :left)

        # Start/Select (center column)
        center = "#{buttons_frame}.center"
        @app.command('ttk::frame', center)
        @app.command(:pack, center, side: :left, expand: 1, pady: [30, 0])
        make_gba_button(GP_BTN_SELECT, center, :select, side: :left)
        make_gba_button(GP_BTN_START, center, :start, side: :left)

        # Bottom bar: Undo (left) | Reset to Defaults (right)
        btn_bar = "#{frame}.btn_bar"
        @app.command('ttk::frame', btn_bar)
        @app.command(:pack, btn_bar, fill: :x, side: :bottom, padx: 10, pady: [4, 8])

        @app.command('ttk::button', GP_UNDO_BTN, text: 'Undo',
          state: :disabled, command: proc { do_undo_gamepad })
        @app.command(:pack, GP_UNDO_BTN, side: :left)

        @app.command('ttk::button', GP_RESET_BTN, text: 'Reset to Defaults',
          command: proc { confirm_reset_gamepad })
        @app.command(:pack, GP_RESET_BTN, side: :right)

        # Dead zone slider (disabled in keyboard mode)
        dz_row = "#{frame}.dz_row"
        @app.command('ttk::frame', dz_row)
        @app.command(:pack, dz_row, fill: :x, padx: 10, pady: [4, 8], side: :bottom)

        @app.command('ttk::label', "#{dz_row}.lbl", text: 'Dead zone:')
        @app.command(:pack, "#{dz_row}.lbl", side: :left)

        @dz_val_label = "#{dz_row}.dz_label"
        @app.command('ttk::label', @dz_val_label, text: '25%', width: 5)
        @app.command(:pack, @dz_val_label, side: :right)

        @app.set_variable(VAR_DEADZONE, '25')
        @app.command('ttk::scale', DEADZONE_SCALE,
          orient: :horizontal, from: 0, to: 50, length: 150,
          variable: VAR_DEADZONE,
          command: proc { |v, *|
            pct = v.to_f.round
            @app.command(@dz_val_label, 'configure', text: "#{pct}%")
            threshold = (pct / 100.0 * 32767).round
            @callbacks[:on_deadzone_change]&.call(threshold)
            mark_dirty
          })
        @app.command(:pack, DEADZONE_SCALE, side: :right, padx: [5, 5])

        # Start in keyboard mode — dead zone disabled
        set_deadzone_enabled(false)
      end

      def make_gba_button(path, parent, gba_btn, side: :left)
        label = btn_display(gba_btn)
        @app.command('ttk::button', path, text: label, width: 16,
          command: proc { start_listening(gba_btn) })
        @app.command(:pack, path, side: side, padx: 2, pady: 2)
      end

      def btn_display(gba_btn)
        gp = @gp_labels[gba_btn] || '?'
        "#{gba_btn.upcase}: #{gp}"
      end

      def confirm_reset_gamepad
        cancel_listening
        result = @app.command('tk_messageBox',
          parent: TOP,
          title: 'Reset Gamepad',
          message: 'Reset all gamepad mappings and dead zone to defaults?',
          type: :yesno,
          icon: :question)
        reset_gamepad_defaults if result == 'yes'
      end

      def reset_gamepad_defaults
        @gp_labels = (@keyboard_mode ? DEFAULT_KB_LABELS : DEFAULT_GP_LABELS).dup
        GBA_BUTTONS.each do |gba_btn, widget|
          @app.command(widget, 'configure', text: btn_display(gba_btn))
        end
        @app.command(DEADZONE_SCALE, 'set', 25) unless @keyboard_mode
        @app.command(GP_UNDO_BTN, 'configure', state: :disabled)
        if @keyboard_mode
          @callbacks[:on_keyboard_reset]&.call
        else
          @callbacks[:on_gamepad_reset]&.call
        end
        mark_dirty
      end

      def do_undo_gamepad
        @callbacks[:on_undo_gamepad]&.call
        @app.command(GP_UNDO_BTN, 'configure', state: :disabled)
      end

      def switch_input_mode
        cancel_listening
        selected = @app.get_variable(VAR_GAMEPAD)
        @keyboard_mode = (selected == 'Keyboard Only')

        if @keyboard_mode
          @gp_labels = DEFAULT_KB_LABELS.dup
          set_deadzone_enabled(false)
        else
          @gp_labels = DEFAULT_GP_LABELS.dup
          set_deadzone_enabled(true)
        end

        GBA_BUTTONS.each do |gba_btn, widget|
          @app.command(widget, 'configure', text: btn_display(gba_btn))
        end

        @app.command(GP_UNDO_BTN, 'configure', state: :disabled)
        @callbacks[:on_input_mode_change]&.call(@keyboard_mode, selected)
      end

      def set_deadzone_enabled(enabled)
        state = enabled ? :normal : :disabled
        @app.command(DEADZONE_SCALE, 'configure', state: state)
      end

      LISTEN_TIMEOUT_MS = 10_000

      def start_listening(gba_btn)
        cancel_listening
        @listening_for = gba_btn
        widget = GBA_BUTTONS[gba_btn]
        @app.command(widget, 'configure', text: "#{gba_btn.upcase}: Press...")
        @listen_timer = @app.after(LISTEN_TIMEOUT_MS) { cancel_listening }

        if @keyboard_mode
          # Use tcl_eval directly because Teek's command() wraps each arg in
          # braces, which breaks Tk event substitutions like %K in bind scripts.
          cb_id = @app.interp.register_callback(
            proc { |keysym, *| capture_mapping(keysym) })
          @app.tcl_eval("bind #{TOP} <Key> {ruby_callback #{cb_id} %K}")
        end
      end

      def cancel_listening
        if @listen_timer
          @app.command(:after, :cancel, @listen_timer)
          @listen_timer = nil
        end
        if @listening_for
          unbind_keyboard_listen
          widget = GBA_BUTTONS[@listening_for]
          @app.command(widget, 'configure', text: btn_display(@listening_for))
          @listening_for = nil
        end
      end

      def unbind_keyboard_listen
        @app.tcl_eval("bind #{TOP} <Key> {}")
      end

      # Called by the player's poll loop when a gamepad button is detected
      # during listen mode.
      public

      # Refresh the gamepad tab widgets from external state (e.g. after undo).
      # @param labels [Hash{Symbol => String}] GBA button → gamepad button name
      # @param dead_zone [Integer] dead zone percentage (0-50)
      def refresh_gamepad(labels, dead_zone)
        @gp_labels = labels.dup
        GBA_BUTTONS.each do |gba_btn, widget|
          @app.command(widget, 'configure', text: btn_display(gba_btn))
        end
        @app.command(DEADZONE_SCALE, 'set', dead_zone)
      end

      def capture_mapping(button)
        return unless @listening_for

        if @listen_timer
          @app.command(:after, :cancel, @listen_timer)
          @listen_timer = nil
        end
        unbind_keyboard_listen

        gba_btn = @listening_for
        @gp_labels[gba_btn] = button.to_s
        widget = GBA_BUTTONS[gba_btn]
        @app.command(widget, 'configure', text: btn_display(gba_btn))
        @listening_for = nil

        if @keyboard_mode
          @callbacks[:on_keyboard_map_change]&.call(gba_btn, button)
        else
          @callbacks[:on_gamepad_map_change]&.call(gba_btn, button)
        end
        @app.command(GP_UNDO_BTN, 'configure', state: :normal)
        mark_dirty
      end
    end
  end
end
