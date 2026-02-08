# frozen_string_literal: true

# Tests for App#bind - event binding with optional substitutions.

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestBind < Minitest::Test
  include TeekTestHelper

  # Basic bind with no substitutions fires the block.
  def test_bind_fires_callback
    assert_tk_app("bind should fire callback on event", method(:app_bind_fires_callback))
  end

  def app_bind_fires_callback
    fired = false

    app.show
    app.tcl_eval("entry .e")
    app.tcl_eval("pack .e")

    app.bind('.e', 'Key-a') { fired = true }

    app.tcl_eval("focus -force .e")
    app.update
    app.tcl_eval("event generate .e <Key-a>")
    app.update

    raise "callback did not fire" unless fired
  end

  # Bind with symbol substitutions passes values to the block.
  def test_bind_with_symbol_subs
    assert_tk_app("bind should forward substitution values", method(:app_bind_with_symbol_subs))
  end

  def app_bind_with_symbol_subs
    received_keysym = nil

    app.show
    app.tcl_eval("entry .e")
    app.tcl_eval("pack .e")

    app.bind('.e', 'KeyPress', :keysym) { |k| received_keysym = k }

    app.tcl_eval("focus -force .e")
    app.update
    app.tcl_eval("event generate .e <KeyPress-a> -keysym a")
    app.update

    raise "keysym not received, got #{received_keysym.inspect}" unless received_keysym == "a"
  end

  # Bind with multiple substitutions passes all values.
  def test_bind_with_multiple_subs
    assert_tk_app("bind should forward multiple subs", method(:app_bind_with_multiple_subs))
  end

  def app_bind_with_multiple_subs
    got_x = nil
    got_y = nil

    app.show
    app.tcl_eval("frame .f -width 100 -height 100")
    app.tcl_eval("pack .f")
    app.update

    app.bind('.f', 'Button-1', :x, :y) { |x, y| got_x = x; got_y = y }

    app.tcl_eval("event generate .f <Button-1> -x 42 -y 17")
    app.update

    raise "x not received, got #{got_x.inspect}" unless got_x == "42"
    raise "y not received, got #{got_y.inspect}" unless got_y == "17"
  end

  # Bind with raw string substitution (for codes not in BIND_SUBS).
  def test_bind_with_raw_sub
    assert_tk_app("bind with raw %W should forward widget path", method(:app_bind_with_raw_sub))
  end

  def app_bind_with_raw_sub
    got_widget = nil

    app.show
    app.tcl_eval("entry .e2")
    app.tcl_eval("pack .e2")

    app.bind('.e2', 'FocusIn', '%W') { |w| got_widget = w }

    app.tcl_eval("focus -force .e2")
    app.update

    raise "widget path not received, got #{got_widget.inspect}" unless got_widget == ".e2"
  end

  # Event string with <> already present should not double-wrap.
  def test_bind_with_angle_brackets
    assert_tk_app("bind should not double-wrap <> in event", method(:app_bind_with_angle_brackets))
  end

  def app_bind_with_angle_brackets
    fired = false

    app.show
    app.tcl_eval("entry .e")
    app.tcl_eval("pack .e")

    app.bind('.e', '<Key-b>') { fired = true }

    app.tcl_eval("focus -force .e")
    app.update
    app.tcl_eval("event generate .e <Key-b>")
    app.update

    raise "callback did not fire with <> event string" unless fired
  end

  # Bind on a class tag (not a widget path) should work.
  def test_bind_on_class_tag
    assert_tk_app("bind on class tag should work", method(:app_bind_on_class_tag))
  end

  def app_bind_on_class_tag
    fired = false

    app.show
    app.tcl_eval("entry .e")
    app.tcl_eval("pack .e")

    app.bind('Entry', 'Key-z') { fired = true }

    app.tcl_eval("focus -force .e")
    app.update
    app.tcl_eval("event generate .e <Key-z>")
    app.update

    # Clean up class binding
    app.unbind('Entry', 'Key-z')

    raise "class binding did not fire" unless fired
  end

  # Unbind removes an event binding so it no longer fires.
  def test_unbind_removes_binding
    assert_tk_app("unbind should remove binding", method(:app_unbind_removes_binding))
  end

  def app_unbind_removes_binding
    count = 0

    app.show
    app.tcl_eval("entry .e")
    app.tcl_eval("pack .e")

    app.bind('.e', 'Key-q') { count += 1 }

    app.tcl_eval("focus -force .e")
    app.update
    app.tcl_eval("event generate .e <Key-q>")
    app.update
    raise "binding didn't fire initially, count=#{count}" unless count == 1

    app.unbind('.e', 'Key-q')

    app.tcl_eval("event generate .e <Key-q>")
    app.update
    raise "binding still fired after unbind, count=#{count}" unless count == 1
  end
end
