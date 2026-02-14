# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../test/tk_test_helper"

class TestMGBAPlayer < Minitest::Test
  include TeekTestHelper

  TEST_ROM = File.expand_path("fixtures/test.gba", __dir__)

  # Launches the full Player with a ROM loaded, runs a few frames,
  # then triggers quit. If the process doesn't exit within the timeout
  # the test fails — catching exit-hang regressions.
  def test_exit_with_rom_loaded_does_not_hang
    code = <<~RUBY
      require "teek/mgba"
      require "support/player_helpers"

      player = Teek::MGBA::Player.new("#{TEST_ROM}")
      app = player.instance_variable_get(:@app)

      poll_until_ready(app) { player.instance_variable_set(:@running, false) }

      player.run
    RUBY

    success, stdout, stderr, _status = tk_subprocess(code, timeout: 15)

    output = []
    output << "STDOUT:\n#{stdout}" unless stdout.empty?
    output << "STDERR:\n#{stderr}" unless stderr.empty?

    assert success, "Player should exit cleanly with ROM loaded (no hang)\n#{output.join("\n")}"
  end

  # Simulate a user pressing F11 twice (fullscreen on → off) then q to quit.
  # Exercises the wm attributes fullscreen path end-to-end. If the toggle
  # causes a hang or crash the subprocess will time out.
  def test_fullscreen_toggle_does_not_hang
    code = <<~RUBY
      require "teek/mgba"
      require "support/player_helpers"

      player = Teek::MGBA::Player.new("#{TEST_ROM}")
      app = player.instance_variable_get(:@app)

      poll_until_ready(app) do
        vp = player.instance_variable_get(:@viewport)
        frame = vp.frame.path

        # User presses F11 → fullscreen on
        app.command(:event, 'generate', frame, '<KeyPress>', keysym: 'F11')
        app.update

        app.after(300) do
          # User presses F11 → fullscreen off
          app.command(:event, 'generate', frame, '<KeyPress>', keysym: 'F11')
          app.update

          app.after(200) do
            # User presses q → quit
            app.command(:event, 'generate', frame, '<KeyPress>', keysym: 'q')
          end
        end
      end

      player.run
    RUBY

    success, stdout, stderr, _status = tk_subprocess(code, timeout: 15)

    output = []
    output << "STDOUT:\n#{stdout}" unless stdout.empty?
    output << "STDERR:\n#{stderr}" unless stderr.empty?

    assert success, "Player should exit cleanly after fullscreen toggle\n#{output.join("\n")}"
  end

  # Simulate a user enabling turbo (Tab), running a few frames at 2x speed,
  # then pressing q to quit. Without the poll_input fix (update_state vs
  # poll_events), SDL_PollEvent steals Tk keyboard events on macOS and
  # the quit key never reaches the KeyPress handler — causing a hang.
  def test_exit_during_turbo_does_not_hang
    code = <<~RUBY
      require "teek/mgba"
      require "support/player_helpers"

      player = Teek::MGBA::Player.new("#{TEST_ROM}")
      app = player.instance_variable_get(:@app)

      poll_until_ready(app) do
        vp = player.instance_variable_get(:@viewport)
        frame = vp.frame.path

        # User presses Tab → enable turbo (2x default)
        app.command(:event, 'generate', frame, '<KeyPress>', keysym: 'Tab')
        app.update

        app.after(500) do
          # User presses q → quit (while still in turbo)
          app.command(:event, 'generate', frame, '<KeyPress>', keysym: 'q')
        end
      end

      player.run
    RUBY

    success, stdout, stderr, _status = tk_subprocess(code, timeout: 15)

    output = []
    output << "STDOUT:\n#{stdout}" unless stdout.empty?
    output << "STDERR:\n#{stderr}" unless stderr.empty?

    assert success, "Player should exit cleanly during turbo mode (no hang)\n#{output.join("\n")}"
  end

  # E2E: quick save (F5), wait for debounce, quick load (F8).
  # Verifies state file + screenshot are created, backup rotation works,
  # and the core remains functional after load.
  def test_quick_save_and_load_creates_files_and_restores_state
    skip "Run: ruby teek-mgba/scripts/generate_test_rom.rb" unless File.exist?(TEST_ROM)

    code = <<~RUBY
      require "teek/mgba"
      require "tmpdir"
      require "fileutils"
      require "support/player_helpers"

      # Use a temp dir for all config/states so we don't pollute the real one
      states_dir = Dir.mktmpdir("teek-states-test")

      player = Teek::MGBA::Player.new("#{TEST_ROM}")
      app = player.instance_variable_get(:@app)
      config = player.instance_variable_get(:@config)

      # Override states dir and reduce debounce for test speed
      config.states_dir = states_dir
      config.save_state_debounce = 0.1

      poll_until_ready(app) do
        core = player.instance_variable_get(:@core)
        state_dir = player.send(:state_dir_for_rom, core)
        vp = player.instance_variable_get(:@viewport)
        frame_path = vp.frame.path

        # Quick save (F5)
        app.command(:event, 'generate', frame_path, '<KeyPress>', keysym: 'F5')
        app.update

        app.after(300) do
          # Verify state file and screenshot exist
          ss_path = File.join(state_dir, "state1.ss")
          png_path = File.join(state_dir, "state1.png")

          unless File.exist?(ss_path)
            $stderr.puts "FAIL: state file not created at \#{ss_path}"
            $stderr.puts "Dir contents: \#{Dir.glob(state_dir + '/**/*').inspect}"
            exit 1
          end

          unless File.exist?(png_path)
            $stderr.puts "FAIL: screenshot not created at \#{png_path}"
            exit 1
          end

          ss_size = File.size(ss_path)
          png_size = File.size(png_path)

          # Save again to test backup rotation (after debounce)
          app.after(200) do
            app.command(:event, 'generate', frame_path, '<KeyPress>', keysym: 'F5')
            app.update

            app.after(300) do
              bak_path = ss_path + ".bak"
              png_bak = png_path + ".bak"

              unless File.exist?(bak_path)
                $stderr.puts "FAIL: backup not created at \#{bak_path}"
                exit 1
              end

              unless File.exist?(png_bak)
                $stderr.puts "FAIL: PNG backup not created at \#{png_bak}"
                exit 1
              end

              # Quick load (F8)
              app.command(:event, 'generate', frame_path, '<KeyPress>', keysym: 'F8')
              app.update

              app.after(200) do
                # Verify core is still functional after load
                begin
                  core.run_frame
                  buf = core.video_buffer
                  unless buf.bytesize == 240 * 160 * 4
                    $stderr.puts "FAIL: video buffer invalid after state load"
                    exit 1
                  end
                rescue => e
                  $stderr.puts "FAIL: core error after load: \#{e.message}"
                  exit 1
                end

                $stdout.puts "PASS"
                $stdout.puts "state_size=\#{ss_size}"
                $stdout.puts "png_size=\#{png_size}"

                # Clean up and quit
                FileUtils.rm_rf(states_dir)
                player.instance_variable_set(:@running, false)
              end
            end
          end
        end
      end

      player.run
    RUBY

    success, stdout, stderr, _status = tk_subprocess(code, timeout: 20)

    output = []
    output << "STDOUT:\n#{stdout}" unless stdout.empty?
    output << "STDERR:\n#{stderr}" unless stderr.empty?

    assert success, "Quick save/load E2E test failed\n#{output.join("\n")}"
    assert_includes stdout, "PASS", "Expected PASS in output\n#{output.join("\n")}"

    # Verify state file was non-trivial
    if stdout =~ /state_size=(\d+)/
      assert $1.to_i > 1000, "State file should be >1KB (got #{$1} bytes)"
    end

    # Verify PNG was created
    if stdout =~ /png_size=(\d+)/
      assert $1.to_i > 100, "PNG screenshot should be >100 bytes (got #{$1} bytes)"
    end
  end

  # E2E: verify debounce blocks rapid-fire saves.
  def test_quick_save_debounce_blocks_rapid_fire
    skip "Run: ruby teek-mgba/scripts/generate_test_rom.rb" unless File.exist?(TEST_ROM)

    code = <<~RUBY
      require "teek/mgba"
      require "tmpdir"
      require "fileutils"
      require "support/player_helpers"

      states_dir = Dir.mktmpdir("teek-debounce-test")

      player = Teek::MGBA::Player.new("#{TEST_ROM}")
      app = player.instance_variable_get(:@app)
      config = player.instance_variable_get(:@config)

      config.states_dir = states_dir
      config.save_state_debounce = 5.0  # long debounce

      poll_until_ready(app) do
        vp = player.instance_variable_get(:@viewport)
        frame_path = vp.frame.path

        # First save should succeed
        app.command(:event, 'generate', frame_path, '<KeyPress>', keysym: 'F5')
        app.update

        app.after(200) do
          core = player.instance_variable_get(:@core)
          state_dir = player.send(:state_dir_for_rom, core)
          ss_path = File.join(state_dir, "state1.ss")

          first_exists = File.exist?(ss_path)
          first_mtime = first_exists ? File.mtime(ss_path) : nil

          # Immediate second save should be debounced (within 5s window)
          app.command(:event, 'generate', frame_path, '<KeyPress>', keysym: 'F5')
          app.update

          app.after(200) do
            second_mtime = File.exist?(ss_path) ? File.mtime(ss_path) : nil

            if !first_exists
              $stderr.puts "FAIL: first save didn't create file"
              exit 1
            end

            if first_mtime != second_mtime
              $stderr.puts "FAIL: debounce didn't block second save (mtime changed)"
              exit 1
            end

            $stdout.puts "PASS"
            FileUtils.rm_rf(states_dir)
            player.instance_variable_set(:@running, false)
          end
        end
      end

      player.run
    RUBY

    success, stdout, stderr, _status = tk_subprocess(code, timeout: 15)

    output = []
    output << "STDOUT:\n#{stdout}" unless stdout.empty?
    output << "STDERR:\n#{stderr}" unless stderr.empty?

    assert success, "Debounce test failed\n#{output.join("\n")}"
    assert_includes stdout, "PASS", "Expected PASS in output\n#{output.join("\n")}"
  end

  # E2E: open Settings via menu, navigate to Save States tab,
  # change quick save slot from 1 → 10, click Save, verify persisted.
  def test_settings_change_quick_slot_and_save
    skip "Run: ruby teek-mgba/scripts/generate_test_rom.rb" unless File.exist?(TEST_ROM)

    code = <<~RUBY
      require "teek/mgba"
      require "tmpdir"
      require "json"
      require "fileutils"
      require "support/player_helpers"

      config_dir = Dir.mktmpdir("teek-settings-test")
      config_path = File.join(config_dir, "settings.json")

      player = Teek::MGBA::Player.new("#{TEST_ROM}")
      app = player.instance_variable_get(:@app)
      config = player.instance_variable_get(:@config)

      # Redirect config to a temp file so we can verify persistence
      config.instance_variable_set(:@path, config_path)

      poll_until_ready(app) do
        nb       = Teek::MGBA::SettingsWindow::NB
        ss_tab   = Teek::MGBA::SettingsWindow::SS_TAB
        slot_combo = Teek::MGBA::SettingsWindow::SS_SLOT_COMBO
        save_btn = Teek::MGBA::SettingsWindow::SAVE_BTN
        var_slot = Teek::MGBA::SettingsWindow::VAR_QUICK_SLOT

        # Open Settings via File menu (index 3: Open ROM, Recent, sep, Settings...)
        app.command('.menubar.file', :invoke, 3)
        app.update

        # Navigate to the Save States tab
        app.command(nb, 'select', ss_tab)
        app.update

        # Verify default slot is 1
        current = app.get_variable(var_slot)
        unless current == '1'
          $stderr.puts "FAIL: expected default slot '1', got '\#{current}'"
          exit 1
        end

        # Change slot to 10 (simulate user selecting from combobox)
        app.set_variable(var_slot, '10')
        app.command(:event, 'generate', slot_combo, '<<ComboboxSelected>>')
        app.update

        # Click the Save button
        app.command(save_btn, 'invoke')
        app.update

        app.after(200) do
          # Verify config file was written
          unless File.exist?(config_path)
            $stderr.puts "FAIL: config file not created at \#{config_path}"
            exit 1
          end

          data = JSON.parse(File.read(config_path))
          saved_slot = data.dig('global', 'quick_save_slot')
          unless saved_slot == 10
            $stderr.puts "FAIL: expected quick_save_slot=10, got \#{saved_slot.inspect}"
            exit 1
          end

          $stdout.puts "PASS"
          $stdout.puts "saved_slot=\#{saved_slot}"
          FileUtils.rm_rf(config_dir)
          player.instance_variable_set(:@running, false)
        end
      end

      player.run
    RUBY

    success, stdout, stderr, _status = tk_subprocess(code, timeout: 15)

    output = []
    output << "STDOUT:\n#{stdout}" unless stdout.empty?
    output << "STDERR:\n#{stderr}" unless stderr.empty?

    assert success, "Settings slot change E2E test failed\n#{output.join("\n")}"
    assert_includes stdout, "PASS", "Expected PASS in output\n#{output.join("\n")}"
    assert_match(/saved_slot=10/, stdout)
  end
end
