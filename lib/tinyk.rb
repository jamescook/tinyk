# frozen_string_literal: true

require 'tcltklib'
require_relative 'tinyk/ractor_support'

module TinyK
  VERSION = "0.1.0"

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
    attr_reader :interp, :widgets

    def initialize(track_widgets: true, &block)
      @interp = TclTkIp.new
      @interp.tcl_eval('package require Tk')
      @interp.tcl_eval('wm withdraw .')
      @widgets = {}
      setup_widget_tracking if track_widgets
      instance_eval(&block) if block
    end

    def tcl_eval(script)
      @interp.tcl_eval(script)
    end

    def tcl_invoke(*args)
      @interp.tcl_invoke(*args)
    end

    def register_callback(proc)
      @interp.register_callback(proc)
    end

    def unregister_callback(id)
      @interp.unregister_callback(id)
    end

    def after(ms, &block)
      id = nil
      id = @interp.register_callback(proc { |*|
        block.call
        @interp.unregister_callback(id)
      })
      @interp.tcl_eval("after #{ms.to_i} {ruby_callback #{id}}")
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

    private

    def setup_widget_tracking
      @create_cb_id = @interp.register_callback(proc { |path, cls|
        @widgets[path] = { class: cls, parent: File.dirname(path).gsub(/\A$/, '.') }
      })
      @destroy_cb_id = @interp.register_callback(proc { |path|
        @widgets.delete(path)
      })

      # Tcl proc called on widget creation (trace leave)
      @interp.tcl_eval("proc ::tinyk_track_create {cmd_string code result op} {
        set path [lindex $cmd_string 1]
        if {$code == 0 && [winfo exists $path]} {
          set cls [winfo class $path]
          ruby_callback #{@create_cb_id} $path $cls
        }
      }")

      # Tcl proc called on widget destruction (bind)
      @interp.tcl_eval("bind all <Destroy> {ruby_callback #{@destroy_cb_id} %W}")

      # Add trace on each widget command
      TinyK::WIDGET_COMMANDS.each do |cmd|
        @interp.tcl_eval("catch {trace add execution #{cmd} leave ::tinyk_track_create}")
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
