# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "json"
require_relative "../../teek-mgba/lib/teek/mgba/config"
require_relative "../../teek-mgba/lib/teek/mgba/version"

class TestMGBAConfig < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("teek-mgba-test")
    @path = File.join(@dir, "settings.json")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def new_config
    Teek::MGBA::Config.new(path: @path)
  end

  # -- Platform paths -------------------------------------------------------

  def test_default_path_ends_with_settings_json
    assert Teek::MGBA::Config.default_path.end_with?("teek-mgba/settings.json")
  end

  def test_config_dir_contains_app_name
    assert_includes Teek::MGBA::Config.config_dir, "teek-mgba"
  end

  # -- Global defaults ------------------------------------------------------

  def test_defaults_scale
    assert_equal 3, new_config.scale
  end

  def test_defaults_volume
    assert_equal 100, new_config.volume
  end

  def test_defaults_muted
    refute new_config.muted?
  end

  # -- Global setters -------------------------------------------------------

  def test_set_scale
    c = new_config
    c.scale = 2
    assert_equal 2, c.scale
  end

  def test_scale_clamps_low
    c = new_config
    c.scale = 0
    assert_equal 1, c.scale
  end

  def test_scale_clamps_high
    c = new_config
    c.scale = 10
    assert_equal 4, c.scale
  end

  def test_set_volume
    c = new_config
    c.volume = 75
    assert_equal 75, c.volume
  end

  def test_volume_clamps
    c = new_config
    c.volume = -5
    assert_equal 0, c.volume
    c.volume = 200
    assert_equal 100, c.volume
  end

  def test_set_muted
    c = new_config
    c.muted = true
    assert c.muted?
    c.muted = false
    refute c.muted?
  end

  # -- Persistence ----------------------------------------------------------

  def test_save_creates_file
    c = new_config
    c.scale = 2
    c.save!
    assert File.exist?(@path)
  end

  def test_save_creates_directory
    nested = File.join(@dir, "sub", "dir", "settings.json")
    c = Teek::MGBA::Config.new(path: nested)
    c.save!
    assert File.exist?(nested)
  end

  def test_save_writes_metadata
    c = new_config
    c.save!
    data = JSON.parse(File.read(@path))
    assert_equal Teek::MGBA::VERSION, data["meta"]["teek_mgba_version"]
    assert data.key?("meta")
    assert data["meta"].key?("saved_at")
  end

  def test_round_trip_global
    c = new_config
    c.scale = 2
    c.volume = 42
    c.muted = true
    c.save!

    c2 = Teek::MGBA::Config.new(path: @path)
    assert_equal 2, c2.scale
    assert_equal 42, c2.volume
    assert c2.muted?
  end

  def test_round_trip_gamepad
    guid = "030000007e0500000920000001800000"
    c = new_config
    c.gamepad(guid, name: "Switch Pro")
    c.set_dead_zone(guid, 15)
    c.set_mapping(guid, :a, :x)
    c.save!

    c2 = Teek::MGBA::Config.new(path: @path)
    assert_equal 15, c2.dead_zone(guid)
    assert_equal "x", c2.mappings(guid)["a"]
    gp = c2.gamepad(guid)
    assert_equal "Switch Pro", gp["name"]
  end

  # -- Gamepad defaults -----------------------------------------------------

  def test_gamepad_defaults
    guid = "abcd1234"
    c = new_config
    assert_equal 25, c.dead_zone(guid)
    assert_equal "a", c.mappings(guid)["a"]
    assert_equal "dpad_up", c.mappings(guid)["up"]
    assert_equal "left_shoulder", c.mappings(guid)["l"]
  end

  def test_set_dead_zone_clamps
    guid = "abcd"
    c = new_config
    c.set_dead_zone(guid, -5)
    assert_equal 0, c.dead_zone(guid)
    c.set_dead_zone(guid, 99)
    assert_equal 50, c.dead_zone(guid)
  end

  def test_set_mapping_removes_duplicate
    guid = "abcd"
    c = new_config
    # Default: a -> a, b -> b
    c.set_mapping(guid, :a, :x)
    m = c.mappings(guid)
    assert_equal "x", m["a"]
    # :x should not be mapped to anything else
    assert_nil m.values.count("x") > 1 ? "dup" : nil
  end

  def test_reset_gamepad
    guid = "abcd"
    c = new_config
    c.set_dead_zone(guid, 10)
    c.set_mapping(guid, :a, :y)
    c.reset_gamepad(guid)
    assert_equal 25, c.dead_zone(guid)
    assert_equal "a", c.mappings(guid)["a"]
  end

  # -- Multiple gamepads ----------------------------------------------------

  def test_separate_guids
    c = new_config
    c.set_dead_zone("guid_a", 10)
    c.set_dead_zone("guid_b", 40)
    assert_equal 10, c.dead_zone("guid_a")
    assert_equal 40, c.dead_zone("guid_b")
  end

  def test_mapping_change_on_one_guid_does_not_affect_other
    c = new_config
    c.set_mapping("guid_a", :a, :y)
    assert_equal "a", c.mappings("guid_b")["a"]
    assert_equal "y", c.mappings("guid_a")["a"]
  end

  # -- Keyboard config (sentinel GUID) -------------------------------------

  def test_keyboard_guid_defaults_to_keysyms
    c = new_config
    m = c.mappings(Teek::MGBA::Config::KEYBOARD_GUID)
    assert_equal "z", m["a"]
    assert_equal "x", m["b"]
    assert_equal "Up", m["up"]
    assert_equal "Return", m["start"]
    assert_equal "BackSpace", m["select"]
  end

  def test_keyboard_guid_dead_zone_is_zero
    c = new_config
    assert_equal 0, c.dead_zone(Teek::MGBA::Config::KEYBOARD_GUID)
  end

  def test_keyboard_does_not_get_gamepad_defaults
    c = new_config
    m = c.mappings(Teek::MGBA::Config::KEYBOARD_GUID)
    # Should NOT have gamepad button names like 'dpad_up'
    refute_includes m.values, "dpad_up"
    refute_includes m.values, "left_shoulder"
  end

  def test_regular_guid_does_not_get_keyboard_defaults
    c = new_config
    m = c.mappings("some_real_guid")
    # Should NOT have keysyms like 'z' or 'Return'
    refute_includes m.values, "z"
    refute_includes m.values, "Return"
  end

  def test_round_trip_keyboard
    c = new_config
    c.set_mapping(Teek::MGBA::Config::KEYBOARD_GUID, :a, "q")
    c.save!

    c2 = Teek::MGBA::Config.new(path: @path)
    assert_equal "q", c2.mappings(Teek::MGBA::Config::KEYBOARD_GUID)["a"]
  end

  def test_reset_keyboard_restores_defaults
    guid = Teek::MGBA::Config::KEYBOARD_GUID
    c = new_config
    c.set_mapping(guid, :a, "q")
    c.reset_gamepad(guid)
    assert_equal "z", c.mappings(guid)["a"]
    assert_equal 0, c.dead_zone(guid)
  end

  # -- Turbo settings ------------------------------------------------------

  def test_defaults_turbo_speed
    assert_equal 2, new_config.turbo_speed
  end

  def test_set_turbo_speed
    c = new_config
    c.turbo_speed = 4
    assert_equal 4, c.turbo_speed
  end

  def test_defaults_turbo_volume_pct
    assert_equal 25, new_config.turbo_volume_pct
  end

  def test_set_turbo_volume_pct
    c = new_config
    c.turbo_volume_pct = 50
    assert_equal 50, c.turbo_volume_pct
  end

  def test_turbo_volume_pct_clamps
    c = new_config
    c.turbo_volume_pct = -10
    assert_equal 0, c.turbo_volume_pct
    c.turbo_volume_pct = 200
    assert_equal 100, c.turbo_volume_pct
  end

  def test_round_trip_turbo
    c = new_config
    c.turbo_speed = 3
    c.turbo_volume_pct = 40
    c.save!

    c2 = Teek::MGBA::Config.new(path: @path)
    assert_equal 3, c2.turbo_speed
    assert_equal 40, c2.turbo_volume_pct
  end

  # -- Aspect ratio --------------------------------------------------------

  def test_defaults_keep_aspect_ratio
    assert new_config.keep_aspect_ratio?
  end

  def test_set_keep_aspect_ratio
    c = new_config
    c.keep_aspect_ratio = false
    refute c.keep_aspect_ratio?
    c.keep_aspect_ratio = true
    assert c.keep_aspect_ratio?
  end

  def test_round_trip_keep_aspect_ratio
    c = new_config
    c.keep_aspect_ratio = false
    c.save!

    c2 = Teek::MGBA::Config.new(path: @path)
    refute c2.keep_aspect_ratio?
  end

  # -- Show FPS ------------------------------------------------------------

  def test_defaults_show_fps
    assert new_config.show_fps?
  end

  def test_set_show_fps
    c = new_config
    c.show_fps = false
    refute c.show_fps?
  end

  def test_round_trip_show_fps
    c = new_config
    c.show_fps = false
    c.save!

    c2 = Teek::MGBA::Config.new(path: @path)
    refute c2.show_fps?
  end

  # -- Saves dir -----------------------------------------------------------

  def test_defaults_saves_dir
    assert new_config.saves_dir.end_with?("teek-mgba/saves")
  end

  def test_set_saves_dir
    c = new_config
    c.saves_dir = "/custom/saves"
    assert_equal "/custom/saves", c.saves_dir
  end

  def test_round_trip_saves_dir
    c = new_config
    c.saves_dir = "/my/saves"
    c.save!

    c2 = Teek::MGBA::Config.new(path: @path)
    assert_equal "/my/saves", c2.saves_dir
  end

  def test_default_saves_dir_class_method
    assert Teek::MGBA::Config.default_saves_dir.end_with?("teek-mgba/saves")
  end

  # -- Recent ROMs ---------------------------------------------------------

  def test_recent_roms_default_empty
    assert_equal [], new_config.recent_roms
  end

  def test_add_recent_rom
    c = new_config
    c.add_recent_rom("/roms/a.gba")
    c.add_recent_rom("/roms/b.gba")
    assert_equal ["/roms/b.gba", "/roms/a.gba"], c.recent_roms
  end

  def test_add_recent_rom_deduplicates
    c = new_config
    c.add_recent_rom("/roms/a.gba")
    c.add_recent_rom("/roms/b.gba")
    c.add_recent_rom("/roms/a.gba")
    assert_equal ["/roms/a.gba", "/roms/b.gba"], c.recent_roms
  end

  def test_add_recent_rom_caps_at_max
    c = new_config
    7.times { |i| c.add_recent_rom("/roms/#{i}.gba") }
    assert_equal Teek::MGBA::Config::MAX_RECENT_ROMS, c.recent_roms.size
    assert_equal "/roms/6.gba", c.recent_roms.first
    assert_equal "/roms/2.gba", c.recent_roms.last
  end

  def test_remove_recent_rom
    c = new_config
    c.add_recent_rom("/roms/a.gba")
    c.add_recent_rom("/roms/b.gba")
    c.remove_recent_rom("/roms/a.gba")
    assert_equal ["/roms/b.gba"], c.recent_roms
  end

  def test_remove_recent_rom_noop_if_missing
    c = new_config
    c.add_recent_rom("/roms/a.gba")
    c.remove_recent_rom("/roms/nope.gba")
    assert_equal ["/roms/a.gba"], c.recent_roms
  end

  def test_clear_recent_roms
    c = new_config
    c.add_recent_rom("/roms/a.gba")
    c.add_recent_rom("/roms/b.gba")
    c.clear_recent_roms
    assert_equal [], c.recent_roms
  end

  def test_round_trip_recent_roms
    c = new_config
    c.add_recent_rom("/roms/a.gba")
    c.add_recent_rom("/roms/b.gba")
    c.save!

    c2 = Teek::MGBA::Config.new(path: @path)
    assert_equal ["/roms/b.gba", "/roms/a.gba"], c2.recent_roms
  end

  # -- States dir ----------------------------------------------------------

  def test_defaults_states_dir
    assert new_config.states_dir.end_with?("teek-mgba/states")
  end

  def test_set_states_dir
    c = new_config
    c.states_dir = "/custom/states"
    assert_equal "/custom/states", c.states_dir
  end

  def test_round_trip_states_dir
    c = new_config
    c.states_dir = "/my/states"
    c.save!

    c2 = Teek::MGBA::Config.new(path: @path)
    assert_equal "/my/states", c2.states_dir
  end

  def test_default_states_dir_class_method
    assert Teek::MGBA::Config.default_states_dir.end_with?("teek-mgba/states")
  end

  # -- Save state debounce -------------------------------------------------

  def test_defaults_save_state_debounce
    assert_in_delta 3.0, new_config.save_state_debounce, 0.01
  end

  def test_set_save_state_debounce
    c = new_config
    c.save_state_debounce = 5.0
    assert_in_delta 5.0, c.save_state_debounce, 0.01
  end

  def test_save_state_debounce_clamps
    c = new_config
    c.save_state_debounce = -1.0
    assert_in_delta 0.0, c.save_state_debounce, 0.01
    c.save_state_debounce = 99.0
    assert_in_delta 30.0, c.save_state_debounce, 0.01
  end

  def test_round_trip_save_state_debounce
    c = new_config
    c.save_state_debounce = 1.5
    c.save!

    c2 = Teek::MGBA::Config.new(path: @path)
    assert_in_delta 1.5, c2.save_state_debounce, 0.01
  end

  # -- Quick save slot -----------------------------------------------------

  def test_defaults_quick_save_slot
    assert_equal 1, new_config.quick_save_slot
  end

  def test_set_quick_save_slot
    c = new_config
    c.quick_save_slot = 5
    assert_equal 5, c.quick_save_slot
  end

  def test_quick_save_slot_clamps
    c = new_config
    c.quick_save_slot = 0
    assert_equal 1, c.quick_save_slot
    c.quick_save_slot = 99
    assert_equal 10, c.quick_save_slot
  end

  def test_round_trip_quick_save_slot
    c = new_config
    c.quick_save_slot = 7
    c.save!

    c2 = Teek::MGBA::Config.new(path: @path)
    assert_equal 7, c2.quick_save_slot
  end

  # -- Save state backup ---------------------------------------------------

  def test_defaults_save_state_backup
    assert new_config.save_state_backup?
  end

  def test_set_save_state_backup
    c = new_config
    c.save_state_backup = false
    refute c.save_state_backup?
    c.save_state_backup = true
    assert c.save_state_backup?
  end

  def test_round_trip_save_state_backup
    c = new_config
    c.save_state_backup = false
    c.save!

    c2 = Teek::MGBA::Config.new(path: @path)
    refute c2.save_state_backup?
  end

  # -- Edge cases -----------------------------------------------------------

  def test_corrupt_json_falls_back_to_defaults
    File.write(@path, "NOT VALID JSON {{{")
    c = Teek::MGBA::Config.new(path: @path)
    assert_equal 3, c.scale
    assert_equal 100, c.volume
  end

  def test_missing_file_uses_defaults
    c = Teek::MGBA::Config.new(path: File.join(@dir, "nope.json"))
    assert_equal 3, c.scale
  end

  def test_forward_compat_new_global_key
    # Simulate an old config file that doesn't have 'muted'
    data = { "global" => { "scale" => 2, "volume" => 80 }, "gamepads" => {} }
    File.write(@path, JSON.generate(data))
    c = Teek::MGBA::Config.new(path: @path)
    assert_equal 2, c.scale
    assert_equal 80, c.volume
    refute c.muted?  # filled in from defaults
  end

  def test_reload
    c = new_config
    c.scale = 2
    c.save!

    # Externally modify the file
    data = JSON.parse(File.read(@path))
    data["global"]["scale"] = 4
    File.write(@path, JSON.generate(data))

    c.reload!
    assert_equal 4, c.scale
  end
end
