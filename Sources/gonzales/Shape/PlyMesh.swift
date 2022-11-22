/// TODO: Redesign this!

import Foundation

protocol DefaultInitializable {
        init()
}

enum PlyError: Error {
        case noZero
        case unsupported
}

extension UInt8: DefaultInitializable {}
extension UInt32: DefaultInitializable {}
extension Int32: DefaultInitializable {}
extension Int: DefaultInitializable {}
extension Float64: DefaultInitializable {}
extension Float32: DefaultInitializable {}
#if os(Linux) && swift(>=5.4)
        extension Float16: DefaultInitializable {}
#endif
extension Point: DefaultInitializable {}
extension Normal: DefaultInitializable {}

func convert<T: DefaultInitializable>(data: Data, at index: inout Data.Index, peek: Bool = false)
        -> T
{
        var value = T()
        let size = MemoryLayout<T>.size
        withUnsafeMutableBytes(of: &value) { (valuePointer) -> Void in
                data.withUnsafeBytes { (dataPointer) -> Void in
                        let source = dataPointer.baseAddress! + index
                        let destination = valuePointer.baseAddress!
                        memcpy(destination, source, size)
                }
        }
        if !peek {
                index += size
        }
        return value
}

func readValue<T: DefaultInitializable>(in data: Data, at index: inout Data.Index) -> T {
        return convert(data: data, at: &index)
}

func peekValue<T: DefaultInitializable>(in data: Data, at index: inout Data.Index) -> T {
        return convert(data: data, at: &index, peek: true)
}

func readCharacter(in data: Data, at index: inout Data.Index) -> Character {
        let c = Character(UnicodeScalar(data[index]))
        index += 1
        return c
}

func peekCharacter(in data: Data, at index: inout Data.Index) -> Character {
        return Character(UnicodeScalar(data[index]))
}

struct PlyMesh {

        struct Property {
                enum PropertyType { case float, int }
                enum PropertyName { case x, y, z, nx, ny, nz, u, v }
                let type: PropertyType
                let name: PropertyName
        }

        struct PlyHeader {
                var vertexCount = 0
                var faceCount = 0
                var vertexProperties = [Property]()
        }

        var listBits = 8

        mutating func readPlyHeader(from data: Data) throws {
                enum HeaderState { case vertex, face, none }
                var headerState = HeaderState.none
                guard readLine(in: data) == "ply" else {
                        throw ApiError.ply(message: "First line myst be ply")
                }
                while true {
                        let line = readLine(in: data)
                        let words = line.components(separatedBy: " ")
                        switch words[0] {
                        case "comment":
                                break
                        case "format":
                                guard words[1] == "binary_little_endian" else {
                                        throw ApiError.ply(message: "binary little endian")
                                }
                                guard words[2] == "1.0" else { throw ApiError.ply(message: "1.0") }
                        case "element":
                                switch words[1] {
                                case "vertex":
                                        headerState = .vertex
                                        guard let vertexCount = Int(words[2]) else {
                                                throw ApiError.ply(message: "vertexCount")
                                        }
                                        plyHeader.vertexCount = vertexCount
                                case "face":
                                        headerState = .face
                                        guard let faceCount = Int(words[2]) else {
                                                throw ApiError.ply(message: "faceCount")
                                        }
                                        plyHeader.faceCount = faceCount
                                default:
                                        throw ApiError.ply(message: "Unknown element \(words[1])")
                                }
                        case "property":
                                switch words[1] {
                                case "float":
                                        guard headerState == .vertex else {
                                                throw ApiError.ply(message: "headerState vertex")
                                        }
                                        switch words[2] {
                                        case "x":
                                                plyHeader.vertexProperties.append(
                                                        Property(type: .float, name: .x))
                                        case "y":
                                                plyHeader.vertexProperties.append(
                                                        Property(type: .float, name: .y))
                                        case "z":
                                                plyHeader.vertexProperties.append(
                                                        Property(type: .float, name: .z))
                                        case "nx":
                                                plyHeader.vertexProperties.append(
                                                        Property(type: .float, name: .nx))
                                        case "ny":
                                                plyHeader.vertexProperties.append(
                                                        Property(type: .float, name: .ny))
                                        case "nz":
                                                plyHeader.vertexProperties.append(
                                                        Property(type: .float, name: .nz))
                                        case "u":
                                                plyHeader.vertexProperties.append(
                                                        Property(type: .float, name: .u))
                                        case "v":
                                                plyHeader.vertexProperties.append(
                                                        Property(type: .float, name: .v))
                                        default:
                                                throw ApiError.ply(
                                                        message:
                                                                "Unknown float property \(words[2])"
                                                )
                                        }
                                case "list":
                                        switch words[2] {
                                        case "uint":
                                                listBits = 32
                                        case "uint8":
                                                listBits = 8
                                        default:
                                                throw ApiError.ply(
                                                        message:
                                                                "Unknown list property \(words[2])"
                                                )
                                        }
                                        break
                                case "int":
                                        switch words[2] {
                                        case "face_indices": hasFaceIndices = true
                                        default:
                                                throw ApiError.ply(
                                                        message: "Unknown int property \(words[2])")
                                        }
                                        break
                                default:
                                        throw ApiError.ply(message: "Unknown property: \(words[1])")
                                }
                        case "end_header":
                                return
                        default:
                                throw ApiError.ply(message: "Unknown ply word: \"\(words[0])\"")
                        }
                }
        }

