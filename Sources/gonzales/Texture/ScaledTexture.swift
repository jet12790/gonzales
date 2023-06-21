import Foundation

final class ScaledTexture: RgbSpectrumTexture {

        init(scale: Texture, texture: Texture) {
                self.scale = scale
                self.texture = texture
        }

        func evaluateRgbSpectrum(at interaction: Interaction) -> RgbSpectrum {
                guard let scale = scale.evaluate(at: interaction) as? FloatX else {
                        return black
                }
                guard let spectrum = texture.evaluate(at: interaction) as? RgbSpectrum else {
                        return black
                }
                return scale * spectrum
        }

        let scale: Texture
        let texture: Texture
}
