class ProtoTurf
  module ProtoText
    ParseInfo = Struct.new(:writer, :package, :message) do
      %i[write write_indent write_line writenl indent dedent].each do |method|
        define_method(method) do |*args|
          writer.send(method, *args)
        end
      end
    end

    class Writer < StringIO
      def initialize(...)
        super
        @indent = 0
      end

      def write_indent(str)
        @indent.times { write(" ") }
        write(str)
      end

      def write_line(line, nl = 1)
        write_indent(line)
        nl.times { writenl }
      end

      def writenl
        write("\n")
      end

      def indent
        @indent += 2
      end

      def dedent
        @indent -= 2
      end
    end

    class << self
      def fetch(message_name)
        name = message_name.start_with?(".") ? message_name[1..] : message_name
        Google::Protobuf::DescriptorPool.generated_pool.lookup(name)
      end

      def output(file_descriptor)
        writer = Writer.new
        info = ParseInfo.new(writer, file_descriptor.package)
        writer.write_line("syntax = \"#{file_descriptor.syntax}\";", 2)
        writer.write_line("package #{file_descriptor.package};")
        writer.writenl
        found = false
        file_descriptor.options.to_h.each do |name, value|
          found = true
          writer.write_line("option #{name} = #{value.to_json};")
        end
        writer.writenl if found

        found = false
        file_descriptor.dependency.each do |dependency|
          found = true
          writer.write_line("import \"#{dependency}\";")
        end
        writer.writenl if found

        writer.writenl if write_options(info, file_descriptor)
        writer.writenl if write_extensions(info, file_descriptor)

        file_descriptor.enum_type.each do |enum_type|
          write_enum(info, enum_type)
        end
        file_descriptor.message_type.each do |message_type|
          write_message(info, message_type)
        end
        file_descriptor.service.each do |service|
          write_service(info, service)
        end
        writer.string
      end

      def write_extensions(info, descriptor)
        descriptor.extension.each do |extension|
          info.write_line("extend #{extension.extendee[1..]} {")
          info.indent
          write_field(info, extension)
          info.dedent
          info.write_line("}")
        end
        descriptor.extension.any?
      end

      def write_reserved(writer, descriptor)
        reserved = descriptor.reserved_range.map do |range|
          (range.start == range.end - 1) ? range.start.to_s : "#{range.start} to #{range.end - 1}"
        end
        found = false
        if reserved.any?
          found = true
          writer.write_line("reserved #{reserved.join(", ")};")
        end
        if descriptor.reserved_name.any?
          found = true
          writer.write_line("reserved #{descriptor.reserved_name.map(&:to_json).join(", ")};")
        end
        writer.writenl if found
      end

      def write_imports(writer, file_descriptor)
        writer.writenl
        file_descriptor.dependency.each do |dependency|
          writer.write_line("import \"#{dependency}\";")
        end
        file_descriptor.public_dependency.each do |public_dependency|
          writer.write_line("import public \"#{public_dependency}\";")
        end
        file_descriptor.option_dependency.each do |option_dependency|
          writer.write_line("import weak \"#{option_dependency}\";")
        end
        writer.writenl
      end

      def write_message(info, message_type)
        info.message = message_type
        info.write_indent("message ")
        info.write("#{message_type.name} {")
        info.writenl
        info.indent

        write_options(info, message_type)
        write_reserved(info, message_type)

        message_type.enum_type.each do |enum|
          info.writenl
          write_enum(info, enum)
        end
        message_type.field.each do |field|
          write_field(info, field)
        end
        message_type.extension.each do |extension|
          write_field(info, extension)
        end
        write_oneofs(info, message_type)
        message_type.nested_type.each do |subtype|
          next if subtype.options&.map_entry

          info.writenl
          write_message(info, subtype)
        end
        info.dedent
        info.write_line("}")
      end

      def field_type(info, field_type)
        case field_type.type
        when :TYPE_INT32
          "int32"
        when :TYPE_INT64
          "int64"
        when :TYPE_UINT32
          "uint32"
        when :TYPE_UINT64
          "uint64"
        when :TYPE_SINT32
          "sint32"
        when :TYPE_SINT64
          "sint64"
        when :TYPE_FIXED32
          "fixed32"
        when :TYPE_FIXED64
          "fixed64"
        when :TYPE_SFIXED32
          "sfixed32"
        when :TYPE_SFIXED64
          "sfixed64"
        when :TYPE_FLOAT
          "float"
        when :TYPE_DOUBLE
          "double"
        when :TYPE_BOOL
          "bool"
        when :TYPE_STRING
          "string"
        when :TYPE_BYTES
          "bytes"
        when :TYPE_ENUM, :TYPE_MESSAGE
          # remove leading .
          type = fetch(field_type.type_name[1..])
          name = type.name.sub("#{info.package}.#{info.message.name}.", "")
          name.sub("#{info.package}.", "")
        end
      end

      def write_field(info, field, oneof: false)
        return if !oneof && field.has_oneof_index?
        info.write_indent("")

        klass = nil
        if field.type_name && field.type_name != ""
          klass = fetch(field.type_name).to_proto
        end

        if field.proto3_optional
          info.write("optional ")
        elsif field.label == :LABEL_REPEATED && !klass&.options&.map_entry
          info.write("repeated ")
        end

        if klass&.options&.map_entry
          info.write("map<#{field_type(info, klass.field[0])}, #{field_type(info, klass.field[1])}>")
        else
          info.write(field_type(info, field).to_s)
        end
        info.write(" #{field.name} = #{field.number}")

        write_field_options(info, field)
        info.write(";")
        info.writenl
      end

      def write_field_options(info, field)
        return unless field.options

        info.write(" [")
        info.write(field.options.to_h.map { |name, value| "#{name} = #{value}" }.join(", "))
        write_options(info, field, include_option_label: false)
        info.write("]")
      end

      def write_oneofs(info, message)
        message.oneof_decl.each_with_index do |oneof, i|
          # synthetic oneof for proto3 optional fields
          next if oneof.name.start_with?("_") &&
            message.field.any? { |f| f.proto3_optional && f.name == oneof.name[1..] }

          info.write_line("oneof #{oneof.name} {")
          info.indent
          message.field.select { |f| f.has_oneof_index? && f.oneof_index == i }.each do |field|
            write_field(info, field, oneof: true)
          end
          info.dedent
          info.write_line("}")
        end
      end

      def write_enum(info, enum_type)
        info.write("enum ")
        info.write("#{enum_type.name} {")
        info.writenl
        info.indent
        write_reserved(info, enum_type)
        enum_type.value.each do |value|
          info.write_line("#{value.name} = #{value.number};")
        end
        info.dedent
        info.write_line("}")
        info.writenl
      end

      def method_type(package, name)
        output = name.sub("#{package}.", "")
        output = output[1..] if output.start_with?(".")
        output
      end

      def write_service(info, service)
        info.write_line("service #{service.name} {")
        info.indent
        service["method"].each do |method|
          info.write_indent("rpc #{method.name}(#{method_type(info.package, method.input_type)}) ")
          info.write("returns (#{method_type(info.package, method.output_type)}) {")
          info.writenl
          info.indent
          if method.options
            write_options(info, method)
          end
          info.dedent
          info.write_line("};")
        end
        info.dedent
        info.write_line("}")
      end

      # @return [Boolean] true if any options were written
      def write_options(info, descriptor, include_option_label: true)
        # unfortunately there doesn't seem to be a way to get the full list of options without
        # resorting to to_json.
        json = JSON.parse(descriptor.options.to_json)
        return if !json || json.empty?

        found = false
        json.keys.each do |name|
          option_name = name.tr("[]", "")
          ext = fetch(option_name)
          next if ext.nil?

          found = true
          options = ext.get(descriptor.options)
          if include_option_label
            info.write_indent("option (#{option_name}) =")
          else
            info.write("(#{option_name}) = ")
          end
          if options.respond_to?(:to_h)
            lines = JSON.pretty_generate(options.to_h).lines(chomp: true)
            lines.each_with_index do |line, i|
              info.write_indent(line)
              info.writenl if i < lines.length - 1
            end
            info.write(";")
          else
            info.write(options.to_json)
          end
          info.writenl
        end
        found
      end
    end
  end
end
