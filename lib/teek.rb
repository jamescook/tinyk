# frozen_string_literal: true

require 'tcltklib'
require_relative 'teek/ractor_support'

module Teek
  VERSION = "0.1.0"

  def self.bool_to_tcl(val)
    val ? "1" : "0"
  end

  WIDGET_COMMANDS = %w[
    button label frame entry text canvas listbox
    scrollbar scale spinbox menu menubutton message
    panedwindow labelframe checkbutton radiobutton
    toplevel
    ttk::button ttk::label ttk::frame ttk::entry
    ttk::combobox ttk::checkbutton ttk::radiobutton
    ttk::scale ttk::scrollbar ttk::spinbox ttk::separator
    ttk::sizegrip ttk::progressbar ttk::notebook
    ttk::panedwindow ttk::labelframe ttk::menubutton
    ttk::treeview
  ].freeze

  class App
    attr_reader :interp, :widgets, :debugger

    def initialize(track_widgets: true, debug: false, &block)
      @interp = Teek::Interp.new
      @interp.tcl_eval('package require Tk')
      hide
      @widgets = {}
      debug ||= !!ENV['TEEK_DEBUG']
      track_widgets = true if debug
      setup_widget_tracking if track_widgets
      if debug
        require_relative 'teek/debugger'
        @debugger = Teek::Debugger.new(self)
      end
      instance_eval(&block) if block
    end

    def tcl_eval(script)
      @interp.tcl_eval(script)
    end

    def tcl_invoke(*args)
      @interp.tcl_invoke(*args)
    end

    def register_callback(callable)
      wrapped = proc { |*args|
        caught = nil
        catch(:teek_break) do
          catch(:teek_continue) do
            catch(:teek_return) do
              callable.call(*args)
              caught = :_none
            end
            caught ||= :return
          end
          caught ||= :continue
        end
        caught ||= :break
        caught == :_none ? nil : caught
      }
      @interp.register_callback(wrapped)
    end

    def unregister_callback(id)
      @interp.unregister_callback(id)
    end

    def after(ms, &block)
      cb_id = nil
      cb_id = @interp.register_callback(proc { |*|
        block.call
        @interp.unregister_callback(cb_id)
      })
      after_id = @interp.tcl_eval("after #{ms.to_i} {ruby_callback #{cb_id}}")
      after_id.instance_variable_set(:@cb_id, cb_id)
      after_id
    end

    def after_idle(&block)
      cb_id = nil
      cb_id = @interp.register_callback(proc { |*|
        block.call
        @interp.unregister_callback(cb_id)
      })
      after_id = @interp.tcl_eval("after idle {ruby_callback #{cb_id}}")
      after_id.instance_variable_set(:@cb_id, cb_id)
      after_id
    end

    def after_cancel(after_id)
      @interp.tcl_eval("after cancel #{after_id}")
      if (cb_id = after_id.instance_variable_get(:@cb_id))
        @interp.unregister_callback(cb_id)
        after_id.instance_variable_set(:@cb_id, nil)
      end
      after_id
    end

    def split_list(str)
      Teek.split_list(str)
    end

    def make_list(*args)
      Teek.make_list(*args)
    end

    def tcl_to_bool(str)
      Teek.tcl_to_bool(str)
    end

    def bool_to_tcl(val)
      Teek.bool_to_tcl(val)
    end

    def command(cmd, *args, **kwargs)
      parts = [cmd.to_s]
      args.each do |arg|
        parts << tcl_value(arg)
      end
      kwargs.each do |key, value|
        parts << "-#{key}"
        parts << tcl_value(value)
      end
      @interp.tcl_eval(parts.join(' '))
    end

    def mainloop
      @interp.mainloop
    end

    def update
      @interp.tcl_eval('update')
    end

    def update_idletasks
      @interp.tcl_eval('update idletasks')
    end

    def show(window = '.')
      @interp.tcl_eval("wm deiconify #{window}")
    end

    def hide(window = '.')
      @interp.tcl_eval("wm withdraw #{window}")
    end

    # Bind a Tk event on a widget, with optional substitutions forwarded
    # as block arguments. Substitutions can be symbols (mapped to Tk's %
    # codes) or raw strings passed through as-is.
    #
    #   # Mouse click with window coordinates
    #   app.bind('.c', 'Button-1', :x, :y) { |x, y| puts "#{x},#{y}" }
    #
    #   # Key press
    #   app.bind('.', 'KeyPress', :keysym) { |k| puts k }
    #
    #   # No substitutions
    #   app.bind('.btn', 'Enter') { highlight }
    #
    #   # Raw Tcl expression (for cases not covered by symbol map)
    #   app.bind('.c', 'Button-1', '%T') { |type| ... }
    #
    # For canvas work, use command() to convert window coords to canvas
    # coords inside the block:
    #
    #   app.bind(canvas, 'Button-1', :x, :y) do |x, y|
    #     cx = app.command(canvas, :canvasx, x).to_f
    #     cy = app.command(canvas, :canvasy, y).to_f
    #   end
    #
    # Performance note: each substitution is passed from Tcl to Ruby as a
    # callback argument (one crossing). Any command() calls inside the block
    # are additional Tcl round-trips. This is negligible for click/key
    # events but could matter in hot-path handlers like <Motion> that fire
    # hundreds of times per second. For those, consider tcl_eval with
    # inline Tcl expressions to do all work in a single evaluation.
    #
    BIND_SUBS = {
      x: '%x', y: '%y',                   # window coordinates
      root_x: '%X', root_y: '%Y',         # screen coordinates
      widget: '%W',                        # widget path
      keysym: '%K', keycode: '%k',         # key events
      char: '%A',                          # character (key events)
      width: '%w', height: '%h',           # Configure events
      button: '%b',                        # mouse button number
      mouse_wheel: '%D',                   # mousewheel delta
      type: '%T',                          # event type
    }.freeze

    def bind(widget, event, *subs, &block)
      event_str = event.start_with?('<') ? event : "<#{event}>"
      cb = register_callback(proc { |*args| block.call(*args) })
      tcl_subs = subs.map { |s| s.is_a?(Symbol) ? BIND_SUBS.fetch(s) : s.to_s }
      sub_str = tcl_subs.empty? ? '' : ' ' + tcl_subs.join(' ')
      @interp.tcl_eval("bind #{widget} #{event_str} {ruby_callback #{cb}#{sub_str}}")
    end

    def unbind(widget, event)
      event_str = event.start_with?('<') ? event : "<#{event}>"
      @interp.tcl_eval("bind #{widget} #{event_str} {}")
    end

    # Toggle the macOS window appearance between light ("aqua") and dark
    # ("darkaqua") mode, or pass a specific value. No-op on non-macOS.
    #
    #   app.appearance          # => "aqua", "darkaqua", or "auto"
    #   app.appearance = :light # force light mode
    #   app.appearance = :dark  # force dark mode
    #   app.appearance = :auto  # follow system setting
    #
    def appearance
      return nil unless aqua?
      if tk_major >= 9
        @interp.tcl_eval('wm attributes . -appearance').delete('"')
      else
        @interp.tcl_eval('tk::unsupported::MacWindowStyle appearance .')
      end
    end

    def appearance=(mode)
      return unless aqua?
      value = case mode.to_sym
              when :light then 'aqua'
              when :dark  then 'darkaqua'
              when :auto  then 'auto'
              else mode.to_s
              end
      if tk_major >= 9
        @interp.tcl_eval("wm attributes . -appearance #{value}")
      else
        @interp.tcl_eval("tk::unsupported::MacWindowStyle appearance . #{value}")
      end
    end

    # Returns true if the window is currently displayed in dark mode.
    # Always returns false on non-macOS.
    def dark?
      return false unless aqua?
      @interp.tcl_eval('tk::unsupported::MacWindowStyle isdark .').delete('"') == '1'
    end

    private

    def aqua?
      @aqua ||= @interp.tcl_eval('tk windowingsystem') == 'aqua'
    end

    def tk_major
      @tk_major ||= @interp.tcl_eval('info patchlevel').split('.').first.to_i
    end

    def setup_widget_tracking
      @create_cb_id = @interp.register_callback(proc { |path, cls|
        next if path.start_with?('.teek_debug')
        @widgets[path] = { class: cls, parent: File.dirname(path).gsub(/\A$/, '.') }
        @debugger&.on_widget_created(path, cls)
      })
      @destroy_cb_id = @interp.register_callback(proc { |path|
        next if path.start_with?('.teek_debug')
        @widgets.delete(path)
        @debugger&.on_widget_destroyed(path)
      })

      # Tcl proc called on widget creation (trace leave)
      @interp.tcl_eval("proc ::teek_track_create {cmd_string code result op} {
        set path [lindex $cmd_string 1]
        if {$code == 0 && [winfo exists $path]} {
          set cls [winfo class $path]
          ruby_callback #{@create_cb_id} $path $cls
        }
      }")

      # Tcl proc called on widget destruction (bind)
      @interp.tcl_eval("bind all <Destroy> {ruby_callback #{@destroy_cb_id} %W}")

      # Add trace on each widget command
      Teek::WIDGET_COMMANDS.each do |cmd|
        @interp.tcl_eval("catch {trace add execution #{cmd} leave ::teek_track_create}")
      end
    end

    def tcl_value(value)
      case value
      when Proc
        id = @interp.register_callback(value)
        "{ruby_callback #{id}}"
      when Symbol
        value.to_s
      else
        "{#{value}}"
      end
    end
  end
end
