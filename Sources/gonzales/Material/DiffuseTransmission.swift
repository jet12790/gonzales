final class DiffuseTransmission: Material {

        init(
                reflectance: RGBSpectrumTexture,
                transmittance: RGBSpectrumTexture,
                scale: FloatTexture
        ) {
                self.reflectance = reflectance
                self.transmittance = transmittance
                self.scale = scale
        }

        func setBsdf(interaction: inout SurfaceInteraction) {
                let reflectance = reflectance.evaluateRGBSpectrum(at: interaction)
                let scale = scale.evaluateFloat(at: interaction)
                // TODO: check same hemisphere and transmission
                // TODO: transmittance
                let bsdfFrame = BsdfFrame(interaction: interaction)
                let diffuseBsdf = DiffuseBsdf(
                        reflectance: scale * reflectance,
                        bsdfFrame: bsdfFrame)
                interaction.bsdf = diffuseBsdf
        }

        var reflectance: RGBSpectrumTexture
        var transmittance: RGBSpectrumTexture
        var scale: FloatTexture
}

func createDiffuseTransmission(parameters: ParameterDictionary) throws -> DiffuseTransmission {
        let reflectance = try parameters.findRGBSpectrumTexture(
                name: "reflectance",
                else: RGBSpectrum(intensity: 1))
        let transmittance = try parameters.findRGBSpectrumTexture(
                name: "transmittance",
                else: RGBSpectrum(intensity: 1))
        let scale = try parameters.findFloatXTexture(name: "scale", else: 1.0)
        return DiffuseTransmission(
                reflectance: reflectance,
                transmittance: transmittance,
                scale: scale)
}
