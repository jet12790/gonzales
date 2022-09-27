public struct Point2<T> {

        public init(x: T, y: T) {
                self.x = x
                self.y = y
        }

        subscript(index: Int) -> T {

                get {
                        switch index {
                        case 0: return x
                        case 1: return y
                        default: return x
                        }
                }

                set(newValue) {
                        switch index {
                        case 0: x = newValue
                        case 1: y = newValue
                        default: break
                        }
                }
        }

        public var x: T
        public var y: T
}

extension Point2: CustomStringConvertible {
        public var description: String {
                return "[ \(x) \(y) ]"
        }
}

extension Point2 where T: FloatingPoint {
        public init() { self.init(x: 0, y: 0) }
        init(from: Vector2<T>) { self.init(x: from.x, y: from.y) }
}

extension Point2 where T: BinaryInteger {
        public init() {
                self.init(x: 0, y: 0)
        }
}

public typealias Point2I = Point2<Int>
public typealias Point2F = Point2<FloatX>

extension Point2 where T: BinaryInteger {

        init(from: Point2I) {
                self.init(
                        x: T(from.x),
                        y: T(from.y))
        }

        init(from: Vector2<T>) {
                self.init(
                        x: T(from.x),
                        y: T(from.y))
        }

        init(from: Point2F) {
                self.init(
                        x: T(from.x),
                        y: T(from.y))
        }

        init(from: Vector2F) {
                self.init(
                        x: T(from.x),
                        y: T(from.y))
        }
}

extension Point2 where T: FloatingPoint {
        init(from: Point2I) {
                self.init(
                        x: T(from.x),
                        y: T(from.y))
        }
}

func * (i: Point2I, f: Point2F) -> Point2F {
        return Point2F(from: i) * f
}

func * (a: Point2F, b: Point2F) -> Point2F {
        return Point2F(x: a.x * b.x, y: a.y * b.y)
}

extension Point2 where T: FloatingPoint {

        public static func + (left: Point2<T>, right: Point2<T>) -> Point2 {
                return Point2(x: left.x + right.x, y: left.y + right.y)
        }

        public static func * (left: T, right: Point2<T>) -> Point2 {
                return Point2(x: left * right.x, y: left * right.y)
        }

        public static func - (left: Point2<T>, right: Vector2<T>) -> Vector2<T> {
                return Vector2(x: left.x - right.x, y: left.y - right.y)
        }

        public static func - (left: Point2<T>, right: Point2<T>) -> Vector2<T> {
                return Vector2(x: left.x - right.x, y: left.y - right.y)
        }

}

extension Point2 where T: BinaryInteger {

        public static func - (left: Point2<T>, right: Point2<T>) -> Vector2<T> {
                return Vector2<T>(x: left.x - right.x, y: left.y - right.y)
        }

        public static func + (left: Point2<T>, right: Point2<T>) -> Point2<T> {
                return Point2<T>(x: left.x + right.x, y: left.y + right.y)
        }
}
