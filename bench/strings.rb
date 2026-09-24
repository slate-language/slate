# The Ruby twin of strings.sl.
#
# **`+` always makes a new string**, so this naive form copies everything built so far on every turn
# and is quadratic, as slate's is. The idiomatic Ruby for building a big string is `<<`, which appends
# in place and is linear; this file is deliberately the naive form for comparison, as the other twins
# are. The text is ASCII, so `length` is the character count and is read without a scan.

def run
  out = ""
  i = 0

  while i < 150_000
    out = out + "x" + (i % 10).to_s
    i = i + 1
  end

  out.length
end

puts run
