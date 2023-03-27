struct CoatedDiffuseBsdf: BxDF {

        init(reflectance: RGBSpectrum, roughness: (FloatX, FloatX)) {
                self.reflectance = reflectance
                self.roughness = roughness
                self.topBxdf = DielectricBsdf(
                        distribution: TrowbridgeReitzDistribution(alpha: (1, 1)),
                        eta: 1)
                self.bottomBxdf = DiffuseBxdf(reflectance: reflectance)
        }

        func evaluate(wo: Vector, wi: Vector) -> RGBSpectrum {
                assert(wo.z > 0)
                assert(sameHemisphere(wi, wo))
                // enterInterface = top
                // enteredTop = true

                let numberOfSamples = 1
                var evaluation = black

                evaluation = FloatX(numberOfSamples) * topBxdf.evaluate(wo: wo, wi: wi)
                return bottomBxdf.evaluate(wo: wo, wi: wi)
        }

        //func sample(wo: Vector, u: Point2F) -> (RGBSpectrum, Vector, FloatX) {
        //        unimplemented()
        //}

        //func probabilityDensity(wo: Vector, wi: Vector) -> FloatX {
        //        unimplemented()
        //}

        func albedo() -> RGBSpectrum { return reflectance }

        let reflectance: RGBSpectrum
        let roughness: (FloatX, FloatX)

        let topBxdf: DielectricBsdf
        let bottomBxdf: DiffuseBxdf
}
