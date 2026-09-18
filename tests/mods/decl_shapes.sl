// A module that declares a class and also does something of its own, so that a VM which loaded only
// the declarations can be asked about both halves.

print("the shapes module ran")

export class Rect
    var w
    var h

    area(self) = self.w * self.h
