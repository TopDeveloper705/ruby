#!/usr/bin/env ruby
# frozen_string_literal: true

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('./Gemfile', __dir__)
require 'bundler/setup'

require 'etc'
require 'fiddle/import'
require 'set'

unless build_dir = ARGV.first
  abort "Usage: #{$0} BUILD_DIR"
end

if Fiddle::SIZEOF_VOIDP == 8
  arch_bits = 64
else
  arch_bits = 32
end

# Help ffi-clang find libclang
if arch_bits == 64
  # apt install libclang1
  ENV['LIBCLANG'] ||= Dir.glob("/lib/#{RUBY_PLATFORM}-gnu/libclang-*.so*").grep_v(/-cpp/).sort.last
else
  # apt install libclang1:i386
  ENV['LIBCLANG'] ||= Dir.glob("/lib/i386-linux-gnu/libclang-*.so*").sort.last
end
require 'ffi/clang'

class Node < Struct.new(
  :kind,
  :spelling,
  :type,
  :typedef_type,
  :bitwidth,
  :sizeof_type,
  :offsetof,
  :enum_value,
  :children,
  keyword_init: true,
)
end

# Parse a C header with ffi-clang and return Node objects.
# To ease the maintenance, ffi-clang should be used only inside this class.
class HeaderParser
  def initialize(header, cflags:)
    @translation_unit = FFI::Clang::Index.new.parse_translation_unit(header, cflags, [], {})
  end

  def parse
    parse_children(@translation_unit.cursor)
  end

  private

  def parse_children(cursor)
    children = []
    cursor.visit_children do |cursor, _parent|
      children << parse_cursor(cursor)
      next :continue
    end
    children
  end

  def parse_cursor(cursor)
    unless cursor.kind.start_with?('cursor_')
      raise "unexpected cursor kind: #{cursor.kind}"
    end
    kind = cursor.kind.to_s.delete_prefix('cursor_').to_sym
    children = parse_children(cursor)

    offsetof = {}
    if kind == :struct
      children.select { |c| c.kind == :field_decl }.each do |child|
        offsetof[child.spelling] = cursor.type.offsetof(child.spelling)
      end
    end

    sizeof_type = nil
    if %i[struct union].include?(kind)
      sizeof_type = cursor.type.sizeof
    end

    enum_value = nil
    if kind == :enum_constant_decl
      enum_value = cursor.enum_value
    end

    Node.new(
      kind: kind,
      spelling: cursor.spelling,
      type: cursor.type.spelling,
      typedef_type: cursor.typedef_type.spelling,
      bitwidth: cursor.bitwidth,
      sizeof_type: sizeof_type,
      offsetof: offsetof,
      enum_value: enum_value,
      children: children,
    )
  end
end

