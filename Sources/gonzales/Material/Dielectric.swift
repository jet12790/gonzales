final class Dielectric {

        init(
                refractiveIndex: FloatTexture = ConstantTexture(value: FloatX(1)),
                roughness: (FloatX, FloatX),
                remapRoughness: Bool
        ) {
                self.refractiveIndex = refractiveIndex
                self.roughness = roughness
                self.remapRoughness = remapRoughness
        }

        func setBsdf(interaction: inout SurfaceInteraction) {
                let refractiveIndex = self.refractiveIndex.evaluateFloat(at: interaction)
                let alpha = remapRoughness ? TrowbridgeReitzDistribution.getAlpha(from: roughness) : roughness
                let distribution = TrowbridgeReitzDistribution(alpha: alpha)
                let bsdfFrame = BsdfFrame(interaction: interaction)
                let dielectricBsdf = DielectricBsdf(
                        distribution: distribution,
                        refractiveIndex: refractiveIndex,
                        bsdfFrame: bsdfFrame)
                interaction.bsdf = dielectricBsdf
        }

        let refractiveIndex: FloatTexture
        let roughness: (FloatX, FloatX)
        let remapRoughness: Bool
}

func createDielectric(parameters: ParameterDictionary) throws -> Dielectric {
        let remapRoughness = try parameters.findOneBool(called: "remaproughness", else: true)
        let roughnessOptional = try parameters.findOneFloatXOptional(called: "roughness")
        let uRoughness =
                try roughnessOptional ?? parameters.findOneFloatX(called: "uroughness", else: 0.0)
        let vRoughness =
                try roughnessOptional ?? parameters.findOneFloatX(called: "vroughness", else: 0.0)
        let roughness = (uRoughness, vRoughness)
        let refractiveIndex = try parameters.findFloatXTexture(name: "eta", else: 1.5)
        return Dielectric(
                refractiveIndex: refractiveIndex,
                roughness: roughness,
                remapRoughness: remapRoughness)
}
