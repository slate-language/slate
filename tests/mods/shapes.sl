export type Point = { x: number, y: number }

type Secret = { hidden: bool }

export origin() = { x: 0, y: 0 }

export isSecret(v) = v is Secret
