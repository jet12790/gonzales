struct SurfaceInteraction: Interaction {

        init(
                valid: Bool = false,
                position: Point = Point(),
                normal: Normal = Normal(),
                shadingNormal: Normal = Normal(),
                wo: Vector = Vector(),
                dpdu: Vector = Vector(),
                uv: Point2F = Point2F(),
                faceIndex: Int = 0,
                areaLight: AreaLight? = nil,
                material: MaterialIndex = -1,
                mediumInterface: MediumInterface? = nil,
                bsdf: GlobalBsdf = DummyBsdf()
        ) {
                self.valid = valid
                self.position = position
                self.normal = normal
                self.shadingNormal = shadingNormal
                self.wo = wo
                self.dpdu = dpdu
                self.uv = uv
                self.faceIndex = faceIndex
                self.material = material
                self.mediumInterface = mediumInterface
                self.bsdf = bsdf
        }

        func evaluateDistributionFunction(wi: Vector) -> RGBSpectrum {
                let reflected = bsdf.evaluateWorld(wo: wo, wi: wi)
                let dot = absDot(wi, Vector(normal: shadingNormal))
                let scatter = reflected * dot
                return scatter
        }

        func sampleDistributionFunction(sampler: Sampler) -> BsdfSample {
                var (bsdfSample, _) = bsdf.sampleWorld(wo: wo, u: sampler.get3D())
                bsdfSample.estimate *= absDot(bsdfSample.incoming, shadingNormal)
                return bsdfSample
        }

        func evaluateProbabilityDensity(wi: Vector) -> FloatX {
                return bsdf.probabilityDensityWorld(wo: wo, wi: wi)
        }

        var valid: Bool
        var position: Point
        var normal: Normal
        var shadingNormal: Normal
        var wo: Vector
        var dpdu: Vector
        var uv: Point2F
        var faceIndex: Int
        var areaLight: AreaLight?
        var material: MaterialIndex
        var mediumInterface: MediumInterface?

        var bsdf: GlobalBsdf
}

extension SurfaceInteraction: CustomStringConvertible {
        var description: String {
                return "[pos: \(position) n: \(normal) wo: \(wo) ]"
        }
}
