// A module whose own top level waits before it has anything to export.

async after(ms, v)
    await sleep(ms)
    v

export val ready = await after(3, "ready")

print("the library finished")
