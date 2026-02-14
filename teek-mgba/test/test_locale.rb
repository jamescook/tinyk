# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../../teek-mgba/lib/teek/mgba/locale"

class TestMGBALocale < Minitest::Test
  # -- Loading ---------------------------------------------------------------

  def test_load_english
    Teek::MGBA::Locale.load('en')
    assert_equal 'en', Teek::MGBA::Locale.language
  end

  def test_load_japanese
    Teek::MGBA::Locale.load('ja')
    assert_equal 'ja', Teek::MGBA::Locale.language
  end

  def test_fallback_to_english_for_unknown_locale
    Teek::MGBA::Locale.load('zz')
    # Should still load (fell back to en.yml) and return translations
    assert_equal 'File', Teek::MGBA::Locale.translate('menu.file')
  end

  def test_load_auto_detects_from_env
    original = ENV['LANG']
    ENV['LANG'] = 'ja_JP.UTF-8'
    Teek::MGBA::Locale.load
    assert_equal 'ja', Teek::MGBA::Locale.language
  ensure
    ENV['LANG'] = original
    Teek::MGBA::Locale.load('en')
  end

  def test_load_auto_string_treated_as_auto_detect
    original = ENV['LANG']
    ENV['LANG'] = 'en_US.UTF-8'
    Teek::MGBA::Locale.load('auto')
    assert_equal 'en', Teek::MGBA::Locale.language
  ensure
    ENV['LANG'] = original
    Teek::MGBA::Locale.load('en')
  end

  # -- Translation -----------------------------------------------------------

  def test_translate_english_string
    Teek::MGBA::Locale.load('en')
    assert_equal 'File', Teek::MGBA::Locale.translate('menu.file')
  end

  def test_translate_japanese_string
    Teek::MGBA::Locale.load('ja')
    assert_equal 'ファイル', Teek::MGBA::Locale.translate('menu.file')
  end

  def test_translate_nested_key
    Teek::MGBA::Locale.load('en')
    assert_equal 'Video', Teek::MGBA::Locale.translate('settings.video')
    assert_equal 'ROM Info', Teek::MGBA::Locale.translate('rom_info.title')
  end

  def test_translate_with_interpolation
    Teek::MGBA::Locale.load('en')
    result = Teek::MGBA::Locale.translate('toast.state_saved', slot: 3)
    assert_equal 'State saved to slot 3', result
  end

  def test_translate_with_multiple_vars
    Teek::MGBA::Locale.load('en')
    # dialog.game_running_msg has {name}
    result = Teek::MGBA::Locale.translate('dialog.game_running_msg', name: 'Zelda')
    assert_equal 'Another game is running. Switch to Zelda?', result
  end

  def test_translate_japanese_with_interpolation
    Teek::MGBA::Locale.load('ja')
    result = Teek::MGBA::Locale.translate('toast.state_saved', slot: 5)
    assert_includes result, '5'
  end

  def test_translate_missing_key_returns_key
    Teek::MGBA::Locale.load('en')
    assert_equal 'nonexistent.key', Teek::MGBA::Locale.translate('nonexistent.key')
  end

  def test_translate_partial_key_returns_key
    Teek::MGBA::Locale.load('en')
    # 'menu' exists but is a Hash, not a string
    assert_equal 'menu', Teek::MGBA::Locale.translate('menu')
  end

  # -- Alias -----------------------------------------------------------------

  def test_t_alias
    Teek::MGBA::Locale.load('en')
    assert_equal 'File', Teek::MGBA::Locale.t('menu.file')
    assert_equal Teek::MGBA::Locale.translate('menu.file'),
                 Teek::MGBA::Locale.t('menu.file')
  end

  # -- Available languages ---------------------------------------------------

  def test_available_languages
    langs = Teek::MGBA::Locale.available_languages
    assert_includes langs, 'en'
    assert_includes langs, 'ja'
    assert_equal langs, langs.sort, 'should be sorted'
  end

  # -- Translatable mixin ----------------------------------------------------

  def test_translatable_mixin
    klass = Class.new { include Teek::MGBA::Locale::Translatable; public :translate, :t }
    obj = klass.new
    Teek::MGBA::Locale.load('en')
    assert_equal 'File', obj.translate('menu.file')
    assert_equal 'File', obj.t('menu.file')
  end

  def test_translatable_mixin_with_interpolation
    klass = Class.new { include Teek::MGBA::Locale::Translatable; public :translate }
    obj = klass.new
    Teek::MGBA::Locale.load('en')
    assert_equal 'State saved to slot 7', obj.translate('toast.state_saved', slot: 7)
  end

  # -- Completeness ----------------------------------------------------------

  def test_en_and_ja_have_same_keys
    en_path = File.expand_path('../lib/teek/mgba/locales/en.yml', __dir__)
    ja_path = File.expand_path('../lib/teek/mgba/locales/ja.yml', __dir__)
    en = YAML.safe_load_file(en_path)
    ja = YAML.safe_load_file(ja_path)

    en_keys = flatten_keys(en)
    ja_keys = flatten_keys(ja)

    missing_in_ja = en_keys - ja_keys
    missing_in_en = ja_keys - en_keys

    assert_empty missing_in_ja, "Keys in en.yml missing from ja.yml: #{missing_in_ja.join(', ')}"
    assert_empty missing_in_en, "Keys in ja.yml missing from en.yml: #{missing_in_en.join(', ')}"
  end

  private

  def flatten_keys(hash, prefix = nil)
    hash.flat_map do |key, value|
      full_key = prefix ? "#{prefix}.#{key}" : key.to_s
      if value.is_a?(Hash)
        flatten_keys(value, full_key)
      else
        [full_key]
      end
    end
  end
end
