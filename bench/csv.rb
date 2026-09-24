# The Ruby twin of csv.sl.
#
# `String#split` and `to_i` are the builtins, and `length` counts characters -- slate's unit, and
# read without a scan, this text being ASCII. The standard library's `CSV` would be the idiomatic
# reader for a real file and would not be the same work: it handles quoting.

def build(rows)
  lines = []
  i = 0

  while i < rows
    lines << "#{i},#{i * 2},name#{i % 100}"
    i = i + 1
  end

  lines.join("\n")
end

def parse(text)
  total = 0

  text.split("\n").each do |line|
    parts = line.split(",")

    total = total + parts[0].to_i + parts[1].to_i + parts[2].length
  end

  total
end

def run
  text = build(20_000)
  total = 0
  turns = 0

  while turns < 30
    total = total + parse(text)
    turns = turns + 1
  end

  total
end

puts run
