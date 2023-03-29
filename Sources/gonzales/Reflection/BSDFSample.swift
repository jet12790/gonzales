struct BSDFSample {

        init(
                _ estimate: RGBSpectrum = black,
                _ incoming: Vector = nullVector,
                _ probabilityDensity: FloatX = 0
        ) {
                self.estimate = estimate
                self.incoming = incoming
                self.probabilityDensity = probabilityDensity
        }

        func throughputWeight(normal: Normal = upNormal) -> RGBSpectrum {
                return estimate * absDot(incoming, normal) / probabilityDensity
        }

        var estimate: RGBSpectrum
        let incoming: Vector
        var probabilityDensity: FloatX
}
