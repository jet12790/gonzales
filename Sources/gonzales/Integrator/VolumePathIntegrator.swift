// Path tracing
// "James Kajiya: The Rendering Equation"
// DOI: 10.1145/15922.15902

final class VolumePathIntegrator {

        init(scene: Scene, maxDepth: Int) {
                self.scene = scene
                self.maxDepth = maxDepth
        }

        private func brdfDensity(
                light: Light,
                interaction: Interaction,
                sample: Vector
        ) -> FloatX {
                return interaction.evaluateProbabilityDensity(wi: sample)
        }

        private func chooseLight(
                sampler: Sampler,
                lightSampler: LightSampler
        ) throws
                -> (Light, FloatX)
        {
                return lightSampler.chooseLight()
        }

        private func intersectOrInfiniteLights(
                ray: Ray,
                tHit: inout FloatX,
                bounce: Int,
                estimate: inout RgbSpectrum,
                interaction: inout SurfaceInteraction
        ) throws {
                try scene.intersect(
                        ray: ray,
                        tHit: &tHit,
                        interaction: &interaction)
                if interaction.valid {
                        return
                }
                let radiance = scene.infiniteLights.reduce(
                        black,
                        { accumulated, light in accumulated + light.radianceFromInfinity(for: ray) }
                )
                if bounce == 0 { estimate += radiance }
        }

        private func sampleLightSource(
                light: Light,
                interaction: Interaction,
                sampler: Sampler
        ) throws -> BsdfSample {
                let (radiance, wi, lightDensity, visibility) = light.sample(
                        for: interaction, u: sampler.get2D())
                guard !radiance.isBlack && !lightDensity.isInfinite else {
                        return invalidBsdfSample
                }
                guard try visibility.unoccluded(scene: scene) else {
                        return invalidBsdfSample
                }
                let scatter = interaction.evaluateDistributionFunction(wi: wi)
                let estimate = scatter * radiance
                return BsdfSample(estimate, wi, lightDensity)
        }

        private func sampleDistributionFunction(
                light: Light,
                interaction: Interaction,
                sampler: Sampler
        ) throws -> BsdfSample {

                let zero = BsdfSample()
                var bsdfSample = interaction.sampleDistributionFunction(sampler: sampler)
                guard bsdfSample.estimate != black && bsdfSample.probabilityDensity > 0 else {
                        return zero
                }
                let ray = interaction.spawnRay(inDirection: bsdfSample.incoming)
                var tHit = FloatX.infinity
                var brdfInteraction = SurfaceInteraction()
                try scene.intersect(
                        ray: ray,
                        tHit: &tHit,
                        interaction: &brdfInteraction)
                if brdfInteraction.valid {
                        return zero
                }
                for light in scene.lights {
                        switch light {
                        case .infinite(let infiniteLight):
                                let radiance = infiniteLight.radianceFromInfinity(for: ray)
                                bsdfSample.estimate *= radiance
                                return bsdfSample  // TODO: Just one infinite light?
                        default:
                                break
                        }
                }
                return zero
        }

        private func sampleLight(
                light: Light,
                interaction: Interaction,
                sampler: Sampler
        ) throws -> RgbSpectrum {
                let lightSample = try sampleLightSource(
                        light: light,
                        interaction: interaction,
                        sampler: sampler)
                if lightSample.probabilityDensity == 0 {
                        return black
                } else {
                        return lightSample.estimate / lightSample.probabilityDensity
                }
        }

        private func sampleGlobalBsdf(
                light: Light,
                interaction: Interaction,
                sampler: Sampler
        ) throws -> RgbSpectrum {
                let bsdfSample = try sampleDistributionFunction(
                        light: light,
                        interaction: interaction,
                        sampler: sampler)
                if bsdfSample.probabilityDensity == 0 {
                        return black
                } else {
                        return bsdfSample.estimate / bsdfSample.probabilityDensity
                }
        }

        //@_noAllocation
        private func sampleMultipleImportance(
                light: Light,
                interaction: Interaction,
                sampler: Sampler
        ) throws -> RgbSpectrum {

                let lightSample = try sampleLightSource(
                        light: light,
                        interaction: interaction,
                        sampler: sampler)
                let brdfDensity = brdfDensity(
                        light: light,
                        interaction: interaction,
                        sample: lightSample.incoming)
                let lightWeight = powerHeuristic(f: lightSample.probabilityDensity, g: brdfDensity)
                let a =
                        lightSample.probabilityDensity == 0
                        ? black : lightSample.estimate * lightWeight / lightSample.probabilityDensity

                let brdfSample = try sampleDistributionFunction(
                        light: light,
                        interaction: interaction,
                        sampler: sampler)
                let lightDensity = try light.probabilityDensityFor(
                        samplingDirection: brdfSample.incoming,
                        from: interaction)
                let brdfWeight = powerHeuristic(f: brdfSample.probabilityDensity, g: lightDensity)
                let b =
                        brdfSample.probabilityDensity == 0
                        ? black : brdfSample.estimate * brdfWeight / brdfSample.probabilityDensity

                return a + b
        }

        private func estimateDirect(
                light: Light,
                interaction: Interaction,
                sampler: Sampler
        ) throws -> RgbSpectrum {
                if light.isDelta {
                        return try sampleLight(
                                light: light,
                                interaction: interaction,
                                sampler: sampler)
                }
                // For debugging uncomment one of the two following methods:
                //return try sampleLight(
                //        light: light,
                //        interaction: interaction,
                //        sampler: sampler)
                //return try sampleGlobalBsdf(
                //        light: light,
                //        interaction: interaction,
                //        sampler: sampler)

                return try sampleMultipleImportance(
                        light: light,
                        interaction: interaction,
                        sampler: sampler)
        }

