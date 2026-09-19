# The Python twin of dispatch.sl, written as `match` -- which Python 3.10 grew and which is the same
# construct slate has, a subject compared against literal patterns in order.


def kind(w):
    match w:
        case "add":
            return 1
        case "sub":
            return 2
        case "mul":
            return 3
        case "div":
            return 4
        case "mod":
            return 5
        case _:
            return 0


def run(words):
    total, i = 0, 0

    while i < 5000000:
        total = total + kind(words[i % 6])
        i = i + 1

    return total


print(run(["add", "sub", "mul", "div", "mod", "nope"]))
