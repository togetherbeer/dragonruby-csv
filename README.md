# dragonruby-csv

This is a DragonRuby friendly port of a RubyMotion friendly port of fasterer-csv by Mason by Mark Rickert:

https://github.com/markrickert/motion-csv
https://rubygems.org/gems/fasterer-csv

## Installation

### Smaug

`smaug add csv`

### Vanilla

Copy lib/stringio.rb and lib/dragonruby-csv.rb to lib/dragonruby-csv in your project directory, then require them:

```ruby
require 'lib/dragonruby-csv/stringio.rb'
require 'lib/dragonruby-csv/dragonruby-csv.rb'
```

## Usage

```ruby
csv_string = "a,b,c,d\n1,2,3,4\n5,6,7,whatever\n"
csv = CSV.parse(csv_string)

puts csv.headers # [:a, :b, :c, :d]
puts csv.first[:b] # 2
puts csv.last[:d] # "whatever"

csv.each do |row|
  # ...
end
```

### Generating a CSV String

```ruby
CSV.generate do |csv|
  csv << ["row", "of", "CSV", "data"]
  csv << ["another", "row"]
end
# "row,of,CSV,data\nanother,row\n"
```

### Convert an Array to CSV
This uses a convenience method on the `Array` class. You can pass it a single or two-dimensional array.

```ruby
["testing", "arrays"].to_csv
# "testing,arrays\n"
```

```ruby
[
  ['array1', 'stuff'],
  ['array2', 'more stuff']
].to_csv
# "array1,stuff\narray2,more stuff\n"
```

### Parse a String
This uses a convenience method on the `String` class.

```ruby
"header1,header2\nCSV,String".parse_csv
# [["CSV", "String"]]
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
