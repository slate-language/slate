export type Point = { x: num, y: num }

type Secret = { hidden: bool }

export origin() = { x: 0, y: 0 }

export isSecret(v) = v is Secret
