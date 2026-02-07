# frozen_string_literal: true

# Tests for callback control flow via throw/catch.
#
# throw :teek_break    → TCL_BREAK   (stops event propagation)
# throw :teek_continue → TCL_CONTINUE
# throw :teek_return   → TCL_RETURN

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestCallbackControlFlow < Minitest::Test
  include TeekTestHelper

  # throw :teek_break in a bind handler should stop event propagation
  # to subsequent binding tags (same as Tcl "break").
  def test_break_stops_event_propagation
    assert_tk_app("throw :teek_break should stop event propagation",
                  method(:app_break_stops_propagation))
  end

  def app_break_stops_propagation
    first_fired = false
    second_fired = false

    app.tcl_eval("wm deiconify .")
    app.tcl_eval("entry .e")
    app.tcl_eval("pack .e")

    # Bind on the widget itself - fires first, throws break
    cb1 = app.register_callback(proc { |*|
      first_fired = true
      throw :teek_break
    })
    app.tcl_eval("bind .e <Key-a> {ruby_callback #{cb1}}")

    # Bind on the Entry class tag - should NOT fire due to break
    cb2 = app.register_callback(proc { |*|
      second_fired = true
    })
    app.tcl_eval("bind Entry <Key-a> {ruby_callback #{cb2}}")

    # Generate the event
    app.tcl_eval("focus -force .e")
    app.update
    app.tcl_eval("event generate .e <Key-a>")
    app.update

    raise "first callback did not fire" unless first_fired
    raise "second callback fired despite break" if second_fired

    # Clean up class binding so it doesn't leak to other tests
    app.tcl_eval("bind Entry <Key-a> {}")
  end

  # throw :teek_return should not crash - returns TCL_RETURN to Tcl.
  def test_return_does_not_crash
    assert_tk_app("throw :teek_return should not crash",
                  method(:app_return_does_not_crash))
  end

  def app_return_does_not_crash
    fired = false

    cb = app.register_callback(proc { |*|
      fired = true
      throw :teek_return
    })

    app.tcl_eval("button .b_ret -command {ruby_callback #{cb}}")
    app.tcl_eval(".b_ret invoke")

    raise "callback did not fire" unless fired
  end

  # Normal callbacks (no throw) should work unchanged.
  def test_normal_callback_unaffected
    assert_tk_app("normal callback should work",
                  method(:app_normal_callback))
  end

  def app_normal_callback
    result = nil

    cb = app.register_callback(proc { |*|
      result = "hello"
    })

    app.tcl_eval("button .b_norm -command {ruby_callback #{cb}}")
    app.tcl_eval(".b_norm invoke")

    raise "callback did not fire, got #{result.inspect}" unless result == "hello"
  end

  # Real exceptions should still propagate as errors, not be
  # confused with control flow.
  def test_real_exception_is_tcl_error
    assert_tk_app("real exception should become Tcl error",
                  method(:app_real_exception))
  end

  def app_real_exception
    cb = app.register_callback(proc { |*|
      raise "boom"
    })

    # Tcl should catch this as an error
    result = app.tcl_eval("catch {ruby_callback #{cb}} errmsg")
    raise "expected Tcl error (1), got #{result}" unless result == "1"

    msg = app.tcl_eval("set errmsg")
    raise "error message lost, got #{msg.inspect}" unless msg.include?("boom")
  end
end
