# frozen_string_literal: true

require 'tcltklib'
require_relative 'teek/version'
require_relative 'teek/ractor_support'

# Ruby interface to Tcl/Tk. Provides a thin wrapper around a Tcl interpreter
# with Ruby callbacks, event bindings, and background work support.
#
# The main entry point is {Teek::App}, which initializes Tcl/Tk and provides
# methods for evaluating Tcl code, creating widgets, and running the event loop.
#
# @example Basic usage
#   app = Teek::App.new
#   app.command('ttk::button', '.btn', text: 'Click', command: proc { puts "hi" })
#   app.command(:pack, '.btn')
#   app.show
#   app.mainloop
#
# @example Background work (keeps UI responsive)
#   app.background_work(urls, mode: :thread) do |task, data|
#     data.each { |url| task.yield(fetch(url)) }
#   end.on_progress { |result| update_ui(result) }
#      .on_done { puts "Finished" }
#
# @see Teek::App
# @see Teek::BackgroundWork
module Teek

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

    # Evaluate a raw Tcl script string and return the result.
    # Prefer {#command} for building commands from Ruby values; use this
    # when you need Tcl-level features like variable substitution or
    # inline expressions that {#command} can't express.
    # @param script [String] Tcl code to evaluate
    # @return [String] the Tcl result
    def tcl_eval(script)
      @interp.tcl_eval(script)
    end

    # Invoke a Tcl command with pre-split arguments (no Tcl parsing).
    # Safer than {#tcl_eval} when arguments may contain special characters.
    # @param args [Array<String>] command name followed by arguments
    # @return [String] the Tcl result
    def tcl_invoke(*args)
      @interp.tcl_invoke(*args)
    end

    # Register a Ruby callable as a Tcl callback.
    # The callable can use +throw+ for Tcl control flow:
    #   throw :teek_break    - stop event propagation (like Tcl "break")
    #   throw :teek_continue - Tcl TCL_CONTINUE
    #   throw :teek_return   - Tcl TCL_RETURN
    # @param callable [#call] a Proc or lambda to invoke from Tcl
    # @return [Integer] callback ID, usable as +ruby_callback <id>+ in Tcl
    # @see #unregister_callback
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

    # Remove a previously registered callback by its ID.
    # @param id [Integer] callback ID returned by {#register_callback}
    # @return [void]
    def unregister_callback(id)
      @interp.unregister_callback(id)
    end

    # Schedule a one-shot timer. Calls the block after +ms+ milliseconds.
    # @param ms [Integer] delay in milliseconds
    # @yield block to call when the timer fires
    # @return [String] timer ID, pass to {#after_cancel} to cancel
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

    # Schedule a block to run once when the event loop is idle.
    # @yield block to call when the event loop is idle
    # @return [String] timer ID, pass to {#after_cancel} to cancel
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

    # Cancel a pending {#after} or {#after_idle} timer.
    # @param after_id [String] timer ID returned by {#after} or {#after_idle}
    # @return [void]
    def after_cancel(after_id)
      @interp.tcl_eval("after cancel #{after_id}")
      if (cb_id = after_id.instance_variable_get(:@cb_id))
        @interp.unregister_callback(cb_id)
        after_id.instance_variable_set(:@cb_id, nil)
      end
      after_id
    end

    # Split a Tcl list string into a Ruby array of strings.
    # @param str [String] a Tcl-formatted list
    # @return [Array<String>]
    def split_list(str)
      Teek.split_list(str)
    end

    # Build a properly-escaped Tcl list from Ruby strings.
    # @param args [Array<String>] elements to join
    # @return [String] a Tcl-formatted list
    def make_list(*args)
      Teek.make_list(*args)
    end

    # Convert a Tcl boolean string ("0", "1", "yes", "no", etc.) to Ruby boolean.
    # @param str [String] a Tcl boolean value
    # @return [Boolean]
    def tcl_to_bool(str)
      Teek.tcl_to_bool(str)
    end

    # Convert a Ruby boolean to a Tcl boolean string ("1" or "0").
    # @param val [Boolean]
    # @return [String] "1" or "0"
    def bool_to_tcl(val)
      Teek.bool_to_tcl(val)
    end

    # Build and evaluate a Tcl command from Ruby values.
    # Positional args are converted: Symbols pass bare, Procs become
    # callbacks, everything else is brace-quoted. Keyword args become
    # +-key value+ option pairs.
    # @example
    #   app.command(:pack, '.btn', side: :left, padx: 10)
    #   # evaluates: pack .btn -side left -padx {10}
    # @param cmd [Symbol, String] the Tcl command name
    # @param args positional arguments
    # @param kwargs keyword arguments mapped to +-key value+ pairs
    # @return [String] the Tcl result
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

    # Enter the Tk event loop. Blocks until the application exits.
    # @return [void]
    def mainloop
      @interp.mainloop
    end

    # Process all pending events and idle callbacks, then return.
    # @return [void]
    def update
      @interp.tcl_eval('update')
    end

    # Process only pending idle callbacks (e.g. geometry redraws), then return.
    # @return [void]
    def update_idletasks
      @interp.tcl_eval('update idletasks')
    end

    # Show a window. Defaults to the root window (".").
    # @param window [String] Tk window path
    # @return [void]
    def show(window = '.')
      @interp.tcl_eval("wm deiconify #{window}")
    end

    # Hide a window without destroying it. Defaults to the root window (".").
    # @param window [String] Tk window path
    # @return [void]
    def hide(window = '.')
      @interp.tcl_eval("wm withdraw #{window}")
    end

    # Bind a Tk event on a widget, with optional substitutions forwarded
    # as block arguments. Substitutions can be symbols (mapped via
    # {BIND_SUBS}) or raw Tcl +%+ codes passed through as-is.
    #
    # @example Mouse click with window coordinates
    #   app.bind('.c', 'Button-1', :x, :y) { |x, y| puts "#{x},#{y}" }
    # @example Key press
    #   app.bind('.', 'KeyPress', :keysym) { |k| puts k }
    # @example No substitutions
    #   app.bind('.btn', 'Enter') { highlight }
    # @example Raw Tcl expression (for codes not in BIND_SUBS)
    #   app.bind('.c', 'Button-1', '%T') { |type| ... }
    # @example Canvas coordinate conversion
    #   app.bind(canvas, 'Button-1', :x, :y) do |x, y|
    #     cx = app.command(canvas, :canvasx, x).to_f
    #     cy = app.command(canvas, :canvasy, y).to_f
    #   end
    #
    # @note Each substitution crosses from Tcl to Ruby once. Any {#command}
    #   calls inside the block are additional round-trips. This is negligible
    #   for click/key events but could matter for hot-path handlers like
    #   +<Motion>+ that fire hundreds of times per second. For those, consider
    #   {#tcl_eval} with inline Tcl expressions to do all work in one evaluation.
    #
    # @param widget [String] Tk widget path or class tag (e.g. ".btn", "Entry")
    # @param event [String] Tk event name, with or without angle brackets
    # @param subs [Array<Symbol, String>] substitution codes (see {BIND_SUBS})
    # @yield [*values] called when the event fires, with substitution values
    # @return [void]
    # @see #unbind
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

    # Remove an event binding previously set with {#bind}.
    # @param widget [String] Tk widget path or class tag
    # @param event [String] Tk event name, with or without angle brackets
    # @return [void]
    # @see #bind
    def unbind(widget, event)
      event_str = event.start_with?('<') ? event : "<#{event}>"
      @interp.tcl_eval("bind #{widget} #{event_str} {}")
    end

    # Get the macOS window appearance. No-op (returns +nil+) on non-macOS.
    # @example
    #   app.appearance          # => "aqua", "darkaqua", or "auto"
    #   app.appearance = :light # force light mode
    #   app.appearance = :dark  # force dark mode
    #   app.appearance = :auto  # follow system setting
    # @return [String, nil] "aqua", "darkaqua", "auto", or nil on non-macOS
    # @see #dark?
    def appearance
      return nil unless aqua?
      if tk_major >= 9
        @interp.tcl_eval('wm attributes . -appearance').delete('"')
      else
        @interp.tcl_eval('tk::unsupported::MacWindowStyle appearance .')
      end
    end

    # Set the macOS window appearance. No-op on non-macOS.
    # @param mode [Symbol, String] +:light+, +:dark+, +:auto+, or a raw Tk value
    # @return [void]
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
    # @return [Boolean]
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
