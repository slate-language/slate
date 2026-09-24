# The Ruby twin of strwalk.sl.
#
# **`s[i]` on a string that is not all ASCII counts from the FRONT**, so this walk is quadratic in
# the length of the string, as slate's used to be and as Lua's is. Ruby keeps the text as UTF-8 and
# indexes characters, which is slate's arrangement; what it lacks is slate's cursor, so each index
# walks the characters before it -- quickly, a word at a time, but from the start every time.
#
# `s.length` counts from the front as well on such a string, so the bound is taken once into a local
# rather than asked each turn, as the Lua twin does -- the fair reading, slate's `s.length` being
# one read of a number the string carries.

def run(s)
  found = 0
  n = s.length
  i = 0

  while i < n
    if s[i] == "本"
      found = found + 1
    end

    i = i + 1
  end

  found
end

puts run(Array.new(1000) { "日本語あいうえおかきく" + "さしすせそたちつてと" }.join)
