// Path tracing
// "James Kajiya: The Rendering Equation"
// DOI: 10.1145/15922.15902

final class PathIntegrator {

        init(scene: Scene, maxDepth: Int) {
                self.scene = scene
                self.maxDepth = maxDepth
        }

        private func chooseLight(
                inScene scene: Scene,
                withSampler sampler: Sampler
        ) throws
                -> (Light, FloatX)
        {

                assert(scene.lights.count > 0)
                guard scene.lights.count + scene.infiniteLights.count > 0 else {
                        throw RenderError.noLights
                }
                let u = sampler.get1D()
                let lightNum = Int(u * FloatX(scene.lights.count))
                let light = scene.lights[lightNum]
                let probabilityDensity: FloatX = 1.0 / FloatX(scene.lights.count)
                return (light, probabilityDensity)
        }

        func sampleOneLight(
                at interaction: SurfaceInteraction,
                bsdf: BSDF,
                with sampler: Sampler
        ) throws -> Spectrum {

                guard scene.lights.count > 0 else { return black }
                let (light, lightPdf) = try chooseLight(inScene: scene, withSampler: sampler)
                let estimate = try estimateDirect(
                        light: light,
                        atInteraction: interaction,
                        bsdf: bsdf,
                        withSampler: sampler)
                return estimate / lightPdf
        }

        @_semantics("optremark")
        private func estimateDirect(
                light: Light,
                atInteraction interaction: SurfaceInteraction,
                bsdf: BSDF,
                withSampler sampler: Sampler
        ) throws -> Spectrum {

                let zero = (black, FloatX(0.0), up)

                func sampleLightSource() throws -> (
                        estimate: Spectrum, density: FloatX, sample: Vector
                ) {
                        let (radiance, wi, lightDensity, visibility) = light.sample(
                                for: interaction, u: sampler.get2D())
                        guard !radiance.isBlack && !lightDensity.isInfinite else {
                                return zero
                        }
                        guard try visibility.unoccluded(scene: scene) else {
                                return zero
                        }
                        let reflected = bsdf.evaluate(wo: interaction.wo, wi: wi)
                        let dot = absDot(wi, Vector(normal: interaction.shadingNormal))
                        let scatter = reflected * dot
                        let estimate = scatter * radiance
                        return (estimate: estimate, density: lightDensity, sample: wi)
                }

                func lightDensity(sample: Vector) throws -> FloatX {
                        return try light.probabilityDensityFor(
                                samplingDirection: sample, from: interaction)
                }

                func sampleBrdf() throws -> (estimate: Spectrum, density: FloatX, sample: Vector) {
                        var (scatter, wi, bsdfDensity, _) = try bsdf.sample(
                                wo: interaction.wo, u: sampler.get2D())
                        guard scatter != black && bsdfDensity > 0 else {
                                return zero
                        }
                        scatter *= absDot(wi, interaction.shadingNormal)
                        let ray = interaction.spawnRay(inDirection: wi)
                        var tHit = FloatX.infinity
                        var brdfInteraction = SurfaceInteraction()
                        try scene.intersect(ray: ray, tHit: &tHit, interaction: &brdfInteraction)
                        if !brdfInteraction.valid {
                                for light in scene.lights {
                                        if light is InfiniteLight {
                                                let radiance = light.radianceFromInfinity(for: ray)
                                                let estimate = scatter * radiance
                                                return (
                                                        estimate: estimate, density: bsdfDensity,
                                                        sample: wi
                                                )
                                        }
                                }
                                return zero
                        }
                        guard let brdfAreaLight = brdfInteraction.areaLight else {
                                return zero
                        }
                        guard let areaLight = light as? AreaLight else {
                                return zero
                        }
                        guard brdfAreaLight === areaLight else {
                                return zero
                        }
                        let radiance = brdfAreaLight.emittedRadiance(
                                from: brdfInteraction,
                                inDirection: -wi)
                        guard radiance != black else {
                                return zero
                        }
                        let estimate = scatter * radiance
                        return (estimate: estimate, density: bsdfDensity, sample: wi)
                }

                func brdfDensity(sample: Vector) -> FloatX {
                        let density = bsdf.probabilityDensity(wo: interaction.wo, wi: sample)
                        return density
                }

                if light.isDelta {
                        let (estimate, density, _) = try sampleLightSource()
                        if density == 0 {
                                return black
                        } else {
                                return estimate / density
                        }
                }

                // Light source sampling only
                //let (estimate, density, _) = try sampleLightSource()
                //if density == 0 {
                //        print("light: black")
                //        return black
                //} else {
                //        print("light: ", estimate / density, estimate, density)
                //        return estimate / density
                //}

                // BRDF sampling only
                //let (estimate, density, _) = try sampleBrdf()
                //print("Brdf: ", estimate, density)
                //if density == 0 {
                //        return black
                //} else {
                //        return estimate / density
                //}

                // Light and BRDF sampling with multiple importance sampling
                let lightSampler = MultipleImportanceSampler<Vector>.Sampler(
                        sample: sampleLightSource, density: lightDensity)
                let brdfSampler = MultipleImportanceSampler<Vector>.Sampler(
                        sample: sampleBrdf, density: brdfDensity)
                let sampler = MultipleImportanceSampler(samplers: (lightSampler, brdfSampler))
                return try sampler.evaluate()
        }

