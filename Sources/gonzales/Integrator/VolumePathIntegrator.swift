// Path tracing
// "James Kajiya: The Rendering Equation"
// DOI: 10.1145/15922.15902

import Foundation  // exit

final class VolumePathIntegrator {

        init(scene: Scene, maxDepth: Int) {
                self.scene = scene
                self.maxDepth = maxDepth
        }

        private func lightDensity(
                light: Light,
                interaction: Interaction,
                sample: Vector,
                bsdf: BSDF
        ) throws -> FloatX {
                return try light.probabilityDensityFor(
                        samplingDirection: sample, from: interaction)
        }

        private func brdfDensity(
                light: Light,
                interaction: Interaction,
                sample: Vector,
                bsdf: BSDF
        ) -> FloatX {
                var density: FloatX = 0
                if interaction is SurfaceInteraction {
                        density = bsdf.probabilityDensity(wo: interaction.wo, wi: sample)
                }
                if let mediumInteraction = interaction as? MediumInteraction {
                        density = mediumInteraction.phase.evaluate(wo: mediumInteraction.wo, wi: sample)
                }
                return density
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
                estimate: inout RGBSpectrum,
                interaction: inout SurfaceInteraction,
                accelerator: Accelerator
        ) throws {
                try scene.intersect(
                        ray: ray,
                        tHit: &tHit,
                        interaction: &interaction,
                        accelerator: accelerator)
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
                sampler: Sampler,
                bsdf: BSDF,
                accelerator: Accelerator
        ) throws -> BSDFSample {
                let zero = BSDFSample()

                let (radiance, wi, lightDensity, visibility) = light.sample(
                        for: interaction, u: sampler.get2D())
                guard !radiance.isBlack && !lightDensity.isInfinite else {
                        return zero
                }
                guard try visibility.unoccluded(scene: scene) else {
                        return zero
                }
                var scatter: RGBSpectrum
                if let mediumInteraction = interaction as? MediumInteraction {
                        let phase = mediumInteraction.phase.evaluate(wo: mediumInteraction.wo, wi: wi)
                        scatter = RGBSpectrum(intensity: phase)
                } else {
                        let reflected = bsdf.evaluate(wo: interaction.wo, wi: wi)
                        let dot = absDot(wi, Vector(normal: interaction.shadingNormal))
                        scatter = reflected * dot
                }
                let estimate = scatter * radiance
                return BSDFSample(estimate, wi, lightDensity)
        }

        private func sampleBrdf(
                light: Light,
                interaction: Interaction,
                sampler: Sampler,
                bsdf: BSDF,
                accelerator: Accelerator
        ) throws -> BSDFSample {

                let zero = BSDFSample()

                var bsdfSample = BSDFSample()
                if let surfaceInteraction = interaction as? SurfaceInteraction {
                        (bsdfSample, _) = try bsdf.sample(wo: surfaceInteraction.wo, u: sampler.get3D())
                        guard bsdfSample.estimate != black && bsdfSample.probabilityDensity > 0 else {
                                return zero
                        }
                        bsdfSample.estimate *= absDot(bsdfSample.incoming, surfaceInteraction.shadingNormal)
                }
                if let mediumInteraction = interaction as? MediumInteraction {
                        let (value, _) = mediumInteraction.phase.samplePhase(
                                wo: interaction.wo,
                                sampler: sampler)
                        bsdfSample.estimate = RGBSpectrum(intensity: value)
                        bsdfSample.probabilityDensity = value
                }
                let ray = interaction.spawnRay(inDirection: bsdfSample.incoming)
                var tHit = FloatX.infinity
                var brdfInteraction = SurfaceInteraction()
                try scene.intersect(
                        ray: ray,
                        tHit: &tHit,
                        interaction: &brdfInteraction,
                        accelerator: accelerator)
                if !brdfInteraction.valid {
                        for light in scene.lights {
                                if light is InfiniteLight {
                                        let radiance = light.radianceFromInfinity(for: ray)
                                        bsdfSample.estimate *= radiance
                                        return bsdfSample
                                }
                        }
                        return zero
                }
                return bsdfSample
        }

        private func sampleLight(
                light: Light,
                interaction: Interaction,
                bsdf: BSDF,
                sampler: Sampler,
                accelerator: Accelerator
        ) throws -> RGBSpectrum {
                let bsdfSample = try sampleLightSource(
                        light: light,
                        interaction: interaction,
                        sampler: sampler,
                        bsdf: bsdf,
                        accelerator: accelerator)
                if bsdfSample.probabilityDensity == 0 {
                        print("light: black")
                        return black
                } else {
                        print("light: ", bsdfSample)
                        return bsdfSample.estimate / bsdfSample.probabilityDensity
                }
        }

