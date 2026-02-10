# frozen_string_literal: true

require "minitest/autorun"
require "teek/sdl2"

class TestSDL2 < Minitest::Test
  def test_version_constant
    assert_match(/\A\d+\.\d+\.\d+\z/, Teek::SDL2::VERSION)
  end

  def test_sdl_version
    version = Teek::SDL2.sdl_version
    assert_match(/\A\d+\.\d+\.\d+\z/, version)
  end

  def test_sdl_compiled_version
    version = Teek::SDL2.sdl_compiled_version
    assert_match(/\A\d+\.\d+\.\d+\z/, version)
  end

  def test_module_structure
    assert_kind_of Module, Teek::SDL2
  end
end
