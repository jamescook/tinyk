# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  require_relative '../../test/simplecov_config'

  coverage_name = ENV['COVERAGE_NAME'] || 'mgba'
  SimpleCov.coverage_dir "#{SimpleCovConfig::PROJECT_ROOT}/coverage/results/#{coverage_name}"
  SimpleCov.command_name "mgba:#{coverage_name}"
  SimpleCov.print_error_status = false
  SimpleCov.formatter SimpleCov::Formatter::SimpleFormatter

  SimpleCov.start do
    SimpleCovConfig.apply_filters(self)
    track_files "#{SimpleCovConfig::PROJECT_ROOT}/lib/**/*.rb"
  end
end

require "minitest/autorun"
