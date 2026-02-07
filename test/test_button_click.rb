# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestButtonClick < Minitest::Test
  include TinyKTestHelper

  def test_button_click_prints_hello_world
    assert_tk_app("button click should print Hello world", method(:app_button_click))
  end

  def app_button_click
    app.command(:button, ".b", text: "click me", command: proc { puts "Hello world" })
    app.command(:pack, ".b")
    app.command(".b", "invoke")
  end
end
