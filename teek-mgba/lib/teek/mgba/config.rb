# frozen_string_literal: true

require 'json'
require 'fileutils'

module Teek
  module MGBA
    # Persists mGBA Player settings to a JSON file in the platform-appropriate
    # config directory.
    #
    # Config file location:
    #   macOS:   ~/Library/Application Support/teek-mgba/settings.json
    #   Linux:   $XDG_CONFIG_HOME/teek-mgba/settings.json  (~/.config/teek-mgba/)
    #   Windows: %APPDATA%/teek-mgba/settings.json
    #
    # Gamepad mappings are keyed by SDL GUID (identifies controller model/type),
    # so different controller types keep separate configs.
    class Config
      APP_NAME = 'teek-mgba'
      FILENAME = 'settings.json'

      GLOBAL_DEFAULTS = {
        'scale'              => 3,
        'volume'             => 100,
        'muted'              => false,
        'turbo_speed'        => 2,
        'turbo_volume_pct'   => 25,
        'keep_aspect_ratio'  => true,
        'show_fps'           => true,
        'toast_duration'     => 1.5,
      }.freeze

      GAMEPAD_DEFAULTS = {
        'dead_zone' => 25,
        'mappings'  => {
          'a' => 'a', 'b' => 'b',
          'l' => 'left_shoulder', 'r' => 'right_shoulder',
          'up' => 'dpad_up', 'down' => 'dpad_down',
          'left' => 'dpad_left', 'right' => 'dpad_right',
          'start' => 'start', 'select' => 'back',
        },
      }.freeze

      # Sentinel GUID for keyboard bindings — stored alongside real gamepad GUIDs.
      KEYBOARD_GUID = 'keyboard'

      KEYBOARD_DEFAULTS = {
        'dead_zone' => 0,
        'mappings'  => {
          'a' => 'z', 'b' => 'x',
          'l' => 'a', 'r' => 's',
          'up' => 'Up', 'down' => 'Down',
          'left' => 'Left', 'right' => 'Right',
          'start' => 'Return', 'select' => 'BackSpace',
        },
      }.freeze

      def initialize(path: nil)
        @path = path || self.class.default_path
        @data = load_file
      end

      # @return [String] path to the config file
      attr_reader :path

      # -- Global settings ---------------------------------------------------

      def scale
        global['scale']
      end

      def scale=(val)
        global['scale'] = val.to_i.clamp(1, 4)
      end

      def volume
        global['volume']
      end

      def volume=(val)
        global['volume'] = val.to_i.clamp(0, 100)
      end

      def muted?
        global['muted']
      end

      def muted=(val)
        global['muted'] = !!val
      end

      # @return [Integer] turbo speed multiplier (2, 3, 4, or 0 for uncapped)
      def turbo_speed
        global['turbo_speed']
      end

      def turbo_speed=(val)
        global['turbo_speed'] = val.to_i
      end

      # @return [Integer] volume percentage during fast-forward (0-100, hidden setting)
      def turbo_volume_pct
        global['turbo_volume_pct']
      end

      def turbo_volume_pct=(val)
        global['turbo_volume_pct'] = val.to_i.clamp(0, 100)
      end

      def keep_aspect_ratio?
        global['keep_aspect_ratio']
      end

      def keep_aspect_ratio=(val)
        global['keep_aspect_ratio'] = !!val
      end

      def show_fps?
        global['show_fps']
      end

      def show_fps=(val)
        global['show_fps'] = !!val
      end

      # @return [Float] toast notification duration in seconds
      def toast_duration
        global['toast_duration'].to_f
      end

      def toast_duration=(val)
        val = val.to_f
        raise ArgumentError, "toast_duration must be positive" if val <= 0
        global['toast_duration'] = val.clamp(0.1, 10.0)
      end

      # @return [String] directory for game save files (.sav)
      def saves_dir
        global['saves_dir'] || self.class.default_saves_dir
      end

      def saves_dir=(val)
        global['saves_dir'] = val.to_s
      end

      # -- Recent ROMs -------------------------------------------------------

      MAX_RECENT_ROMS = 5

      # @return [Array<String>] ROM paths, newest first
      def recent_roms
        @data['recent_roms'] ||= []
      end

      # Add a ROM path to the front of the recent list (deduplicates).
      # @param path [String] absolute path to the ROM file
      def add_recent_rom(path)
        list = recent_roms
        list.delete(path)
        list.unshift(path)
        list.pop while list.size > MAX_RECENT_ROMS
      end

      # Remove a specific ROM path from the recent list.
      # @param path [String]
      def remove_recent_rom(path)
        recent_roms.delete(path)
      end

      def clear_recent_roms
        @data['recent_roms'] = []
      end

      # -- Per-gamepad settings ----------------------------------------------

      # @param guid [String] SDL joystick GUID, or KEYBOARD_GUID for keyboard bindings
      # @param name [String] human-readable controller name (stored for reference)
      # @return [Hash] gamepad config (dead_zone, mappings)
      def gamepad(guid, name: nil)
        defaults = guid == KEYBOARD_GUID ? KEYBOARD_DEFAULTS : GAMEPAD_DEFAULTS
        gp = gamepads[guid] ||= deep_dup(defaults)
        gp['name'] = name if name
        gp
      end

      # @param guid [String]
      # @return [Integer] dead zone percentage (0-50)
      def dead_zone(guid)
        gamepad(guid)['dead_zone']
      end

      # @param guid [String]
      # @param val [Integer] percentage (0-50)
      def set_dead_zone(guid, val)
        gamepad(guid)['dead_zone'] = val.to_i.clamp(0, 50)
      end

      # @param guid [String]
      # @return [Hash] GBA button (String) → gamepad button (String)
      def mappings(guid)
        gamepad(guid)['mappings']
      end

      # @param guid [String]
      # @param gba_btn [Symbol, String] e.g. :a, "a"
      # @param gp_btn [Symbol, String] e.g. :x, "dpad_up"
      def set_mapping(guid, gba_btn, gp_btn)
        m = gamepad(guid)['mappings']
        m.delete_if { |_, v| v == gp_btn.to_s }
        m[gba_btn.to_s] = gp_btn.to_s
      end

      # @param guid [String]
      def reset_gamepad(guid)
        defaults = guid == KEYBOARD_GUID ? KEYBOARD_DEFAULTS : GAMEPAD_DEFAULTS
        gamepads[guid] = deep_dup(defaults)
      end

      # -- Persistence -------------------------------------------------------

      def save!
        @data['meta'] = {
          'teek_version'      => (defined?(Teek::VERSION) && Teek::VERSION) || 'unknown',
          'teek_mgba_version' => (defined?(Teek::MGBA::VERSION) && Teek::MGBA::VERSION) || 'unknown',
          'saved_at'          => Time.now.iso8601,
        }
        dir = File.dirname(@path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        File.write(@path, JSON.pretty_generate(@data))
      end

      def reload!
        @data = load_file
      end

      # -- Platform paths ----------------------------------------------------

      def self.default_path
        File.join(config_dir, FILENAME)
      end

      def self.config_dir
        case RUBY_PLATFORM
        when /darwin/
          File.join(Dir.home, 'Library', 'Application Support', APP_NAME)
        when /mswin|mingw|cygwin/
          File.join(ENV.fetch('APPDATA', File.join(Dir.home, 'AppData', 'Roaming')), APP_NAME)
        else
          # Linux / other Unix — XDG Base Directory Specification
          base = ENV.fetch('XDG_CONFIG_HOME', File.join(Dir.home, '.config'))
          File.join(base, APP_NAME)
        end
      end

      # @return [String] default directory for game save files (.sav)
      def self.default_saves_dir
        File.join(config_dir, 'saves')
      end

      private

      def global
        @data['global'] ||= deep_dup(GLOBAL_DEFAULTS)
      end

      def gamepads
        @data['gamepads'] ||= {}
      end

      def load_file
        return default_data unless File.exist?(@path)

        data = JSON.parse(File.read(@path))
        data['global'] = GLOBAL_DEFAULTS.merge(data['global'] || {})
        data['gamepads'] ||= {}
        data['recent_roms'] ||= []
        data
      rescue JSON::ParserError
        default_data
      end

      def default_data
        { 'global' => deep_dup(GLOBAL_DEFAULTS), 'gamepads' => {}, 'recent_roms' => [] }
      end

      def deep_dup(hash)
        JSON.parse(JSON.generate(hash))
      end
    end
  end
end
