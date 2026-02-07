# frozen_string_literal: true

# Shared SimpleCov configuration for all test contexts:
# - Main test process
# - TinyK::TestWorker subprocess
# - Collation (Rakefile)
# - Subprocess preamble (tk_test_helper.rb)

module SimpleCovConfig
  PROJECT_ROOT = File.expand_path('..', __dir__)

  FILTERS = [
    '/test/',
    %r{^/ext/},
  ].freeze

  def self.apply_filters(simplecov_context)
    FILTERS.each { |f| simplecov_context.add_filter(f) }
  end

  def self.apply_groups(simplecov_context)
    simplecov_context.add_group 'Core', 'lib/tinyk.rb'
  end

  # Generate add_filter code lines from FILTERS array (for subprocess preamble)
  def self.filters_as_code
    FILTERS.map do |f|
      case f
      when Regexp then "add_filter #{f.inspect}"
      when String then "add_filter '#{f}'"
      end
    end.join("\n          ")
  end

  # Ruby code string for subprocess SimpleCov setup
  def self.subprocess_preamble(project_root: PROJECT_ROOT)
    <<~RUBY
      if ENV['COVERAGE']
        require 'simplecov'

        coverage_name = ENV['COVERAGE_NAME'] || 'default'
        SimpleCov.coverage_dir "#{project_root}/coverage/results/\#{coverage_name}_sub_\#{Process.pid}"
        SimpleCov.command_name "subprocess:\#{Process.pid}"
        SimpleCov.print_error_status = false
        SimpleCov.formatter SimpleCov::Formatter::SimpleFormatter

        SimpleCov.start do
          #{filters_as_code}
          track_files "#{project_root}/lib/**/*.rb"
        end
      end
    RUBY
  end
end
