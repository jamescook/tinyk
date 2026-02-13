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

      player = Teek::MGBA::Player.new("#{TEST_ROM}")
      app = player.instance_variable_get(:@app)

      # After SDL2 init + a few emulated frames, trigger quit
      app.after(500) { player.instance_variable_set(:@running, false) }

      player.run
    RUBY

    success, stdout, stderr, _status = tk_subprocess(code, timeout: 15)

    output = []
    output << "STDOUT:\n#{stdout}" unless stdout.empty?
    output << "STDERR:\n#{stderr}" unless stderr.empty?

    assert success, "Player should exit cleanly with ROM loaded (no hang)\n#{output.join("\n")}"
  end
end
