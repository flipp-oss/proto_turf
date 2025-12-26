# frozen_string_literal: true

class ProtoTurf
  module Wire
    class << self
      # Write an int with zig-zag encoding. Copied from Avro.
      def write_int(stream, n)
        n = (n << 1) ^ (n >> 63)
        while (n & ~0x7F) != 0
          stream.write(((n & 0x7f) | 0x80).chr)
          n >>= 7
        end
        stream.write(n.chr)
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
