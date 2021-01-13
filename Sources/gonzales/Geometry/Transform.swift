import Foundation // tan

typealias Transform = GenericTransformWithInverse<Matrix>

struct GenericTransformWithInverse<TransformMatrix: MatrixProtocol> {

        public init(matrix: TransformMatrix, inverseMatrix: TransformMatrix) {
                self.matrix = matrix
                self.inverseMatrix = inverseMatrix
        }

        public init(matrix: TransformMatrix) throws {
                self.init(matrix: matrix, inverseMatrix: matrix.inverse)
        }

        public init() {
                matrix = TransformMatrix()
                inverseMatrix = TransformMatrix()
        }

        var inverse: GenericTransformWithInverse {
                get {
                        return GenericTransformWithInverse(matrix: self.inverseMatrix, inverseMatrix: self.matrix)
                }
        }

        private var matrix: TransformMatrix
        private var inverseMatrix: TransformMatrix
}

enum GenericTransformWithoutInverseError {
        case notAffine
}

struct GenericTransformWithoutInverse<TransformMatrix: MatrixProtocol> {

        public init() {
                m = TransformMatrix()
        }

        public init(m: TransformMatrix) {
                self.m = m
        }

        public init(_ transform: GenericTransformWithoutInverse) {
                self.m = transform.m
        }

        var inverse: GenericTransformWithoutInverse {
                get {
                        return GenericTransformWithoutInverse(m: self.m.inverse)
                }
        }

        var isAffine: Bool {
                return m.isAffine
        }

        public var m: TransformMatrix
}

extension Transform {

        public static func * (t: Transform, v: Vector) -> Vector {
                let m = t.matrix
                return Vector(x: m[0, 0] * v.x + m[0, 1] * v.y + m[0, 2] * v.z,
                              y: m[1, 0] * v.x + m[1, 1] * v.y + m[1, 2] * v.z,
                              z: m[2, 0] * v.x + m[2, 1] * v.y + m[2, 2] * v.z)
        }

        public static func * (t: Transform, n: Normal) -> Normal {
                let i = t.inverse.matrix
                return Normal(x: i[0, 0] * n.x + i[1, 0] * n.y + i[2, 0] * n.z,
                              y: i[0, 1] * n.x + i[1, 1] * n.y + i[2, 1] * n.z,
                              z: i[0, 2] * n.x + i[1, 2] * n.y + i[2, 2] * n.z)
        }

        public static func * (t: Transform, p: Point) -> Point {
                let m = t.matrix
                let point = Point(x: m[0, 0] * p.x + m[0, 1] * p.y + m[0, 2] * p.z + m[0, 3],
                                  y: m[1, 0] * p.x + m[1, 1] * p.y + m[1, 2] * p.z + m[1, 3],
                                  z: m[2, 0] * p.x + m[2, 1] * p.y + m[2, 2] * p.z + m[2, 3])
                let wp = m[3, 0] * p.x + m[3, 1] * p.y + m[3, 2] * p.z + m[3, 3]
                return point / wp
        }

        public static func *=(left: inout Transform, right: Transform) throws {
                left = try left * right
        }

        public static func * (left: Transform, right: Transform) throws -> Transform {
                return try Transform(matrix: left.matrix * right.matrix)
        }
}

extension Transform: CustomStringConvertible {
        public var description: String {
                return "Transform:\n" + matrix.description + "\n"
        }
}

extension Transform {
        static public func makePerspective(fov: FloatX, near: FloatX, far: FloatX) throws -> Transform {
                let persp = Matrix(t00: 1, t01: 0, t02: 0, t03: 0,
                                   t10: 0, t11: 1, t12: 0, t13: 0,
                                   t20: 0, t21: 0, t22: fov / (fov - near), t23: -fov * near / (fov - near),
                                   t30: 0, t31: 0, t32: 1, t33: 0)
                let invTanAng = 1 / tan(radians(deg: fov) / 2)
                return try makeScale(x: invTanAng, y: invTanAng, z: 1) * Transform(matrix: persp)
        }

        static func makeScale(x: FloatX, y: FloatX, z: FloatX) throws -> Transform {
                let m = Matrix(t00: x, t01: 0, t02: 0, t03: 0,
                               t10: 0, t11: y, t12: 0, t13: 0,
                               t20: 0, t21: 0, t22: z, t23: 0,
                               t30: 0, t31: 0, t32: 0, t33: 1)
                return try Transform(matrix: m)
        }

        static func makeTranslation(from delta: Vector) throws -> Transform {
                let m = Matrix(t00: 1, t01: 0, t02: 0, t03: delta.x,
                               t10: 0, t11: 1, t12: 0, t13: delta.y,
                               t20: 0, t21: 0, t22: 1, t23: delta.z,
                               t30: 0, t31: 0, t32: 0, t33: 1)
                return try Transform(matrix: m)
        }
}

extension Transform {

        static func * (transform: Transform, ray: Ray) -> Ray {
                return Ray(origin: transform * ray.origin,
                           direction: transform * ray.direction)
        }
}

extension Transform {

        static func * (left: Transform, right: SurfaceInteraction) -> SurfaceInteraction {
                return SurfaceInteraction(position: left * right.position,
                                        normal: normalized(left * right.normal),
                                        shadingNormal: normalized(left * right.shadingNormal),
                                        wo: normalized(left * right.wo),
                                        dpdu: left * right.dpdu,
                                        uv: right.uv,
                                        faceIndex: right.faceIndex,
                                        primitive: right.primitive)
        }
}

