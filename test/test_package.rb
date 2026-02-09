# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestPackage < Minitest::Test
  include TeekTestHelper

  def test_require_package_loads_and_returns_version
    assert_tk_app("require_package should load package and return version", method(:app_require_package))
  end

  def app_require_package
    fixtures = File.join(Dir.pwd, 'test', 'fixtures')
    app.tcl_eval("lappend ::auto_path {#{fixtures}}")

    version = app.require_package('teektest')
    raise "expected version '1.0', got #{version.inspect}" unless version == '1.0'

    result = app.tcl_eval('::teektest::hello World')
    raise "expected 'Hello, World!', got #{result.inspect}" unless result == 'Hello, World!'
  end

  def test_require_package_with_version
    assert_tk_app("require_package with version should work", method(:app_require_package_version))
  end

  def app_require_package_version
    fixtures = File.join(Dir.pwd, 'test', 'fixtures')
    app.tcl_eval("lappend ::auto_path {#{fixtures}}")

    version = app.require_package('teektest', '1.0')
    raise "expected version '1.0', got #{version.inspect}" unless version == '1.0'
  end

  def test_require_package_missing_raises_tcl_error
    assert_tk_app("require_package should raise on missing package", method(:app_require_missing))
  end

  def app_require_missing
    begin
      app.require_package('nonexistent_package_xyz')
      raise "expected TclError but nothing was raised"
    rescue Teek::TclError => e
      raise "error message should mention package name: #{e.message}" unless e.message.include?('nonexistent_package_xyz')
    end
  end

  def test_package_names
    assert_tk_app("package_names should return array of available packages", method(:app_package_names))
  end

  def app_package_names
    names = app.package_names
    raise "expected Array, got #{names.class}" unless names.is_a?(Array)
    raise "expected Tk in package names" unless names.include?('Tk')
  end

  def test_package_present
    assert_tk_app("package_present? should detect loaded packages", method(:app_package_present))
  end

  def app_package_present
    raise "Tk should be present" unless app.package_present?('Tk')
    raise "nonexistent should not be present" if app.package_present?('nonexistent_xyz')
  end

  def test_package_versions
    assert_tk_app("package_versions should return available versions", method(:app_package_versions))
  end

  def app_package_versions
    fixtures = File.join(Dir.pwd, 'test', 'fixtures')
    app.add_package_path(fixtures)

    versions = app.package_versions('teektest')
    raise "expected Array, got #{versions.class}" unless versions.is_a?(Array)
    raise "expected ['1.0'], got #{versions.inspect}" unless versions == ['1.0']
  end

  def test_add_package_path_and_require
    assert_tk_app("add_package_path should make packages loadable", method(:app_add_package_path))
  end

  def app_add_package_path
    fixtures = File.join(Dir.pwd, 'test', 'fixtures')
    app.add_package_path(fixtures)

    version = app.require_package('teektest')
    raise "expected version '1.0', got #{version.inspect}" unless version == '1.0'
  end

  def test_add_package_path_appears_in_auto_path
    assert_tk_app("add_package_path should append to auto_path", method(:app_add_package_path_visible))
  end

  def app_add_package_path_visible
    app.add_package_path('/tmp/fake_packages')
    paths = app.split_list(app.tcl_eval('set ::auto_path'))
    raise "expected /tmp/fake_packages in auto_path" unless paths.include?('/tmp/fake_packages')
  end
end
