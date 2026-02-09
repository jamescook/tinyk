# frozen_string_literal: true

module Teek
  # Thin wrapper around a Tk widget path. Holds a reference to the App and
  # the widget's Tcl path string.
  #
  # Instances are interchangeable with plain strings anywhere a widget path
  # is expected thanks to {#to_s} returning the path.
  #
  # Created via {App#create_widget}:
  #
  # @example
  #   btn = app.create_widget('ttk::button', text: 'Click')
  #   btn.command(:configure, text: 'Updated')
  #   app.command(:pack, btn, pady: 10)  # to_s makes this work
  #   btn.destroy
  #
  # @see App#create_widget
  class Widget
    attr_reader :app, :path

    def initialize(app, path)
      @app = app
      @path = path
    end

    # @return [String] the Tcl widget path
    def to_s
      @path
    end

    # Invoke a widget subcommand. Prepends the widget path as the Tcl command.
    #
    # @example
    #   btn.command(:configure, text: 'New')  # => .ttkbutton1 configure -text {New}
    #   btn.command(:invoke)                  # => .ttkbutton1 invoke
    #
    # @param args positional arguments
    # @param kwargs keyword arguments mapped to -key value pairs
    # @return [String] the Tcl result
    def command(*args, **kwargs)
      @app.command(@path, *args, **kwargs)
    end

    # Destroy this widget and all its children.
    # @return [void]
    def destroy
      @app.destroy(@path)
    end

    # Check if this widget still exists in the Tk interpreter.
    # @return [Boolean]
    def exist?
      @app.tcl_eval("winfo exists #{@path}") == '1'
    end

    # Pack this widget.
    # @param kwargs options passed to the Tk pack command
    # @return [self]
    def pack(**kwargs)
      @app.command(:pack, @path, **kwargs)
      self
    end

    # Grid this widget.
    # @param kwargs options passed to the Tk grid command
    # @return [self]
    def grid(**kwargs)
      @app.command(:grid, @path, **kwargs)
      self
    end

    # Bind an event on this widget.
    # @param event [String] Tk event name
    # @param subs [Array<Symbol, String>] substitution codes
    # @yield called when the event fires
    # @return [void]
    # @see App#bind
    def bind(event, *subs, &block)
      @app.bind(@path, event, *subs, &block)
    end

    # Remove an event binding from this widget.
    # @param event [String] Tk event name
    # @return [void]
    # @see App#unbind
    def unbind(event)
      @app.unbind(@path, event)
    end

    def inspect
      "#<Teek::Widget #{@path}>"
    end

    def ==(other)
      other.is_a?(Widget) ? @path == other.path : @path == other.to_s
    end
    alias eql? ==

    def hash
      @path.hash
    end
  end
end
