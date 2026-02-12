# frozen_string_literal: true

require_relative "test_helper"
require "teek/sdl2"

class TestGamepad < Minitest::Test
  GP = Teek::SDL2::Gamepad

  def setup
    GP.init_subsystem
  end

  def teardown
    GP.detach_virtual
    GP.shutdown_subsystem
  end

  # -- subsystem lifecycle ---------------------------------------------------

  def test_init_and_shutdown_do_not_raise
    GP.shutdown_subsystem
    GP.init_subsystem
  end

  def test_double_init_is_safe
    GP.init_subsystem
  end

  def test_double_shutdown_is_safe
    GP.shutdown_subsystem
    GP.shutdown_subsystem
  end

  # -- count -----------------------------------------------------------------

  def test_count_returns_zero_without_gamepads
    c = GP.count
    assert_kind_of Integer, c
    # May be > 0 if physical gamepads are connected, but at least non-negative
    assert c >= 0
  end

  def test_count_increases_with_virtual_gamepad
    before = GP.count
    GP.attach_virtual
    assert_equal before + 1, GP.count
  end

  # -- open guards -----------------------------------------------------------

  def test_open_negative_index_raises_argument_error
    assert_raises(ArgumentError) { GP.open(-1) }
  end

  def test_open_negative_index_message
    err = assert_raises(ArgumentError) { GP.open(-1) }
    assert_match(/non-negative/, err.message)
  end

  def test_open_out_of_range_raises_runtime_error
    assert_raises(RuntimeError) { GP.open(999) }
  end

  # -- virtual gamepad -------------------------------------------------------

  def test_attach_virtual_returns_device_index
    idx = GP.attach_virtual
    assert_kind_of Integer, idx
    assert idx >= 0
  end

  def test_virtual_device_index_nil_when_not_attached
    assert_nil GP.virtual_device_index
  end

  def test_virtual_device_index_returns_index_after_attach
    idx = GP.attach_virtual
    assert_equal idx, GP.virtual_device_index
  end

  def test_double_attach_raises
    GP.attach_virtual
    assert_raises(RuntimeError) { GP.attach_virtual }
  end

  def test_detach_virtual_clears_index
    GP.attach_virtual
    GP.detach_virtual
    assert_nil GP.virtual_device_index
  end

  def test_detach_without_attach_is_safe
    GP.detach_virtual # should not raise
  end

  # -- open / first / all with virtual gamepad --------------------------------

  def test_open_virtual_gamepad
    idx = GP.attach_virtual
    gp = GP.open(idx)
    refute_nil gp
    assert_kind_of GP, gp
    gp.close
  end

  def test_first_returns_virtual_gamepad
    GP.attach_virtual
    gp = GP.first
    refute_nil gp
    assert_kind_of GP, gp
    gp.close
  end

  def test_all_includes_virtual_gamepad
    GP.attach_virtual
    gamepads = GP.all
    assert_kind_of Array, gamepads
    refute_empty gamepads
    gamepads.each(&:close)
  end

  # -- instance methods on virtual gamepad -----------------------------------

  def test_name_returns_string
    idx = GP.attach_virtual
    gp = GP.open(idx)
    assert_kind_of String, gp.name
    assert_match(/Teek Virtual Gamepad/, gp.name)
    gp.close
  end

  def test_attached_returns_true
    idx = GP.attach_virtual
    gp = GP.open(idx)
    assert gp.attached?
    gp.close
  end

  def test_instance_id_returns_integer
    idx = GP.attach_virtual
    gp = GP.open(idx)
    assert_kind_of Integer, gp.instance_id
    gp.close
  end

  def test_button_polling_all_buttons
    idx = GP.attach_virtual
    gp = GP.open(idx)
    GP.buttons.each do |btn|
      refute gp.button?(btn), "#{btn} should not be pressed initially"
    end
    gp.close
  end

  def test_axis_polling_all_axes
    idx = GP.attach_virtual
    gp = GP.open(idx)
    GP.axes.each do |ax|
      val = gp.axis(ax)
      assert_kind_of Integer, val
    end
    gp.close
  end

  def test_button_with_invalid_symbol_raises
    idx = GP.attach_virtual
    gp = GP.open(idx)
    assert_raises(ArgumentError) { gp.button?(:bogus) }
    gp.close
  end

  def test_axis_with_invalid_symbol_raises
    idx = GP.attach_virtual
    gp = GP.open(idx)
    assert_raises(ArgumentError) { gp.axis(:bogus) }
    gp.close
  end

  def test_button_with_non_symbol_raises_type_error
    idx = GP.attach_virtual
    gp = GP.open(idx)
    assert_raises(TypeError) { gp.button?("a") }
    gp.close
  end

  def test_axis_with_non_symbol_raises_type_error
    idx = GP.attach_virtual
    gp = GP.open(idx)
    assert_raises(TypeError) { gp.axis("left_x") }
    gp.close
  end

  # -- virtual button / axis setting -----------------------------------------

  def test_set_virtual_button_and_poll
    idx = GP.attach_virtual
    gp = GP.open(idx)

    refute gp.button?(:a), "button A should start unpressed"

    gp.set_virtual_button(:a, true)
    # Need to pump events so SDL processes the virtual input
    sdl_pump
    assert gp.button?(:a), "button A should be pressed after set_virtual_button"

    gp.set_virtual_button(:a, false)
    sdl_pump
    refute gp.button?(:a), "button A should be released"

    gp.close
  end

  def test_set_virtual_axis_and_poll
    idx = GP.attach_virtual
    gp = GP.open(idx)

    gp.set_virtual_axis(:left_x, 16000)
    sdl_pump
    val = gp.axis(:left_x)
    assert_equal 16000, val

    gp.set_virtual_axis(:left_x, -32000)
    sdl_pump
    val = gp.axis(:left_x)
    assert_equal(-32000, val)

    gp.close
  end

  def test_set_virtual_trigger
    idx = GP.attach_virtual
    gp = GP.open(idx)

    # Triggers are remapped by SDL from joystick range (-32768..32767)
    # to controller range (0..32767). Setting raw max yields trigger max.
    gp.set_virtual_axis(:trigger_left, 32767)
    sdl_pump
    val = gp.axis(:trigger_left)
    assert_equal 32767, val

    # Raw minimum (-32768) maps to trigger 0
    gp.set_virtual_axis(:trigger_left, -32768)
    sdl_pump
    val = gp.axis(:trigger_left)
    assert_equal 0, val

    gp.close
  end

  def test_set_virtual_button_invalid_sym_raises
    idx = GP.attach_virtual
    gp = GP.open(idx)
    assert_raises(ArgumentError) { gp.set_virtual_button(:bogus, true) }
    gp.close
  end

  def test_set_virtual_axis_invalid_sym_raises
    idx = GP.attach_virtual
    gp = GP.open(idx)
    assert_raises(ArgumentError) { gp.set_virtual_axis(:bogus, 100) }
    gp.close
  end

  # -- event callbacks with virtual gamepad ----------------------------------

  def test_on_button_callback_fires
    idx = GP.attach_virtual
    gp = GP.open(idx)
    events = []

    GP.on_button { |id, btn, pressed| events << [id, btn, pressed] }

    gp.set_virtual_button(:a, true)
    GP.poll_events

    gp.set_virtual_button(:a, false)
    GP.poll_events

    assert events.length >= 2, "expected at least 2 button events, got #{events.length}"

    press_event = events.find { |_, btn, pressed| btn == :a && pressed == true }
    release_event = events.find { |_, btn, pressed| btn == :a && pressed == false }

    refute_nil press_event, "should have a press event for :a"
    refute_nil release_event, "should have a release event for :a"

    gp.close
  end

  def test_on_axis_callback_fires
    idx = GP.attach_virtual
    gp = GP.open(idx)
    events = []

    GP.on_axis { |id, ax, val| events << [id, ax, val] }

    gp.set_virtual_axis(:left_x, 20000)
    GP.poll_events

    axis_event = events.find { |_, ax, _| ax == :left_x }
    refute_nil axis_event, "should have an axis event for :left_x"
    assert_equal 20000, axis_event[2]

    gp.close
  end

  # -- close / destroy lifecycle ---------------------------------------------

  def test_close_and_closed
    idx = GP.attach_virtual
    gp = GP.open(idx)
    refute gp.closed?
    refute gp.destroyed?

    gp.close
    assert gp.closed?
    assert gp.destroyed?
  end

  def test_double_close_is_safe
    idx = GP.attach_virtual
    gp = GP.open(idx)
    gp.close
    gp.close # should not raise
  end

  def test_closed_gamepad_raises_on_method_call
    idx = GP.attach_virtual
    gp = GP.open(idx)
    gp.close

    assert_raises(RuntimeError) { gp.name }
    assert_raises(RuntimeError) { gp.attached? }
    assert_raises(RuntimeError) { gp.button?(:a) }
    assert_raises(RuntimeError) { gp.axis(:left_x) }
    assert_raises(RuntimeError) { gp.rumble(0, 0, 0) }
  end

  # -- first / all without gamepads ------------------------------------------

  def test_first_returns_nil_when_no_gamepads
    # Don't attach virtual — rely on no physical gamepads either
    # This test only meaningful if no physical gamepads are connected
    skip "physical gamepads connected" if GP.count > 0
    assert_nil GP.first
  end

  def test_all_returns_empty_array_when_no_gamepads
    skip "physical gamepads connected" if GP.count > 0
    result = GP.all
    assert_kind_of Array, result
    assert_empty result
  end

  # -- buttons / axes introspection ------------------------------------------

  def test_buttons_returns_15_symbols
    btns = GP.buttons
    assert_equal 15, btns.length
    btns.each { |b| assert_kind_of Symbol, b }
  end

  def test_buttons_includes_all_expected
    btns = GP.buttons
    %i[a b x y back start guide
       dpad_up dpad_down dpad_left dpad_right
       left_shoulder right_shoulder left_stick right_stick].each do |expected|
      assert_includes btns, expected
    end
  end

  def test_axes_returns_6_symbols
    axes = GP.axes
    assert_equal 6, axes.length
    axes.each { |a| assert_kind_of Symbol, a }
  end

  def test_axes_includes_all_expected
    axes = GP.axes
    %i[left_x left_y right_x right_y trigger_left trigger_right].each do |expected|
      assert_includes axes, expected
    end
  end

  # -- poll_events -----------------------------------------------------------

  def test_poll_events_returns_integer
    assert_kind_of Integer, GP.poll_events
  end

  def test_poll_events_before_init_returns_zero
    GP.shutdown_subsystem
    assert_equal 0, GP.poll_events
    GP.init_subsystem
  end

  # -- callback registration -------------------------------------------------

  def test_on_button_requires_block
    assert_raises(LocalJumpError) { GP.on_button }
  end

  def test_on_axis_requires_block
    assert_raises(LocalJumpError) { GP.on_axis }
  end

  def test_on_added_requires_block
    assert_raises(LocalJumpError) { GP.on_added }
  end

  def test_on_removed_requires_block
    assert_raises(LocalJumpError) { GP.on_removed }
  end

  # -- axis range constants ---------------------------------------------------

  def test_axis_range_constants
    assert_equal(-32768, GP::AXIS_MIN)
    assert_equal 32767, GP::AXIS_MAX
  end

  def test_trigger_range_constants
    assert_equal 0, GP::TRIGGER_MIN
    assert_equal 32767, GP::TRIGGER_MAX
  end

  # -- dead zone helper (Ruby) -----------------------------------------------

  def test_dead_zone_constant
    assert_equal 8000, GP::DEAD_ZONE
  end

  def test_apply_dead_zone_within_threshold
    assert_equal 0, GP.apply_dead_zone(5000)
    assert_equal 0, GP.apply_dead_zone(-5000)
    assert_equal 0, GP.apply_dead_zone(0)
    assert_equal 0, GP.apply_dead_zone(7999)
  end

  def test_apply_dead_zone_outside_threshold
    assert_equal 8001, GP.apply_dead_zone(8001)
    assert_equal(-8001, GP.apply_dead_zone(-8001))
    assert_equal 32767, GP.apply_dead_zone(32767)
  end

  def test_apply_dead_zone_custom_threshold
    assert_equal 0, GP.apply_dead_zone(500, 1000)
    assert_equal 1001, GP.apply_dead_zone(1001, 1000)
  end

  # -- rumble on virtual (should succeed or fail gracefully) -----------------

  def test_rumble_returns_boolean
    idx = GP.attach_virtual
    gp = GP.open(idx)
    result = gp.rumble(0, 0, 100)
    assert_includes [true, false], result
    gp.close
  end

  private

  def sdl_pump
    # Pump SDL events so virtual input changes are processed
    GP.poll_events
  end
end
