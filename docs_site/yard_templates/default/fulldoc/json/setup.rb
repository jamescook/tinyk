# frozen_string_literal: true

require "json"

include Helpers::ModuleHelper

def init
  options.objects = objects = run_verifier(options.objects)
  options.delete(:objects)
  options.delete(:files)
  options.serializer.extension = "json"

  objects.each do |object|
    next if object.name == :root
    next if api_private?(object)

    begin
      Templates::Engine.with_serializer(object, options.serializer) { serialize(object) }
    rescue => e
      path = options.serializer.serialized_path(object)
      log.error "Exception occurred while generating '#{path}'"
      log.backtrace(e)
    end
  end
end

def serialize(object)
  # Check for @official tag (URL to official Tcl/Tk docs)
  official_tag = object.tags.find { |t| t.tag_name == "official" }
  official_url = official_tag&.text

  data = {
    name: object.name.to_s,
    path: object.path,
    type: object.type.to_s,
    title: format_object_title(object),
    docstring: object.docstring.to_s,
    tags: serialize_tags(object.tags, object),
    official_url: official_url,
  }.compact

  # Inheritance
  if object.is_a?(YARD::CodeObjects::ClassObject) && object.superclass
    data[:superclass] = object.superclass.to_s
  end

  # Mixins
  [:class, :instance].each do |scope|
    mixins = run_verifier(object.mixins(scope))
    if mixins.any?
      data[:"#{scope}_mixins"] = mixins.map { |m| m.path }
    end
  end

  # Class methods
  class_methods = public_class_methods(object)
  if class_methods.any?
    data[:class_methods] = class_methods.map { |m| serialize_method(m, object) }
  end

  # Instance methods
  instance_methods = public_instance_methods(object)
  if instance_methods.any?
    data[:instance_methods] = instance_methods.map { |m| serialize_method(m, object) }
  end

  # Attributes
  attrs = attr_listing(object)
  if attrs.any?
    data[:attributes] = attrs.map { |a| serialize_attribute(a, object) }
  end

  # Inherited/included methods
  inherited = inherited_methods(object)
  if inherited.any?
    data[:inherited_methods] = inherited
  end

  JSON.pretty_generate(data)
end

def serialize_method(method, parent_object)
  source = method.source rescue nil
  source = nil if source.to_s.empty?
  source_lines = source ? source.lines.count : nil
  source_language = "ruby"
  source_file = method.file
  source_line = method.line

  # If no Ruby source (e.g. @!method directive), look for C source
  if source.nil?
    c_src = find_c_source(method)
    if c_src
      source = c_src[:source]
      source_lines = c_src[:lines]
      source_file = c_src[:file]
      source_line = c_src[:line]
      source_language = "c"
    end
  end

  {
    name: method.name.to_s,
    signature: method_signature(method),
    scope: method.scope.to_s,
    group: method.group,
    docstring: method.docstring.to_s,
    tags: serialize_tags(method.tags, parent_object),
    parameters: method.parameters.map { |p| { name: p[0].to_s, default: p[1] } },
    has_content: !method.docstring.empty? || method.tags.any?,
    source_file: source_file,
    source_line: source_line,
    source_lines: source_lines,
    source: source,
    source_language: source_language
  }
end

def serialize_attribute(attr, parent_object)
  {
    name: attr.name.to_s,
    reader: attr.reader?,
    writer: attr.writer?,
    docstring: attr.docstring.to_s,
    tags: serialize_tags(attr.tags, parent_object),
    has_content: !attr.docstring.empty? || attr.tags.any?
  }
end

def serialize_tags(tags, context_object)
  regular = []
  params = []
  returns = []
  options = []
  examples = []
  see_also = []
  official_docs_url = nil
  official_docs_text = nil

  tags.each do |tag|
    case tag.tag_name
    when "param"
      params << {
        name: tag.name,
        types: tag.types,
        text: tag.text
      }
    when "return"
      returns << {
        types: tag.types,
        text: tag.text
      }
    when "example"
      examples << {
        title: tag.name,
        code: tag.text
      }
    when "see"
      see_tag = serialize_see_tag(tag, context_object)
      next unless see_tag

      # Extract official Tcl/Tk docs to separate field
      if see_tag[:type] == "official_docs"
        official_docs_url = see_tag[:url]
        official_docs_text = see_tag[:text]
      else
        see_also << see_tag
      end
    when "option"
      opt = tag.pair
      options << {
        name: opt.name,
        types: opt.types,
        text: opt.text
      }
    else
      regular << {
        tag: tag.tag_name,
        name: tag.name,
        types: tag.types,
        text: tag.text
      }
    end
  end

  result = {}
  result[:regular] = regular if regular.any?
  result[:params] = params if params.any?
  result[:returns] = returns if returns.any?
  result[:options] = options if options.any?
  result[:examples] = examples if examples.any?
  result[:see_also] = see_also if see_also.any?
  if official_docs_url
    result[:official_docs_url] = official_docs_url
    result[:official_docs_text] = official_docs_text if official_docs_text
  end
  result