        func russianRoulette(beta: inout Spectrum) -> Bool {
                let roulette = FloatX.random(in: 0..<1)
                let probability: FloatX = 0.5
                if roulette < probability {
                        return true
                } else {
                        beta /= probability
                        return false
                }
        }

        func intersectOrInfiniteLights(
                ray: Ray,
                tHit: inout FloatX,
                bounce: Int,
                l: inout Spectrum,
                interaction: inout SurfaceInteraction,
                scene: Scene
        ) throws {
                try scene.intersect(ray: ray, tHit: &tHit, interaction: &interaction)
                if interaction.valid {
                        return
                }
                let radiance = scene.infiniteLights.reduce(
                        black,
                        { accumulated, light in accumulated + light.radianceFromInfinity(for: ray) }
                )
                if bounce == 0 { l += radiance }
        }

        func getRadianceAndAlbedo(
                from ray: Ray, tHit: inout FloatX, with sampler: Sampler
        ) throws
                -> (radiance: Spectrum, albedo: Spectrum, normal: Normal)
        {
                var l = black
                var beta = white
                var ray = ray
                var albedo = black
                var normal = Normal()
                var interaction = SurfaceInteraction()
                for bounce in 0...maxDepth {
                        interaction.valid = false
                        try intersectOrInfiniteLights(
                                ray: ray,
                                tHit: &tHit,
                                bounce: bounce,
                                l: &l,
                                interaction: &interaction,
                                scene: scene)
                        if !interaction.valid {
                                break
                        }
                        if bounce == 0 {
                                if let areaLight = interaction.areaLight {
                                        l +=
                                                beta
                                                * areaLight.emittedRadiance(
                                                        from: interaction,
                                                        inDirection: interaction.wo)
                                }
                        }
                        guard bounce < maxDepth else {
                                break
                        }
                        if interaction.material == -1 {
                                break
                        }
                        guard let material = materials[interaction.material] else {
                                break
                        }
                        let (bsdf, _) = material.computeScatteringFunctions(
                                interaction: interaction)
                        if bounce == 0 {
                                albedo = bsdf.albedo()
                                normal = interaction.normal
                        }
                        let ld =
                                try beta
                                * sampleOneLight(
                                        at: interaction, bsdf: bsdf, with: sampler)
                        l += ld
                        let (f, wi, pdf, _) = try bsdf.sample(
                                wo: interaction.wo, u: sampler.get2D())
                        guard pdf != 0 && !pdf.isNaN else {
                                return (l, white, Normal())
                        }
                        beta = beta * f * absDot(wi, interaction.normal) / pdf
                        ray = interaction.spawnRay(inDirection: wi)
                        tHit = FloatX.infinity
                        if bounce > 3 && russianRoulette(beta: &beta) {
                                break
                        }
                }
                intelHack(&albedo)
                return (radiance: l, albedo, normal)
        }

        // HACK: Imagemagick's converts grayscale images to one channel which Intel
        // denoiser can't read. Make white a little colorful
        private func intelHack(_ albedo: inout Spectrum) {
                if albedo.r == albedo.g && albedo.r == albedo.b {
                        albedo.r += 0.01
                }
        }

        var scene: Scene
        var maxDepth: Int
}
