final class Tile {

        init(integrator: VolumePathIntegrator, bounds: Bounds2i) {
                self.integrator = integrator
                self.bounds = bounds
        }

        func render(
                reporter: ProgressReporter,
                sampler: Sampler,
                camera: Camera,
                scene: Scene,
                lightSampler: LightSampler
        ) throws -> [Sample] {
                var samples = [Sample]()
                var cameraSamples = [CameraSample]()
                var rays = [Ray]()
                var tHits = [Float]()
                for pixel in bounds {
                        for _ in 0..<sampler.samplesPerPixel {
                                let cameraSample = sampler.getCameraSample(pixel: pixel)
                                cameraSamples.append(cameraSample)
                                let ray = camera.generateRay(cameraSample: cameraSample)
                                rays.append(ray)
                                tHits.append(Float.infinity)
                        }
                }
                let radianceAlbedoNormals = try integrator.getRadiancesAndAlbedos(
                        from: rays,
                        tHits: &tHits,
                        with: sampler,
                        lightSampler: lightSampler)
                let rayWeight: FloatX = 1.0
                for (radianceAlbedoNormal, cameraSample) in zip(radianceAlbedoNormals, cameraSamples) {
                        let radiance = radianceAlbedoNormal.0
                        let albedo = radianceAlbedoNormal.1
                        let normal = radianceAlbedoNormal.2
                        let sample = Sample(
                                light: radiance,
                                albedo: albedo,
                                normal: normal,
                                weight: rayWeight,
                                location: Point2F(x: cameraSample.film.0, y: cameraSample.film.1))
                        samples.append(sample)
                }
                reporter.update()
                return samples
        }

        unowned var integrator: VolumePathIntegrator
        var bounds: Bounds2i
}
