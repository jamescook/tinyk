# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test/tk_test_helper"

class TestSettingsWindow < Minitest::Test
  include TeekTestHelper

  # -- Video scale --------------------------------------------------------

  def test_scale_combobox_defaults_to_3x
    assert_tk_app("scale combobox defaults to 3x") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      assert_equal '3x', app.get_variable(Teek::MGBA::SettingsWindow::VAR_SCALE)
    end
  end

  def test_selecting_2x_scale_fires_callback
    assert_tk_app("selecting 2x scale fires on_scale_change") do
      require "teek/mgba/settings_window"
      received = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_scale_change: proc { |s| received = s }
      })
      sw.show
      app.update

      # Simulate user selecting "2x" from the combobox
      app.set_variable(Teek::MGBA::SettingsWindow::VAR_SCALE, '2x')
      app.command(:event, 'generate', Teek::MGBA::SettingsWindow::SCALE_COMBO, '<<ComboboxSelected>>')
      app.update

      assert_equal 2, received
    end
  end

  def test_selecting_4x_scale_fires_callback
    assert_tk_app("selecting 4x scale fires on_scale_change") do
      require "teek/mgba/settings_window"
      received = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_scale_change: proc { |s| received = s }
      })
      sw.show
      app.update

      app.set_variable(Teek::MGBA::SettingsWindow::VAR_SCALE, '4x')
      app.command(:event, 'generate', Teek::MGBA::SettingsWindow::SCALE_COMBO, '<<ComboboxSelected>>')
      app.update

      assert_equal 4, received
    end
  end

  # -- Volume slider ------------------------------------------------------

  def test_volume_defaults_to_100
    assert_tk_app("volume defaults to 100") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      assert_equal '100', app.get_variable(Teek::MGBA::SettingsWindow::VAR_VOLUME)
    end
  end

  def test_dragging_volume_to_50_fires_callback
    assert_tk_app("dragging volume to 50 fires on_volume_change") do
      require "teek/mgba/settings_window"
      received = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_volume_change: proc { |v| received = v }
      })
      sw.show
      app.update

      # Simulate user dragging volume slider to 50
      app.command(Teek::MGBA::SettingsWindow::VOLUME_SCALE, 'set', 50)
      app.update

      assert_in_delta 0.5, received, 0.01
    end
  end

  def test_volume_at_zero
    assert_tk_app("volume at zero") do
      require "teek/mgba/settings_window"
      received = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_volume_change: proc { |v| received = v }
      })
      sw.show
      app.update

      app.command(Teek::MGBA::SettingsWindow::VOLUME_SCALE, 'set', 0)
      app.update

      assert_in_delta 0.0, received, 0.01
    end
  end

  # -- Mute checkbox ------------------------------------------------------

  def test_mute_defaults_to_off
    assert_tk_app("mute defaults to off") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      assert_equal '0', app.get_variable(Teek::MGBA::SettingsWindow::VAR_MUTE)
    end
  end

  def test_clicking_mute_fires_callback
    assert_tk_app("clicking mute fires on_mute_change") do
      require "teek/mgba/settings_window"
      received = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_mute_change: proc { |m| received = m }
      })
      sw.show
      app.update

      # Simulate user clicking the mute checkbox
      app.command(Teek::MGBA::SettingsWindow::MUTE_CHECK, 'invoke')
      app.update

      assert_equal true, received
    end
  end

  def test_clicking_mute_twice_unmutes
    assert_tk_app("clicking mute twice unmutes") do
      require "teek/mgba/settings_window"
      received = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_mute_change: proc { |m| received = m }
      })
      sw.show
      app.update

      app.command(Teek::MGBA::SettingsWindow::MUTE_CHECK, 'invoke')
      app.update
      assert_equal true, received

      app.command(Teek::MGBA::SettingsWindow::MUTE_CHECK, 'invoke')
      app.update
      assert_equal false, received
    end
  end

  # -- Window lifecycle ---------------------------------------------------

  def test_settings_starts_hidden
    assert_tk_app("settings starts hidden") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      app.update

      assert_equal 'withdrawn', app.command(:wm, 'state', Teek::MGBA::SettingsWindow::TOP)
    end
  end

  def test_show_and_hide
    assert_tk_app("show makes window visible, hide withdraws it") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})

      sw.show
      app.update
      assert_equal 'normal', app.command(:wm, 'state', Teek::MGBA::SettingsWindow::TOP)

      sw.hide
      app.update
      assert_equal 'withdrawn', app.command(:wm, 'state', Teek::MGBA::SettingsWindow::TOP)
    end
  end

  # -- Gamepad tab ---------------------------------------------------------

  def test_gamepad_tab_exists
    assert_tk_app("gamepad tab exists in notebook") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      tabs = app.command(Teek::MGBA::SettingsWindow::NB, 'tabs')
      assert_includes tabs, Teek::MGBA::SettingsWindow::GAMEPAD_TAB
    end
  end

  def test_deadzone_defaults_to_25
    assert_tk_app("dead zone defaults to 25") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      assert_equal '25', app.get_variable(Teek::MGBA::SettingsWindow::VAR_DEADZONE)
    end
  end

  def test_deadzone_change_fires_callback
    assert_tk_app("dead zone change fires on_deadzone_change") do
      require "teek/mgba/settings_window"
      received = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_deadzone_change: proc { |t| received = t }
      })
      sw.show
      app.update

      app.command(Teek::MGBA::SettingsWindow::DEADZONE_SCALE, 'set', 15)
      app.update

      # 15% of 32767 ≈ 4915
      assert_equal 4915, received
    end
  end

  def test_clicking_gba_button_enters_listen_mode
    assert_tk_app("clicking GBA button enters listen mode") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      # Click the A button
      app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'invoke')
      app.update

      assert_equal :a, sw.listening_for
      text = app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'cget', '-text')
      assert_equal 'A: Press...', text
    end
  end

  def test_capture_mapping_updates_button_label
    assert_tk_app("capture_mapping updates button label") do
      require "teek/mgba/settings_window"
      received_gba = nil
      received_gp = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_gamepad_map_change: proc { |g, b| received_gba = g; received_gp = b }
      })
      sw.show
      app.update

      # Enter listen mode for A
      app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'invoke')
      app.update

      # Simulate gamepad button capture
      sw.capture_mapping(:x)
      app.update

      assert_nil sw.listening_for
      assert_equal :a, received_gba
      assert_equal :x, received_gp
      text = app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'cget', '-text')
      assert_equal 'A: x', text
    end
  end

  def test_gamepad_selector_defaults_to_keyboard_only
    assert_tk_app("gamepad selector defaults to Keyboard Only") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      assert_equal 'Keyboard Only', app.get_variable(Teek::MGBA::SettingsWindow::VAR_GAMEPAD)
    end
  end

  # -- Virtual gamepad integration ------------------------------------------

  def test_virtual_gamepad_listen_and_capture
    assert_tk_app("virtual gamepad button press captured in listen mode") do
      require "teek/mgba/settings_window"
      require "teek/sdl2"
      gp_cls = Teek::SDL2::Gamepad

      gp_cls.init_subsystem
      idx = gp_cls.attach_virtual
      gp = gp_cls.open(idx)

      received_gba = nil
      received_gp = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_gamepad_map_change: proc { |g, b| received_gba = g; received_gp = b }
      })
      sw.show
      app.update

      # Enter listen mode for B button
      app.command(Teek::MGBA::SettingsWindow::GP_BTN_B, 'invoke')
      app.update
      assert_equal :b, sw.listening_for

      # Press X on virtual gamepad
      gp.set_virtual_button(:x, true)
      gp_cls.poll_events

      # Simulate what the player's probe timer does
      gp_cls.buttons.each do |btn|
        if gp.button?(btn)
          sw.capture_mapping(btn)
          break
        end
      end
      app.update

      assert_nil sw.listening_for
      assert_equal :b, received_gba
      assert_equal :x, received_gp

      text = app.command(Teek::MGBA::SettingsWindow::GP_BTN_B, 'cget', '-text')
      assert_equal 'B: x', text

      gp.set_virtual_button(:x, false)
      gp.close
      gp_cls.detach_virtual
      gp_cls.shutdown_subsystem
    end
  end

end
