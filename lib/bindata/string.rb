require "bindata/single"

module BinData
  # A String is a sequence of bytes.  This is the same as strings in Ruby.
  # The issue of character encoding is ignored by this class.
  #
  #   require 'bindata'
  #
  #   data = "abcdefghij"
  #
  #   obj = BinData::String.new(:read_length => 5)
  #   obj.read(data)
  #   obj.value #=> "abcde"
  #
  #   obj = BinData::String.new(:length => 6)
  #   obj.read(data)
  #   obj.value #=> "abcdef"
  #   obj.value = "abcdefghij"
  #   obj.value #=> "abcdef"
  #   obj.value = "abcd"
  #   obj.value #=> "abcd\000\000"
  #
  #   obj = BinData::String.new(:length => 6, :trim_value => true)
  #   obj.value = "abcd"
  #   obj.value #=> "abcd"
  #   obj.to_s #=> "abcd\000\000"
  #
  #   obj = BinData::String.new(:length => 6, :pad_char => 'A')
  #   obj.value = "abcd"
  #   obj.value #=> "abcdAA"
  #   obj.to_s #=> "abcdAA"
  #
  # == Parameters
  #
  # String objects accept all the params that BinData::Single
  # does, as well as the following:
  #
  # <tt>:read_length</tt>::    The length to use when reading a value.
  # <tt>:length</tt>::         The fixed length of the string.  If a shorter
  #                            string is set, it will be padded to this length.
  # <tt>:pad_char</tt>::       The character to use when padding a string to a
  #                            set length.  Valid values are Integers and
  #                            Strings of length 1.  "\0" is the default.
  # <tt>:trim_padding</tt>::   Boolean, default false.  If set, #value will
  #                            return the value with all pad_chars trimmed
  #                            from the end of the string.  The value will
  #                            not be trimmed when writing.
  class String < BinData::Single

    register(self.name, self)

    bindata_optional_parameters :read_length, :length, :trim_padding
    bindata_default_parameters  :pad_char => "\0"
    bindata_mutually_exclusive_parameters :read_length, :length
    bindata_mutually_exclusive_parameters :length, :value

    class << self

      def deprecate!(params, old_key, new_key)
        if params.has_key?(old_key)
          warn ":#{old_key} is deprecated. Replacing with :#{new_key}"
          params[new_key] = params.delete(old_key)
        end
      end

      def sanitize_parameters!(sanitizer, params)
        # warn about deprecated param - remove before releasing 1.0
        deprecate!(params, :trim_value, :trim_padding)

        warn_replacement_parameter(params, :initial_length, :read_length)

        if params.has_key?(:pad_char)
          ch = params[:pad_char]
          params[:pad_char] = sanitized_pad_char(ch)
        end

        super(sanitizer, params)
      end

      #-------------
      private

      def sanitized_pad_char(ch)
        result = ch.respond_to?(:chr) ? ch.chr : ch.to_s
        if result.length > 1
          raise ArgumentError, ":pad_char must not contain more than 1 char"
        end
        result
      end
    end

    def value
      result = _value
      if has_param?(:length)
        result = truncate_or_pad_to_length(result)
      end
      if no_eval_param(:trim_padding) == true
        result = trim_padding(result)
      end
      result
    end

    #---------------
    private

    def truncate_or_pad_to_length(str)
      len = eval_param(:length) || str.length
      if str.length == len
        str
      elsif str.length > len
        str.slice(0, len)
      else
        str + (eval_param(:pad_char) * (len - str.length))
      end
    end

    def trim_padding(str)
      str.sub(/#{eval_param(:pad_char)}*$/, "")
    end

    def value_to_string(val)
      truncate_or_pad_to_length(val)
    end

    def read_and_return_value(io)
      len = eval_param(:read_length) || eval_param(:length) || 0
      io.readbytes(len)
    end

    def sensible_default
      ""
    end
  end
end
