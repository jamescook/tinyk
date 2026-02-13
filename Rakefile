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

  desc "Generate per-method coverage JSON from SimpleCov data"
  task :method_coverage do
    if Dir.exist?('coverage/results')
      require_relative 'lib/teek/method_coverage_service'
      Teek::MethodCoverageService.new(coverage_dir: 'coverage').call
    else
      puts "No coverage data found (run tests with COVERAGE=1 first)"
    end
  end

  desc "Generate API docs (YARD JSON -> HTML)"
  task yard: [:yard_json, :method_coverage] do
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
CLOBBER.include('teek-sdl2/lib/*.bundle', 'teek-sdl2/lib/*.so', 'teek-sdl2/ext/**/*.o', 'teek-sdl2/ext/**/*.bundle')
CLOBBER.include('teek-mgba/lib/*.bundle', 'teek-mgba/lib/*.so', 'teek-mgba/ext/**/*.o', 'teek-mgba/ext/**/*.bundle')

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

  Rake::ExtensionTask.new do |ext|
    ext.name = 'teek_sdl2'
    ext.ext_dir = 'teek-sdl2/ext/teek_sdl2'
    ext.lib_dir = 'teek-sdl2/lib'
  end

  Rake::ExtensionTask.new do |ext|
    ext.name = 'teek_mgba'
    ext.ext_dir = 'teek-mgba/ext/teek_mgba'
    ext.lib_dir = 'teek-mgba/lib'
  end
end

namespace :screenshots do
  desc "Bless current unverified screenshots as the new baselines"
  task :bless do
    require_relative 'test/screenshot_helper'
    src = ScreenshotHelper.unverified_dir
    dst = ScreenshotHelper.blessed_dir

    pngs = Dir.glob(File.join(src, '*.png'))
    if pngs.empty?
      puts "No unverified screenshots in #{src}"
      next
    end

    FileUtils.mkdir_p(dst)
    pngs.each do |f|
      FileUtils.cp(f, dst)
      puts "  Blessed: #{File.basename(f)}"
    end
    puts "#{pngs.size} screenshot(s) blessed to #{dst}"
  end

  desc "Remove unverified screenshots and diffs"
  task :clean do
    require_relative 'test/screenshot_helper'
    [ScreenshotHelper.unverified_dir, ScreenshotHelper.diffs_dir].each do |dir|
      if Dir.exist?(dir)
        FileUtils.rm_rf(dir)
        puts "  Removed: #{dir}"
      end
    end
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

namespace :sdl2 do
  desc "Compile teek-sdl2 C extension"
  task compile: 'compile:teek_sdl2'

  Rake::TestTask.new(:test) do |t|
    t.libs << 'teek-sdl2/test' << 'teek-sdl2/lib'
    t.test_files = FileList['teek-sdl2/test/**/test_*.rb'] - FileList['teek-sdl2/test/test_helper.rb']
    t.ruby_opts << '-r test_helper'
    t.verbose = true
  end
  task test: 'compile:teek_sdl2'
end

namespace :mgba do
  desc "Compile teek-mgba C extension"
  task compile: 'compile:teek_mgba'

  Rake::TestTask.new(:test) do |t|
    t.libs << 'teek-mgba/test' << 'teek-mgba/lib' << 'teek-sdl2/lib'
    t.test_files = FileList['teek-mgba/test/**/test_*.rb'] - FileList['teek-mgba/test/test_helper.rb']
    t.ruby_opts << '-r test_helper'
    t.verbose = true
  end
  task test: ['compile:teek_mgba', 'compile:teek_sdl2']

  desc "Download and build libmgba from source (for macOS / platforms without libmgba-dev)"
  task :deps do
    require 'fileutils'
    require 'etc'

    vendor_dir  = File.expand_path('teek-mgba/vendor')
    mgba_src    = File.join(vendor_dir, 'mgba')
    build_dir   = File.join(vendor_dir, 'build')
    install_dir = File.join(vendor_dir, 'install')

    unless File.directory?(mgba_src)
      FileUtils.mkdir_p(vendor_dir)
      sh "git clone --depth 1 --branch 0.10.3 https://github.com/mgba-emu/mgba.git #{mgba_src}"
    end

    FileUtils.mkdir_p(build_dir)
    cmake_flags = %W[
      -DBUILD_SHARED=OFF
      -DBUILD_STATIC=ON
      -DBUILD_QT=OFF
      -DBUILD_SDL=OFF
      -DBUILD_GL=OFF
      -DBUILD_GLES2=OFF
      -DBUILD_GLES3=OFF
      -DBUILD_LIBRETRO=OFF
      -DSKIP_FRONTEND=ON
      -DUSE_SQLITE3=OFF
      -DUSE_ELF=OFF
      -DUSE_LZMA=OFF
      -DUSE_EDITLINE=OFF
      -DCMAKE_INSTALL_PREFIX=#{install_dir}
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    ].join(' ')

    sh "cmake -S #{mgba_src} -B #{build_dir} #{cmake_flags}"
    sh "cmake --build #{build_dir} -j #{Etc.nprocessors}"
    sh "cmake --install #{build_dir}"

    puts "libmgba built and installed to #{install_dir}"
  end
