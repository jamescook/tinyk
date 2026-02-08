# frozen_string_literal: true

# Canvas and Tcl helpers for the Goldberg demo.
# Provides a thin wrapper around Tcl canvas commands so the draw/move
# methods read almost like the original tk-ng version.
#
# Including class must provide:
#   @app    - Teek::App instance
#   @canvas - Tcl path of the canvas widget (String)

module GoldbergHelpers

  # -- Tcl value formatting ------------------------------------------------

  def tcl_val(v)
    case v
    when true  then '1'
    when false then '0'
    when nil   then '{}'
    when Symbol then v.to_s
    when Array
      inner = v.map { |e|
        s = e.is_a?(Symbol) ? e.to_s : e.to_s
        s.include?(' ') ? "{#{s}}" : s
      }.join(' ')
      "{#{inner}}"
    when String
      v.empty? ? '{}' : "{#{v}}"
    when Numeric
      v.to_s
    else
      "{#{v}}"
    end
  end

  def format_font(f)
    return "{#{f}}" if f.is_a?(String)
    parts = f.map { |p|
      s = p.is_a?(Symbol) ? p.to_s : p.to_s
      s.include?(' ') ? "{#{s}}" : s
    }
    "{#{parts.join(' ')}}"
  end

  def tcl_opts(opts)
    opts.map { |k, v|
      key = k == :tag ? :tags : k
      val = key == :font ? format_font(v) : tcl_val(v)
      "-#{key} #{val}"
    }.join(' ')
  end

  # -- Canvas item creation ------------------------------------------------
  # All return the Tcl item id (string).

  def ccreate(type, *coords, **opts)
    c = coords.flatten.join(' ')
    o = opts.empty? ? '' : " #{tcl_opts(opts)}"
    @app.tcl_eval("#{@canvas} create #{type} #{c}#{o}")
  end

  def cline(*coords, **opts)   = ccreate(:line, *coords, **opts)
  def cpoly(*coords, **opts)   = ccreate(:polygon, *coords, **opts)
  def coval(*coords, **opts)   = ccreate(:oval, *coords, **opts)
  def carc(*coords, **opts)    = ccreate(:arc, *coords, **opts)
  def crect(*coords, **opts)   = ccreate(:rectangle, *coords, **opts)
  def ctext(*coords, **opts)   = ccreate(:text, *coords, **opts)
  def cbitmap(*coords, **opts) = ccreate(:bitmap, *coords, **opts)

  # -- Canvas operations ---------------------------------------------------

  def cmove(tag, dx, dy)
    @app.tcl_eval("#{@canvas} move #{tag} #{dx} #{dy}")
  end

  def ccoords(tag, new_coords = nil)
    if new_coords
      @app.tcl_eval("#{@canvas} coords #{tag} #{new_coords.flatten.join(' ')}")
    else
      @app.tcl_eval("#{@canvas} coords #{tag}").split.map(&:to_f)
    end
  end

  def cdel(*tags)
    tags.each { |t| @app.tcl_eval("#{@canvas} delete #{t}") }
  end

  def cbbox(tag)
    r = @app.tcl_eval("#{@canvas} bbox #{tag}")
    r.empty? ? nil : r.split.map(&:to_f)
  end

  def cscale(tag, ox, oy, sx, sy)
    @app.tcl_eval("#{@canvas} scale #{tag} #{ox} #{oy} #{sx} #{sy}")
  end

  def citemconfig(tag, **opts)
    @app.tcl_eval("#{@canvas} itemconfigure #{tag} #{tcl_opts(opts)}")
  end

  def citemcget(tag, opt)
    @app.tcl_eval("#{@canvas} itemcget #{tag} -#{opt}")
  end

  def cfind(tag)
    r = @app.tcl_eval("#{@canvas} find withtag #{tag}")
    r.empty? ? [] : r.split
  end

  def craise(tag, above = nil)
    cmd = "#{@canvas} raise #{tag}"
    cmd += " #{above}" if above
    @app.tcl_eval(cmd)
  end

  def clower(tag, below = nil)
    cmd = "#{@canvas} lower #{tag}"
    cmd += " #{below}" if below
    @app.tcl_eval(cmd)
  end

  # Bind an event on a canvas item (tag).
  def cbind_item(tag, event, &block)
    id = @app.register_callback(proc { |*| block.call })
    @app.tcl_eval("#{@canvas} bind #{tag} <#{event}> {ruby_callback #{id}}")
  end

  # Bind an event on the canvas widget itself.
  def canvas_bind(event, &block)
    @app.bind(@canvas, event, &block)
  end

  def canvas_bind_remove(event)
    @app.unbind(@canvas, event)
  end

  # -- Misc helpers --------------------------------------------------------

  def winfo_pixels(val)
    @app.tcl_eval("winfo pixels #{@canvas} #{val}").to_i
  end

  def clock_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  end

  # Simple wrapper for a Tcl variable (for -textvariable / -variable binding).
  class TclVar
    attr_reader :name

    def initialize(app, var_name, initial = '')
      @app = app
      @name = "::gb_#{var_name}"
      set(initial)
    end

    def get
      @app.tcl_eval("set #{@name}")
    end

    def set(v)
      @app.tcl_eval("set #{@name} {#{v}}")
    end

    def to_s = get
    def to_i = get.to_i
    def to_f = get.to_f
    def bool = (get != '0' && !get.empty?)
  end
end
