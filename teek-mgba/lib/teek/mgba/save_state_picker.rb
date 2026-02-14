# frozen_string_literal: true

require_relative "child_window"
require_relative "locale"

module Teek
  module MGBA
    # Grid picker window for save state slots.
    #
    # Displays up to 10 slots in a 2×5 grid. Each cell shows a PNG
    # thumbnail screenshot, the slot number, and the save timestamp —
    # or an "Empty" placeholder. Left-click a populated slot to load,
    # click an empty slot to save. The current quick-save slot is
    # highlighted with a distinct border.
    #
    # Uses native Tk photo images for thumbnails (loaded via
    # `image create photo -file`). Pure Tk — no SDL2.
    class SaveStatePicker
      include ChildWindow
      include Locale::Translatable

      TOP = ".mgba_state_picker"

      # Thumbnail size: half of native GBA resolution (240×160)
      THUMB_W = 120
      THUMB_H = 80
      COLS    = 5
      ROWS    = 2
      SLOTS   = 10

      # @param app [Teek::App]
      # @param callbacks [Hash] :on_save, :on_load — called with slot number
      def initialize(app, callbacks: {})
        @app = app
        @callbacks = callbacks
        @built = false
        @photos = {}   # slot => photo image name
        @cells  = {}   # slot => { frame:, thumb:, label:, time: }
        @quick_slot = 1
      end

      # @param state_dir [String] path to per-ROM state directory
      # @param quick_slot [Integer] current quick-save slot (1-10)
      def show(state_dir:, quick_slot: 1)
        @state_dir = state_dir
        @quick_slot = quick_slot
        build_ui unless @built
        refresh
        show_window
      end

      def hide
        hide_window
        cleanup_photos
      end

      private

      def build_ui
        build_toplevel(translate('picker.title'), geometry: '700x380') do
          build_grid
        end
        @built = true
      end

      def build_grid
        grid = "#{TOP}.grid"
        @app.command('ttk::frame', grid, padding: 8)
        @app.command(:pack, grid, fill: :x)

        # Blank image keeps the label in pixel-sizing mode even without a screenshot
        @blank_thumb = "__teek_ss_blank"
        @app.tcl_eval("image create photo #{@blank_thumb} -width #{THUMB_W} -height #{THUMB_H}")

        SLOTS.times do |i|
          slot = i + 1
          row = i / COLS
          col = i % COLS

          cell = "#{grid}.slot#{slot}"
          @app.command('ttk::frame', cell, relief: :groove, borderwidth: 2, padding: 4)
          @app.command(:grid, cell, row: row, column: col, padx: 4, pady: 4, sticky: :new)

          # Thumbnail label (shows image or "Empty" text overlay)
          thumb = "#{cell}.thumb"
          @app.command(:label, thumb,
            image: @blank_thumb, compound: :center,
            bg: '#1a1a2e', fg: '#666666',
            text: translate('picker.empty'), anchor: :center,
            font: '{TkDefaultFont} 9')
          @app.command(:pack, thumb, pady: [0, 4])

          # Slot number + timestamp
          info = "#{cell}.info"
          @app.command('ttk::label', info, text: translate('picker.slot', n: slot), anchor: :center)
          @app.command(:pack, info, fill: :x)

          time_lbl = "#{cell}.time"
          @app.command('ttk::label', time_lbl, text: '', anchor: :center,
            font: '{TkDefaultFont} 8')
          @app.command(:pack, time_lbl, fill: :x)

          # Bind click on the whole cell + thumbnail
          click = proc { on_slot_click(slot) }
          @app.command(:bind, cell, '<Button-1>', click)
          @app.command(:bind, thumb, '<Button-1>', click)
          @app.command(:bind, info, '<Button-1>', click)
          @app.command(:bind, time_lbl, '<Button-1>', click)

          @cells[slot] = { frame: cell, thumb: thumb, info: info, time: time_lbl }
        end

        # Make columns expand evenly
        COLS.times { |c| @app.command(:grid, :columnconfigure, grid, c, weight: 1) }

        # Spacer absorbs leftover vertical space so cells don't stretch
        spacer = "#{TOP}.spacer"
        @app.command('ttk::frame', spacer)
        @app.command(:pack, spacer, fill: :both, expand: 1)

        # Close button
        close_btn = "#{TOP}.close_btn"
        @app.command('ttk::button', close_btn, text: translate('picker.close'), command: proc { hide })
        @app.command(:pack, close_btn, pady: [0, 8])
      end

      def refresh
        cleanup_photos

        SLOTS.times do |i|
          slot = i + 1
          cell = @cells[slot]
          ss_path  = File.join(@state_dir, "state#{slot}.ss")
          png_path = File.join(@state_dir, "state#{slot}.png")

          populated = File.exist?(ss_path)

          if populated && File.exist?(png_path)
            load_thumbnail(slot, png_path)
          else
            # Clear thumbnail — show Empty or just slot text on blank image
            @app.command(cell[:thumb], :configure,
              image: @blank_thumb, compound: :center,
              text: populated ? translate('picker.no_preview') : translate('picker.empty'))
          end

          # Timestamp
          if populated
            mtime = File.mtime(ss_path)
            @app.command(cell[:time], :configure, text: mtime.strftime('%b %d %H:%M'))
          else
            @app.command(cell[:time], :configure, text: '')
          end

          # Highlight quick-save slot
          border = slot == @quick_slot ? 'solid' : 'groove'
          color_opt = slot == @quick_slot ? { borderwidth: 3 } : { borderwidth: 2 }
          @app.command(cell[:frame], :configure, relief: border, **color_opt)
        end
      end

      def load_thumbnail(slot, png_path)
        photo_name = "__teek_ss_thumb_#{slot}"

        # Load full-size PNG, then subsample to thumbnail size
        src_name = "__teek_ss_src_#{slot}"
        @app.tcl_eval("image create photo #{src_name} -file {#{png_path}}")
        @app.tcl_eval("image create photo #{photo_name} -width #{THUMB_W} -height #{THUMB_H}")
        @app.tcl_eval("#{photo_name} copy #{src_name} -subsample 2 2")
        @app.tcl_eval("image delete #{src_name}")

        @app.command(@cells[slot][:thumb], :configure,
          image: photo_name, compound: :none, text: '')
        @photos[slot] = photo_name
      rescue StandardError => e
        warn "SaveStatePicker: failed to load thumbnail for slot #{slot}: #{e.message}"
        @app.tcl_eval("image delete #{src_name}") rescue nil
        @app.tcl_eval("image delete #{photo_name}") rescue nil
        @app.command(@cells[slot][:thumb], :configure,
          image: @blank_thumb, compound: :center, text: translate('picker.no_preview'))
      end

      def cleanup_photos
        @photos.each_value do |name|
          @app.tcl_eval("image delete #{name}") rescue nil
        end
        @photos.clear
      end

      def on_slot_click(slot)
        ss_path = File.join(@state_dir, "state#{slot}.ss")
        if File.exist?(ss_path)
          @callbacks[:on_load]&.call(slot)
        else
          @callbacks[:on_save]&.call(slot)
        end
        hide
      end
    end
  end
end
