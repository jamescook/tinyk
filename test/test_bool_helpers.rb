# frozen_string_literal: true

# Tests for Teek.tcl_to_bool and Teek.bool_to_tcl.
# Pure Tcl value conversion — no Tk/interpreter dependency.

require 'minitest/autorun'
require 'tcltklib'
require 'teek'

class TestBoolHelpers < Minitest::Test

  # -- Teek.tcl_to_bool --------------------------------------------------

  def test_tcl_to_bool_true_variants
    %w[1 true TRUE True yes YES Yes on ON On].each do |s|
      assert_equal true, Teek.tcl_to_bool(s), "expected true for #{s.inspect}"
    end
  end

  def test_tcl_to_bool_false_variants
    %w[0 false FALSE False no NO No off OFF Off].each do |s|
      assert_equal false, Teek.tcl_to_bool(s), "expected false for #{s.inspect}"
    end
  end

  def test_tcl_to_bool_numeric_nonzero
    %w[2 -1 42 3.14].each do |s|
      assert_equal true, Teek.tcl_to_bool(s), "expected true for numeric #{s.inspect}"
    end
  end

  def test_tcl_to_bool_numeric_zero
    assert_equal false, Teek.tcl_to_bool("0")
    assert_equal false, Teek.tcl_to_bool("0.0")
  end

  def test_tcl_to_bool_invalid
    assert_raises(Teek::TclError) { Teek.tcl_to_bool("maybe") }
    assert_raises(Teek::TclError) { Teek.tcl_to_bool("") }
    assert_raises(Teek::TclError) { Teek.tcl_to_bool("yep") }
  end

  def test_tcl_to_bool_non_string
    assert_raises(TypeError) { Teek.tcl_to_bool(nil) }
    assert_raises(TypeError) { Teek.tcl_to_bool(1) }
  end

  # -- Teek.bool_to_tcl --------------------------------------------------

  def test_bool_to_tcl_truthy
    assert_equal "1", Teek.bool_to_tcl(true)
    assert_equal "1", Teek.bool_to_tcl(1)
    assert_equal "1", Teek.bool_to_tcl("anything")
    assert_equal "1", Teek.bool_to_tcl(:sym)
  end

  def test_bool_to_tcl_falsy
    assert_equal "0", Teek.bool_to_tcl(false)
    assert_equal "0", Teek.bool_to_tcl(nil)
  end

  # -- Round-trip ---------------------------------------------------------

  def test_round_trip
    assert_equal true,  Teek.tcl_to_bool(Teek.bool_to_tcl(true))
    assert_equal false, Teek.tcl_to_bool(Teek.bool_to_tcl(false))
    assert_equal false, Teek.tcl_to_bool(Teek.bool_to_tcl(nil))
  end
end
