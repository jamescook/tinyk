# frozen_string_literal: true

# Tests for Teek::CallbackBreak, CallbackContinue, CallbackReturn.
#
# These exceptions translate to TCL_BREAK, TCL_CONTINUE, TCL_RETURN
# when raised inside a Ruby callback invoked from Tcl.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestCallbackExceptions < Minitest::Test
  include TeekTestHelper

  # CallbackBreak in a bind handler should stop event propagation
  # to subsequent binding tags (same as Tcl "break").
  def test_callback_break_stops_event_propagation
    assert_tk_app("CallbackBreak should stop event propagation",
                  method(:app_callback_break))
  end

  def app_callback_break
    first_fired = false
    second_fired = false

    app.tcl_eval("entry .e")
    app.tcl_eval("pack .e")

    # Bind on the widget itself - fires first, raises break
    cb1 = app.register_callback(proc { |*|
      first_fired = true
      raise Teek::CallbackBreak
    })
    app.tcl_eval("bind .e <Key-a> {ruby_callback #{cb1}}")

    # Bind on the Entry class tag - should NOT fire due to break
    cb2 = app.register_callback(proc { |*|
      second_fired = true
    })
    app.tcl_eval("bind Entry <Key-a> {ruby_callback #{cb2}}")

    # Generate the event
    app.tcl_eval("focus .e")
    app.update
    app.tcl_eval("event generate .e <Key-a>")
    app.update

    raise "first callback did not fire" unless first_fired
    raise "second callback fired despite break" if second_fired

    # Clean up class binding so it doesn't leak to other tests
    app.tcl_eval("bind Entry <Key-a> {}")
  end

  # CallbackReturn in a bind handler should stop propagation
  # but with TCL_RETURN semantics (like Tcl "return").
  def test_callback_return
    assert_tk_app("CallbackReturn should return TCL_RETURN",
                  method(:app_callback_return))
  end

  def app_callback_return
    fired = false

    cb = app.register_callback(proc { |*|
      fired = true
      raise Teek::CallbackReturn
    })

    # Use a button command - CallbackReturn should not crash
    app.tcl_eval("button .b_ret -command {ruby_callback #{cb}}")
    app.tcl_eval(".b_ret invoke")

    raise "callback did not fire" unless fired
  end

  # Verify the exception classes exist and have correct hierarchy
  def test_exception_hierarchy
    assert_tk_app("Callback exceptions should be StandardError subclasses",
                  method(:app_exception_hierarchy))
  end

  def app_exception_hierarchy
    [Teek::CallbackBreak, Teek::CallbackContinue, Teek::CallbackReturn].each do |klass|
      raise "#{klass} is not a StandardError" unless klass < StandardError
      raise "#{klass} should not be a RuntimeError" if klass < RuntimeError
    end
  end
end
