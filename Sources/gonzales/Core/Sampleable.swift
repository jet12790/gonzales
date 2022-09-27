/// A type that can be sampled.
///
/// For example, to render area lights a renderer typically chooses a point
/// on the area light and calculates the light from there. If many such
/// points are chosen and the light calculated, the average approximates
/// the analytical solution.

protocol Sampleable {
        func sample(u: Point2F) -> (interaction: Interaction, pdf: FloatX)
        func sample(ref: Interaction, u: Point2F) -> (Interaction, FloatX)
        func probabilityDensityFor(
                samplingDirection direction: Vector,
                from interaction: Interaction
        )
                throws -> FloatX
        func area() -> FloatX
}

extension Sampleable {
        func sample(ref: Interaction, u: Point2F) -> (Interaction, FloatX) {
                var (intr, pdf) = sample(u: u)
                let wi: Vector = normalized(intr.position - ref.position)
                let squaredDistance = distanceSquared(ref.position, intr.position)
                let angle = absDot(Vector(normal: intr.normal), -wi)
                pdf *= squaredDistance / angle
                return (intr, pdf)
        }
}

extension Sampleable where Self: Intersectable {
        func probabilityDensityFor(
                samplingDirection direction: Vector,
                from interaction: Interaction
        )
                throws -> FloatX
        {
                let ray = interaction.spawnRay(inDirection: direction)
                var tHit: FloatX = 0.0
                let isect = try intersect(ray: ray, tHit: &tHit, material: -1)
                if !isect.valid {
                        return 0
                }
                let squaredDistance = distanceSquared(interaction.position, isect.position)
                let angle = absDot(isect.normal, -direction)
                let angleTimesArea = angle * area()
                let density = squaredDistance / angleTimesArea
                if density.isInfinite {
                        return 0
                }
                return density
        }
}
