# frozen_string_literal: true

require "minitest/autorun"
require "teek/mgba"

class TestMGBA < Minitest::Test
  def test_version_constant
    assert_match(/\A\d+\.\d+\.\d+\z/, Teek::MGBA::VERSION)
  end

  def test_module_structure
    assert_kind_of Module, Teek::MGBA
    assert_equal Class, Teek::MGBA::Core.class
  end

  def test_key_constants_are_unique_powers_of_two
    keys = %i[KEY_A KEY_B KEY_SELECT KEY_START
              KEY_RIGHT KEY_LEFT KEY_UP KEY_DOWN KEY_R KEY_L]

    values = keys.map { |k| Teek::MGBA.const_get(k) }
    assert_equal values.size, values.uniq.size, "all key constants should be unique"
    values.each do |v|
      assert_equal 0, v & (v - 1), "#{v} should be a power of 2"
    end
  end
end
