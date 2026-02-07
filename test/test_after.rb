# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestAfter < Minitest::Test
  include TeekTestHelper

  def test_after_fires
    assert_tk_app("after should fire callback", method(:app_after_fires))
  end

  def app_after_fires
    fired = false
    app.after(50) { fired = true }

    # Pump the event loop until the timer fires
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2.0
    until fired || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      app.update
      sleep 0.01
    end

    raise "timer did not fire" unless fired
  end

  def test_after_idle_fires
    assert_tk_app("after_idle should fire callback", method(:app_after_idle_fires))
  end

  def app_after_idle_fires
    fired = false
    app.after_idle { fired = true }

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2.0
    until fired || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      app.update
      sleep 0.01
    end

    raise "after_idle did not fire" unless fired
  end

  def test_after_cancel
    assert_tk_app("after_cancel should prevent callback", method(:app_after_cancel))
  end

  def app_after_cancel
    fired = false
    timer_id = app.after(50) { fired = true }
    app.after_cancel(timer_id)

    # Wait long enough that it would have fired
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.3
    until Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      app.update
      sleep 0.01
    end

    raise "callback fired despite cancel" if fired
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
      app.update
      sleep 0.01
    end

    raise "expected [first, second], got #{results.inspect}" unless results == ["first", "second"]
  end
end
