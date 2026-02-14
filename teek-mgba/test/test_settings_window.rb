# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test/tk_test_helper"

class TestMGBASettingsWindow < Minitest::Test
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
      app.show
      app.update
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})

      sw.show
      app.command(:focus, '-force', Teek::MGBA::SettingsWindow::TOP)
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

      # Switch to gamepad mode (dead zone is disabled in keyboard mode)
      sw.update_gamepad_list(['Keyboard Only', 'Test Gamepad'])
      app.set_variable(Teek::MGBA::SettingsWindow::VAR_GAMEPAD, 'Test Gamepad')
      app.command(:event, 'generate', Teek::MGBA::SettingsWindow::GAMEPAD_COMBO, '<<ComboboxSelected>>')
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
      assert_equal "A: Press\u2026", text
    end
  end

  def test_capture_mapping_updates_button_label
    assert_tk_app("capture_mapping updates button label") do
      require "teek/mgba/settings_window"
      received_gba = nil
      received_key = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_keyboard_map_change: proc { |g, b| received_gba = g; received_key = b }
      })
      sw.show
      app.update

      # Default mode is keyboard — enter listen mode for A
      app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'invoke')
      app.update

      # Simulate keyboard key capture
      sw.capture_mapping('q')
      app.update

      assert_nil sw.listening_for
      assert_equal :a, received_gba
      assert_equal 'q', received_key
      text = app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'cget', '-text')
      assert_equal 'A: q', text
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

  # -- Undo button ----------------------------------------------------------

  def test_undo_starts_disabled
    assert_tk_app("undo button starts disabled") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      state = app.command(Teek::MGBA::SettingsWindow::GP_UNDO_BTN, 'cget', '-state')
      assert_equal 'disabled', state
    end
  end

  def test_undo_enabled_after_remap
    assert_tk_app("undo enabled after capturing a mapping") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'invoke')
      app.update
      sw.capture_mapping(:x)
      app.update

      state = app.command(Teek::MGBA::SettingsWindow::GP_UNDO_BTN, 'cget', '-state')
      assert_equal 'normal', state
    end
  end

  def test_undo_fires_callback_and_disables
    assert_tk_app("undo fires on_undo_gamepad and disables itself") do
      require "teek/mgba/settings_window"
      undo_called = false
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_undo_gamepad: proc { undo_called = true }
      })
      sw.show
      app.update

      # Remap to enable undo
      app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'invoke')
      app.update
      sw.capture_mapping(:x)
      app.update

      # Click undo
      app.command(Teek::MGBA::SettingsWindow::GP_UNDO_BTN, 'invoke')
      app.update

      assert undo_called
      state = app.command(Teek::MGBA::SettingsWindow::GP_UNDO_BTN, 'cget', '-state')
      assert_equal 'disabled', state
    end
  end

  def test_reset_disables_undo
    assert_tk_app("reset to defaults disables undo button") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      # Remap to enable undo
      app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'invoke')
      app.update
      sw.capture_mapping(:x)
      app.update

      state = app.command(Teek::MGBA::SettingsWindow::GP_UNDO_BTN, 'cget', '-state')
      assert_equal 'normal', state

      # refresh_gamepad simulates what reset/undo would do from the player side
      sw.refresh_gamepad(Teek::MGBA::SettingsWindow::DEFAULT_GP_LABELS, 25)
      app.update

      # Verify labels restored
      text = app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'cget', '-text')
      assert_equal 'A: a', text
    end
  end

  # -- Aspect ratio checkbox ------------------------------------------------

  def test_aspect_ratio_defaults_to_on
    assert_tk_app("aspect ratio checkbox defaults to on") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      assert_equal '1', app.get_variable(Teek::MGBA::SettingsWindow::VAR_ASPECT_RATIO)
    end
  end

  def test_unchecking_aspect_ratio_fires_callback
    assert_tk_app("unchecking aspect ratio fires on_aspect_ratio_change") do
      require "teek/mgba/settings_window"
      received = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_aspect_ratio_change: proc { |keep| received = keep }
      })
      sw.show
      app.update

      # Simulate user unchecking the checkbox
      app.command(Teek::MGBA::SettingsWindow::ASPECT_CHECK, 'invoke')
      app.update

      assert_equal false, received
    end
  end

  def test_checking_aspect_ratio_fires_callback
    assert_tk_app("re-checking aspect ratio fires callback with true") do
      require "teek/mgba/settings_window"
      received = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_aspect_ratio_change: proc { |keep| received = keep }
      })
      sw.show
      app.update

      # Uncheck then re-check
      app.command(Teek::MGBA::SettingsWindow::ASPECT_CHECK, 'invoke')
      app.update
      app.command(Teek::MGBA::SettingsWindow::ASPECT_CHECK, 'invoke')
      app.update

      assert_equal true, received
    end
  end

  # -- Show FPS checkbox ----------------------------------------------------

  def test_show_fps_defaults_to_on
    assert_tk_app("show fps checkbox defaults to on") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      assert_equal '1', app.get_variable(Teek::MGBA::SettingsWindow::VAR_SHOW_FPS)
    end
  end

  def test_unchecking_show_fps_fires_callback
    assert_tk_app("unchecking show fps fires on_show_fps_change") do
      require "teek/mgba/settings_window"
      received = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_show_fps_change: proc { |show| received = show }
      })
      sw.show
      app.update

      app.command(Teek::MGBA::SettingsWindow::SHOW_FPS_CHECK, 'invoke')
      app.update

      assert_equal false, received
    end
  end

  # -- Keyboard mode --------------------------------------------------------

  def test_starts_in_keyboard_mode
    assert_tk_app("starts in keyboard mode") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      assert sw.keyboard_mode?
    end
  end

  def test_keyboard_mode_labels_show_keysyms
    assert_tk_app("keyboard mode shows keysym labels") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      text = app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'cget', '-text')
      assert_equal 'A: z', text
      text = app.command(Teek::MGBA::SettingsWindow::GP_BTN_START, 'cget', '-text')
      assert_equal 'START: Return', text
    end
  end

  def test_switching_to_gamepad_mode_changes_labels
    assert_tk_app("switching to gamepad shows gamepad labels") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      sw.update_gamepad_list(['Keyboard Only', 'Test Gamepad'])
      app.set_variable(Teek::MGBA::SettingsWindow::VAR_GAMEPAD, 'Test Gamepad')
      app.command(:event, 'generate', Teek::MGBA::SettingsWindow::GAMEPAD_COMBO, '<<ComboboxSelected>>')
      app.update

      refute sw.keyboard_mode?
      text = app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'cget', '-text')
      assert_equal 'A: a', text
      text = app.command(Teek::MGBA::SettingsWindow::GP_BTN_START, 'cget', '-text')
      assert_equal 'START: start', text
    end
  end

  def test_deadzone_disabled_in_keyboard_mode
    assert_tk_app("dead zone slider disabled in keyboard mode") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      state = app.command(Teek::MGBA::SettingsWindow::DEADZONE_SCALE, 'cget', '-state')
      assert_equal 'disabled', state
    end
  end

  def test_deadzone_enabled_in_gamepad_mode
    assert_tk_app("dead zone slider enabled in gamepad mode") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      sw.update_gamepad_list(['Keyboard Only', 'Test Gamepad'])
      app.set_variable(Teek::MGBA::SettingsWindow::VAR_GAMEPAD, 'Test Gamepad')
      app.command(:event, 'generate', Teek::MGBA::SettingsWindow::GAMEPAD_COMBO, '<<ComboboxSelected>>')
      app.update

      state = app.command(Teek::MGBA::SettingsWindow::DEADZONE_SCALE, 'cget', '-state')
      assert_equal 'normal', state
    end
  end

  def test_keyboard_capture_fires_keyboard_callback
    assert_tk_app("keyboard capture fires on_keyboard_map_change") do
      require "teek/mgba/settings_window"
      received_gba = nil
      received_key = nil
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {
        on_keyboard_map_change: proc { |g, k| received_gba = g; received_key = k }
      })
      sw.show
      app.update

      app.command(Teek::MGBA::SettingsWindow::GP_BTN_B, 'invoke')
      app.update
      sw.capture_mapping('space')
      app.update

      assert_equal :b, received_gba
      assert_equal 'space', received_key
    end
  end

  def test_switching_mode_cancels_listen
    assert_tk_app("switching input mode cancels active listen") do
      require "teek/mgba/settings_window"
      sw = Teek::MGBA::SettingsWindow.new(app, callbacks: {})
      sw.show
      app.update

      # Start listening in keyboard mode
      app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'invoke')
      app.update
      assert_equal :a, sw.listening_for

      # Switch to gamepad mode — should cancel listen
      sw.update_gamepad_list(['Keyboard Only', 'Test Gamepad'])
      app.set_variable(Teek::MGBA::SettingsWindow::VAR_GAMEPAD, 'Test Gamepad')
      app.command(:event, 'generate', Teek::MGBA::SettingsWindow::GAMEPAD_COMBO, '<<ComboboxSelected>>')
      app.update

      assert_nil sw.listening_for
      text = app.command(Teek::MGBA::SettingsWindow::GP_BTN_A, 'cget', '-text')
      assert_equal 'A: a', text  # reverted to gamepad default (not "Press...")
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

      # Switch to gamepad mode (default is keyboard)
      sw.update_gamepad_list(['Keyboard Only', gp.name])
      app.set_variable(Teek::MGBA::SettingsWindow::VAR_GAMEPAD, gp.name)
      app.command(:event, 'generate', Teek::MGBA::SettingsWindow::GAMEPAD_COMBO, '<<ComboboxSelected>>')
      app.update
      refute sw.keyboard_mode?

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
