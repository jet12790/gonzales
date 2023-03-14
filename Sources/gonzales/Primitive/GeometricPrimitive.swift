struct GeometricPrimitive: Boundable, Intersectable, Material {

        func intersect(
                ray: Ray,
                tHit: inout FloatX,
                material: MaterialIndex,
                interaction: inout SurfaceInteraction
        ) throws {
                // argument material is unused
                try shape.intersect(
                        ray: ray,
                        tHit: &tHit,
                        material: self.material,
                        interaction: &interaction)
        }

        func worldBound() -> Bounds3f {
                return shape.worldBound()
        }

        func objectBound() -> Bounds3f {
                return shape.objectBound()
        }

        func computeScatteringFunctions(interaction: Interaction) -> BSDF {
                return materials[material]!.computeScatteringFunctions(interaction: interaction)
        }

        var shape: Shape
        var material: MaterialIndex
        var mediumInterface: MediumInterface?
}

typealias MaterialIndex = Int
var materials: [Int: Material] = [:]
var materialCounter: MaterialIndex = 0