end

task :default => :compile

namespace :release do
  desc "Build gems, install to temp dir, run smoke test"
  task :smoke do
    require 'tmpdir'
    require 'fileutils'

    Dir.mktmpdir('teek-smoke') do |tmpdir|
      gem_home = File.join(tmpdir, 'gems')

      # Build both gems
      puts "Building gems..."
      sh "gem build teek.gemspec -o #{tmpdir}/teek.gem 2>&1"
      Dir.chdir('teek-sdl2') { sh "gem build teek-sdl2.gemspec -o #{tmpdir}/teek-sdl2.gem 2>&1" }

      # Install into isolated GEM_HOME
      puts "\nInstalling gems..."
      sh "GEM_HOME=#{gem_home} gem install #{tmpdir}/teek.gem --no-document 2>&1"
      sh "GEM_HOME=#{gem_home} gem install #{tmpdir}/teek-sdl2.gem --no-document 2>&1"

      # Run smoke test using only the installed gems (no -I, no bundle)
      puts "\nRunning SDL2 smoke test..."
      smoke = <<~'RUBY'
        require "teek"
        require "teek/sdl2"

        app = Teek::App.new
        app.set_window_title("Release Smoke Test")
        app.set_window_geometry("320x240")
        app.show
        app.update

        vp = Teek::SDL2::Viewport.new(app, width: 300, height: 200)
        vp.pack

        vp.render do |r|
          r.clear(30, 30, 30)
          r.fill(20, 20, 120, 80, r: 200, g: 50, b: 50)
          r.outline(160, 20, 120, 80, r: 50, g: 200, b: 50)
          r.line(20, 130, 280, 180, r: 50, g: 50, b: 200)
        end

        w, h = vp.renderer.output_size
        pixels = vp.renderer.read_pixels
        raise "read_pixels size mismatch" unless pixels.bytesize == w * h * 4

        app.after(500) { vp.destroy; app.destroy }
        app.mainloop
        puts "Release smoke test passed (teek #{Teek::VERSION}, teek-sdl2 #{Teek::SDL2::VERSION})"
      RUBY

      smoke_file = File.join(tmpdir, 'smoke.rb')
      File.write(smoke_file, smoke)
      sh "GEM_HOME=#{gem_home} GEM_PATH=#{gem_home} ruby #{smoke_file}"
    end
  end
end

