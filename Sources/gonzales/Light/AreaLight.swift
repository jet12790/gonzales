import Foundation

struct AreaLight: Boundable, Intersectable {

        init(brightness: RgbSpectrum, shape: Shape, alpha: FloatX) {
                self.brightness = brightness
                self.shape = shape
                self.alpha = alpha
        }

        func emittedRadiance(from interaction: Interaction, inDirection direction: Vector)
                -> RgbSpectrum
        {
                return dot(Vector(normal: interaction.normal), direction) > 0 ? brightness : black
        }

        func sample(for ref: Interaction, u: TwoRandomVariables) -> (
                radiance: RgbSpectrum, direction: Vector, pdf: FloatX, visibility: Visibility
        ) {
                let (shapeInteraction, pdf) = shape.sample(ref: ref, u: u)
                let direction: Vector = normalized(shapeInteraction.position - ref.position)
                assert(!direction.isNaN)
                let visibility = Visibility(from: ref, to: shapeInteraction)
                let radiance = emittedRadiance(from: shapeInteraction, inDirection: -direction)
                return (radiance, direction, pdf, visibility)
        }

        func probabilityDensityFor(samplingDirection direction: Vector, from reference: Interaction)
                throws -> FloatX
        {
                return try shape.probabilityDensityFor(
                        samplingDirection: direction, from: reference)
        }

        func radianceFromInfinity(for ray: Ray) -> RgbSpectrum { return black }

        func power() -> FloatX {
                return brightness.average() * shape.area() * FloatX.pi
        }

        var isDelta: Bool { return false }

        func worldBound() -> Bounds3f {
                return shape.worldBound()
        }

        func objectBound() -> Bounds3f {
                return shape.objectBound()
        }

        func intersect(
                ray: Ray,
                tHit: inout FloatX,
                material: MaterialIndex,
                interaction: inout SurfaceInteraction
        ) throws {
                if alpha == 0 { return }
                try shape.intersect(
                        ray: ray,
                        tHit: &tHit,
                        material: material,
                        interaction: &interaction)
                interaction.areaLight = self
        }

        func setBsdf(interaction: inout SurfaceInteraction) {
                let diffuse = Diffuse(reflectance: ConstantTexture(value: white))
                diffuse.setBsdf(interaction: &interaction)
        }

        let shape: Shape
        let brightness: RgbSpectrum
        let alpha: FloatX
}