        mutating func appendPoint(from data: Data) {
                let x: FloatX = readValue(in: data, at: &dataIndex)
                let y: FloatX = readValue(in: data, at: &dataIndex)
                let z: FloatX = readValue(in: data, at: &dataIndex)
                points.append(Point(x: FloatX(x), y: FloatX(y), z: FloatX(z)))
        }

        mutating func appendNormal(from data: Data) {
                let nx: FloatX = readValue(in: data, at: &dataIndex)
                let ny: FloatX = readValue(in: data, at: &dataIndex)
                let nz: FloatX = readValue(in: data, at: &dataIndex)
                normals.append(Normal(x: FloatX(nx), y: FloatX(ny), z: FloatX(nz)))
        }

        mutating func appendUV(from data: Data) {
                let u: FloatX = readValue(in: data, at: &dataIndex)
                let v: FloatX = readValue(in: data, at: &dataIndex)
                uvs.append(Vector2F(x: FloatX(u), y: FloatX(v)))
        }

        mutating func readVertices(from data: Data) throws {
                let properties = plyHeader.vertexProperties
                for _ in 0..<plyHeader.vertexCount {

                        if plyHeader.vertexProperties.count == 3 {
                                guard
                                        properties[0].name == Property.PropertyName.x
                                                && properties[1].name == Property.PropertyName.y
                                                && properties[2].name == Property.PropertyName.z
                                else { throw PlyError.unsupported }
                                appendPoint(from: data)
                        } else if plyHeader.vertexProperties.count == 5 {
                                guard
                                        properties[0].name == Property.PropertyName.x
                                                && properties[1].name == Property.PropertyName.y
                                                && properties[2].name == Property.PropertyName.z
                                                && properties[3].name == Property.PropertyName.u
                                                && properties[4].name == Property.PropertyName.v
                                else { throw PlyError.unsupported }
                                appendPoint(from: data)
                                appendUV(from: data)
                        } else if plyHeader.vertexProperties.count == 6 {
                                guard
                                        properties[0].name == Property.PropertyName.x
                                                && properties[1].name == Property.PropertyName.y
                                                && properties[2].name == Property.PropertyName.z
                                                && properties[3].name == Property.PropertyName.nx
                                                && properties[4].name == Property.PropertyName.ny
                                                && properties[5].name == Property.PropertyName.nz
                                else { throw PlyError.unsupported }
                                appendPoint(from: data)
                                appendNormal(from: data)
                        } else if plyHeader.vertexProperties.count == 8 {
                                if properties[0].name == Property.PropertyName.x
                                        && properties[1].name == Property.PropertyName.y
                                        && properties[2].name == Property.PropertyName.z
                                        && properties[3].name == Property.PropertyName.nx
                                        && properties[4].name == Property.PropertyName.ny
                                        && properties[5].name == Property.PropertyName.nz
                                        && properties[6].name == Property.PropertyName.u
                                        && properties[7].name == Property.PropertyName.v
                                {
                                        appendPoint(from: data)
                                        appendNormal(from: data)
                                        appendUV(from: data)
                                } else if properties[0].name == Property.PropertyName.x
                                        && properties[1].name == Property.PropertyName.y
                                        && properties[2].name == Property.PropertyName.z
                                        && properties[3].name == Property.PropertyName.u
                                        && properties[4].name == Property.PropertyName.v
                                        && properties[5].name == Property.PropertyName.nx
                                        && properties[6].name == Property.PropertyName.ny
                                        && properties[7].name == Property.PropertyName.nz
                                {
                                        appendPoint(from: data)
                                        appendUV(from: data)
                                        appendNormal(from: data)
                                } else {
                                        throw PlyError.unsupported
                                }
                        } else {
                                throw PlyError.unsupported
                        }
                }
        }

