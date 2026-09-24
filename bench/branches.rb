# The Ruby twin of branches.sl.
#
# `case`/`when` on integer literals is the `match` (CRuby compiles it to a hash dispatch, as
# dispatch.rb says), `next` is Ruby's `continue` inside a `while`, `raise`/`rescue` is the `try`, and
# the `if`-as-expression is Ruby's own `if`, which is an expression already. Ruby's integers are
# arbitrary precision, so nothing here can overflow; the values stay under 2^31 anyway.

def risky(r)
  if r == 0
    raise ArgumentError, "boom"
  end

  0
end

def run
  seed = 1
  i = 0
  flag_count = 0
  chain_total = 0
  nested_count = 0
  continue_count = 0
  expr_sum = 0
  match_total = 0
  fault_count = 0

  while i < 2_000_000
    seed = (seed * 16807) % 2147483647

    r = seed % 1000

    i = i + 1

    if r % 7 == 0
      flag_count = flag_count + 1
    end

    if r < 100
      chain_total = chain_total + 1

      if r % 13 == 0
        nested_count = nested_count + 1
      end
    elsif r < 400
      chain_total = chain_total + 2
    elsif r < 700
      chain_total = chain_total + 3
    else
      chain_total = chain_total + 4
    end

    if r % 97 == 0
      continue_count = continue_count + 1
      next
    end

    k = r % 5

    case k
    when 0 then match_total = match_total + 10
    when 1 then match_total = match_total + 20
    when 2 then match_total = match_total + 30
    when 3 then match_total = match_total + 40
    else match_total = match_total + 50
    end

    bonus = if r % 2 == 0 then 1 else 2 end

    expr_sum = expr_sum + bonus

    if i % 1000 == 0
      begin
        fault_count = fault_count + risky(r)
      rescue ArgumentError
        fault_count = fault_count + 1
      end
    end
  end

  flag_count + chain_total * 3 + nested_count * 7 + continue_count * 11 +
    expr_sum * 13 + match_total * 17 + fault_count * 19
end

puts run