        //@_noAllocation
        private func sampleOneLight(
                at interaction: Interaction,
                with sampler: Sampler,
                lightSampler: LightSampler
        ) throws -> RgbSpectrum {
                let (light, lightPdf) = try chooseLight(
                        sampler: sampler,
                        lightSampler: lightSampler)
                let estimate = try estimateDirect(
                        light: light,
                        interaction: interaction,
                        sampler: sampler)
                return estimate / lightPdf
        }

        private func stopWithRussianRoulette(bounce: Int, pathThroughputWeight: inout RgbSpectrum) -> Bool {
                if pathThroughputWeight.maxValue < 1 && bounce > 1 {
                        let probability: FloatX = max(0, 1 - pathThroughputWeight.maxValue)
                        let roulette = FloatX.random(in: 0..<1)
                        if roulette < probability {
                                return true
                        }
                        pathThroughputWeight /= 1 - probability
                }
                return false
        }

        private func sampleMedium(
                pathThroughputWeight: RgbSpectrum,
                mediumInteraction: MediumInteraction,
                sampler: Sampler,
                lightSampler: LightSampler,
                ray: Ray
        ) throws -> (RgbSpectrum, Ray) {
                let estimate =
                        try pathThroughputWeight
                        * sampleOneLight(
                                at: mediumInteraction,
                                with: sampler,
                                lightSampler: lightSampler)
                let (_, wi) = mediumInteraction.phase.samplePhase(
                        wo: -ray.direction,
                        sampler: sampler)
                let spawnedRay = mediumInteraction.spawnRay(inDirection: wi)
                return (estimate, spawnedRay)
        }

        //@_noAllocation
        func getRadianceAndAlbedo(
                from ray: Ray,
                tHit: inout FloatX,
                with sampler: Sampler,
                lightSampler: LightSampler
        ) throws
                -> (estimate: RgbSpectrum, albedo: RgbSpectrum, normal: Normal)
        {
                var estimate = black

                // Path throughput weight
                // The product of all GlobalBsdfs and cosines divided by the pdf
                // Π f |cosθ| / pdf
                var pathThroughputWeight = white

                var ray = ray
                var albedo = black
                var firstNormal = zeroNormal
                var interaction = SurfaceInteraction()
                for bounce in 0...maxDepth {
                        interaction.valid = false
                        try intersectOrInfiniteLights(
                                ray: ray,
                                tHit: &tHit,
                                bounce: bounce,
                                estimate: &estimate,
                                interaction: &interaction)
                        if !interaction.valid {
                                break
                        }
                        let (mediumL, mediumInteraction) =
                                ray.medium?.sample(ray: ray, tHit: tHit, sampler: sampler) ?? (white, nil)
                        pathThroughputWeight *= mediumL
                        if pathThroughputWeight.isBlack {
                                break
                        }
                        guard bounce < maxDepth else {
                                break
                        }
                        if let mediumInteraction {
                                var mediumRadiance = black
                                (mediumRadiance, ray) = try sampleMedium(
                                        pathThroughputWeight: pathThroughputWeight,
                                        mediumInteraction: mediumInteraction,
                                        sampler: sampler,
                                        lightSampler: lightSampler,
                                        ray: ray)
                                estimate += mediumRadiance
                        } else {
                                var surfaceInteraction = interaction
                                if bounce == 0 {
                                        if let areaLight = surfaceInteraction.areaLight {
                                                estimate +=
                                                        pathThroughputWeight
                                                        * areaLight.emittedRadiance(
                                                                from: surfaceInteraction,
                                                                inDirection: surfaceInteraction.wo)
                                        }
                                }
                                if surfaceInteraction.material == noMaterial {
                                        break
                                }
                                if materials[surfaceInteraction.material].isInterface {
                                        var spawnedRay = surfaceInteraction.spawnRay(
                                                inDirection: ray.direction)
                                        if let interface = surfaceInteraction.mediumInterface {
                                                spawnedRay.medium = state.namedMedia[interface.interior]
                                        }
                                        ray = spawnedRay
                                        continue
                                }
                                surfaceInteraction.setBsdf()
                                if bounce == 0 {
                                        albedo = surfaceInteraction.bsdf.albedo()
                                        firstNormal = surfaceInteraction.normal
                                }
                                let lightEstimate =
                                        try pathThroughputWeight
                                        * sampleOneLight(
                                                at: surfaceInteraction,
                                                with: sampler,
                                                lightSampler: lightSampler)
                                estimate += lightEstimate
                                let (bsdfSample, _) = surfaceInteraction.bsdf.sampleWorld(
                                        wo: surfaceInteraction.wo, u: sampler.get3D())
                                guard
                                        bsdfSample.probabilityDensity != 0
                                                && !bsdfSample.probabilityDensity.isNaN
                                else {
                                        return (estimate, albedo, firstNormal)
                                }
                                pathThroughputWeight *= bsdfSample.throughputWeight(
                                        normal: surfaceInteraction.normal)
                                let spawnedRay = surfaceInteraction.spawnRay(inDirection: bsdfSample.incoming)
                                ray = spawnedRay
                        }
                        tHit = FloatX.infinity
                        if stopWithRussianRoulette(
                                bounce: bounce,
                                pathThroughputWeight: &pathThroughputWeight)
                        {
                                break
                        }
                }
                intelHack(&albedo)
                return (estimate: estimate, albedo: albedo, normal: firstNormal)
        }

        // HACK: Imagemagick's converts grayscale images to one channel which Intel
        // denoiser can't read. Make white a little colorful
        private func intelHack(_ albedo: inout RgbSpectrum) {
                if albedo.r == albedo.g && albedo.r == albedo.b {
                        albedo.r += 0.01
                }
        }

        let scene: Scene
        var maxDepth: Int
}
