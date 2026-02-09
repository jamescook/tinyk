require "bundler/gem_tasks"
require 'rake/testtask'
require 'rake/clean'

# Documentation tasks - all doc gems are in docs_site/Gemfile
namespace :docs do
  desc "Install docs dependencies (docs_site/Gemfile)"
  task :setup do
    Dir.chdir('docs_site') do
      Bundler.with_unbundled_env { sh 'bundle install' }
    end
  end

  task :yard_clean do
    FileUtils.rm_rf('doc')
    FileUtils.rm_rf('docs_site/_api')
    FileUtils.rm_rf('docs_site/_site')
    FileUtils.rm_rf('docs_site/.jekyll-cache')
    FileUtils.rm_f('docs_site/assets/js/search-data.json')
  end

  desc "Generate YARD JSON (uses docs_site/Gemfile)"
  task yard_json: :yard_clean do
    Bundler.with_unbundled_env do
      sh 'BUNDLE_GEMFILE=docs_site/Gemfile bundle exec yard doc'
    end
  end

  desc "Generate API docs (YARD JSON -> HTML)"
  task yard: :yard_json do
    Bundler.with_unbundled_env do
      sh 'BUNDLE_GEMFILE=docs_site/Gemfile bundle exec ruby docs_site/build_api_docs.rb'
    end
  end

  desc "Bless recordings from recordings/ into docs_site/assets/recordings/"
  task :bless_recordings do
    require 'fileutils'
    src = 'recordings'
    dest = 'docs_site/assets/recordings'
    FileUtils.mkdir_p(dest)
    videos = Dir.glob("#{src}/*.{mp4,webm}")
    if videos.empty?
      puts "No recordings in #{src}/ to bless."
      next
    end
    videos.each do |path|
      FileUtils.cp(path, dest)
      puts "  #{File.basename(path)} -> #{dest}/"
    end
    puts "Blessed #{videos.size} recording(s)."
  end

  desc "Generate recordings gallery page"
  task :recordings do
    sh 'ruby docs_site/build_recordings.rb'
  end

  desc "Generate full docs site (YARD + Jekyll)"
  task generate: [:yard, :recordings] do
    Dir.chdir('docs_site') do
      Bundler.with_unbundled_env { sh 'bundle exec jekyll build' }
    end
    puts "Docs generated in docs_site/_site/"
  end

  desc "Serve docs locally"
  task serve: [:yard, :recordings] do
    Dir.chdir('docs_site') do
      Bundler.with_unbundled_env { sh 'bundle exec jekyll serve' }
    end
  end
end

# Aliases for convenience
task doc: 'docs:yard'
task yard: 'docs:yard'

# Compiling on macOS with Homebrew:
#
# Tcl/Tk 9.0:
#   rake clean && rake compile -- --with-tcltkversion=9.0 \
#     --with-tcl-lib=$(brew --prefix tcl-tk)/lib \
#     --with-tcl-include=$(brew --prefix tcl-tk)/include/tcl-tk \
#     --with-tk-lib=$(brew --prefix tcl-tk)/lib \
#     --with-tk-include=$(brew --prefix tcl-tk)/include/tcl-tk \
#     --without-X11
#
# Tcl/Tk 8.6:
#   rake clean && rake compile -- --with-tcltkversion=8.6 \
#     --with-tcl-lib=$(brew --prefix tcl-tk@8)/lib \
#     --with-tcl-include=$(brew --prefix tcl-tk@8)/include \
#     --with-tk-lib=$(brew --prefix tcl-tk@8)/lib \
#     --with-tk-include=$(brew --prefix tcl-tk@8)/include \
#     --without-X11

# Clean up extconf cached config files
CLEAN.include('ext/teek/config_list')
CLOBBER.include('tmp', 'lib/*.bundle', 'lib/*.so', 'ext/**/*.o', 'ext/**/*.bundle', 'ext/**/*.bundle.dSYM')

# Clean coverage artifacts before test runs to prevent accumulation
CLEAN.include('coverage/.resultset.json', 'coverage/results')

# Conditionally load rake-compiler
if Gem::Specification.find_all_by_name('rake-compiler').any?
  require 'rake/extensiontask'
  Rake::ExtensionTask.new do |ext|
    ext.name = 'tcltklib'
    ext.ext_dir = 'ext/teek'
    ext.lib_dir = 'lib'
  end
end

desc "Clear stale coverage artifacts"
task :clean_coverage do
  require 'fileutils'
  FileUtils.rm_f('coverage/.resultset.json')
  FileUtils.rm_rf('coverage/results')
  FileUtils.mkdir_p('coverage/results')
end

namespace :coverage do
  desc "Collate coverage results from multiple test runs into a single report"
  task :collate do
    require 'simplecov'
    require 'simplecov_json_formatter'
    require_relative 'test/simplecov_config'

    result_files = Dir['coverage/results/*/.resultset.json']
    if result_files.empty?
      puts "No coverage results found in coverage/results/"
      next
    end

    puts "Collating coverage from: #{result_files.map { |f| File.dirname(f).split('/').last }.join(', ')}"

    SimpleCov.collate(result_files) do
      coverage_dir 'coverage'
      formatter SimpleCov::Formatter::MultiFormatter.new([
        SimpleCov::Formatter::HTMLFormatter,
        SimpleCov::Formatter::JSONFormatter
      ])
      SimpleCovConfig.apply_filters(self)
      SimpleCovConfig.apply_groups(self)
    end

    puts "Coverage report generated: coverage/index.html, coverage/coverage.json"
  end

  desc "Full coverage pipeline: collate results"
  task :full => :collate
end

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/test_*.rb']
  t.verbose = true
end

task test: [:compile, :clean_coverage]

