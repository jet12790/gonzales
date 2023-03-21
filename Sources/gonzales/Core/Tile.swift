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
                hierarchy: Accelerator,
                lightSampler: LightSampler
        ) throws -> [Sample] {

                var samples = [Sample]()
                for pixel in bounds {
                        let pixelSamples = try renderPixel(
                                pixel: pixel,
                                reporter: reporter,
                                sampler: sampler,
                                camera: camera,
                                scene: scene,
                                hierarchy: hierarchy,
                                lightSampler: lightSampler)
                        samples.append(contentsOf: pixelSamples)
                }
                return samples
        }

        func renderPixel(
                pixel: Point2I,
                reporter: ProgressReporter,
                sampler: Sampler,
                camera: Camera,
                scene: Scene,
                hierarchy: Accelerator,
                lightSampler: LightSampler
        ) throws -> [Sample] {
                var samples = [Sample]()
                for _ in 0..<sampler.samplesPerPixel {
                        let cameraSample = sampler.getCameraSample(pixel: pixel)
                        let ray = camera.generateRay(sample: cameraSample)
                        var tHit = Float.infinity
                        let (L, albedo, normal) = try integrator.getRadianceAndAlbedo(
                                from: ray,
                                tHit: &tHit,
                                with: sampler,
                                scene: scene,
                                hierarchy: hierarchy,
                                lightSampler: lightSampler)
                        let rayWeight: FloatX = 1.0
                        let sample = Sample(
                                light: L,
                                albedo: albedo,
                                normal: normal,
                                weight: rayWeight,
                                location: cameraSample.film)
                        samples.append(sample)
                        reporter.update()
                }
                return samples
        }

        static let size = 32

        unowned var integrator: VolumePathIntegrator
        var bounds: Bounds2i
}
