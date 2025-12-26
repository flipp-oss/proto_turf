# frozen_string_literal: true

class ProtoTurf
  module Wire
    class << self
      # Write an int with zig-zag encoding. Copied from Avro.
      def write_int(stream, num)
        num = (num << 1) ^ (num >> 63)
        while (num & ~0x7F) != 0
          stream.write(((num & 0x7f) | 0x80).chr)
          num >>= 7
        end
        stream.write(num.chr)
      end

      # Read an int with zig-zag encoding. Copied from Avro.
      def read_int(stream)
        b = stream.readbyte
        n = b & 0x7F
        shift = 7
        while (b & 0x80) != 0
          b = stream.readbyte
          n |= (b & 0x7F) << shift
          shift += 7
        end
        (n >> 1) ^ -(n & 1)
      end
    end
  end
end
