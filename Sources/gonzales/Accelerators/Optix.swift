import Foundation
import cuda

enum OptixError: Error {
        case cudaCheck
        case noDevice
        case noFile
        case optixCheck
}

class Optix {

        init() {
                do {
                        try initializeCuda()
                        try initializeOptix()
                        try createContext()
                        try createModule()
                } catch (let error) {
                        fatalError("OptixError: \(error)")
                }
        }

        private func cudaCheck(_ cudaError: cudaError_t) throws {
                if cudaError != cudaSuccess {
                        throw OptixError.cudaCheck
                }
        }

        private func cudaCheck(_ cudaResult: CUresult) throws {
                if cudaResult != CUDA_SUCCESS {
                        throw OptixError.cudaCheck
                }
        }

        private func optixCheck(_ optixResult: OptixResult) throws {
                if optixResult != OPTIX_SUCCESS {
                        print("OptixError, result: \(optixResult)")
                        throw OptixError.optixCheck
                }
        }

        func initializeCuda() throws {
                var numDevices: Int32 = 0
                var cudaError: cudaError_t
                cudaError = cudaGetDeviceCount(&numDevices)
                try cudaCheck(cudaError)
                guard numDevices == 1 else {
                        throw OptixError.noDevice
                }

                var cudaDevice: Int32 = 0
                cudaError = cudaGetDevice(&cudaDevice)
                try cudaCheck(cudaError)
                //print("Cuda device used: \(cudaDevice)")

                var cudaDeviceProperties: cudaDeviceProp = cudaDeviceProp()
                cudaError = cudaGetDeviceProperties_v2(&cudaDeviceProperties, cudaDevice)
                try cudaCheck(cudaError)

                let deviceName = withUnsafePointer(to: cudaDeviceProperties.name) {
                        $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: $0)) {
                                String(cString: $0)
                        }
                }
                print(deviceName)
        }

        func printGreen(_ message: String) {
                let escape = "\u{001B}"
                let bold = "1"
                let green = "32"
                let ansiEscapeGreen = escape + "[" + bold + ";" + green + "m"
                let ansiEscapeReset = escape + "[" + "0" + "m"
                print(ansiEscapeGreen + message + ansiEscapeReset)
        }

        func initializeOptix() throws {
                let optixResult = optixInit()
                try optixCheck(optixResult)
                printGreen("Initializing Optix ok.")
        }

        func createContext() throws {
                var cudaError: cudaError_t
                cudaError = cudaStreamCreate(&stream)
                try cudaCheck(cudaError)
                printGreen("Cuda stream created.")

                var cudaResult: CUresult
                cudaResult = cuCtxGetCurrent(&cudaContext)
                try cudaCheck(cudaResult)
                printGreen("Cuda context ok.")

                let optixResult = optixDeviceContextCreate(cudaContext, nil, &optixContext)
                try optixCheck(optixResult)
                printGreen("Optix context ok.")
        }

        func createModule() throws {
                var moduleOptions = OptixModuleCompileOptions()
                moduleOptions.maxRegisterCount = 50
                moduleOptions.optLevel = OPTIX_COMPILE_OPTIMIZATION_DEFAULT
                moduleOptions.debugLevel = OPTIX_COMPILE_DEBUG_LEVEL_NONE

                var pipelineOptions = OptixPipelineCompileOptions()
                pipelineOptions.traversableGraphFlags = OPTIX_TRAVERSABLE_GRAPH_FLAG_ALLOW_SINGLE_GAS.rawValue
                pipelineOptions.usesMotionBlur = Int32(truncating: false)
                pipelineOptions.numPayloadValues = 2
                pipelineOptions.numAttributeValues = 2
                pipelineOptions.exceptionFlags = OPTIX_EXCEPTION_FLAG_NONE.rawValue
                let optixLaunchParams = "optixLaunchParams"
                optixLaunchParams.withCString {
                        pipelineOptions.pipelineLaunchParamsVariableName = $0
                }

                let fileManager = FileManager.default
                let urlString = "file://" + fileManager.currentDirectoryPath + "/Sources/bla.optixir"
                guard let url = URL(string: urlString) else {
                        throw OptixError.noFile
                }
                let data = try Data(contentsOf: url)
                try data.withUnsafeBytes { input in
                        let inputSize = data.count
                        var logSize = 0
                        var module: OptixModule? = nil
                        let optixResult = optixModuleCreate(
                                optixContext,
                                &moduleOptions,
                                &pipelineOptions,
                                input.bindMemory(to: UInt8.self).baseAddress!,
                                inputSize,
                                nil,
                                &logSize,
                                &module)
                        try optixCheck(optixResult)
                }
        }

        func dummy() {}

        static let shared = Optix()

        var stream: cudaStream_t?
        var cudaContext: CUcontext?
        var optixContext: OptixDeviceContext?
}
