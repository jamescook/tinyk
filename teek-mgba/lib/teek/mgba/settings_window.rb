# frozen_string_literal: true

module Teek
  module MGBA
    # Settings window for the mGBA Player.
    #
    # Opens a Toplevel with a ttk::notebook containing Video and Audio tabs.
    # Closing the window hides it (withdraw) rather than destroying it.
    #
    # Widget paths and Tcl variable names are exposed as constants so tests
    # can interact with the UI the same way a user would (set variable,
    # generate event, assert result).
    class SettingsWindow
      TOP = ".mgba_settings"
      NB  = "#{TOP}.nb"

      # Widget paths for test interaction
      SCALE_COMBO = "#{NB}.video.scale_row.scale_combo"
      VOLUME_SCALE = "#{NB}.audio.vol_row.vol_scale"
      MUTE_CHECK = "#{NB}.audio.mute_row.mute"

      # Tcl variable names
      VAR_SCALE  = '::mgba_scale'
      VAR_VOLUME = '::mgba_volume'
      VAR_MUTE   = '::mgba_mute'

      # @param app [Teek::App]
      # @param callbacks [Hash] :on_scale_change, :on_volume_change, :on_mute_change
      def initialize(app, callbacks: {})
        @app = app
        @callbacks = callbacks

        app.command(:toplevel, TOP)
        app.command(:wm, 'title', TOP, 'Settings')
        app.command(:wm, 'geometry', TOP, '300x200')
        app.command(:wm, 'resizable', TOP, 0, 0)

        # Hide on close, don't destroy
        close_proc = proc { |*| app.command(:wm, 'withdraw', TOP) }
        app.command(:wm, 'protocol', TOP, 'WM_DELETE_WINDOW', close_proc)

        setup_ui

        # Start hidden
        app.command(:wm, 'withdraw', TOP)
      end

      def show
        @app.command(:wm, 'deiconify', TOP)
        @app.command(:raise, TOP)
      end

      def hide
        @app.command(:wm, 'withdraw', TOP)
      end

      private

      def setup_ui
        @app.command('ttk::notebook', NB)
        @app.command(:pack, NB, fill: :both, expand: 1, padx: 5, pady: 5)

        setup_video_tab
        setup_audio_tab
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
            @callbacks[:on_scale_change]&.call(scale) if scale > 0
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
          })
        @app.command(:pack, MUTE_CHECK, side: :left)
      end
    end
  end
end
