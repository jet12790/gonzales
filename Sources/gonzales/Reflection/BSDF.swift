///        Bidirectional Scattering Distribution Function
///        Describes how light is scattered by a surface.
struct BSDF {

        init() {
                bxdf = LambertianReflection(reflectance: black)
                ng = Normal()
                ns = Normal()
                ss = up
                ts = up
        }

        init(interaction: Interaction) {
                bxdf = LambertianReflection(reflectance: black)
                ng = interaction.normal
                ns = interaction.shadingNormal
                ss = normalized(interaction.dpdu)
                ts = cross(Vector(normal: ns), ss)
        }

        mutating func set(bxdf: BxDF) {
                self.bxdf = bxdf
        }

        func evaluate(wo woWorld: Vector, wi wiWorld: Vector) -> Spectrum {
                var totalLightScattered = black
                let woLocal = worldToLocal(world: woWorld)
                let wiLocal = worldToLocal(world: wiWorld)
                let reflect = dot(wiWorld, ng) * dot(woWorld, ng) > 0
                if reflect && bxdf.isReflective {
                        //print("reflect and reflective")
                        totalLightScattered += bxdf.evaluate(wo: woLocal, wi: wiLocal)
                }
                if !reflect && bxdf.isTransmissive {
                        //print("not reflect and transmissive")
                        totalLightScattered += bxdf.evaluate(wo: woLocal, wi: wiLocal)
                }
                return totalLightScattered
        }

        func albedo() -> Spectrum {
                return bxdf.albedo()
        }

        private func worldToLocal(world: Vector) -> Vector {
                return normalized(Vector(x: dot(world, ss), y: dot(world, ts), z: dot(world, ns)))
        }

        private func localToWorld(local: Vector) -> Vector {
                return normalized(
                        Vector(
                                x: ss.x * local.x + ts.x * local.y + ns.x * local.z,
                                y: ss.y * local.x + ts.y * local.y + ns.y * local.z,
                                z: ss.z * local.x + ts.z * local.y + ns.z * local.z))
        }

        func sample(wo woWorld: Vector, u: Point2F) throws -> (
                L: Spectrum, wi: Vector, pdf: FloatX, isTransmissive: Bool
        ) {
                let woLocal = worldToLocal(world: woWorld)
                let (estimate, wiLocal, density) = bxdf.sample(wo: woLocal, u: u)
                let wiWorld = localToWorld(local: wiLocal)
                return (estimate, wiWorld, density, bxdf.isTransmissive)
        }

        func probabilityDensity(wo woWorld: Vector, wi wiWorld: Vector) -> FloatX {
                let wiLocal = worldToLocal(world: wiWorld)
                let woLocal = worldToLocal(world: woWorld)
                if woLocal.z == 0 { return 0 }
                return bxdf.probabilityDensity(wo: woLocal, wi: wiLocal)
        }

        var bxdf: BxDF
        var ng = Normal()
        var ns = Normal()
        var ss = up
        var ts = up
        var eta: FloatX = 1.0
}
