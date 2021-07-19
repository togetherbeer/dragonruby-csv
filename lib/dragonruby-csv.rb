module DragonRubyCSV

  module InstanceData
    # This is a hack to support _some_ form of instance data
    # given that mruby doesn't support ivars on core classes
    # or subclasses of the same.

    module ClassMethods
      def attr_reader(*names)
        names.each do |name|
          define_method(name) { idata[name] }
        end
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    def idata
      idata = {}
      define_singleton_method(:idata) { idata }
      idata
    end
  end

  class Table < Array

    include InstanceData

    class << self
      def format_headers(unformatted)
        unformatted.map { |header| Row.to_key(header) }
      end
    end

    attr_reader :headers, :lines, :line_block

    def initialize(headers, fail_on_malformed_columns = true, &line_block)
      idata[:headers] = Table.format_headers(headers)
      idata[:fail_on_malformed_columns] = fail_on_malformed_columns
      idata[:line_block] = line_block
      idata[:lines] = 0
      idata[:indexes] = {}
    end

    def <<(row)
      idata[:lines] += 1
      if !row.is_a?(Row)
        row = Row.new(self, row, idata[:lines])
      end
      if idata[:headers].length != row.length
        error = "*** WARNING - COLUMN COUNT MISMATCH - WARNING ***\n*** ROW #{size} : EXPECTED #{idata[:headers].length} : FOUND #{row.length}\n\n"
        len = 0
        headers.each do |header|
          len = header.to_s.length if header.to_s.length > len
        end
        headers.each_with_index do |header, i|
          error << sprintf("%-32s : %s\n", header, row[i])
        end
        puts error
        raise error if idata[:fail_on_malformed_columns]
      end
      if line_block
        line_block.call(row)
      else
        super(row)
      end
    end
    alias_method :push, :<<

    def merge(*tables)

      tables.each do |table|
        matching = self.headers & table.headers

        key = {}

        table.each do |row|
          matching.each do |match|
            key[match] = row[match]
          end

          self.lookup(key) { |r| r.merge(row) }
        end
      end

      self

    end

    def index(columns, reindex = false)
      columns = columns.compact.uniq.sort { |a, b| a.to_s <=> b.to_s }.map { |column| Row.to_key(column) }

      key = columns.join('|#|')

      idata[:indexes][key] ||= {}

      index = idata[:indexes][key]

      if reindex || index.empty?

        self.each do |row|
          vkey = columns.map { |column| row[column] }
          index[vkey] ||= []
          index[vkey] << row
        end
      end
      index
    end

    def lookup(key)

      values  = []
      columns = key.keys.compact.uniq.sort { |a, b| a.to_s <=> b.to_s }.map do |column|
        values << key[column]
        Row.to_key(column)
      end

      rows = index(columns)[values]
      if rows && block_given?
        rows.each do |row|
          yield(row)
        end
      end

      rows
    end

    def write(file, quot = '"', sep = ',')
      DragonRubyCSV.write(file, quot, sep) do |out|
        out << headers
        each do |row|
          out << row
        end
      end
    end

    alias_method :rows, :to_a
    alias_method :merge!, :merge

  end

  class Row < Array

    include InstanceData

    class << self
      def parameterize(str)
        return '' unless str
        str = str.downcase
        str.tr!("\r", "")
        str.tr!("\n\t ", "___")
        str
      end

      def to_key(key)
        key = parameterize(key.to_s)
        key.empty? ? :_ : key.to_sym
      end
    end

    def headers
      idata[:headers] ||= idata[:table].headers.dup
    end

    attr_reader :line

    def initialize(table, array, line=-1)
      idata[:table] = table
      idata[:line] = line
      super()
      concat array
    end

    def [](*is)
      is.each do |i|
        val = if i.is_a? Fixnum
          super
        else
          found = headers.index(Row::to_key(i))
          found ? super(found) : nil
        end
        return val unless val.nil?
      end
      nil
    end

    def []=(key, val)
      if key.is_a? Fixnum
        super
      else
        key = Row::to_key(key)
        headers << key unless headers.include? key
        found = headers.index(key)
        super(found, val)
      end
    end

    def pull(*columns)
      columns.map do |column|
        column = [nil] if column.nil?
        self[*column]
      end
    end

    def merge(row)
      if row.is_a? Row
        row.headers.each do |header|
          self[header] = row[header]
        end
      else
        row.each do |key, value|
          self[key] = value
        end
      end
      self
    end

    def to_hash
      headers.inject({}) do |memo, h|
        memo[h] = self[h]
        memo
      end
    end

    def key?(key)
      keys.include?(Row.to_key(key))
    end

    def value?(value)
      values.include?(value)
    end

    def method_missing(method, *args, &block)
      to_hash.send(method, *args, &block)
    end

    alias_method :keys, :headers
    alias_method :values, :to_a

    alias_method :has_key?, :key?
    alias_method :member?, :key?
    alias_method :include?, :key?

    alias_method :has_value?, :value?
    alias_method :merge!, :merge

  end

  class NumericConversion < Array

    include InstanceData

    def initialize
      idata[:int] = idata[:float] = true
      idata[:dot] = false
    end

    def clear
      idata[:int] = idata[:float] = true
      idata[:dot] = false
      super
    end

    def <<(ch)
      if ch == ?-.ord
        idata[:float] = idata[:int] = size == 0
      elsif (ch > ?9.ord || ch < ?0.ord) && ch != ?..ord
        idata[:int] = idata[:float] = false
      elsif ch == ?..ord && idata[:dot]
        idata[:int] = idata[:float] = false
      elsif ch == ?..ord
        idata[:int] = false
        idata[:dot] = true
      end

      super(ch.chr)
    end

    def convert(as_string = false)
      if as_string
        join
      elsif empty?
        nil
      elsif idata[:int]
        join.to_i
      elsif idata[:float]
        join.to_f
      else
        join
      end
    end

  end

  class NoConversion < Array

    include InstanceData

    def <<(ch)
      super(ch.chr)
    end

    def convert(as_string = false)
      if as_string
        join
      elsif empty?
        nil
      else
        join
      end
    end

  end

  class IOWriter
    def initialize(file, quot = '"', sep = ',', quotenum = false)
      @first = true; @io = file; @quot = quot; @sep = sep; @quotenum = quotenum
    end

    def <<(row)
      raise "can only write arrays! #{row.class} #{row.inspect}" unless row.is_a? Array
      if @first && row.is_a?(Row)
        self.<<(row.headers)
      end
      @first = false
      @io.syswrite DragonRubyCSV::quot_row(row, @quot, @sep, @quotenum)
      row
    end
  end

  class << self

    def headers(file, quot = '"', sep = ',', fail_on_malformed = true, column = NoConversion.new, &block)
      parse_headers(File.open(file, 'r') { |io| io.gets }, quot, sep, fail_on_malformed, column, &block)
    end

    def read(file, quot = '"', sep = ',', fail_on_malformed = true, column = NoConversion.new, &block)
      File.open(file, 'r') do |io|
        parse(io, quot, sep, fail_on_malformed, column, &block)
      end
    end

    def convread(file, quot = '"', sep = ',', fail_on_malformed = true, column = NumericConversion.new, &block)
      File.open(file, 'r') do |io|
        parse(io, quot, sep, fail_on_malformed, column, &block)
      end
    end

    def parse_headers(data, quot = '"', sep = ',', fail_on_malformed = true, column = NoConversion.new, &block)
      parse(data, quot, sep, fail_on_malformed, column, &block).headers
    end

    def parse(io, quot = '"', sep = ',', fail_on_malformed = true, column = NoConversion.new, &block)
      q, s, row, inquot, clean, maybe, table, field, endline = quot.ord, sep.ord, [], false, true, false, nil, true, false

      io.each_byte do |c|
        next if c == ?\r.ord

        if maybe && c == s
          row << column.convert(true)
          column.clear
          clean, inquot, maybe, field, endline = true, false, false, true, false
        elsif maybe && c == ?\n.ord && table.nil?
          row << column.convert(true) unless (column.empty? && endline)
          column.clear
          table = Table.new(row, fail_on_malformed, &block) unless row.empty?
          row, clean, inquot, maybe, field, endline = [], true, false, false, false, true
        elsif maybe && c == ?\n.ord
          row << column.convert(true) unless (column.empty? && endline)
          column.clear
          table << row unless row.empty?
          row, clean, inquot, maybe, field, endline = [], true, false, false, false, true
        elsif clean && c == q
          inquot, clean, endline = true, false, false
        elsif maybe && c == q
          column << c
          clean, maybe, endline = false, false, false
        elsif c == q
          maybe, endline = true, false
        elsif inquot
          column << c
          clean, endline = false, false
        elsif c == s
          row << column.convert(false)
          column.clear
          clean, field, endline = true, true, false
        elsif c == ?\n.ord && table.nil?

          row << column.convert(false) unless column.empty? && endline

          column.clear
          table = Table.new(row, fail_on_malformed, &block) unless row.empty?
          row, clean, inquot, field, endline = [], true, false, false, true
        elsif c == ?\n.ord

          row << column.convert(false) unless column.empty? && endline

          column.clear
          table << row unless row.empty?
          row, clean, inquot, field, endline = [], true, false, false, true
        else
          column << c
          clean, endline = false, false
        end
      end

      if !clean
        row << column.convert(maybe)
        if table
          table << row unless row.empty?
        else
          table = Table.new(row, fail_on_malformed, &block) unless row.empty?
        end
      elsif field
        row << column.convert(maybe)
      end

      table
    end

    def quot_row(row, q = '"', s = ',', numquot = false)
      row.map do |val|
        if val.nil?
          ""
        elsif val.is_a? Numeric
          val.to_s
        else
          val = String(val)
          if val.length == 0
            q * 2
          elsif val.include?(q) or val.include?(s) or val.include?("\n")
            q + val.gsub(q, q * 2) + q
          else
            val
          end
        end
      end
    end

    def generate(quot = '"', sep = ',', &block)
      builder = StringIO.new
      write(builder, quot, sep, &block)
      builder.string
    end

    def write(data, quot = '"', sep = ',', quotenum = false, &block)
      out(data, 'w', quot, sep, quotenum, &block)
    end

    def append(data, quot = '"', sep = ',', quotenum = false, &block)
      out(data, 'a', quot, sep, quotenum, &block)
    end

    def out(data, mode = 'w', quot = '"', sep = ',', quotenum = false, &block)
      if data.class == String
        File.open(data, mode) do |io|
          out(io, mode, quot, sep, quotenum, &block)
        end
      else
        yield(IOWriter.new(data, quot, sep, quotenum))
      end
    end

  end
end

class Array

  def to_csv
    DragonRubyCSV.generate do |csv|
      if self.depth == 2
        self.each do |a|
          csv << a
        end
      else
        csv << self
      end
    end
  end

  def depth
    # Thanks, StackOverflow! http://stackoverflow.com/a/10863610/814123
    b, depth = self.dup, 1
    until b==self.flatten
      depth+=1
      b=b.flatten(1)
    end
    depth
  end

end

class String

  def parse_csv
    DragonRubyCSV.parse(self)
  end

end

CSV = DragonRubyCSV
