# The Ruby twin of dispatch.sl, written as `case`/`when` -- a subject compared against literal
# patterns in order, which is slate's `match`.
#
# **CRuby compiles a `case` whose `when`s are all literal strings to a HASH lookup** (the
# `opt_case_dispatch` instruction) where `String#===` has not been redefined, so this is the "one
# that could hash the subject once" dispatch.sl's header anticipates, and it shows here.

def kind(w)
  case w
  when "add" then 1
  when "sub" then 2
  when "mul" then 3
  when "div" then 4
  when "mod" then 5
  else 0
  end
end

def run(words)
  total = 0
  i = 0

  while i < 5_000_000
    total = total + kind(words[i % 6])
    i = i + 1
  end

  total
end

puts run(["add", "sub", "mul", "div", "mod", "nope"])
