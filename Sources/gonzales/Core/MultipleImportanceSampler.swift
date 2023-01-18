struct MultipleImportanceSampler<Sample> {

        struct MISSampler {
                typealias sampleFunc = (Light, Interaction, Sampler, BSDF, Scene, Accelerator)
                        throws -> (
                                estimate: RGBSpectrum,
                                density: FloatX,
                                sample: Sample
                        )

                typealias densityFunc = (Light, Interaction, Sample, BSDF) throws -> FloatX

                let sample: sampleFunc
                let density: densityFunc
        }

        func evaluate(
                scene: Scene,
                hierarchy: Accelerator,
                light: Light,
                interaction: Interaction,
                sampler: Sampler,
                bsdf: BSDF
        ) throws -> RGBSpectrum {

                func evaluate(
                        first: MISSampler,
                        second: MISSampler,
                        light: Light,
                        interaction: Interaction,
                        sampler: Sampler,
                        bsdf: BSDF
                ) throws -> RGBSpectrum {
                        let (estimate, density, sample) = try first.sample(
                                light, interaction, sampler, bsdf, scene, hierarchy)
                        let otherDensity = try second.density(
                                light, interaction, sample, bsdf)
                        let weight = powerHeuristic(f: density, g: otherDensity)
                        return density == 0 ? black : estimate * weight / density
                }

                let a = try evaluate(
                        first: samplers.0,
                        second: samplers.1,
                        light: light,
                        interaction: interaction,
                        sampler: sampler,
                        bsdf: bsdf)
                let b = try evaluate(
                        first: samplers.1,
                        second: samplers.0,
                        light: light,
                        interaction: interaction,
                        sampler: sampler,
                        bsdf: bsdf)
                return a + b
        }

        let samplers: (MISSampler, MISSampler)
}
