final class Tile {

        init(scene: Scene, integrator: PathIntegrator, bounds: Bounds2i) {
                self.scene = scene
                self.integrator = integrator
                self.bounds = bounds
        }

        func render(
                reporter: ProgressReporter,
                sampler: Sampler,
                camera: Camera
        ) throws -> [Sample] {
                var samples = [Sample]()
                for pixel in bounds {
                        let pixelSamples = try renderPixel(
                                pixel: pixel,
                                reporter: reporter,
                                sampler: sampler,
                                camera: camera)
                        samples.append(contentsOf: pixelSamples)
                }
                return samples
        }

        func renderPixel(
                pixel: Point2I,
                reporter: ProgressReporter,
                sampler: Sampler,
                camera: Camera
        ) throws -> [Sample] {
                var samples = [Sample]()
                for _ in 0..<sampler.samplesPerPixel {
                        let cameraSample = sampler.getCameraSample(pixel: pixel)
                        let ray = camera.generateRay(sample: cameraSample)
                        var tHit = Float.infinity
                        let (L, albedo, normal) = try integrator.getRadianceAndAlbedo(
                                from: ray,
                                tHit: &tHit,
                                with: sampler)
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

        static let size = 64

        unowned var scene: Scene
        unowned var integrator: PathIntegrator
        var bounds: Bounds2i
}
