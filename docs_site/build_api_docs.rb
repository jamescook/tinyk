#!/usr/bin/env ruby
# frozen_string_literal: true

# ============================================================================
# API Documentation Builder
# ============================================================================
#
# PIPELINE:
#   1. YARD parses Ruby source files
#   2. vendor/yard-json outputs JSON (with markdown in docstrings)
#   3. THIS SCRIPT (build_api_docs.rb) transforms JSON → HTML via ERB templates
#   4. Jekyll builds the final site from docs_site/
#
# TO MODIFY DOC OUTPUT:
#   - Templates are in scripts/templates/*.html.erb
#   - JSON generation: Edit vendor/yard-json/templates/default/fulldoc/json/setup.rb
#
# DO NOT edit vendor/yard-json/.../markdown/setup.rb for doc changes -
# that's only used if generating standalone markdown files, not our JSON→HTML flow.
#
# USAGE:
#   ruby scripts/build_api_docs.rb           # Generate HTML in docs_site/_api/
#   cd docs_site && bundle exec jekyll build # Build full site
#   cd docs_site && bundle exec jekyll serve # Preview locally
#
# ============================================================================

require "json"
require "erb"
require "fileutils"
require "cgi"
require "kramdown"

# Helper for building navigation tree
module NavHelper
  # Build a nested hash tree from flat paths like ["Tk", "Tk::Button", "Tk::Canvas"]
  def self.build_tree(paths)
    root = { children: {}, path: nil, type: nil }

    paths.each do |path, meta|
      parts = path.split('::')
      current = root

      parts.each_with_index do |part, i|
        full_path = parts[0..i].join('::')
        current[:children][part] ||= { children: {}, path: full_path, type: nil }
        current = current[:children][part]
      end
      current[:type] = meta[:type]
    end

    root[:children]
  end

  # Sort tree: modules first, then classes, then alphabetically
  def self.sort_tree(tree)
    tree.sort_by do |name, node|
      type_order = node[:type] == 'module' ? 0 : 1
      [type_order, name.downcase]
    end.to_h
  end
end

class APIDocBuilder
  TEMPLATES_DIR = File.expand_path('templates', __dir__)

  def initialize(json_dir:, output_dir:)
    @json_dir = json_dir
    @output_dir = output_dir
    @nav_order = 0
    @children = Hash.new { |h, k| h[k] = [] }
    @templates = {}
    # Inverse indexes: module/class -> who uses it
    @included_by = Hash.new { |h, k| h[k] = [] }
    @extended_by = Hash.new { |h, k| h[k] = [] }
    @inherited_by = Hash.new { |h, k| h[k] = [] }
    # Method coverage data (nil if unavailable)
    @method_coverage = load_method_coverage
    # Git info for GitHub links
    @github_repo = detect_github_repo
    @git_commit = `git rev-parse HEAD 2>/dev/null`.strip
    @git_commit = 'main' if @git_commit.empty?
  end

  def load_method_coverage
    coverage_path = File.join(File.dirname(@output_dir), '..', 'coverage', 'method_coverage.json')
    return nil unless File.exist?(coverage_path)

    puts "Loading method coverage data"
    JSON.parse(File.read(coverage_path))
  rescue => e
    warn "Failed to load method coverage: #{e.message}"
    nil
  end

  def detect_github_repo
    remote = `git remote get-url origin 2>/dev/null`.strip
    return nil if remote.empty?

    # Handle git@github.com:user/repo.git or https://github.com/user/repo.git
    if remote =~ %r{github\.com[:/](.+?)(?:\.git)?$}
      "https://github.com/#{$1.sub(/\.git$/, '')}"
    else
      nil
    end
  end

  # Returns coverage level: :high (>=80), :medium (50-79.9), :low (<50), or nil
  def coverage_level(percent)
    return nil if percent.nil?
    if percent >= 80
      :high
    elsif percent >= 50
      :medium
    else
      :low
    end
  end

  def template(name)
    @templates[name] ||= ERB.new(File.read(File.join(TEMPLATES_DIR, "#{name}.html.erb")), trim_mode: '-')
  end

  def partial(name)
    @templates[name] ||= ERB.new(File.read(File.join(TEMPLATES_DIR, "#{name}.erb")), trim_mode: '-')
    @templates[name].result(binding)
  end

  def build
    FileUtils.rm_rf(@output_dir)
    FileUtils.mkdir_p(@output_dir)

    # First pass: identify parent-child relationships, collect metadata, build inverse indexes
    @all_paths = {}
    json_files.each do |file|
      doc = JSON.parse(File.read(file))
      path = doc['path']
      @all_paths[path] = { type: doc['type'] }

      parts = path.split('::')
      if parts.size > 1
        parent = parts[0..-2].join('::')
        @children[parent] << parts.last
      end

      # Build inverse indexes
      doc['instance_mixins']&.each { |m| @included_by[m] << path }
      doc['class_mixins']&.each { |m| @extended_by[m] << path }
      @inherited_by[doc['superclass']] << path if doc['superclass']
    end

    # Generate navigation include
    generate_nav

    # Generate search index
    generate_search_index

    # Generate index page
    generate_index

    # Generate stats include
    generate_stats

    # Generate stubs for namespace-only nodes (appear in nav but have no JSON)
    stub_count = generate_namespace_stubs

    # Second pass: generate HTML
    json_files.each do |file|
      process_file(file)
    end

    puts "Generated #{json_files.size + stub_count + 1} API doc pages in #{@output_dir}"
  end

  def generate_index
    content = <<~HTML
