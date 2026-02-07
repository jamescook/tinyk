# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestAfter < Minitest::Test
  include TinyKTestHelper

  def test_after_fires
    assert_tk_app("after should fire callback", method(:app_after_fires))
  end

  def app_after_fires
    fired = false
    app.after(50) { fired = true }

    # Pump the event loop until the timer fires
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2.0
    until fired || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      app.tcl_eval('update')
      sleep 0.01
    end

    raise "timer did not fire" unless fired
  end

  def test_nested_after
    assert_tk_app("nested timers should both fire", method(:app_nested_after))
  end

  def app_nested_after
    results = []

    app.after(50) do
      results << "first"
      app.after(50) do
        results << "second"
      end
    end

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2.0
    until results.size >= 2 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      app.tcl_eval('update')
      sleep 0.01
    end

    raise "expected [first, second], got #{results.inspect}" unless results == ["first", "second"]
  end
end
