// Case, whitespace and normal forms, on both back ends.
//
// **The interpreter walks a database and a JavaScript host answers natively, so this is the file
// that says the two are one operation.** `upper`, `lower` and the four normal forms are the host's
// under `slate js` and `sysl.unicode` here; `trim` is written out on both, ECMAScript's whitespace
// not being Unicode's; and `casefold` is written out under `slate js`, no host having it.
//
// **Everything below was chosen from a sweep rather than by taste.** Every code point there is was
// run through both back ends and the answers compared, which is how the interpreter's tables were
// built at all; what is kept here is one case per rule the sweep proved, so a change that breaks a
// rule reddens a line naming it rather than a byte count.

// -- upper is not a per-character map ------------------------------------------------------------

// A hundred and two characters uppercase to more than one, and a walk over the simple mapping
// answers `ẞ` for the first of them where every host answers `SS`.
print(upper("ß"), upper("Straße"), upper("ﬁ"), upper("ﬄ"), upper("ŉ"))

// Three characters out, from one in.
print(upper("ΐ"), upper("ΰ"))

// The Armenian ligature, and the two Greek ones with a subscript iota.
print(upper("և"), upper("ᾀ"), upper("ᾼ"))

print(upper("héllo"), upper("abc123"), upper(""), upper("日本語"))

// -- lower has two cases of its own --------------------------------------------------------------

// `İ` is the one lower case in the database longer than what it came from.
print(lower("İ"), len(lower("İ")))

// A final sigma is context and not a table: last letter of a word, and not otherwise.
print(lower("ΟΔΟΣ"), lower("ΣΟΦΟΣ"), lower("ΟΣΟ"))

// An accent, an apostrophe and a full stop are looked THROUGH, and a letter after it is not.
print(lower("ΟΔΟΣ'"), lower("ΟΔΟΣ."), lower("ΟΔΟΣΑ"), lower("Σ"))

print(lower("HÉLLO"), lower("ABC123"), lower(""))

// -- trim is `White_Space` and not ECMAScript's --------------------------------------------------

// A no-break space is a space and a zero-width no-break space is not, which is exactly where the
// host's own `trim` disagrees with the database in both directions.
print("[" + trim("\u{a0}\u{85}\u{2003}x\u{2009}\u{3000}") + "]")
print("[" + trim("\u{feff}x\u{feff}") + "]")
print("[" + trim("  x\t\n  ") + "]", "[" + trimStart("  x  ") + "]", "[" + trimEnd("  x  ") + "]")
print("[" + trim("") + "]", "[" + trim("   ") + "]", "[" + trim("x") + "]")

// The ogham space mark, which is the one `Zs` character that is not blank.
print("[" + trim("\u{1680}x\u{1680}") + "]")

// -- the four normal forms -----------------------------------------------------------------------

val composed = "é"
val decomposed = "e\u{301}"

print(composed == decomposed, normalize(composed, "NFD") == decomposed, normalize(decomposed, "NFC") == composed)
print(len(normalize(composed, "NFD")), len(normalize(decomposed, "NFC")))

// The compatibility forms throw information away, which is what makes them for matching.
print(normalize("ﬁ", "NFKC"), normalize("²", "NFKC"), normalize("①", "NFKC"))
print(normalize("Ⅻ", "NFKD"), normalize("ｱ", "NFKC"))

// Combining marks come out in canonical order whichever order they went in.
print(normalize("q\u{323}\u{307}", "NFD") == normalize("q\u{307}\u{323}", "NFD"))

// The angstrom sign is a singleton: it normalizes to the letter and stops being itself.
print(normalize("\u{212b}", "NFC") == "Å", normalize("\u{2126}", "NFC") == "Ω")

// -- casefold is not lower -----------------------------------------------------------------------

print(casefold("STRASSE") == casefold("Straße"), lower("STRASSE") == lower("Straße"))
print(casefold("ẞ"), casefold("ß"), casefold("ﬁ"), casefold("ǰ"))

// Folding crosses an alphabet where lowering does not: a micro sign is a Greek mu, a long s is an
// s, a combining iota is a letter, and a final sigma is a plain one.
print(casefold("µ") == casefold("μ"), casefold("ſ") == "s", casefold("ΟΔΟΣ") == casefold("οδος"))

// Cherokee folds to UPPER case, which is the one script in the database that runs that way.
print(casefold("Ꭰ") == casefold("ꭰ"), casefold("Ꭰ") == "Ꭰ")

// Folding is idempotent where lowering is not.
print(casefold(casefold("Straße")) == casefold("Straße"))

// It composes what it answers, so two spellings of one word fold alike without a pass of their own.
print(casefold("ÉCOLE") == casefold("e\u{301}cole"))

print(casefold(""), casefold("abc"), casefold("日本語"))

// -- as methods ----------------------------------------------------------------------------------

print("Straße".upper(), "HÉLLO".lower(), "  x  ".trim(), "Straße".casefold())
print("e\u{301}".normalize("NFC") == "é")

// -- what each one refuses -----------------------------------------------------------------------

// **`anything` is what hands the machine a value the checker cannot see**, an unannotated function
// answering `any` by design -- without it these are refused at the compile and the run-time check
// underneath, which is what a value arriving from a socket meets, is never reached.
anything(v) = v

print(normalize("x", "nfc") catch e -> e.message)
print(normalize("x", "NFC ") catch e -> e.message)
print(upper(anything(42)) catch e -> e.message)
print(lower(anything(true)) catch e -> e.message)
print(trim(anything([1])) catch e -> e.message)
print(casefold(anything(null)) catch e -> e.message)
print(normalize(anything(7), "NFC") catch e -> e.message)
