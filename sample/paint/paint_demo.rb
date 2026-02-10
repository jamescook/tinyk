#!/usr/bin/env ruby
# teek-record: title=Paint Demo
# frozen_string_literal: true

# Paint Demo - Simple MS Paint-style drawing application
#
# Demonstrates what's possible with Teek beyond "hello world":
# - Teek::Photo for fast CPU-side pixel manipulation (flood fill, spray paint)
# - Canvas for vector drawing (strokes, shapes)
# - Layers with sparse pixel storage and photo image backing
# - Multi-window UI (tools palette, color palette, main canvas)
# - Undo/redo system
# - Menu bars and keyboard shortcuts
#
# This is NOT meant to be a production paint app -- it's a showcase of
# Teek's capabilities for anyone wondering "what can I actually build?"
#
# Tool icons in assets/ from Lucide (https://lucide.dev, MIT license)
# and Iconoir (https://iconoir.com, MIT license).

require_relative '../../lib/teek'
require_relative 'layer_manager'

class PaintDemo
  # Classic 16-color palette (Windows/VGA style)
  COLORS = [
    '#000000', '#808080', '#800000', '#808000',
    '#008000', '#008080', '#000080', '#800080',
    '#FFFFFF', '#C0C0C0', '#FF0000', '#FFFF00',
    '#00FF00', '#00FFFF', '#0000FF', '#FF00FF'
  ].freeze

  MAX_UNDO = 10

  PHOTO_WIDTH = 800
  PHOTO_HEIGHT = 600
  ASSETS_DIR = File.join(__dir__, 'assets').freeze

  def initialize(app)
    @app = app
    @brush_color = '#000000'
    @bg_color_hex = '#FFFFFF'
    @brush_size = 1
    @spray_density = 3
    @canvas_width = PHOTO_WIDTH
    @canvas_height = PHOTO_HEIGHT
    @last_x = nil
    @last_y = nil

    # Undo/redo stacks
    @undo_stack = []
    @redo_stack = []
    @current_stroke_items = []

    # Layer manager (created after canvas in setup_main_window)
    @layers = nil

    setup_main_window
    setup_tools_window
    setup_palette_window
  end

  def setup_main_window
    @app.set_window_title('Paint')
    @app.set_window_geometry("#{PHOTO_WIDTH}x#{PHOTO_HEIGHT + 40}")

    # Menu bar
    @app.command(:menu, '.menubar')
    @app.command('.', :configure, menu: '.menubar')
    create_edit_menu('.menubar')
    create_layer_menu('.menubar')
    create_window_menu('.menubar')

    # Status bar (packed first so canvas gets remaining space)
    status_frame = @app.create_widget('ttk::frame')
    status_frame.pack(side: :bottom, fill: :x)

    # Canvas fills the rest of the window
    @canvas = @app.create_widget(:canvas, background: :gray, cursor: :crosshair)
    @canvas.pack(fill: :both, expand: true)

    # Layer manager handles photo images and pixel buffers
    @layers = LayerManager.new(@app, @canvas, PHOTO_WIDTH, PHOTO_HEIGHT)
    @layers.active_layer.ensure_photo!
    @layers.active_layer.refresh_display

    # Drawing bindings
    @canvas.bind('ButtonPress-1', :x, :y) { |x, y| start_stroke(x.to_i, y.to_i) }
    @canvas.bind('B1-Motion', :x, :y) { |x, y| continue_stroke(x.to_i, y.to_i) }
    @canvas.bind('ButtonRelease-1') { end_stroke }

    # Keyboard shortcuts
    @app.bind('.', 'c') { clear_active_layer }
    @app.bind('.', 'Escape') { @app.destroy('.') }
    @app.bind('.', 'Control-z') { undo }
    @app.bind('.', 'Control-Z') { redo_action }
    @app.bind('.', 'Control-y') { redo_action }

    # Tool shortcuts
    @app.bind('.', 'b') { select_tool(:brush) }
    @app.bind('.', 'e') { select_tool(:eraser) }
    @app.bind('.', 'g') { select_tool(:bucket) }
    @app.bind('.', 's') { select_tool(:spray) }

    # Layer shortcuts
    @app.bind('.', 'Control-N') { add_layer }
    @app.bind('.', 'Control-period') { toggle_layer_visibility }
    (1..9).each do |n|
      @app.bind('.', "Key-#{n}") { select_layer_by_number(n - 1) }
    end

    @color_indicator = @app.create_widget(:canvas, parent: status_frame,
                                          width: 20, height: 20, highlightthickness: 1)
    @color_indicator.pack(side: :left, padx: 5, pady: 3)
    update_color_indicator

    @layer_var = 'paint_layer_info'
    @app.set_variable(@layer_var, '[0] Background')
    @app.create_widget('ttk::label', parent: status_frame,
                       textvariable: @layer_var, width: 20).pack(side: :left, padx: 5)

    # Brush size control
    @app.create_widget('ttk::label', parent: status_frame,
                       text: 'Size:').pack(side: :left, padx: 5)
    @brush_size_var = 'paint_brush_size'
    @app.set_variable(@brush_size_var, @brush_size.to_s)
    size_spinbox = @app.create_widget('ttk::spinbox', parent: status_frame,
                                      from: 1, to: 10, width: 3,
                                      textvariable: @brush_size_var,
                                      command: proc { update_brush_size })
    size_spinbox.pack(side: :left)
    size_spinbox.bind('KeyRelease') { update_brush_size }

    # Spray density control (only visible when spray tool selected)
    @density_label = @app.create_widget('ttk::label', parent: status_frame,
                                         text: 'Density:')
    @spray_density_var = 'paint_spray_density'
    @app.set_variable(@spray_density_var, @spray_density.to_s)
    @density_spinbox = @app.create_widget('ttk::spinbox', parent: status_frame,
                                           from: 1, to: 20, width: 3,
                                           textvariable: @spray_density_var,
                                           command: proc { update_spray_density })
    @density_spinbox.bind('KeyRelease') { update_spray_density }
    # Hidden by default (shown when spray tool is selected)

    @coords_var = 'paint_coords'
    @app.set_variable(@coords_var, '0, 0')
    @app.create_widget('ttk::label', parent: status_frame,
                       textvariable: @coords_var, width: 12).pack(side: :left, padx: 10)

    @app.create_widget('ttk::label', parent: status_frame,
                       text: "Ruby #{RUBY_VERSION}").pack(side: :right, padx: 10)

    # Track mouse position
    @last_coords_update = 0
    @canvas.bind('Motion', :x, :y) do |x, y|
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if (now - @last_coords_update) >= 0.005
        @app.set_variable(@coords_var, "#{x}, #{y}")
        @last_coords_update = now
      end
    end

    # Resize layers when canvas resizes
    @canvas.bind('Configure', :width, :height) do |w, h|
      new_w = w.to_i
      new_h = h.to_i
      if new_w > 0 && new_h > 0 && (new_w != @canvas_width || new_h != @canvas_height)
        @canvas_width = new_w
        @canvas_height = new_h
        @layers.resize(new_w, new_h)
      end
    end

    update_title
  end

  def setup_tools_window
    @tools_path = '.tools'
    @app.command(:toplevel, @tools_path)
    @app.command(:wm, :title, @tools_path, 'Tools')
    @app.command(:wm, :geometry, @tools_path, '50x200+910+300')
    @app.command(:wm, :resizable, @tools_path, 0, 0)

    @current_tool = :brush

    # Load PNG icons from assets
    @tool_icons = {}
    { brush: 'pencil', eraser: 'eraser', bucket: 'bucket', spray: 'spray' }.each do |tool, file|
      path = File.join(ASSETS_DIR, "#{file}.png")
      @tool_icons[tool] = Teek::Photo.new(@app, file: path)
    end

    tool_defs = [
      [:brush,  'Brush (B)'],
      [:eraser, 'Eraser (E)'],
      [:bucket, 'Fill (G)'],
      [:spray,  'Spray (S)']
    ]

    @tool_buttons = {}
    tool_defs.each do |tool, tip|
      btn = @app.create_widget(:canvas, "#{@tools_path}.#{tool}",
                               width: 36, height: 36, background: :white,
                               highlightthickness: 2, highlightbackground: :gray)
      btn.pack(padx: 4, pady: 4)
      @app.command(btn, :create, :image, 18, 18,
                   image: @tool_icons[tool].name, anchor: :center)
      btn.bind('ButtonPress-1') { select_tool(tool) }
      add_tooltip(btn, tip)
      @tool_buttons[tool] = btn
    end

    select_tool(:brush)

    @app.command(:wm, :protocol, @tools_path, 'WM_DELETE_WINDOW',
                 proc { @app.command(:wm, :withdraw, @tools_path) })
  end

  def setup_palette_window
    @palette_path = '.palette'
    @app.command(:toplevel, @palette_path)
    @app.command(:wm, :title, @palette_path, 'Colors')
    @app.command(:wm, :geometry, @palette_path, '170x160+910+100')
    @app.command(:wm, :resizable, @palette_path, 0, 0)

    # Grid of color buttons (4x4)
    COLORS.each_with_index do |color, i|
      row = i / 4
      col = i % 4

      btn = @app.create_widget(:canvas, parent: @palette_path,
                                width: 32, height: 32, background: color,
                                highlightthickness: 2, highlightbackground: :gray)
      btn.grid(row: row, column: col, padx: 2, pady: 2)
      btn.bind('ButtonPress-1') { select_color(color) }
    end

    @app.command(:wm, :protocol, @palette_path, 'WM_DELETE_WINDOW',
                 proc { @app.command(:wm, :withdraw, @palette_path) })
  end

  def create_edit_menu(menubar)
    @app.command(:menu, "#{menubar}.edit", tearoff: 0)
    @app.command(menubar, :add, :cascade, label: 'Edit', menu: "#{menubar}.edit")
    @app.command("#{menubar}.edit", :add, :command,
                 label: 'Undo', accelerator: 'Ctrl+Z', command: proc { undo })
    @app.command("#{menubar}.edit", :add, :command,
                 label: 'Redo', accelerator: 'Ctrl+Shift+Z', command: proc { redo_action })
    @app.command("#{menubar}.edit", :add, :separator)
    @app.command("#{menubar}.edit", :add, :command,
                 label: 'Clear Layer', command: proc { clear_active_layer })
    @app.command("#{menubar}.edit", :add, :command,
                 label: 'Clear All Layers', command: proc { clear_canvas })
  end

  def create_layer_menu(menubar)
    @app.command(:menu, "#{menubar}.layer", tearoff: 0)
    @app.command(menubar, :add, :cascade, label: 'Layer', menu: "#{menubar}.layer")
    @app.command("#{menubar}.layer", :add, :command,
                 label: 'Add Layer', command: proc { add_layer })
    @app.command("#{menubar}.layer", :add, :command,
                 label: 'Delete Layer', command: proc { delete_layer })
    @app.command("#{menubar}.layer", :add, :separator)
    @app.command("#{menubar}.layer", :add, :command,
                 label: 'Toggle Visibility', command: proc { toggle_layer_visibility })
    @app.command("#{menubar}.layer", :add, :separator)
    @app.command("#{menubar}.layer", :add, :command,
                 label: 'Flatten All', command: proc { flatten_layers })
  end

  def create_window_menu(menubar)
    @app.command(:menu, "#{menubar}.window", tearoff: 0)
    @app.command(menubar, :add, :cascade, label: 'Window', menu: "#{menubar}.window")
    @app.command("#{menubar}.window", :add, :command,
                 label: 'Show Tools', command: proc { @app.command(:wm, :deiconify, @tools_path) })
    @app.command("#{menubar}.window", :add, :command,
                 label: 'Show Colors', command: proc { @app.command(:wm, :deiconify, @palette_path) })
  end

  def add_tooltip(widget, text)
    widget.bind('Enter') do
      @app.tcl_eval('catch {destroy .tooltip}')
      @app.command(:toplevel, '.tooltip', background: '#FFFFE0')
      @app.command(:wm, :overrideredirect, '.tooltip', 1)
      @app.tcl_eval('catch {wm attributes .tooltip -type tooltip}')
      @app.tcl_eval('catch {wm attributes .tooltip -transparent true}')
      x = @app.tcl_eval('winfo pointerx .').to_i + 15
      y = @app.tcl_eval('winfo pointery .').to_i + 10
      @app.command(:wm, :geometry, '.tooltip', "+#{x}+#{y}")
      @app.create_widget(:frame, '.tooltip.f',
                         background: '#FFFFE0', relief: :solid,
                         borderwidth: 1).pack(fill: :both, expand: true)
      @app.create_widget(:label, '.tooltip.f.l', text: text,
                         background: '#FFFFE0', foreground: '#000000',
                         padx: 4, pady: 2).pack
    end
    widget.bind('Leave') do
      @app.tcl_eval('catch {destroy .tooltip}')
    end
  end

  def select_tool(tool)
    @current_tool = tool
    @tool_buttons.each do |_name, btn|
      btn.command(:configure, background: :white, highlightbackground: :gray, highlightthickness: 2)
    end
    @tool_buttons[tool]&.command(:configure, background: '#ADD8E6',
                                 highlightbackground: :black, highlightthickness: 3)

    cursor = case tool
             when :brush  then :crosshair
             when :eraser then :dotbox
             when :bucket then :target
             when :spray  then :spraycan
             else :crosshair
             end
    @canvas.command(:configure, cursor: cursor)

    # Show/hide spray density control
    if tool == :spray
      @density_label.pack(side: :left, padx: 5)
      @density_spinbox.pack(side: :left)
    else
      @app.command(:pack, :forget, @density_label) rescue nil
      @app.command(:pack, :forget, @density_spinbox) rescue nil
    end
  end

  def select_color(color)
    @brush_color = color
    update_color_indicator
  end

  def update_color_indicator
    @color_indicator.command(:configure, background: @brush_color)
  end

  def update_brush_size
    size = @app.get_variable(@brush_size_var).to_i
    size = 1 if size < 1
    size = 10 if size > 10
    @brush_size = size
  end

  def update_spray_density
    d = @app.get_variable(@spray_density_var).to_i
    d = 1 if d < 1
    d = 20 if d > 20
    @spray_density = d
  end

  # -- Drawing operations ---------------------------------------------------

  def start_stroke(x, y)
    if @current_tool == :bucket
      flood_fill(x, y)
      return
    end

    if @current_tool == :spray
      layer = @layers.active_layer
      @spray_old_pixels = layer.snapshot_pixels
      spray_paint(x, y)
      return
    end

    return unless @current_tool == :brush || @current_tool == :eraser
    @current_stroke_items = []
    @last_x = x
    @last_y = y
    draw_point(x, y)
  end

  def continue_stroke(x, y)
    if @current_tool == :spray
      spray_paint(x, y)
      return
    end

    return unless @current_tool == :brush || @current_tool == :eraser
    return unless @last_x && @last_y

    color = @current_tool == :eraser ? @bg_color_hex : @brush_color
    size = @current_tool == :eraser ? @brush_size * 3 : @brush_size

    item = @app.command(@canvas, :create, :line, @last_x, @last_y, x, y,
                        fill: color, width: size, capstyle: :round, joinstyle: :round)
    @current_stroke_items << item

    @last_x = x
    @last_y = y
  end

  def end_stroke
    if @current_tool == :spray
      layer = @layers.active_layer
      if @spray_old_pixels
        push_undo(LayerPixelsCommand.new(layer, @spray_old_pixels, layer.snapshot_pixels))
      end
      @spray_old_pixels = nil
      return
    end

    if @current_stroke_items && @current_stroke_items.any?
      push_undo(StrokeCommand.new(@app, @canvas, @current_stroke_items.dup))
    end
    @current_stroke_items = []
    @last_x = nil
    @last_y = nil
  end

  def draw_point(x, y)
    color = @current_tool == :eraser ? @bg_color_hex : @brush_color
    size = @current_tool == :eraser ? @brush_size * 3 : @brush_size
    r = size / 2.0
    item = @app.command(@canvas, :create, :oval, x - r, y - r, x + r, y + r,
                        fill: color, outline: color)
    @current_stroke_items << item if @current_stroke_items
  end

  # -- Layer operations -----------------------------------------------------

  def clear_canvas
    @layers.clear_all
    @layers.refresh_all
  end

  def clear_active_layer
    layer = @layers.active_layer
    return unless layer
    layer.clear
    layer.refresh_display
  end

  def add_layer
    @layers.add_layer
    update_title
  end

  def delete_layer
    return if @layers.layers.size <= 1
    @layers.remove_layer(@layers.active_index)
    @layers.refresh_all
    update_title
  end

  def toggle_layer_visibility
    layer = @layers.active_layer
    return unless layer
    layer.toggle_visibility
  end

  def flatten_layers
    @layers.flatten
    update_title
  end

  def update_title
    layer = @layers.active_layer
    layer_info = layer ? "[#{@layers.active_index}] #{layer.name}" : ""
    @app.set_window_title("Paint - #{layer_info}")
    @app.set_variable(@layer_var, layer_info) if @layer_var
  end

  def select_layer_by_number(index)
    return unless index >= 0 && index < @layers.layers.size
    @layers.active_index = index
    update_title
  end

  # -- Pixel operations -----------------------------------------------------

  def get_pixel(x, y)
    @layers.active_layer&.get_rgba(x, y)
  end

  def set_pixel(x, y, rgba)
    layer = @layers.active_layer
    return unless layer
    layer.set_rgba(x, y, *rgba)
  end

  def parse_hex_color(hex)
    hex = hex.delete('#')
    r = hex[0, 2].to_i(16)
    g = hex[2, 2].to_i(16)
    b = hex[4, 2].to_i(16)
    [r, g, b, 255]
  end

  def colors_match?(c1, c2, tolerance = 0)
    return false unless c1 && c2
    (c1[0] - c2[0]).abs <= tolerance &&
      (c1[1] - c2[1]).abs <= tolerance &&
      (c1[2] - c2[2]).abs <= tolerance
  end

  # -- Flood fill -----------------------------------------------------------

  def flood_fill(x, y)
    x = x.to_i
    y = y.to_i
    layer = @layers.active_layer
    return unless layer
    return if x < 0 || x >= @canvas_width || y < 0 || y >= @canvas_height

    target_color = get_pixel(x, y)
    fill_color = parse_hex_color(@brush_color)

    return if colors_match?(target_color, fill_color)

    old_pixels = layer.snapshot_pixels
    scanline_fill(x, y, target_color, fill_color)
    layer.refresh_display
    push_undo(LayerPixelsCommand.new(layer, old_pixels, layer.snapshot_pixels))
  end

  def scanline_fill(start_x, start_y, target_color, fill_color)
    stack = [[start_x, start_y]]

    while !stack.empty?
      x, y = stack.pop
      next if y < 0 || y >= @canvas_height

      lx = x
      while lx > 0 && colors_match?(get_pixel(lx - 1, y), target_color)
        lx -= 1
      end

      span_above = false
      span_below = false

      while lx < @canvas_width && colors_match?(get_pixel(lx, y), target_color)
        set_pixel(lx, y, fill_color)

        if y > 0
          above_matches = colors_match?(get_pixel(lx, y - 1), target_color)
          if !span_above && above_matches
            stack.push([lx, y - 1])
            span_above = true
          elsif span_above && !above_matches
            span_above = false
          end
        end

        if y < @canvas_height - 1
          below_matches = colors_match?(get_pixel(lx, y + 1), target_color)
          if !span_below && below_matches
            stack.push([lx, y + 1])
            span_below = true
          elsif span_below && !below_matches
            span_below = false
          end
        end

        lx += 1
      end
    end
  end

  # -- Spray paint ----------------------------------------------------------

  def spray_paint(x, y)
    x = x.to_i
    y = y.to_i
    layer = @layers.active_layer
    return unless layer

    fill_color = parse_hex_color(@brush_color)
    radius = @brush_size * 5
    pixels_per_spray = @brush_size * @spray_density

    pixels_per_spray.times do
      angle = rand * 2 * Math::PI
      r = rand * radius
      px = x + (r * Math.cos(angle)).to_i
      py = y + (r * Math.sin(angle)).to_i
      set_pixel(px, py, fill_color)
    end

    layer.refresh_display
  end

  # -- Undo/Redo ------------------------------------------------------------

  def push_undo(command)
    @undo_stack << command
    @undo_stack.shift if @undo_stack.size > MAX_UNDO
    @redo_stack.clear
  end

  def undo
    return if @undo_stack.empty?
    command = @undo_stack.pop
    command.undo
    @redo_stack << command
  end

  def redo_action
    return if @redo_stack.empty?
    command = @redo_stack.pop
    command.redo
    @undo_stack << command
  end

  # Command classes for undo/redo
  class StrokeCommand
    def initialize(app, canvas, items)
      @app = app
      @canvas = canvas
      @items = items
      @configs = items.map do |item|
        type = @app.command(@canvas, :type, item)
        coords = @app.split_list(@app.command(@canvas, :coords, item))
        {
          type: type,
          coords: coords,
          fill: (@app.command(@canvas, :itemcget, item, '-fill') rescue nil),
          width: (@app.command(@canvas, :itemcget, item, '-width') rescue nil),
          outline: (@app.command(@canvas, :itemcget, item, '-outline') rescue nil),
          capstyle: (@app.command(@canvas, :itemcget, item, '-capstyle') rescue nil),
          joinstyle: (@app.command(@canvas, :itemcget, item, '-joinstyle') rescue nil)
        }
      end
    end

    def undo
      @items.each { |item| @app.command(@canvas, :delete, item) }
    end

    def redo
      @items = @configs.map do |cfg|
        case cfg[:type]
        when 'line'
          opts = { fill: cfg[:fill], width: cfg[:width] }
          opts[:capstyle] = cfg[:capstyle] if cfg[:capstyle] && cfg[:capstyle] != ''
          opts[:joinstyle] = cfg[:joinstyle] if cfg[:joinstyle] && cfg[:joinstyle] != ''
          @app.command(@canvas, :create, :line, *cfg[:coords], **opts)
        when 'oval'
          @app.command(@canvas, :create, :oval, *cfg[:coords],
                       fill: cfg[:fill], outline: cfg[:outline] || cfg[:fill])
        when 'rectangle'
          @app.command(@canvas, :create, :rectangle, *cfg[:coords],
                       outline: cfg[:outline], width: cfg[:width])
        end
      end
    end
  end

  class LayerPixelsCommand
    def initialize(layer, old_pixels, new_pixels)
      @layer = layer
      @old_pixels = old_pixels
      @new_pixels = new_pixels
    end

    def undo
      @layer.restore_pixels(@old_pixels)
    end

    def redo
      @layer.restore_pixels(@new_pixels)
    end
  end

  # -- Auto-paint demo (for TeekDemo) --------------------------------------
  # Simulates real user interaction via virtual mouse events.
  # Actions are chained sequentially so the event loop can process display
  # updates between each one.

  def run_auto_demo
    # Move tools window onto the canvas so it's visible in the recording
    @app.command(:wm, :geometry, @tools_path, '+10+80')
    @app.command(:wm, :deiconify, @tools_path)

    @demo_queue = []
    @demo_canvas_path = @canvas.path
    @demo_interval = TeekDemo.delay(test: 1, record: 15)
    @demo_action_num = 0

    # Helper: queue a virtual mouse event
    q_mouse = proc do |event, x, y|
      @demo_queue << proc {
        @app.tcl_eval("event generate #{@demo_canvas_path} <#{event}> -x #{x} -y #{y}")
      }
    end

    # Helper: queue a UI action
    q_act = proc do |&block|
      @demo_queue << block
    end

    # -- Fill background sky blue with bucket tool --
    q_act.call { select_color('#87CEEB') }
    q_act.call { select_tool(:bucket) }
    q_mouse.call('ButtonPress-1', 400, 300)
    q_mouse.call('ButtonRelease-1', 400, 300)

    # -- Spray green ground --
    q_act.call { select_color('#228B22') }
    q_act.call { select_tool(:spray) }
    q_act.call do
      @brush_size = 10
      @app.set_variable(@brush_size_var, '10')
      @spray_density = 20
      @app.set_variable(@spray_density_var, '20')
    end
    q_mouse.call('ButtonPress-1', 50, 500)
    (100..750).step(40) do |x|
      q_mouse.call('B1-Motion', x, 480 + rand(40))
    end
    q_mouse.call('ButtonRelease-1', 750, 510)
    q_mouse.call('ButtonPress-1', 750, 550)
    (710..50).step(-40) do |x|
      q_mouse.call('B1-Motion', x, 530 + rand(40))
    end
    q_mouse.call('ButtonRelease-1', 50, 560)

    # -- Spray white clouds --
    q_act.call { select_color('#FFFFFF') }
    q_act.call do
      @brush_size = 8
      @app.set_variable(@brush_size_var, '8')
      @spray_density = 8
      @app.set_variable(@spray_density_var, '8')
    end
    q_mouse.call('ButtonPress-1', 180, 100)
    [[195, 90], [210, 85], [225, 90], [240, 100]].each { |x, y| q_mouse.call('B1-Motion', x, y) }
    q_mouse.call('ButtonRelease-1', 240, 100)
    q_mouse.call('ButtonPress-1', 520, 110)
    [[540, 100], [560, 95], [580, 100], [595, 110]].each { |x, y| q_mouse.call('B1-Motion', x, y) }
    q_mouse.call('ButtonRelease-1', 595, 110)

    # -- Spray golden sun --
    q_act.call { select_color('#FFD700') }
    q_act.call do
      @brush_size = 10
      @app.set_variable(@brush_size_var, '10')
      @spray_density = 10
      @app.set_variable(@spray_density_var, '10')
    end
    q_mouse.call('ButtonPress-1', 660, 80)
    [[670, 70], [680, 85], [665, 90], [675, 75]].each { |x, y| q_mouse.call('B1-Motion', x, y) }
    q_mouse.call('ButtonRelease-1', 670, 80)

    # -- Brush strokes: winding path --
    q_act.call { select_color('#8B6914') }
    q_act.call { select_tool(:brush) }
    q_act.call do
      @brush_size = 5
      @app.set_variable(@brush_size_var, '5')
    end
    path = [[100, 550], [200, 520], [320, 530], [450, 510], [550, 520], [680, 500], [780, 510]]
    q_mouse.call('ButtonPress-1', *path.first)
    path[1..].each { |x, y| q_mouse.call('B1-Motion', x, y) }
    q_mouse.call('ButtonRelease-1', *path.last)

    # -- Brush strokes: tree trunks and canopy --
    [[160, 440], [620, 430]].each do |tx, ty|
      q_act.call { select_color('#8B4513') }
      q_mouse.call('ButtonPress-1', tx, ty)
      q_mouse.call('B1-Motion', tx, ty + 70)
      q_mouse.call('ButtonRelease-1', tx, ty + 70)
      q_act.call do
        select_color('#006400')
        @brush_size = 8
        @app.set_variable(@brush_size_var, '8')
      end
      [[-20, -10], [0, -25], [20, -10], [-10, -18], [10, -18]].each do |dx, dy|
        q_mouse.call('ButtonPress-1', tx + dx, ty + dy)
        q_mouse.call('ButtonRelease-1', tx + dx, ty + dy)
      end
    end

    # -- Eraser demo: zigzag sweep so it's clearly erasing --
    q_act.call { select_tool(:eraser) }
    q_act.call do
      @brush_size = 6
      @app.set_variable(@brush_size_var, '6')
    end
    q_mouse.call('ButtonPress-1', 300, 280)
    [[330, 320], [360, 270], [390, 320], [420, 270],
     [450, 320], [480, 270], [510, 320]].each do |x, y|
      q_mouse.call('B1-Motion', x, y)
    end
    q_mouse.call('ButtonRelease-1', 510, 320)

    # -- Reset and finish --
    q_act.call do
      select_tool(:brush)
      @brush_size = 1
      @app.set_variable(@brush_size_var, '1')
    end

    $stdout.puts "[paint-demo] queued #{@demo_queue.size} actions"
    $stdout.flush
    run_next_demo_action
  end

  def run_next_demo_action
    if @demo_queue.empty?
      $stdout.puts "[paint-demo] all actions complete"
      $stdout.flush
      @app.after(@demo_interval) { TeekDemo.finish } if defined?(TeekDemo) && TeekDemo.active?
      return
    end

    action = @demo_queue.shift
    @demo_action_num += 1
    if (@demo_action_num % 20).zero?
      $stdout.puts "[paint-demo] action #{@demo_action_num}..."
      $stdout.flush
    end
    action.call
    @app.after(@demo_interval) { run_next_demo_action }
  end
end

# -- Main ------------------------------------------------------------------

app = Teek::App.new(track_widgets: false)
app.show

paint = PaintDemo.new(app)

# Automated demo support
require_relative '../../lib/teek/demo_support'
TeekDemo.app = app

if TeekDemo.active?
  TeekDemo.on_visible do
    app.after(200) { paint.run_auto_demo }
  end
end

app.mainloop