# Convert Node objects to a Ruby binding source.
class BindingGenerator
  BINDGEN_BEG = '### MJIT bindgen begin ###'
  BINDGEN_END = '### MJIT bindgen end ###'
  DEFAULTS = { '_Bool' => 'CType::Bool.new' }
  DEFAULTS.default_proc = proc { |_h, k| "CType::Stub.new(:#{k})" }

  attr_reader :src

  # @param src_path [String] Source path used for preamble/postamble
  # @param macros [Array<String>] Imported macros
  # @param enums [Hash{ Symbol => Array<String> }] Imported enum values
  # @param types [Array<String>] Imported types
  # @param ruby_fields [Hash{ Symbol => Array<String> }] Struct VALUE fields that are considered Ruby objects
  def initialize(src_path:, macros:, enums:, types:, ruby_fields:)
    @preamble, @postamble = split_ambles(src_path)
    @src = String.new
    @macros = macros.sort
    @enums = enums.transform_keys(&:to_s).transform_values(&:sort).sort.to_h
    @types = types.sort
    @ruby_fields = ruby_fields.transform_keys(&:to_s)
    @references = Set.new
  end

  def generate(_nodes)
    println @preamble

    # Define macros
    @macros.each do |macro|
      println "  def C.#{macro} = #{generate_macro(macro)}"
      println
    end

    print @postamble
  end

  # TODO: Remove this
  def legacy_generate(nodes)
    # TODO: Support nested declarations
    nodes_index = nodes.group_by(&:spelling).transform_values(&:last)

    println "require_relative 'c_type'"
    println
    println "module RubyVM::MJIT"

    # Define enum values
    @enums.each do |enum, values|
      values.each do |value|
        unless definition = generate_enum(nodes_index[enum], value)
          raise "Failed to generate enum value: #{value}"
        end
        println "  def C.#{value} = #{definition}"
        println
      end
    end

    # Define types
    @types.each do |type|
      unless definition = generate_node(nodes_index[type])
        raise "Failed to generate type: #{type}"
      end
      println "  def C.#{type}"
      println "@#{type} ||= #{definition}".gsub(/^/, "    ").chomp
      println "  end"
      println
    end

    # Leave a stub for types that are referenced but not targeted
    (@references - @types).each do |type|
      println "  def C.#{type} = #{DEFAULTS[type]}"
      println
    end

    chomp
    println "end"
  end

  private

  # Return code before BINDGEN_BEG and code after BINDGEN_END
  def split_ambles(src_path)
    lines = File.read(src_path).lines

    preamble_end = lines.index { |l| l.include?(BINDGEN_BEG) }
    raise "`#{BINDGEN_BEG}` was not found in '#{src_path}'" if preamble_end.nil?

    postamble_beg = lines.index { |l| l.include?(BINDGEN_END) }
    raise "`#{BINDGEN_END}` was not found in '#{src_path}'" if postamble_beg.nil?
    raise "`#{BINDGEN_BEG}` was found after `#{BINDGEN_END}`" if preamble_end >= postamble_beg

    return lines[0..preamble_end].join, lines[postamble_beg..-1].join
  end

  def generate_macro(macro)
    if macro.start_with?('USE_')
      "Primitive.cexpr! %q{ RBOOL(#{macro} != 0) }"
    else
      "Primitive.cexpr! %q{ INT2NUM(#{macro}) }"
    end
  end

  def generate_enum(node, value)
    case node
    in Node[kind: :enum_decl, children:]
      children.find { |c| c.spelling == value }&.enum_value
    in Node[kind: :typedef_decl, children: [child]]
      generate_enum(child, value)
    end
  end

  # Generate code from a node. Used for constructing a complex nested node.
  # @param node [Node]
  def generate_node(node)
    case node&.kind
    when :struct, :union
      # node.spelling is often empty for union, but we'd like to give it a name when it has one.
      buf = +"CType::#{node.kind.to_s.sub(/\A[a-z]/, &:upcase)}.new(\n"
      buf << "  \"#{node.spelling}\", #{node.sizeof_type},\n"
      node.children.each do |child|
        field_builder = proc do |field, type|
          if node.kind == :struct
            to_ruby = @ruby_fields.fetch(node.spelling, []).include?(field)
            "  #{field}: [#{node.offsetof.fetch(field)}, #{type}#{', true' if to_ruby}],\n"
          else
            "  #{field}: #{type},\n"
          end
        end

        case child
        # BitField is struct-specific. So it must be handled here.
        in Node[kind: :field_decl, spelling:, bitwidth:, children: [_grandchild]] if bitwidth > 0
          buf << field_builder.call(spelling, "CType::BitField.new(#{bitwidth}, #{node.offsetof.fetch(spelling) % 8})")
        # In most cases, we'd like to let generate_type handle the type unless it's "(unnamed ...)".
        in Node[kind: :field_decl, spelling:, type:] if !type.empty? && !type.match?(/\((unnamed|anonymous) [^)]+\)\z/)
          buf << field_builder.call(spelling, generate_type(type))
        # Lastly, "(unnamed ...)" struct and union are handled here, which are also struct-specific.
        in Node[kind: :field_decl, spelling:, children: [grandchild]]
          buf << field_builder.call(spelling, generate_node(grandchild).gsub(/^/, '  ').sub(/\A +/, ''))
        else # forward declarations are ignored
        end
      end
      buf << ")"
    when :typedef_decl
      case node.children
      in [child]
        generate_node(child)
      in [child, Node[kind: :integer_literal]]
        generate_node(child)
      in _ unless node.typedef_type.empty?
        generate_type(node.typedef_type)
      end
    when :enum_decl
      generate_type('int')
    when :type_ref
      generate_type(node.spelling)
    end
  end

  # Generate code from a type name. Used for resolving the name of a simple leaf node.
  # @param type [String]
  def generate_type(type)
    if type.match?(/\[\d+\]\z/)
      return "CType::Pointer.new { #{generate_type(type.sub!(/\[\d+\]\z/, ''))} }"
    end
    type = type.delete_suffix('const')
    if type.end_with?('*')
      return "CType::Pointer.new { #{generate_type(type.delete_suffix('*').rstrip)} }"
    end

    type = type.gsub(/((const|volatile) )+/, '').rstrip
    if type.start_with?(/(struct|union|enum) /)
      target = type.split(' ', 2).last
      push_target(target)
      "self.#{target}"
    else
      begin
        ctype = Fiddle::Importer.parse_ctype(type)
        "CType::Immediate.new(#{ctype})"
      rescue Fiddle::DLError
        push_target(type)
        "self.#{type}"
      end
    end
  end

  def print(str)
    @src << str
  end

  def println(str = "")
    @src << str << "\n"
  end

  def chomp
    @src.delete_suffix!("\n")
  end

  def rstrip!
    @src.rstrip!
  end

  def push_target(target)
    unless target.match?(/\A\w+\z/)
      raise "invalid target: #{target}"
    end
    @references << target
  end
