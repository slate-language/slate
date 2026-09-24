# The Ruby twin of options.sl.
#
# A Hash with `fetch` and a default is what Ruby writes where slate writes a pattern default. Keyword
# arguments (`def sized(width: 10, height:, scale: 2)` called with `**opts`) would be the other
# spelling, and would build a second hash per call on the caller's side.

def sized(opts)
  width = opts.fetch(:width, 10)
  height = opts[:height]
  scale = opts.fetch(:scale, 2)

  width * height * scale
end

def run(given, partial)
  total = 0
  turns = 0

  while turns < 2_000_000
    total = total + sized(given) + sized(partial)
    turns = turns + 1
  end

  total
end

puts run({ width: 3, height: 4, scale: 5 }, { height: 4 })
