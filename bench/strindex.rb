# The Ruby twin of strindex.sl.
#
# **`s[i]` is a constant-time read here**, so this walk is linear. A Ruby String remembers whether
# it is all ASCII (its "code range"), and for one that is, a character index is a byte index; the
# unit is still the character, slate's unit. `s.length` is likewise read without a scan.

def run(s)
  found = 0
  i = 0

  while i < s.length
    if s[i] == "x"
      found = found + 1
    end

    i = i + 1
  end

  found
end

puts run(Array.new(1000) { "abcdexfghi" + "jklmnxopqr" }.join)