end

def serialize_see_tag(tag, context_object)
  ref = tag.name || tag.text
  return nil if ref.nil? || ref.empty?

  context_name = context_object.name.to_s
  context_path = context_object.path

  if ref =~ /\Ahttps?:\/\//
    # Check if official Tcl/Tk docs
    if ref.include?('tcl.tk') || ref.include?('tcl-lang.org')
      { type: "official_docs", url: ref, text: tag.text }
    else
      { type: "url", url: ref, text: tag.text }
    end
  elsif ref.start_with?('#')
    # #method_name -> instance method on same page
    { type: "instance_method", ref: ref, text: tag.text }
  elsif ref.start_with?('.')
    # .method_name -> class method on same page
    { type: "class_method", ref: ref, text: tag.text }
  elsif ref =~ /\A([A-Z]\w*)\.(\w+)\z/
    # ClassName.method - check if ClassName matches current context
    class_name, method_name = $1, $2
    if class_name == context_name || "#{context_path}".end_with?("::#{class_name}") || context_path == class_name
      # Same class - in-page class method
      { type: "class_method", ref: ".#{method_name}", text: tag.text }
    else
      { type: "external_class_method", ref: ref, class_name: class_name, method_name: method_name, text: tag.text }
    end
  elsif ref =~ /\A([A-Z][\w:]*)\#(\w+)\z/
    # ClassName#method - check if ClassName matches current context
    class_name, method_name = $1, $2
    if class_name == context_name || context_path.end_with?("::#{class_name}") || context_path == class_name
      # Same class - in-page instance method
      { type: "instance_method", ref: "##{method_name}", text: tag.text }
    else
      { type: "external_method", ref: ref, text: tag.text }
    end
  else
    { type: "reference", ref: ref, text: tag.text }
  end
end

def method_signature(method)
  params = method.parameters.map do |p|
    if p[1]
      "#{p[0]} #{p[1]}"
    else
      p[0].to_s
    end
  end.join(", ")

  if params.empty?
    method.name.to_s
  else
    "#{method.name}(#{params})"
  end
end

def public_method_list(object)
  # Filter to only methods defined directly in this object's namespace
  # (not from extended/included modules)
  prune_method_listing(
    object.meths(inherited: false, included: false, visibility: [:public]),
    included: false
  ).select { |m| m.namespace == object }.sort_by { |m| m.name.to_s }
end

def public_class_methods(object)
  public_method_list(object).select { |o| o.scope == :class }
end

def public_instance_methods(object)
  public_method_list(object).select { |o| o.scope == :instance }
end

# Get inherited/included methods grouped by source
def inherited_methods(object)
  inherited = {}

  # Get all public methods including inherited
  all_meths = object.meths(inherited: true, included: true, visibility: [:public])

  # Get methods defined directly on this object
  direct = public_method_list(object).map(&:name)

  all_meths.each do |m|
    next if direct.include?(m.name)
    next if m.namespace == object
    next unless m.namespace

    source = m.namespace.path
    inherited[source] ||= { class_methods: [], instance_methods: [] }

    if m.scope == :class
      inherited[source][:class_methods] << m.name.to_s
    else
      inherited[source][:instance_methods] << m.name.to_s
    end
  end

  # Sort method names and convert to final format
  inherited.transform_values do |v|
    v[:class_methods].sort!
    v[:instance_methods].sort!
    v
  end
end

def attr_listing(object)
  attrs = []
  object.inheritance_tree(true).each do |superclass|
    next if superclass.is_a?(YARD::CodeObjects::Proxy)
    next if !options.embed_mixins.empty? && !options.embed_mixins_match?(superclass)
    %i[class instance].each do |scope|
      superclass.attributes[scope].each do |_name, rw|
        attr = prune_method_listing([rw[:read], rw[:write]].compact, false).first
        attrs << attr if attr
      end
    end
    break if options.embed_mixins.empty?
  end
  attrs.sort_by { |o| [o.scope.to_s, o.name.to_s.downcase] }
