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
      @interp.tcl_eval('wm withdraw .')
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

    private

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