# Docker tasks for local testing and CI
namespace :docker do
  DOCKERFILE = 'Dockerfile.ci-test'
  DOCKER_LABEL = 'project=teek'

  def docker_image_name(tcl_version, ruby_version = nil)
    ruby_version ||= ruby_version_from_env
    base = tcl_version == '8.6' ? 'teek-ci-test-8' : 'teek-ci-test-9'
    ruby_version == '4.0' ? base : "#{base}-ruby#{ruby_version}"
  end

  def warn_if_containers_running(image_name)
    running = `docker ps --filter ancestor=#{image_name} --format '{{.ID}} {{.Status}}'`.strip
    return if running.empty?
    count = running.lines.size
    warn "\n⚠  #{count} container(s) already running on #{image_name}:"
    running.lines.each { |l| warn "   #{l.strip}" }
    warn "   This usually means a previous test suite is stuck. Consider: docker kill $(docker ps -q --filter ancestor=#{image_name})\n"
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

    warn_if_containers_running(image_name)

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

  desc "Force rebuild Docker image (no cache)"
  task :rebuild do
    tcl_version = tcl_version_from_env
    ruby_version = ruby_version_from_env
    image_name = docker_image_name(tcl_version, ruby_version)

    puts "Rebuilding Docker image (no cache) for Ruby #{ruby_version}, Tcl #{tcl_version}..."
    cmd = "docker build -f #{DOCKERFILE} --no-cache"
    cmd += " --label #{DOCKER_LABEL}"
    cmd += " --build-arg RUBY_VERSION=#{ruby_version}"
    cmd += " --build-arg TCL_VERSION=#{tcl_version}"
    cmd += " -t #{image_name} ."

    sh cmd
  end

  desc "Remove dangling Docker images from teek builds"
  task :prune do
    sh "docker image prune -f --filter label=#{DOCKER_LABEL}"
  end

  Rake::Task['docker:test'].enhance { Rake::Task['docker:prune'].invoke }

  namespace :test do
    desc "Run teek-sdl2 tests in Docker"
    task sdl2: :build do
      tcl_version = tcl_version_from_env
      ruby_version = ruby_version_from_env
      image_name = docker_image_name(tcl_version, ruby_version)

      require 'fileutils'
      FileUtils.mkdir_p('coverage')

      warn_if_containers_running(image_name)

      puts "Running teek-sdl2 tests in Docker (Ruby #{ruby_version}, Tcl #{tcl_version})..."
      cmd = "docker run --rm --init"
      cmd += " -v #{Dir.pwd}/coverage:/app/coverage"
      cmd += " -v #{Dir.pwd}/screenshots:/app/screenshots"
      cmd += " -e TCL_VERSION=#{tcl_version}"
      if ENV['COVERAGE'] == '1'
        cmd += " -e COVERAGE=1"
        cmd += " -e COVERAGE_NAME=#{ENV['COVERAGE_NAME'] || 'sdl2'}"
      end
      cmd += " #{image_name}"
      cmd += " xvfb-run -a bundle exec rake sdl2:test"

      sh cmd
    end

    desc "Run teek-mgba tests in Docker"
    task mgba: :build do
      tcl_version = tcl_version_from_env
      ruby_version = ruby_version_from_env
      image_name = docker_image_name(tcl_version, ruby_version)

      require 'fileutils'
      FileUtils.mkdir_p('coverage')

      warn_if_containers_running(image_name)

      puts "Running teek-mgba tests in Docker (Ruby #{ruby_version}, Tcl #{tcl_version})..."
      cmd = "docker run --rm --init"
      cmd += " -v #{Dir.pwd}/coverage:/app/coverage"
      cmd += " -e TCL_VERSION=#{tcl_version}"
      if ENV['COVERAGE'] == '1'
        cmd += " -e COVERAGE=1"
        cmd += " -e COVERAGE_NAME=#{ENV['COVERAGE_NAME'] || 'mgba'}"
      end
      cmd += " #{image_name}"
      cmd += " xvfb-run -a bundle exec rake mgba:test"

      sh cmd
    end

    desc "Run all tests (teek + teek-sdl2 + teek-mgba) with coverage and generate report"
    task all: 'docker:build' do
      tcl_version = tcl_version_from_env
      ruby_version = ruby_version_from_env
      image_name = docker_image_name(tcl_version, ruby_version)

      require 'fileutils'
      FileUtils.rm_rf('coverage')
      FileUtils.mkdir_p('coverage/results')

      # Run both test suites with coverage enabled and distinct COVERAGE_NAMEs
      ENV['COVERAGE'] = '1'

      ENV['COVERAGE_NAME'] = 'main'
      Rake::Task['docker:test'].invoke

      ENV['COVERAGE_NAME'] = 'sdl2'
      Rake::Task['docker:test:sdl2'].reenable
      Rake::Task['docker:build'].reenable
      Rake::Task['docker:test:sdl2'].invoke

      # Collate inside Docker (paths match /app/lib/...)
      puts "Collating coverage results..."
      cmd = "docker run --rm --init"
      cmd += " -v #{Dir.pwd}/coverage:/app/coverage"
      cmd += " #{image_name}"
      cmd += " bundle exec rake coverage:collate"

      sh cmd

      # Generate per-method coverage (runs locally, just needs Prism)
      puts "Generating per-method coverage..."
      Rake::Task['docs:method_coverage'].invoke

      puts "Coverage report: coverage/index.html"
    end
  end

  namespace :screenshots do
    desc "Bless linux screenshots inside Docker (copies unverified/ to blessed/)"
    task bless: :build do
      ruby_version = ruby_version_from_env
      tcl_version = tcl_version_from_env
      image_name = docker_image_name(tcl_version, ruby_version)

      cmd = "docker run --rm --init"
      cmd += " -v #{Dir.pwd}/screenshots:/app/screenshots"
      cmd += " #{image_name}"
      cmd += " bundle exec rake screenshots:bless"

      sh cmd
    end
  end

  # Scan sample files for # teek-record magic comment
  # Format: # teek-record: title=My Demo, codec=vp9
  def find_recordable_samples
    Dir['sample/**/*.rb', 'teek-sdl2/sample/**/*.rb'].filter_map do |path|
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
      env += " AUDIO=1" if demo['audio']
      sh "#{env} ./scripts/docker-record.sh #{sample}"
    end

    puts "Done! Recordings in: recordings/"
  end

  Rake::Task['docker:record_demos'].enhance { Rake::Task['docker:prune'].invoke }
end