end

# Check if object has @api private tag
def api_private?(object)
  object.tags.any? { |t| t.tag_name == "api" && t.text == "private" }
end

# ── C source extraction for @!method directives ──────────────────────────

# Lazily build a map of Ruby method names → C function names from all .c files.
# Returns { "ClassName" => { "method_name:scope" => { func:, file:, abs_file: } } }
def c_source_map
  @c_source_map ||= build_c_source_map
end

def build_c_source_map
  map = {}

  c_files = Dir.glob([
    File.join(Dir.pwd, 'ext', '**', '*.c'),
    File.join(Dir.pwd, 'teek-sdl2', 'ext', '**', '*.c')
  ])

  # First pass: build global C-variable → Ruby-name mapping across all files
  # (e.g. mTeekSDL2 is defined in teek_sdl2.c but used in sdl2mixer.c)
  vars = {}
  c_files.each do |abs_file|
    content = File.read(abs_file)
    content.scan(/(\w+)\s*=\s*rb_define_(?:module|class)(?:_under)?\s*\([^"]*"(\w+)"/) do |var, name|
      vars[var] = name
    end
  end

  # Second pass: map rb_define_method calls to C functions
  c_files.each do |abs_file|
    content = File.read(abs_file)
    rel_file = abs_file.sub("#{Dir.pwd}/", '')

    # Instance methods: rb_define_method(cVar, "name", c_func, argc)
    content.scan(/rb_define_method\s*\(\s*(\w+)\s*,\s*"([^"]+)"\s*,\s*(\w+)/) do |cvar, ruby_name, c_func|
      class_name = vars[cvar] || cvar
      map[class_name] ||= {}
      map[class_name]["#{ruby_name}:instance"] = { func: c_func, file: rel_file, abs_file: abs_file }
    end

    # Singleton/module methods: rb_define_singleton_method or rb_define_module_function
    content.scan(/rb_define_(?:singleton_method|module_function)\s*\(\s*(\w+)\s*,\s*"([^"]+)"\s*,\s*(\w+)/) do |cvar, ruby_name, c_func|
      class_name = vars[cvar] || cvar
      map[class_name] ||= {}
      map[class_name]["#{ruby_name}:class"] = { func: c_func, file: rel_file, abs_file: abs_file }
    end
  end

  map
end

# Look up C source for a YARD method object. Returns nil or
# { source:, file:, line:, lines: }
def find_c_source(method)
  class_name = method.namespace.name.to_s
  key = "#{method.name}:#{method.scope}"

  entry = c_source_map.dig(class_name, key)
  return nil unless entry

  content = File.read(entry[:abs_file])
  extract_c_function(content, entry[:func], entry[:file])
end

# Extract a C function body by name. The codebase style is:
#   static VALUE
#   func_name(VALUE self, ...)
#   {
#       ...
#   }
def extract_c_function(content, func_name, rel_file)
  lines = content.lines

  # Find the line where the function name starts at column 0
  func_idx = nil
  lines.each_with_index do |line, idx|
    if line =~ /\A#{Regexp.escape(func_name)}\s*\(/
      func_idx = idx
      break
    end
  end
  return nil unless func_idx

  # Go backwards to capture the return type line (e.g. "static VALUE")
  start_idx = func_idx
  if func_idx > 0 && lines[func_idx - 1] =~ /\A\w/
    start_idx = func_idx - 1
  end

  # Find the opening brace
  brace_idx = nil
  (func_idx..lines.length - 1).each do |idx|
    if lines[idx].include?('{')
      brace_idx = idx
      break
    end
  end
  return nil unless brace_idx

  # Count braces to find the matching close
  depth = 0
  end_idx = nil
  (brace_idx..lines.length - 1).each do |idx|
    lines[idx].each_char do |c|
      depth += 1 if c == '{'
      depth -= 1 if c == '}'
    end
    if depth == 0
      end_idx = idx
      break
    end
  end
  return nil unless end_idx

  {
    source: lines[start_idx..end_idx].join,
    file: rel_file,
    line: start_idx + 1, # 1-based
    lines: end_idx - start_idx + 1
  }
end