def detect_platform
  case RUBY_PLATFORM
  when /darwin/ then 'darwin'
  when /linux/ then 'linux'
  when /mingw|mswin/ then 'windows'
  else 'unknown'
  end
end

task :default => :compile

# Docker tasks for local testing and CI
namespace :docker do
  DOCKERFILE = 'Dockerfile.ci-test'
  DOCKER_LABEL = 'project=teek'

  def docker_image_name(tcl_version, ruby_version = nil)
    ruby_version ||= ruby_version_from_env
    base = tcl_version == '8.6' ? 'teek-ci-test-8' : 'teek-ci-test-9'
    ruby_version == '4.0' ? base : "#{base}-ruby#{ruby_version}"
  end

  def tcl_version_from_env
    version = ENV.fetch('TCL_VERSION', '9.0')
    unless ['8.6', '9.0'].include?(version)
      abort "Invalid TCL_VERSION='#{version}'. Must be '8.6' or '9.0'."
    end
    version
  end

  def ruby_version_from_env
    ENV.fetch('RUBY_VERSION', '4.0')
  end

  desc "Build Docker image (TCL_VERSION=9.0|8.6, RUBY_VERSION=3.4|4.0|...)"
  task :build do
    tcl_version = tcl_version_from_env
    ruby_version = ruby_version_from_env
    image_name = docker_image_name(tcl_version, ruby_version)

    verbose = ENV['VERBOSE'] || ENV['V']
    quiet = !verbose
    if quiet
      puts "Building Docker image for Ruby #{ruby_version}, Tcl #{tcl_version}... (VERBOSE=1 for details)"
    else
      puts "Building Docker image for Ruby #{ruby_version}, Tcl #{tcl_version}..."
    end
    cmd = "docker build -f #{DOCKERFILE}"
    cmd += " -q" if quiet
    cmd += " --label #{DOCKER_LABEL}"
    cmd += " --build-arg RUBY_VERSION=#{ruby_version}"
    cmd += " --build-arg TCL_VERSION=#{tcl_version}"
    cmd += " -t #{image_name} ."

    sh cmd, verbose: !quiet
  end

  desc "Run tests in Docker (TCL_VERSION=9.0|8.6, RUBY_VERSION=3.4|4.0|..., TEST=path/to/test.rb)"
  task test: :build do
    tcl_version = tcl_version_from_env
    ruby_version = ruby_version_from_env
    image_name = docker_image_name(tcl_version, ruby_version)

    require 'fileutils'
    FileUtils.mkdir_p('coverage')

    puts "Running tests in Docker (Ruby #{ruby_version}, Tcl #{tcl_version})..."
    cmd = "docker run --rm --init"
    cmd += " -v #{Dir.pwd}/coverage:/app/coverage"
    cmd += " -e TCL_VERSION=#{tcl_version}"
    cmd += " -e TEST='#{ENV['TEST']}'" if ENV['TEST']
    cmd += " -e TESTOPTS='#{ENV['TESTOPTS']}'" if ENV['TESTOPTS']
    if ENV['COVERAGE'] == '1'
      cmd += " -e COVERAGE=1"
      cmd += " -e COVERAGE_NAME=#{ENV['COVERAGE_NAME'] || 'main'}"
    end
    cmd += " #{image_name}"

    sh cmd
  end

  desc "Run interactive shell in Docker (TCL_VERSION=9.0|8.6, RUBY_VERSION=3.4|4.0|...)"
  task shell: :build do
    tcl_version = tcl_version_from_env
    ruby_version = ruby_version_from_env
    image_name = docker_image_name(tcl_version, ruby_version)

    cmd = "docker run --rm --init -it"
    cmd += " -v #{Dir.pwd}/coverage:/app/coverage"
    cmd += " -e TCL_VERSION=#{tcl_version}"
    cmd += " #{image_name} bash"

    sh cmd
  end

  desc "Remove dangling Docker images from teek builds"
  task :prune do
    sh "docker image prune -f --filter label=#{DOCKER_LABEL}"
  end

  Rake::Task['docker:test'].enhance { Rake::Task['docker:prune'].invoke }

  # Scan sample files for # teek-record magic comment
  # Format: # teek-record: title=My Demo, codec=vp9
  def find_recordable_samples
    Dir['sample/**/*.rb'].filter_map do |path|
      first_lines = File.read(path, 500)
      match = first_lines.match(/^#\s*teek-record(?::\s*(.+))?$/)
      next unless match

      options = {}
      if match[1]
        match[1].split(',').each do |pair|
          key, value = pair.strip.split('=', 2)
          options[key.strip] = value&.strip if key
        end
      end
      options['sample'] = path
      options
    end
  end

  desc "Record demos in Docker (TCL_VERSION=9.0|8.6, DEMO=sample/foo.rb)"
  task record_demos: :build do
    require 'fileutils'
    FileUtils.mkdir_p('recordings')

    demos = if ENV['DEMO']
              find_recordable_samples.select { |d| d['sample'] == ENV['DEMO'] }
            else
              find_recordable_samples
            end

    if demos.empty?
      puts "No recordable samples found. Add '# teek-record' comment to samples."
      next
    end

    demos.each do |demo|
      sample = demo['sample']
      codec = ENV['CODEC'] || demo['codec'] || 'x264'
      name = demo['name']

      puts
      puts "Recording #{sample} (#{codec})..."
      env = "CODEC=#{codec}"
      env += " NAME=#{name}" if name
      sh "#{env} ./scripts/docker-record.sh #{sample}"
    end

    puts "Done! Recordings in: recordings/"
  end

  Rake::Task['docker:record_demos'].enhance { Rake::Task['docker:prune'].invoke }
end
