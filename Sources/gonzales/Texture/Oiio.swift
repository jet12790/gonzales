import oiio

final class OiioTextureSystem {

        static let shared = OiioTextureSystem()

        func oiioTexture(filename: String, s: Float, t: Float) -> RGBSpectrum {
                let pointer = UnsafeMutablePointer<Float>.allocate(capacity: 3)
                let successful = texture(filename, s, t, pointer)
                if !successful {
                        warnOnce("Could not evaluate texture!")
                        return black
                }
                let result = RGBSpectrum(r: pointer[0], g: pointer[1], b: pointer[2])
                return result
        }

        private init() {
                createTextureSystem()
        }

        deinit {
                destroyTextureSystem()
        }
}

final class OiioTexture: RGBSpectrumTexture {

        init(path: String) {
                filename = path
        }

        let filename: String

        func evaluateRGBSpectrum(at interaction: Interaction) -> RGBSpectrum {
                let s = interaction.uv.x
                let t = interaction.uv.y
                return OiioTextureSystem.shared.oiioTexture(filename: filename, s: s, t: t)
        }

}
