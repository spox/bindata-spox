module BinData
  # A wrapper around an IO object.  The wrapper provides a consistent
  # interface for BinData objects to use when accessing the IO.
  class IO

    # Create a new IO wrapper around +io+.  +io+ must support #read if used
    # for reading, #write if used for writing, #pos if reading the current
    # stream position and #seek if setting the current stream position.  If
    # +io+ is a string it will be automatically wrapped in an StringIO object.
    #
    # The IO can handle bitstreams in either big or little endian format.
    # 
    #      M  byte1   L      M  byte2   L
    #      S 76543210 S      S fedcba98 S
    #      B          B      B          B
    #
    # In big endian format:
    #   readbits(6), readbits(5) #=> [765432, 10fed]
    #
    # In little endian format:
    #   readbits(6), readbits(5) #=> [543210, a9876]
    #
    def initialize(io)
      raise ArgumentError, "io must not be a BinData::IO" if BinData::IO === io

      # wrap strings in a StringIO
      if io.respond_to?(:to_str)
        io = StringIO.new(io)
      end

      @raw_io = io

      # initial stream position if stream supports positioning
      @initial_pos = positioning_supported? ? io.pos : 0

      # bits when reading
      @rnbits  = 0
      @rval    = 0
      @rendian = nil

      # bits when writing
      @wnbits  = 0
      @wval    = 0
      @wendian = nil
    end

    # Access to the underlying raw io.
    attr_reader :raw_io

    # Returns the current offset of the io stream.  The exact value of
    # the offset when reading bitfields is not defined.
    def offset
      if positioning_supported?
        @raw_io.pos - @initial_pos
      else
        0
      end
    end

    # Seek +n+ bytes from the current position in the io stream.
    def seekbytes(n)
      @raw_io.seek(n, ::IO::SEEK_CUR)
    end

    # Reads exactly +n+ bytes from +io+.
    #
    # If the data read is nil an EOFError is raised.
    #
    # If the data read is too short an IOError is raised.
    def readbytes(n)
      raise "Internal state error nbits = #{@rnbits}" if @rnbits > 8
      @rnbits = 0
      @rval   = 0

      str = @raw_io.read(n)
      raise EOFError, "End of file reached" if str.nil?
      raise IOError, "data truncated" if str.size < n
      str
    end

    # Reads all remaining bytes from the stream.
    def read_all_bytes
      raise "Internal state error nbits = #{@rnbits}" if @rnbits > 8
      @rnbits = 0
      @rval   = 0

      @raw_io.read
    end

    # Reads exactly +nbits+ bits from the stream. +endian+ specifies whether
    # the bits are stored in +:big+ or +:little+ endian format.
    def readbits(nbits, endian = :big)
      if @rendian != endian
        # don't mix bits of differing endian
        @rnbits  = 0
        @rval    = 0
        @rendian = endian
      end

      if endian == :big
        read_big_endian_bits(nbits)
      else
        read_little_endian_bits(nbits)
      end
    end

    # Writes the given string of bytes to the io stream.
    def writebytes(str)
      flushbits
      @raw_io.write(str)
    end

    # Writes +nbits+ bits from +val+ to the stream. +endian+ specifies whether
    # the bits are to be stored in +:big+ or +:little+ endian format.
    def writebits(val, nbits, endian = :big)
      # clamp val to range
      val = val & mask(nbits)

      if @wendian != endian
        # don't mix bits of differing endian
        flushbits if @wnbits > 0

        @wendian = endian
      end

      if endian == :big
        write_big_endian_bits(val, nbits)
      else
        write_little_endian_bits(val, nbits)
      end
    end

    # To be called after all +writebits+ have been applied.
    def flushbits
      if @wnbits > 8
        raise "Internal state error nbits = #{@wnbits}" if @wnbits > 8
      elsif @wnbits > 0
        writebits(0, 8 - @wnbits, @wendian)
      else
        # do nothing
      end
    end
    alias_method :flush, :flushbits

    #---------------
    private

    def positioning_supported?
      unless defined? @positioning_supported
        @positioning_supported = begin
          @raw_io.pos
          true
        rescue NoMethodError, Errno::ESPIPE
          false
        end
      end
      @positioning_supported
    end

    def read_big_endian_bits(nbits)
      while @rnbits < nbits
        accumulate_big_endian_bits
      end

      val     = (@rval >> (@rnbits - nbits)) & mask(nbits)
      @rnbits -= nbits
      @rval   &= mask(@rnbits)

      val
    end

    def accumulate_big_endian_bits
      byte = @raw_io.read(1)
      raise EOFError, "End of file reached" if byte.nil?
      byte = byte.unpack('C').at(0) & 0xff

      @rval = (@rval << 8) | byte
      @rnbits += 8
    end

    def read_little_endian_bits(nbits)
      while @rnbits < nbits
        accumulate_little_endian_bits
      end

      val     = @rval & mask(nbits)
      @rnbits -= nbits
      @rval   >>= nbits

      val
    end

    def accumulate_little_endian_bits
      byte = @raw_io.read(1)
      raise EOFError, "End of file reached" if byte.nil?
      byte = byte.unpack('C').at(0) & 0xff

      @rval = @rval | (byte << @rnbits)
      @rnbits += 8
    end

    def write_big_endian_bits(val, nbits)
      while nbits > 0
        bits_req = 8 - @wnbits
        if nbits >= bits_req
          msb_bits = (val >> (nbits - bits_req)) & mask(bits_req)
          nbits -= bits_req
          val &= mask(nbits)

          @wval   = (@wval << bits_req) | msb_bits
          @raw_io.write(@wval.chr)

          @wval   = 0
          @wnbits = 0
        else
          @wval = (@wval << nbits) | val
          @wnbits += nbits
          nbits = 0
        end
      end
    end

    def write_little_endian_bits(val, nbits)
      while nbits > 0
        bits_req = 8 - @wnbits
        if nbits >= bits_req
          lsb_bits = val & mask(bits_req)
          nbits -= bits_req
          val >>= bits_req

          @wval   |= (lsb_bits << @wnbits)
          @raw_io.write(@wval.chr)

          @wval   = 0
          @wnbits = 0
        else
          @wval   |= (val << @wnbits)
          @wnbits += nbits
          nbits = 0
        end
      end
    end

    def mask(nbits)
      (1 << nbits) - 1
    end
  end
end
