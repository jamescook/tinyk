# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestDebugConsole < Minitest::Test
  include TeekTestHelper

  def test_add_debug_console_returns_boolean
    assert_tk_app("add_debug_console returns true or false") do
      result = app.add_debug_console
      assert_includes [true, false], result
    end
  end

  def test_add_debug_console_starts_hidden
    assert_tk_app("console starts hidden after add_debug_console") do
      skip "console not available" unless app.add_debug_console
      # console hide should not raise — it's already hidden
      app.tcl_eval('console hide')
    end
  end

  def test_add_debug_console_toggle_show_hide
    assert_tk_app("console can be shown and hidden") do
      skip "console not available" unless app.add_debug_console
      app.tcl_eval('console show')
      app.tcl_eval('console hide')
    end
  end

  def test_add_debug_console_custom_keybinding
    assert_tk_app("custom keybinding is accepted") do
      result = app.add_debug_console('<F11>')
      assert_includes [true, false], result
    end
  end
end
