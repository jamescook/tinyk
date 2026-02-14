# frozen_string_literal: true

require 'yaml'

module Teek
  module MGBA
    # Lightweight YAML-backed localization. No external gem dependencies.
    #
    # @example
    #   Locale.load('ja')
    #   Locale.translate('menu.file')           #=> "ファイル"
    #   Locale.translate('toast.state_saved', slot: 3)  #=> "スロット3にステートをセーブしました"
    module Locale
      # Load translations for the given language code.
      # Falls back to English if the requested locale file doesn't exist.
      #
      # @param lang [String, nil] two-letter language code (e.g. 'en', 'ja').
      #   When nil, auto-detects from the OS environment.
      # @return [String] the language code that was loaded
      def self.load(lang = nil)
        lang = detect_language if lang.nil? || lang == 'auto'
        path = locale_path(lang)
        path = locale_path('en') unless File.exist?(path)
        @strings = YAML.safe_load_file(path)
        @lang = lang
      end

      # Look up a translation by dot-separated key, with optional variable
      # interpolation. Returns the key itself if no translation is found.
      #
      # @param key [String] dot-separated path (e.g. 'menu.file', 'toast.state_saved')
      # @param vars [Hash] interpolation variables — replaces `{name}` in the string
      # @return [String]
      def self.translate(key, **vars)
        parts = key.split('.')
        str = @strings&.dig(*parts)
        return key unless str.is_a?(String)

        vars.each { |k, v| str = str.gsub("{#{k}}", v.to_s) }
        str
      end

      class << self
        alias_method :t, :translate
      end

      # @return [String] the currently loaded language code
      def self.language
        @lang
      end

      # @return [Array<String>] sorted list of available language codes
      def self.available_languages
        Dir[locale_path('*')].map { |f| File.basename(f, '.yml') }.sort
      end

      # Detect the user's preferred language from environment variables.
      # @return [String] two-letter language code (e.g. 'en', 'ja')
      # @api private
      private_class_method def self.detect_language
        env = ENV['LANG'] || ENV['LC_ALL'] || ENV['LANGUAGE'] || 'en'
        env[0, 2].downcase
      end

      # @api private
      private_class_method def self.locale_path(lang)
        File.join(__dir__, 'locales', "#{lang}.yml")
      end

      # Auto-load English on first require so translate() always works,
      # even when loaded outside the full Teek::MGBA boot path.
      load('en') unless @strings

      # Mixin for classes that need translation access.
      # Include this to call `translate` / `t` as instance methods.
      #
      # @example
      #   class Player
      #     include Teek::MGBA::Locale::Translatable
      #     def build_menu
      #       label: translate('menu.file')
      #     end
      #   end
      module Translatable
        private

        def translate(key, **vars)
          Locale.translate(key, **vars)
        end
        alias_method :t, :translate
      end
    end
  end
end