end

src_dir = File.expand_path('../..', __dir__)
src_path = File.join(src_dir, 'mjit_c.rb')
build_dir = File.expand_path(build_dir)
cflags = [
  src_dir,
  build_dir,
  File.join(src_dir, 'include'),
  File.join(build_dir, ".ext/include/#{RUBY_PLATFORM}"),
].map { |dir| "-I#{dir}" }

nodes = HeaderParser.new(File.join(src_dir, 'mjit_compiler.h'), cflags: cflags).parse
generator = BindingGenerator.new(
  src_path: src_path,
  macros: %w[
    NOT_COMPILED_STACK_SIZE
    USE_LAZY_LOAD
    USE_RVARGC
    VM_CALL_KW_SPLAT
    VM_CALL_TAILCALL
  ],
  enums: {
    rb_method_type_t: %w[
      VM_METHOD_TYPE_CFUNC
      VM_METHOD_TYPE_ISEQ
    ],
    vm_call_flag_bits: %w[
      VM_CALL_KW_SPLAT_bit
      VM_CALL_TAILCALL_bit
    ],
  },
  types: %w[
    CALL_DATA
    IC
    IVC
    RB_BUILTIN
    VALUE
    compile_branch
    compile_status
    inlined_call_context
    iseq_inline_constant_cache
    iseq_inline_constant_cache_entry
    iseq_inline_iv_cache_entry
    iseq_inline_storage_entry
    mjit_options
    rb_builtin_function
    rb_call_data
    rb_callable_method_entry_struct
    rb_callcache
    rb_callinfo
    rb_cref_t
    rb_control_frame_t
    rb_execution_context_t
    rb_execution_context_struct
    rb_iseq_constant_body
    rb_iseq_location_t
    rb_iseq_struct
    rb_iseq_t
    rb_iv_index_tbl_entry
    rb_method_definition_struct
    rb_method_iseq_t
    rb_method_type_t
    rb_mjit_compile_info
    rb_mjit_unit
    rb_serial_t
  ],
  ruby_fields: {
    rb_iseq_location_struct: %w[
      base_label
      first_lineno
      label
      pathobj
    ]
  },
)
generator.generate(nodes)

File.write(src_path, generator.src)
