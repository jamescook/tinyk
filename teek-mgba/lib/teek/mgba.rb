# frozen_string_literal: true

require "teek"
require "teek/sdl2"
require_relative "mgba/version"
require "teek_mgba"
require_relative "mgba/config"
require_relative "mgba/core"
require_relative "mgba/settings_window"
require_relative "mgba/player"

module Teek
  module MGBA
    # Lazily loaded user config — shared across the application.
    # @return [Teek::MGBA::Config]
    def self.user_config
      @user_config ||= Config.new
    end
  end
end