        private func sampleBSDF(
                light: Light,
                interaction: Interaction,
                bsdf: BSDF,
                sampler: Sampler,
                accelerator: Accelerator
        ) throws -> RGBSpectrum {
                let bsdfSample = try sampleBrdf(
                        light: light,
                        interaction: interaction,
                        sampler: sampler,
                        bsdf: bsdf,
                        accelerator: accelerator)
                if bsdfSample.probabilityDensity == 0 {
                        return black
                } else {
                        return bsdfSample.estimate / bsdfSample.probabilityDensity
                }
        }

        private func sampleMultipleImportance(
                light: Light,
                interaction: Interaction,
                bsdf: BSDF,
                sampler: Sampler,
                accelerator: Accelerator
        ) throws -> RGBSpectrum {
                let lightSampler = MultipleImportanceSampler.MISSampler(
                        sample: sampleLightSource, density: lightDensity)
                let brdfSampler = MultipleImportanceSampler.MISSampler(
                        sample: sampleBrdf, density: brdfDensity)
                let misSampler = MultipleImportanceSampler(
                        scene: scene,
                        samplers: (lightSampler, brdfSampler))
                return try misSampler.evaluate(
                        accelerator: accelerator,
                        light: light,
                        interaction: interaction,
                        sampler: sampler,
                        bsdf: bsdf)
        }

        private func estimateDirect(
                light: Light,
                interaction: Interaction,
                bsdf: BSDF,
                sampler: Sampler,
                accelerator: Accelerator
        ) throws -> RGBSpectrum {
                if light.isDelta {
                        return try sampleLight(
                                light: light,
                                interaction: interaction,
                                bsdf: bsdf,
                                sampler: sampler,
                                accelerator: accelerator)
                }
                //return try sampleLight(
                //        light: light,
                //        interaction: interaction,
                //        bsdf: bsdf,
                //        sampler: sampler,
                //        accelerator: accelerator)
                //return try sampleBSDF(
                //        light: light,
                //        interaction: interaction,
                //        bsdf: bsdf,
                //        sampler: sampler,
                //        accelerator: accelerator)
                return try sampleMultipleImportance(
                        light: light,
                        interaction: interaction,
                        bsdf: bsdf,
                        sampler: sampler,
                        accelerator: accelerator)
        }

        private func sampleOneLight(
                at interaction: Interaction,
                bsdf: BSDF,
                with sampler: Sampler,
                accelerator: Accelerator,
                lightSampler: LightSampler
        ) throws -> RGBSpectrum {
                guard scene.lights.count > 0 else { return black }
                let (light, lightPdf) = try chooseLight(
                        sampler: sampler,
                        lightSampler: lightSampler)
                let estimate = try estimateDirect(
                        light: light,
                        interaction: interaction,
                        bsdf: bsdf,
                        sampler: sampler,
                        accelerator: accelerator)
                return estimate / lightPdf
        }

        private func russianRoulette(pathThroughputWeight: inout RGBSpectrum) -> Bool {
                let roulette = FloatX.random(in: 0..<1)
                let probability: FloatX = 0.5
                if roulette < probability {
                        return true
                } else {
                        pathThroughputWeight /= probability
                        return false
                }
        }

        private func sampleMedium(
                pathThroughputWeight: RGBSpectrum,
                mediumInteraction: MediumInteraction,
                sampler: Sampler,
                accelerator: Accelerator,
                lightSampler: LightSampler,
                ray: Ray
        ) throws -> (RGBSpectrum, Ray) {
                let dummy = BSDF()
                let estimate =
                        try pathThroughputWeight
                        * sampleOneLight(
                                at: mediumInteraction,
                                bsdf: dummy,
                                with: sampler,
                                accelerator: accelerator,
                                lightSampler: lightSampler)
                let (_, wi) = mediumInteraction.phase.samplePhase(
                        wo: -ray.direction,
                        sampler: sampler)
                let spawnedRay = mediumInteraction.spawnRay(inDirection: wi)
                return (estimate, spawnedRay)
        }