        mutating func readFaces(from data: Data) throws {
                for _ in 0..<plyHeader.faceCount {
                        var numberIndices: UInt32 = 0
                        switch listBits {
                        case 8:
                                let value: UInt8 = readValue(in: data, at: &dataIndex)
                                numberIndices = UInt32(value)
                        case 32:
                                let value: UInt32 = readValue(in: data, at: &dataIndex)
                                numberIndices = value
                        default:
                                fatalError("argh!")
                        }
                        if numberIndices != 3 {
                                throw ApiError.ply(
                                        message:
                                                "Number of indices must be 3 but is \(numberIndices)"
                                )
                        }
                        for _ in 0..<numberIndices {
                                let index: Int32 = readValue(in: data, at: &dataIndex)
                                indices.append(Int(index))
                        }

                        if hasFaceIndices {
                                let faceIndex: Int32 = readValue(in: data, at: &dataIndex)
                                faceIndices.append(Int(faceIndex))
                        }
                }
        }

        init(from data: Data) throws {
                try readPlyHeader(from: data)
                try readVertices(from: data)
                try readFaces(from: data)
        }

        mutating func readLine(in data: Data) -> String {
                var line = ""
                var c = readCharacter(in: data, at: &dataIndex)
                while !c.isNewline {
                        line.append(c)
                        c = readCharacter(in: data, at: &dataIndex)
                }
                return line
        }

        var plyHeader = PlyHeader()
        var points = [Point]()
        var normals = [Normal]()
        var uvs = [Vector2F]()
        var indices = [Int]()
        var faceIndices = [Int]()
        var hasFaceIndices = false
        var dataIndex = 0
}

func createPlyMesh(objectToWorld: Transform, parameters: ParameterDictionary) throws
        -> (TriangleMesh?, [Shape])
{
        let relativeFileName = try parameters.findString(called: "filename") ?? ""
        let absoluteFileName = sceneDirectory + "/" + relativeFileName
        guard FileManager.default.fileExists(atPath: absoluteFileName) else {
                warning("Could not find ply file at: \(absoluteFileName)")
                return (nil, [])
        }
        guard let file = FileHandle(forReadingAtPath: absoluteFileName) else {
                throw RenderError.noFileHandle
        }
        let data = file.readDataToEndOfFile()
        let plyMesh = try PlyMesh(from: data)
        return try createTriangleMesh(
                objectToWorld: objectToWorld,
                indices: plyMesh.indices,
                points: plyMesh.points,
                normals: plyMesh.normals,
                uvs: plyMesh.uvs,
                faceIndices: plyMesh.faceIndices)

}
