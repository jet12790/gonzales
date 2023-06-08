///        Bidirectional Scattering Distribution Function
///        Describes how light is scattered by a surface.
struct BSDF {

        init() {
                bxdf = DiffuseBsdf(reflectance: black)
        }

        init(bxdf: BxDF, interaction: Interaction) {
                self.bxdf = bxdf
                geometricNormal = interaction.normal
                let ss = normalized(interaction.dpdu)
                let ts = cross(Vector(normal: interaction.shadingNormal), ss)
                frame = ShadingFrame(x: Vector(normal: interaction.shadingNormal), y: ss, z: ts)
        }

        private func isReflecting(wi: Vector, wo: Vector) -> Bool {
                return dot(wi, geometricNormal) * dot(wo, geometricNormal) > 0
        }

        func evaluate(wo woWorld: Vector, wi wiWorld: Vector) -> RGBSpectrum {
                var totalLightScattered = black
                let woLocal = frame.worldToLocal(world: woWorld)
                let wiLocal = frame.worldToLocal(world: wiWorld)
                let reflect = isReflecting(wi: wiWorld, wo: woWorld)
                if reflect && bxdf.isReflective {
                        totalLightScattered += bxdf.evaluate(wo: woLocal, wi: wiLocal)
                }
                if !reflect && bxdf.isTransmissive {
                        totalLightScattered += bxdf.evaluate(wo: woLocal, wi: wiLocal)
                }
                return totalLightScattered
        }

        func albedo() -> RGBSpectrum {
                return bxdf.albedo()
        }

        func sample(wo woWorld: Vector, u: ThreeRandomVariables)
                throws -> (bsdfSample: BSDFSample, isTransmissive: Bool)
        {
                let woLocal = frame.worldToLocal(world: woWorld)
                let bsdfSample = bxdf.sample(wo: woLocal, u: u)
                let wiWorld = frame.localToWorld(local: bsdfSample.incoming)
                return (
                        BSDFSample(bsdfSample.estimate, wiWorld, bsdfSample.probabilityDensity),
                        bxdf.isTransmissive
                )
        }

        func probabilityDensity(wo woWorld: Vector, wi wiWorld: Vector) -> FloatX {
                let wiLocal = frame.worldToLocal(world: wiWorld)
                let woLocal = frame.worldToLocal(world: woWorld)
                if woLocal.z == 0 { return 0 }
                return bxdf.probabilityDensity(wo: woLocal, wi: wiLocal)
        }

        var bxdf: BxDF
        var geometricNormal = Normal()
        var frame = ShadingFrame()
}