---
layout: default
title: API Reference
nav_order: 2
has_children: true
---

<h1>API Reference</h1>

<p>Browse the Ruby/Tk class and module documentation.</p>
    HTML

    File.write(File.join(@output_dir, 'index.html'), content)
  end

  def generate_stats
    modules = 0
    classes = 0
    methods = 0

    json_files.each do |file|
      doc = JSON.parse(File.read(file))
      if doc['type'] == 'module'
        modules += 1
      else
        classes += 1
      end
      methods += (doc['class_methods']&.size || 0)
      methods += (doc['instance_methods']&.size || 0)
    end

    require_relative '../lib/teek/version'
    version = Teek::VERSION

    includes_dir = File.join(File.dirname(@output_dir), '_includes')
    content = <<~HTML
      <span>v#{version}</span>
      <span>#{modules} modules</span>
      <span>#{classes} classes</span>
      <span>#{methods} methods</span>
    HTML
    File.write(File.join(includes_dir, 'stats.html'), content.strip)

    puts "Generated stats: v#{version}, #{modules} modules, #{classes} classes, #{methods} methods"
  end

  def generate_namespace_stubs
    # Find paths that are implied parents but have no JSON file
    implied = Set.new
    @all_paths.each_key do |path|
      parts = path.split('::')
      (1...parts.size).each do |i|
        ancestor = parts[0...i].join('::')
        implied << ancestor unless @all_paths.key?(ancestor)
      end
    end

    implied.each do |path|
      @all_paths[path] = { type: 'module' }
      parts = path.split('::')
      if parts.size > 1
        parent = parts[0..-2].join('::')
        @children[parent] << parts.last unless @children[parent].include?(parts.last)
      end
    end

    # Generate stub pages
    implied.each do |path|
      parts = path.split('::')
      @parent = parts.size > 1 ? parts[0..-2].join('::') : nil
      @has_children = @children[path].any?
      @title = path

      children_list = @children[path].sort.map do |child_name|
        full_path = "#{path}::#{child_name}"
        child_type = @all_paths[full_path]&.[](:type) || 'class'
        { name: child_name, url: full_path.gsub('::', '/'), type: child_type }
      end
      @children_modules = children_list.select { |c| c[:type] == 'module' }
      @children_classes = children_list.select { |c| c[:type] != 'module' }

      @doc = {
        'path' => path,
        'type' => 'module',
        'docstring' => '',
        'superclass' => nil,
        'class_mixins' => [],
        'instance_mixins' => [],
        'class_methods' => [],
        'instance_methods' => [],
        'attributes' => [],
        'inherited_methods' => {}
      }

      @tpl_included_by = @included_by[path].sort
      @tpl_extended_by = @extended_by[path].sort
      @tpl_inherited_by = @inherited_by[path].sort
      @class_coverage = nil
      @class_coverage_total = nil
      @class_coverage_level = nil

      @nav_order += 1

      content = template('page').result(binding)
      rel_path = path.gsub('::', '/') + '.html'
      output_path = File.join(@output_dir, rel_path)
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, content)
    end

    puts "Generated #{implied.size} namespace stub(s): #{implied.to_a.join(', ')}" if implied.any?
    implied.size
  end

  def generate_nav
    nav_tree = NavHelper.build_tree(@all_paths)
    nav_tree = NavHelper.sort_tree(nav_tree)

    includes_dir = File.join(File.dirname(@output_dir), '_includes')
    FileUtils.mkdir_p(includes_dir)

    content = template('nav').result(binding)
    File.write(File.join(includes_dir, 'nav.html'), content)

    puts "Generated navigation include: #{includes_dir}/nav.html"
  end

  def generate_search_index
    search_data = {}
    idx = 0

    json_files.each do |file|
      doc = JSON.parse(File.read(file))
      url = "/api/#{doc['path'].gsub('::', '/')}/"

      # Separate fields for weighted search
      method_names = []
      docstrings = [doc['docstring'].to_s]

      (doc['class_methods'] || []).each do |m|
        method_names << m['name']
        docstrings << m['docstring'].to_s
      end
      (doc['instance_methods'] || []).each do |m|
        method_names << m['name']
        docstrings << m['docstring'].to_s
      end

      # Include path parts in content so entries are searchable even without docstrings
      # Split path on :: so "Tk::BWidget::DragSite" becomes searchable as "DragSite"
      path_parts = doc['path'].split('::').join(' ')
      content_text = ([path_parts] + docstrings).join(' ').gsub(/\s+/, ' ').strip

      search_data[idx.to_s] = {
        title: doc['path'],
        type: doc['type'],
        url: url,
        methods: method_names.join(' '),
        content: content_text[0, 500]
      }
      idx += 1
    end

    js_dir = File.join(File.dirname(@output_dir), 'assets', 'js')
    FileUtils.mkdir_p(js_dir)
    File.write(File.join(js_dir, 'search-data.json'), JSON.pretty_generate(search_data))

    puts "Generated search index: #{js_dir}/search-data.json (#{idx} entries)"
  end

  def render_nav_tree(tree, depth = 0)
    sorted = NavHelper.sort_tree(tree)
    result = []
    count = sorted.size

    sorted.each_with_index do |(name, node), idx|
      url_path = node[:path].gsub('::', '/')
      children = node[:children]
      indent = '  ' * depth
      is_last = (idx == count - 1)

      result << template('nav_item').result(binding)
    end

    result.join
  end

  private

  def json_files
    @json_files ||= Dir.glob(File.join(@json_dir, "**/*.json")).sort
  end

  def process_file(json_file)
    @doc = JSON.parse(File.read(json_file))

    rel_path = json_file.sub(@json_dir, '').sub(/^\//, '').sub('.json', '.html')
    output_path = File.join(@output_dir, rel_path)

    parts = @doc['path'].split('::')
    @parent = parts.size > 1 ? parts[0..-2].join('::') : nil
    @title = @doc['path']
    @has_children = @children[@doc['path']].any?

    # Build children list with names, URLs, and types
    children_list = @children[@doc['path']].sort.map do |child_name|
      full_path = "#{@doc['path']}::#{child_name}"
      child_type = @all_paths[full_path]&.[](:type) || 'class'
      { name: child_name, url: full_path.gsub('::', '/'), type: child_type }
    end
    @children_modules = children_list.select { |c| c[:type] == 'module' }
    @children_classes = children_list.select { |c| c[:type] != 'module' }

    # Inverse relationships for this doc
    @tpl_included_by = @included_by[@doc['path']].sort
    @tpl_extended_by = @extended_by[@doc['path']].sort
    @tpl_inherited_by = @inherited_by[@doc['path']].sort

    # Coverage data for this class/module
    @class_coverage = @method_coverage&.dig(@doc['path'])
    @class_coverage_total = @class_coverage&.dig('total')
    @class_coverage_level = coverage_level(@class_coverage_total)

    @nav_order += 1

    content = template('page').result(binding)

    FileUtils.mkdir_p(File.dirname(output_path))
    File.write(output_path, content)
  end

  def render_method(method, class_coverage: nil)
    # Look up method coverage - [percent, lines_str] format
    method_cov = nil
    method_cov_lines = nil
    if class_coverage
      scope_key = method['scope'] == 'class' ? 'class_methods' : 'instance_methods'
      cov_data = class_coverage.dig(scope_key, method['name'])
      if cov_data
        method_cov, method_cov_lines = cov_data
      end
    end
    method_coverage_level = coverage_level(method_cov)
    github_url = method_github_url(method)

    template('method').result(binding)
  end

  def method_github_url(method)
    return nil unless @github_repo && method['source_file'] && method['source_line']

    file = method['source_file']
    start_line = method['source_line']
    end_line = method['source_lines'] ? start_line + method['source_lines'] - 1 : start_line

    "#{@github_repo}/blob/#{@git_commit}/#{file}#L#{start_line}-L#{end_line}"
  end

  def render_attribute(attr)
    template('attribute').result(binding)
  end

  def render_tags(tags)
    template('tags').result(binding)
  end

  def h(str)
    CGI.escapeHTML(str.to_s)
  end

  # HTML-escape, then convert YARD +code+ markup to <code> tags.
  def ht(str)
    h(str).gsub(/\+([^+]+)\+/, '<code>\1</code>')
  end

  def md(text, current_path: nil)
    return '' if text.nil? || text.to_s.strip.empty?
    # Convert YARD +code+ to markdown `code` before Kramdown processing
    converted = text.to_s.gsub(/\+([^+]+)\+/, '`\1`')
    # Convert YARD link syntax to markdown links before Kramdown processing
    converted = convert_yard_links(converted, current_path)
    Kramdown::Document.new(converted).to_html
  end

  # Convert YARD {#method}, {ClassName}, {Class#method} syntax to markdown links
  def convert_yard_links(text, current_path)
    text.gsub(/\{([^}]+)\}/) do |match|
      ref = $1.strip
      convert_single_yard_link(ref, current_path)
    end
  end

  def convert_single_yard_link(ref, current_path)
    # Kramdown attribute syntax for disabling Turbo on in-page anchors
    turbo_off = '{: data-turbo="false"}'

    case ref
    when /^#(\w+)$/
      # {#method_name} -> instance method on same page
      method_name = $1
      "[`##{method_name}`](#method-#{method_name})#{turbo_off}"
    when /^\.(\w+)$/
      # {.method_name} -> class method on same page
      method_name = $1
      "[`.#{method_name}`](#class-method-#{method_name})#{turbo_off}"
    when /^([A-Z][\w:]+)#(\w+)$/
      # {ClassName#method} -> instance method on another page
      class_name, method_name = $1, $2
      url_path = class_name.gsub('::', '/')
      "[`#{class_name}##{method_name}`](/api/#{url_path}/#method-#{method_name})"
    when /^([A-Z][\w:]+)\.(\w+)$/
      # {ClassName.method} -> class method on another page
      class_name, method_name = $1, $2
      url_path = class_name.gsub('::', '/')
      "[`#{class_name}.#{method_name}`](/api/#{url_path}/#class-method-#{method_name})"
    when /^([A-Z][\w:]+)$/
      # {ClassName} or {Module::Class} -> link to that page
      class_name = $1
      url_path = class_name.gsub('::', '/')
      "[`#{class_name}`](/api/#{url_path}/)"
    else
      # Unknown format, leave as code
      "`#{ref}`"
    end
  end

  def method_anchor(method)
    scope = method['scope'] == 'class' ? 'class-method' : 'method'
    "#{scope}-#{method['name']}"
  end

  def render_see_link(see)
    case see['type']
    when 'url'
      "<a href=\"#{h see['url']}\" target=\"_blank\" rel=\"noopener\">#{h see['url']}</a>"
    when 'instance_method'
      # #method_name -> link to #method-method_name on same page
      method_name = see['ref'].sub(/^#/, '')
      text = see['text'].to_s.empty? ? '' : " #{h see['text']}"
      "<a href=\"#method-#{h method_name}\" data-turbo=\"false\"><code>#{h see['ref']}</code></a>#{text}"
    when 'class_method'
      # .method_name -> link to #class-method-method_name on same page
      method_name = see['ref'].sub(/^\./, '')
      text = see['text'].to_s.empty? ? '' : " #{h see['text']}"
      "<a href=\"#class-method-#{h method_name}\" data-turbo=\"false\"><code>#{h see['ref']}</code></a>#{text}"
    when 'external_method'
      # ClassName#method -> link to ClassName.html#method-method_name
      if see['ref'] =~ /^(.+)#(.+)$/
        class_name, method_name = $1, $2
        text = see['text'].to_s.empty? ? '' : " #{h see['text']}"
        "<a href=\"#{h class_name}.html#method-#{h method_name}\" data-turbo=\"false\"><code>#{h see['ref']}</code></a>#{text}"
      else
        "<code>#{h see['ref']}</code> #{h see['text']}"
      end
    when 'external_class_method'
      # ClassName.method -> link to ClassName.html#class-method-method_name
      class_name = see['class_name']
      method_name = see['method_name']
      text = see['text'].to_s.empty? ? '' : " #{h see['text']}"
      "<a href=\"#{h class_name}.html#class-method-#{h method_name}\" data-turbo=\"false\"><code>#{h see['ref']}</code></a>#{text}"
    when 'reference'
      # Class or module name -> link to that page
      text = see['text'].to_s.empty? ? '' : " #{h see['text']}"
      "<a href=\"#{h see['ref']}.html\"><code>#{h see['ref']}</code></a>#{text}"
    else
      "<code>#{h see['ref']}</code> #{h see['text']}"
    end
  end
end

# Main
if __FILE__ == $0
  project_root = File.expand_path('../..', __FILE__)
  json_dir = File.join(project_root, 'doc')
  output_dir = File.join(project_root, 'docs_site', '_api')

  builder = APIDocBuilder.new(json_dir: json_dir, output_dir: output_dir)
  builder.build
end