        private func sampleSurface(
                bounce: Int,
                surfaceInteraction: SurfaceInteraction,
                pathThroughputWeight: inout RGBSpectrum,
                ray: Ray,
                albedo: inout RGBSpectrum,
                firstNormal: inout Normal,
                sampler: Sampler,
                accelerator: Accelerator,
                lightSampler: LightSampler
        ) throws -> (RGBSpectrum, Ray, shouldBreak: Bool, shouldContinue: Bool, shouldReturn: Bool) {
                var ray = ray
                var estimate = black
                if bounce == 0 {
                        if let areaLight = surfaceInteraction.areaLight {
                                estimate +=
                                        pathThroughputWeight
                                        * areaLight.emittedRadiance(
                                                from: surfaceInteraction,
                                                inDirection: surfaceInteraction.wo)
                        }
                }
                guard bounce < maxDepth else {
                        return (black, ray, true, false, false)
                }
                if surfaceInteraction.material == -1 {
                        return (black, ray, true, false, false)
                }
                guard let material = materials[surfaceInteraction.material] else {
                        return (black, ray, true, false, false)
                }
                if material is Interface {
                        ray = surfaceInteraction.spawnRay(inDirection: ray.direction)
                        if let interface = surfaceInteraction.mediumInterface {
                                ray.medium = state.namedMedia[interface.interior]
                        }
                        return (black, ray, false, true, false)
                }
                let bsdf = material.getBSDF(interaction: surfaceInteraction)
                if bounce == 0 {
                        albedo = bsdf.albedo()
                        firstNormal = surfaceInteraction.normal
                }
                let lightEstimate =
                        try pathThroughputWeight
                        * sampleOneLight(
                                at: surfaceInteraction,
                                bsdf: bsdf,
                                with: sampler,
                                accelerator: accelerator,
                                lightSampler: lightSampler)
                estimate += lightEstimate
                let (bsdfSample, _) = try bsdf.sample(
                        wo: surfaceInteraction.wo, u: sampler.get3D())
                guard bsdfSample.probabilityDensity != 0 && !bsdfSample.probabilityDensity.isNaN else {
                        return (estimate, ray, false, false, true)
                }
                pathThroughputWeight *= bsdfSample.throughputWeight(normal: surfaceInteraction.normal)
                ray = surfaceInteraction.spawnRay(inDirection: bsdfSample.incoming)
                return (estimate, ray, false, false, false)
        }

        func getRadianceAndAlbedo(
                from ray: Ray,
                tHit: inout FloatX,
                with sampler: Sampler,
                accelerator: Accelerator,
                lightSampler: LightSampler
        ) throws
                -> (estimate: RGBSpectrum, albedo: RGBSpectrum, normal: Normal)
        {
                var estimate = black

                // Path throughput weight
                // The product of all BSDFs and cosines divided by the pdf
                // Π f |cosθ| / pdf
                var pathThroughputWeight = white

                var ray = ray
                var albedo = black
                var firstNormal = Normal()
                var interaction = SurfaceInteraction()
                for bounce in 0...maxDepth {
                        interaction.valid = false
                        try intersectOrInfiniteLights(
                                ray: ray,
                                tHit: &tHit,
                                bounce: bounce,
                                estimate: &estimate,
                                interaction: &interaction,
                                accelerator: accelerator)
                        if !interaction.valid {
                                break
                        }
                        var mediumL: RGBSpectrum
                        var mediumInteraction: MediumInteraction? = nil
                        if let medium = ray.medium {
                                (mediumL, mediumInteraction) = medium.sample(
                                        ray: ray,
                                        tHit: tHit,
                                        sampler: sampler)
                                pathThroughputWeight *= mediumL
                        }
                        if pathThroughputWeight.isBlack {
                                break
                        }
                        if let mediumInteraction {
                                guard bounce < maxDepth else {
                                        break
                                }
                                var mediumRadiance = black
                                (mediumRadiance, ray) = try sampleMedium(
                                        pathThroughputWeight: pathThroughputWeight,
                                        mediumInteraction: mediumInteraction,
                                        sampler: sampler,
                                        accelerator: accelerator,
                                        lightSampler: lightSampler,
                                        ray: ray)
                                estimate += mediumRadiance
                        } else {
                                var surfaceRadiance = black
                                var shouldBreak = false
                                var shouldContinue = false
                                var shouldReturn = false
                                (surfaceRadiance, ray, shouldBreak, shouldContinue, shouldReturn) =
                                        try sampleSurface(
                                                bounce: bounce,
                                                surfaceInteraction: interaction,
                                                pathThroughputWeight: &pathThroughputWeight,
                                                ray: ray,
                                                albedo: &albedo,
                                                firstNormal: &firstNormal,
                                                sampler: sampler,
                                                accelerator: accelerator,
                                                lightSampler: lightSampler)
                                if shouldReturn {
                                        estimate += surfaceRadiance
                                        return (estimate, white, Normal())
                                }
                                if shouldBreak {
                                        break
                                }
                                if shouldContinue {
                                        continue
                                }
                                estimate += surfaceRadiance
                        }
                        tHit = FloatX.infinity
                        if bounce > 3 && russianRoulette(pathThroughputWeight: &pathThroughputWeight) {
                                break
                        }
                }
                intelHack(&albedo)
                return (estimate: estimate, albedo: albedo, normal: firstNormal)
        }

        // HACK: Imagemagick's converts grayscale images to one channel which Intel
        // denoiser can't read. Make white a little colorful
        private func intelHack(_ albedo: inout RGBSpectrum) {
                if albedo.r == albedo.g && albedo.r == albedo.b {
                        albedo.r += 0.01
                }
        }

        let scene: Scene
        var maxDepth: Int
}
