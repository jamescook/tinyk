# frozen_string_literal: true

# Tests for Ruby threading + Tk event loop interaction
#
# Key C functions exercised:
#   - lib_eventloop_core / lib_eventloop_launcher (update, after)
#   - ip_ruby_cmd (widget callbacks - Tcl calling Ruby)
#   - tcl_protect_core (exception handling)
#   - ip_eval_real, tk_funcall (Tcl eval round-trips)

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestThreading < Minitest::Test
  include TinyKTestHelper

  # Timer fires correctly (exercises after callback)
  def test_after_fires
    assert_tk_app("after callback should fire", method(:app_after_fires))
  end

  def app_after_fires
    timer_fired = false
    app.after(50) { timer_fired = true }

    # Run event loop briefly
    start = Time.now
    while Time.now - start < 0.3
      app.tcl_eval('update')
      sleep 0.01
    end

    raise "after callback did not fire" unless timer_fired
  end

  # Ruby Thread runs alongside Tk
  def test_ruby_thread_alongside_tk
    assert_tk_app("Ruby Thread should execute alongside Tk", method(:app_ruby_thread_alongside_tk))
  end

  def app_ruby_thread_alongside_tk
    thread_result = nil
    t = Thread.new { thread_result = 42 }

    start = Time.now
    while Time.now - start < 0.3
      app.tcl_eval('update')
      sleep 0.01
    end

    t.join(1)
    raise "Ruby Thread did not execute, got #{thread_result.inspect}" unless thread_result == 42
  end

  # Widget callback (exercises ip_ruby_cmd - Tcl calling Ruby)
  def test_widget_callback
    assert_tk_app("Widget callback should fire via ip_ruby_cmd", method(:app_widget_callback))
  end

  def app_widget_callback
    callback_fired = false
    app.command(:button, ".b_cb", command: proc { callback_fired = true })
    app.command(:pack, ".b_cb")
    app.command(".b_cb", "invoke")

    start = Time.now
    while Time.now - start < 0.1
      app.tcl_eval('update')
      sleep 0.01
    end

    raise "Widget callback did not fire" unless callback_fired
  end

  # Callback spawning a thread
  def test_callback_spawns_thread
    assert_tk_app("Callback should be able to spawn threads", method(:app_callback_spawns_thread))
  end

  def app_callback_spawns_thread
    callback_thread_result = nil
    app.command(:button, ".b_thr", command: proc {
      Thread.new { callback_thread_result = "from_callback" }.join
    })
    app.command(:pack, ".b_thr")
    app.command(".b_thr", "invoke")

    start = Time.now
    while Time.now - start < 0.1
      app.tcl_eval('update')
      sleep 0.01
    end

    raise "Thread in callback failed, got #{callback_thread_result.inspect}" unless callback_thread_result == "from_callback"
  end

  # Round-trip Tcl eval
  def test_tcl_eval_roundtrip
    assert_tk_app("Tcl eval should return correct result", method(:app_tcl_eval_roundtrip))
  end

  def app_tcl_eval_roundtrip
    result = app.tcl_eval("expr {2 + 2}")
    raise "Expected '4', got '#{result}'" unless result == "4"
  end

  # Round-trip with string data
  def test_tcl_eval_string_roundtrip
    assert_tk_app("Tcl variable round-trip should preserve string", method(:app_tcl_eval_string_roundtrip))
  end

  def app_tcl_eval_string_roundtrip
    app.tcl_eval('set testvar "hello from tcl"')
    result = app.tcl_eval('set testvar')
    raise "Expected 'hello from tcl', got '#{result}'" unless result == "hello from tcl"
  end
end
