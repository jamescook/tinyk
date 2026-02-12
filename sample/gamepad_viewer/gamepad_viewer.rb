# frozen_string_literal: true
#
# Gamepad Viewer — SDL2 gamepad input visualized with pure Tk widgets.
#
# Demonstrates:
#   - Teek::SDL2::Gamepad for controller input (polling + events)
#   - Virtual gamepad wired to keyboard for testing without hardware
#   - Combobox for gamepad selection with hot-plug detection
#   - Canvas overlay highlights on a controller image
#   - Tk label indicators for button/axis state
#   - Periodic polling via app.every (50ms game loop)
#
# Controller artwork: "Generic Gamepad Template" by Erratic (CC0)
# https://opengameart.org/content/generic-gamepad-template

require_relative '../../lib/teek'
require_relative '../../teek-sdl2/lib/teek/sdl2'

class GamepadViewer
  GP = Teek::SDL2::Gamepad

  # Approximate pixel coordinates for button highlights on controller.png (479x310)
  # Format: [center_x, center_y, radius]
  BUTTON_POS = {
    a:              [352, 140, 18],
    b:              [390, 107, 18],
    x:              [315, 107, 18],
    y:              [353,  71, 18],
    dpad_up:        [127,  74, 12],
    dpad_down:      [127, 143, 12],
    dpad_left:      [ 93, 111, 12],
    dpad_right:     [160, 110, 12],
    left_shoulder:  [ 97,  18, 20],
    right_shoulder: [383,  21, 20],
    back:           [215,  93, 10],
    start:          [262,  95, 10],
    left_stick:     [165, 200, 16],
    right_stick:    [313, 200, 16],
    guide:          [242, 135, 12],
  }.freeze

  # Center of each analog stick for the position dot
  STICK_CENTER = {
    left:  [165, 200],
    right: [313, 200],
  }.freeze

  # Keyboard → virtual gamepad button mapping
  KEY_MAP_BUTTONS = {
    'space'     => :a,
    'shift_l'   => :b,
    'shift_r'   => :b,
    'z'         => :x,
    'c'         => :y,
    'return'    => :start,
    'tab'       => :back,
    'q'         => :left_shoulder,
    'e'         => :right_shoulder,
    'up'        => :dpad_up,
    'down'      => :dpad_down,
    'left'      => :dpad_left,
    'right'     => :dpad_right,
    'f'         => :left_stick,
    'g'         => :right_stick,
    'escape'    => :guide,
  }.freeze

  # Keyboard → virtual analog stick mapping
  # WASD → left stick, IJKL → right stick
  KEY_MAP_AXES = {
    'w' => [:left_y,  -GP::AXIS_MAX],
    's' => [:left_y,   GP::AXIS_MAX],
    'a' => [:left_x,   GP::AXIS_MIN],
    'd' => [:left_x,   GP::AXIS_MAX],
    'i' => [:right_y, -GP::AXIS_MAX],
    'k' => [:right_y,  GP::AXIS_MAX],
    'j' => [:right_x,  GP::AXIS_MIN],
    'l' => [:right_x,  GP::AXIS_MAX],
  }.freeze

  def initialize(calibrate: false)
    @calibrate = calibrate
    @app = Teek::App.new(title: calibrate ? 'Gamepad Viewer — CALIBRATE' : 'Gamepad Viewer')
    @gamepads = []       # [[display_name, :virtual | device_index], ...]
    @current_gp = nil    # opened Gamepad instance
    @current_mode = nil  # :virtual or device index
    @keys_held = {}      # keysym → true (for virtual stick axes)
    @var_counter = 0     # unique Tcl variable names
    @prev_buttons = {}   # btn → pressed (skip UI update when unchanged)
    @prev_axes = {}      # ax → value

    GP.init_subsystem

    build_ui
    unless @calibrate
      refresh_gamepad_list
      start_poll_loop
    end
    @app.show
  end

  def run
    @app.mainloop
  ensure
    @poll_timer&.cancel
    @current_gp&.close unless @current_gp&.closed?
    GP.detach_virtual
    GP.shutdown_subsystem
  end

  private

  # ── UI construction ────────────────────────────────────────────────────────

  def build_ui
    # Top bar: gamepad selector
    top = @app.create_widget('ttk::frame')
    top.pack(fill: :x, padx: 8, pady: 4)

    @app.create_widget('ttk::label', parent: top, text: 'Gamepad:')
        .pack(side: :left)

    # Tcl variable must exist before combobox references it via -textvariable
    @combo_var = next_var
    set_var(@combo_var, '')
    @combo = @app.create_widget('ttk::combobox', parent: top,
                                textvariable: @combo_var,
                                state: :readonly, width: 35)
    @combo.pack(side: :left, padx: 4)
    @combo.bind('<<ComboboxSelected>>') { on_gamepad_selected }

    @app.create_widget('ttk::button', parent: top, text: 'Refresh',
                       command: proc { refresh_gamepad_list })
        .pack(side: :left, padx: 4)

    # Main area: canvas (left) + info panel (right)
    main = @app.create_widget('ttk::frame')
    main.pack(fill: :both, expand: true, padx: 8, pady: 4)

    build_canvas(main)
    build_info_panel(main)

    # Status bar (left = status text, right = mouse coords on canvas)
    status_frame = @app.create_widget('ttk::frame')
    status_frame.pack(fill: :x, side: :bottom, padx: 8, pady: 4)

    @status_var = next_var
    set_var(@status_var, 'Select a gamepad to begin')
    @app.create_widget('ttk::label', parent: status_frame,
                       textvariable: @status_var, anchor: :w)
        .pack(fill: :x, side: :left, expand: true)

    @mouse_var = next_var
    set_var(@mouse_var, 'x: — y: —')
    @app.create_widget('ttk::label', parent: status_frame,
                       textvariable: @mouse_var, anchor: :e,
                       width: 16, font: 'TkFixedFont')
        .pack(side: :right, padx: [4, 0])

    # Keyboard bindings for virtual mode (skip in calibrate — it uses its own)
    unless @calibrate
      @app.bind('all', 'KeyPress', :keysym)   { |k| on_key_press(k) }
      @app.bind('all', 'KeyRelease', :keysym) { |k| on_key_release(k) }
    end
  end

  def build_canvas(parent)
    @canvas = @app.create_widget('canvas', parent: parent,
                                 width: 479, height: 310,
                                 background: '#2b2b2b', highlightthickness: 0)
    @canvas.pack(side: :left, padx: [0, 8])

    # Load controller image
    img_path = File.join(__dir__, 'assets', 'controller.png')
    @controller_img = "gp_controller"
    @app.command(:image, :create, :photo, @controller_img, file: img_path)
    @canvas.command(:create, :image, 0, 0, anchor: :nw, image: @controller_img,
                    tag: :controller)

    # Mouse coordinate tracking for tweaking button positions
    @canvas.bind('Motion', :x, :y) do |x, y|
      set_var(@mouse_var, "x:#{x} y:#{y}")
    end

    # Create highlight ovals for each button
    @highlight_items = {}
    @calibrate_pos = {}  # live positions for calibration mode
    BUTTON_POS.each do |btn, (cx, cy, r)|
      color = button_highlight_color(btn)
      tag = "hl_#{btn}"
      @canvas.command(:create, :oval, cx - r, cy - r, cx + r, cy + r,
                      fill: color, outline: '', tag: tag,
                      state: @calibrate ? :normal : :hidden)
      @highlight_items[btn] = tag
      @calibrate_pos[btn] = [cx, cy, r]

      if @calibrate
        # Label each highlight so you know which is which
        @canvas.command(:create, :text, cx, cy - r - 8,
                        text: btn.to_s, fill: '#ffffff',
                        font: 'TkSmallCaptionFont', tag: "lbl_#{btn}")
      end
    end

    if @calibrate
      setup_calibration_drag
    end

    # Stick position dots
    @stick_dots = {}
    STICK_CENTER.each do |side, (cx, cy)|
      tag = "stick_#{side}"
      r = 6
      @canvas.command(:create, :oval, cx - r, cy - r, cx + r, cy + r,
                      fill: '#00ff88', outline: '#00cc66', width: 2, tag: tag)
      @stick_dots[side] = tag
    end
  end

  def build_info_panel(parent)
    info = @app.create_widget('ttk::labelframe', parent: parent, text: 'State')
    info.pack(side: :right, fill: :both, expand: true)

    # Button indicators
    btn_frame = @app.create_widget('ttk::labelframe', parent: info, text: 'Buttons')
    btn_frame.pack(fill: :x, padx: 4, pady: 2)

    @btn_labels = {}
    GP.buttons.each_slice(4) do |row|
      rf = @app.create_widget('ttk::frame', parent: btn_frame)
      rf.pack(fill: :x)
      row.each do |btn|
        var = next_var
        set_var(var, btn.to_s)
        # Use plain label (not ttk) for background color support
        lbl = @app.create_widget('label', parent: rf,
                                 textvariable: var,
                                 width: 12, relief: :groove,
                                 anchor: :center, padx: 2, pady: 1)
        lbl.pack(side: :left, padx: 1, pady: 1)
        # Store default colors so we can restore them when button is released
        default_bg = lbl.command(:cget, '-background')
        default_fg = lbl.command(:cget, '-foreground')
        @btn_labels[btn] = { var: var, label: lbl,
                             default_bg: default_bg, default_fg: default_fg }
      end
    end

    # Axis readouts
    axis_frame = @app.create_widget('ttk::labelframe', parent: info, text: 'Axes')
    axis_frame.pack(fill: :x, padx: 4, pady: 2)

    @axis_labels = {}
    GP.axes.each do |ax|
      rf = @app.create_widget('ttk::frame', parent: axis_frame)
      rf.pack(fill: :x)
      @app.create_widget('ttk::label', parent: rf, text: "#{ax}:",
                         width: 14, anchor: :e)
          .pack(side: :left)
      var = next_var
      set_var(var, '0')
      @app.create_widget('ttk::label', parent: rf, textvariable: var,
                         width: 8, anchor: :w, font: 'TkFixedFont')
          .pack(side: :left, padx: 4)
      @axis_labels[ax] = var
    end

    # Key help for virtual mode
    help_frame = @app.create_widget('ttk::labelframe', parent: info,
                                    text: 'Virtual Keys')
    help_frame.pack(fill: :x, padx: 4, pady: 2)

    help_text = "WASD: L-stick  IJKL: R-stick\n" \
                "Arrows: D-pad  Space: A\n" \
                "Shift: B  Z: X  C: Y\n" \
                "Enter: Start  Tab: Back\n" \
                "Q/E: Shoulders  F/G: Sticks"
    @app.create_widget('ttk::label', parent: help_frame,
                       text: help_text, justify: :left)
        .pack(padx: 4, pady: 2)
  end

  # ── Gamepad selection ──────────────────────────────────────────────────────

  def refresh_gamepad_list
    @gamepads = [['Virtual (Keyboard)', :virtual]]

    # Probe device indices for connected gamepads
    8.times do |i|
      gp = begin; GP.open(i); rescue; nil; end
      next unless gp
      @gamepads << [gp.name, i]
      gp.close
    end

    values = @gamepads.map(&:first)
    @combo.command(:configure, values: values)

    # Select first if nothing selected
    current = get_var(@combo_var)
    if current.empty? || !values.include?(current)
      set_var(@combo_var, values.first)
      on_gamepad_selected
    end
  end

  def on_gamepad_selected
    name = get_var(@combo_var)
    entry = @gamepads.find { |n, _| n == name }
    return unless entry

    _, mode = entry
    switch_gamepad(mode)
  end

  def switch_gamepad(mode)
    # Close current
    @current_gp&.close unless @current_gp&.closed?
    @current_gp = nil
    GP.detach_virtual

    @prev_buttons.clear
    @prev_axes.clear

    if mode == :virtual
      idx = GP.attach_virtual
      @current_gp = GP.open(idx)
      @current_mode = :virtual
      set_var(@status_var, "Virtual gamepad active \u2014 use keyboard")
    else
      begin
        @current_gp = GP.open(mode)
        @current_mode = mode
        set_var(@status_var, "Connected: #{@current_gp.name}")
      rescue => e
        set_var(@status_var, "Error: #{e.message}")
        @current_mode = nil
      end
    end
  end

  # ── Keyboard → Virtual gamepad ─────────────────────────────────────────────

  def on_key_press(keysym)
    return unless @current_mode == :virtual && @current_gp && !@current_gp.closed?

    key = keysym.downcase

    if (btn = KEY_MAP_BUTTONS[key])
      @current_gp.set_virtual_button(btn, true)
    end

    if KEY_MAP_AXES[key]
      @keys_held[key] = true
      update_virtual_axes
    end
  end

  def on_key_release(keysym)
    return unless @current_mode == :virtual && @current_gp && !@current_gp.closed?

    key = keysym.downcase

    if (btn = KEY_MAP_BUTTONS[key])
      @current_gp.set_virtual_button(btn, false)
    end

    if KEY_MAP_AXES[key]
      @keys_held.delete(key)
      update_virtual_axes
    end
  end

  def update_virtual_axes
    return unless @current_gp && !@current_gp.closed?

    # Compute net axis values from held keys
    axes = Hash.new(0)
    @keys_held.each_key do |key|
      ax, val = KEY_MAP_AXES[key]
      axes[ax] = val
    end

    # Set each axis — reset to 0 if no key held for that axis
    %i[left_x left_y right_x right_y].each do |ax|
      @current_gp.set_virtual_axis(ax, axes[ax])
    end
  end

  # ── Poll loop ──────────────────────────────────────────────────────────────

  def start_poll_loop
    @poll_timer = @app.every(50, on_error: ->(e) {
      set_var(@status_var, "Poll error: #{e.message}")
    }) {
      GP.poll_events
      if @current_gp && !@current_gp.closed?
        update_buttons
        update_axes
      end
    }
  end

  def update_buttons
    GP.buttons.each do |btn|
      pressed = @current_gp.button?(btn)
      next if @prev_buttons[btn] == pressed

      @prev_buttons[btn] = pressed
      info = @btn_labels[btn]
      next unless info

      if pressed
        set_var(info[:var], "[ #{btn} ]")
        info[:label].command(:configure,
                             background: button_highlight_color(btn),
                             foreground: '#ffffff')
      else
        set_var(info[:var], btn.to_s)
        info[:label].command(:configure,
                             background: info[:default_bg],
                             foreground: info[:default_fg])
      end

      tag = @highlight_items[btn]
      @canvas.command(:itemconfigure, tag, state: pressed ? :normal : :hidden) if tag
    end
  end

  def update_axes
    GP.axes.each do |ax|
      val = @current_gp.axis(ax)
      next if @prev_axes[ax] == val

      @prev_axes[ax] = val
      set_var(@axis_labels[ax], val.to_s.rjust(6))
    end

    # Only move stick dots when their axes actually changed
    lx = @current_gp.axis(:left_x);  ly = @current_gp.axis(:left_y)
    rx = @current_gp.axis(:right_x); ry = @current_gp.axis(:right_y)
    move_stick_dot(:left,  lx, ly)  if @prev_axes[:left_x]  != lx || @prev_axes[:left_y]  != ly
    move_stick_dot(:right, rx, ry)  if @prev_axes[:right_x] != rx || @prev_axes[:right_y] != ry
  end

  def move_stick_dot(side, raw_x, raw_y)
    cx, cy = STICK_CENTER[side]
    max_offset = 15.0  # pixels of travel on screen
    nx = raw_x.to_f / GP::AXIS_MAX
    ny = raw_y.to_f / GP::AXIS_MAX
    px = cx + (nx * max_offset)
    py = cy + (ny * max_offset)
    r = 6
    @canvas.command(:coords, @stick_dots[side],
                    (px - r).round, (py - r).round,
                    (px + r).round, (py + r).round)
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  def button_highlight_color(btn)
    case btn
    when :a              then '#22cc44'
    when :b              then '#dd3333'
    when :x              then '#3388ee'
    when :y              then '#ee8822'
    when :dpad_up, :dpad_down, :dpad_left, :dpad_right then '#44aaff'
    when :left_shoulder, :right_shoulder then '#aa66dd'
    when :left_stick, :right_stick       then '#00ff88'
    when :back, :start, :guide           then '#ffaa22'
    else '#cccccc'
    end
  end

  # ── Calibration mode ────────────────────────────────────────────────────────

  def setup_calibration_drag
    @drag_btn = nil
    @drag_offset = [0, 0]

    @canvas.bind('ButtonPress-1', :x, :y) { |x, y| calibrate_press(x.to_i, y.to_i) }
    @canvas.bind('B1-Motion', :x, :y)     { |x, y| calibrate_drag(x.to_i, y.to_i) }
    @canvas.bind('ButtonRelease-1')        { @drag_btn = nil }

    # Print final coordinates to console
    @app.bind('all', 'KeyPress', :keysym) do |k|
      print_calibrated_positions if k.downcase == 'return'
    end

    set_var(@status_var, 'Drag circles into position. Press Enter to print coordinates.')
  end

  def calibrate_press(mx, my)
    # Find the closest button highlight to the click
    @drag_btn = nil
    best_dist = 999
    @calibrate_pos.each do |btn, (cx, cy, _r)|
      d = Math.sqrt((mx - cx)**2 + (my - cy)**2)
      if d < best_dist
        best_dist = d
        @drag_btn = btn
        @drag_offset = [mx - cx, my - cy]
      end
    end
    @drag_btn = nil if best_dist > 40
  end

  def calibrate_drag(mx, my)
    return unless @drag_btn

    cx = mx - @drag_offset[0]
    cy = my - @drag_offset[1]
    _, _, r = @calibrate_pos[@drag_btn]
    @calibrate_pos[@drag_btn] = [cx, cy, r]

    tag = @highlight_items[@drag_btn]
    @canvas.command(:coords, tag, cx - r, cy - r, cx + r, cy + r)
    @canvas.command(:coords, "lbl_#{@drag_btn}", cx, cy - r - 8)
    set_var(@mouse_var, "#{@drag_btn}: #{cx},#{cy}")
  end

  def print_calibrated_positions
    puts "\n# Updated BUTTON_POS — paste into gamepad_viewer.rb"
    puts "BUTTON_POS = {"
    @calibrate_pos.each do |btn, (cx, cy, r)|
      puts "  %-17s [%3d, %3d, %2d]," % ["#{btn}:", cx, cy, r]
    end
    puts "}.freeze"

    # Also print stick centers from the stick buttons
    ls = @calibrate_pos[:left_stick]
    rs = @calibrate_pos[:right_stick]
    puts "\nSTICK_CENTER = {"
    puts "  left:  [#{ls[0]}, #{ls[1]}],"
    puts "  right: [#{rs[0]}, #{rs[1]}],"
    puts "}.freeze"
  end

  # Tcl variable helpers
  def next_var
    @var_counter += 1
    "::gpv_#{@var_counter}"
  end

  def set_var(name, value)
    @app.command(:set, name, value)
  end

  def get_var(name)
    @app.command(:set, name)
  end
end

GamepadViewer.new(calibrate: ARGV.include?('--calibrate')).run
