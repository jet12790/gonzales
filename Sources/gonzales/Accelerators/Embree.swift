import Foundation
import embree3

let embree = Embree()

final class Embree: Accelerator {

        init() {
                rtcDevice = rtcNewDevice(nil)
                check(rtcDevice)
                rtcScene = rtcNewScene(rtcDevice)
                check(rtcScene)
        }

        private func check(_ pointer: Any?) {
                guard pointer != nil else {
                        embreeError()
                }
        }

        func addPrimitives(primitives: inout [Boundable & Intersectable]) {
                for primitive in primitives {
                        switch primitive {
                        case let geometricPrimitive as GeometricPrimitive:
                                switch geometricPrimitive.shape {
                                case let curve as EmbreeCurve:
                                        geometry(curve: curve, geomID: geomID)
                                        bounds = union(first: bounds, second: curve.worldBound())
                                        materials[geomID] = geometricPrimitive.material
                                        mediumInterfaces[geomID] = geometricPrimitive.mediumInterface
                                case let triangle as Triangle:
                                        geometry(triangle: triangle, geomID: geomID)
                                        bounds = union(first: bounds, second: triangle.worldBound())
                                        materials[geomID] = geometricPrimitive.material
                                        mediumInterfaces[geomID] = geometricPrimitive.mediumInterface
                                case let sphere as Sphere:
                                        geometry(sphere: sphere, geomID: geomID)
                                        bounds = union(first: bounds, second: sphere.worldBound())
                                        materials[geomID] = geometricPrimitive.material
                                        mediumInterfaces[geomID] = geometricPrimitive.mediumInterface
                                case let disk as Disk:
                                        _ = disk
                                        warnOnce("Ignoring disk!")
                                default:
                                        var message = "Unknown shape in geometric primitive: "
                                        message += "\(geometricPrimitive.shape)"
                                        embreeError(message)
                                }
                        case let areaLight as AreaLight:
                                switch areaLight.shape {
                                case let triangle as Triangle:
                                        geometry(triangle: triangle, geomID: geomID)
                                        bounds = union(first: bounds, second: triangle.worldBound())
                                        areaLights[geomID] = areaLight
                                case let disk as Disk:
                                        _ = disk
                                        warnOnce("Ignoring disk in area light!")
                                case let sphere as Sphere:
                                        _ = sphere
                                        warnOnce("Ignoring sphere in area light!")
                                default:
                                        embreeError("Unknown shape in AreaLight.")
                                }
                        default:
                                embreeError("Unknown primitive.")
                        }
                        geomID += 1
                }
                rtcCommitScene(rtcScene)
        }

        deinit {
                rtcReleaseScene(rtcScene)
                rtcReleaseDevice(rtcDevice)
        }

        private func geometry(curve: EmbreeCurve, geomID: UInt32) {
                let points = curve.controlPoints
                embreeCurve(points: points, widths: curve.widths)
        }

        private func geometry(triangle: Triangle, geomID: UInt32) {
                let points = triangle.getWorldPoints()
                let a = points.0
                let b = points.1
                let c = points.2

                let uv = triangleMeshes.getUVFor(
                        meshIndex: triangle.meshIndex,
                        indices: (triangle.vertexIndex0, triangle.vertexIndex1, triangle.vertexIndex2))
                embreeTriangle(
                        ax: a.x, ay: a.y, az: a.z, bx: b.x, by: b.y, bz: b.z, cx: c.x, cy: c.y,
                        cz: c.z)
                triangleMeshIndices[geomID] = triangle.meshIndex
                triangleIndices[geomID] = triangle.idx
                triangleUVs[geomID] = uv
        }

        private func geometry(sphere: Sphere, geomID: UInt32) {
                let center = sphere.objectToWorld * Point()
                let radius = sphere.radius
                embreeSphere(center: center, radius: radius)
        }

        func intersect(
                ray: Ray,
                tHit: inout FloatX,
                material: MaterialIndex,
                interaction: inout SurfaceInteraction
        ) throws {

                let empty = { (line: Int) in
                        //print("No triangle intersection at line ", line)
                        return
                }

                var tout: FloatX = 0
                var geomID: UInt32 = 0

                let rtcInvalidGeometryId = UInt32.max

                var rayhit = RTCRayHit()
                rayhit.ray.org_x = ray.origin.x
                rayhit.ray.org_y = ray.origin.y
                rayhit.ray.org_z = ray.origin.z
                rayhit.ray.dir_x = ray.direction.x
                rayhit.ray.dir_y = ray.direction.y
                rayhit.ray.dir_z = ray.direction.z
                rayhit.ray.tnear = 0
                rayhit.ray.tfar = tHit
                rayhit.hit.geomID = rtcInvalidGeometryId

                var context = RTCIntersectContext()
                rtcInitIntersectContext(&context)
                rtcIntersect1(rtcScene, &context, &rayhit)

                guard rayhit.hit.geomID != rtcInvalidGeometryId else {
                        return empty(#line)
                }
                tout = rayhit.ray.tfar
                geomID = rayhit.hit.geomID

                if let areaLight = areaLights[geomID] {
                        if areaLight.alpha == 0 {
                                return empty(#line)
                        }
                }

                let bary1 = rayhit.hit.u
                let bary2 = rayhit.hit.v
                let bary0 = 1 - bary1 - bary2
                guard let uvs = triangleUVs[geomID] else {
                        embreeError("TriangleUVs is nil!")
                }

                let uv = Point2F(
                        x: bary0 * uvs.0.x + bary1 * uvs.1.x + bary2 * uvs.2.x,
                        y: bary0 * uvs.0.y + bary1 * uvs.1.y + bary2 * uvs.2.y
                )
                interaction.valid = true
                interaction.position = ray.origin + tout * ray.direction
                interaction.normal = normalized(
                        Normal(
                                x: rayhit.hit.Ng_x,
                                y: rayhit.hit.Ng_y,
                                z: rayhit.hit.Ng_z))
                interaction.shadingNormal = interaction.normal
                interaction.wo = -ray.direction
                interaction.uv = uv

                let (dpdu, _) = makeCoordinateSystem(from: Vector(normal: interaction.normal))
                interaction.dpdu = dpdu

                interaction.faceIndex = 0  // TODO
                if let areaLight = areaLights[geomID] {
                        interaction.areaLight = areaLight
                }
                if let material = materials[geomID] {
                        interaction.material = material
                }
                if let mediumInterface = mediumInterfaces[geomID] {
                        interaction.mediumInterface = mediumInterface
                }

                tHit = tout
        }

        func worldBound() -> Bounds3f {
                return bounds
        }

        func objectBound() -> Bounds3f {
                return bounds
        }

        private func embreeCurve(points: [Point], widths: (Float, Float)) {

                // TODO: Just width.0 used

                guard
                        let geometry = rtcNewGeometry(
                                rtcDevice,
                                RTC_GEOMETRY_TYPE_ROUND_BSPLINE_CURVE)
                else {
                        embreeError()
                }
                let numIndices = points.count - 3
                let indexSlot: UInt32 = 0
                guard
                        let indices = rtcSetNewGeometryBuffer(
                                geometry,
                                RTC_BUFFER_TYPE_INDEX,
                                indexSlot,
                                RTC_FORMAT_UINT,
                                unsignedIntSize,
                                numIndices)
                else {
                        embreeError()
                }
                for index in 0..<numIndices {
                        let offset = unsignedIntSize * index
                        indices.storeBytes(of: UInt32(index), toByteOffset: offset, as: UInt32.self)
                }

                let numVertices = points.count
                let vertexSlot: UInt32 = 0
                guard
                        let vertices = rtcSetNewGeometryBuffer(
                                geometry,
                                RTC_BUFFER_TYPE_VERTEX,
                                vertexSlot,
                                RTC_FORMAT_FLOAT4,
                                vec4fSize,
                                numVertices)
                else {
                        embreeError()
                }
                let curveRadius = widths.0 / 2
                for (counter, point) in points.enumerated() {
                        let xIndex = 4 * counter * floatSize
                        let yIndex = xIndex + floatSize
                        let zIndex = yIndex + floatSize
                        let wIndex = zIndex + floatSize
                        vertices.storeBytes(of: point.x, toByteOffset: xIndex, as: Float.self)
                        vertices.storeBytes(of: point.y, toByteOffset: yIndex, as: Float.self)
                        vertices.storeBytes(of: point.z, toByteOffset: zIndex, as: Float.self)
                        vertices.storeBytes(of: curveRadius, toByteOffset: wIndex, as: Float.self)
                }
                rtcCommitGeometry(geometry)
                rtcAttachGeometry(rtcScene, geometry)
                rtcReleaseGeometry(geometry)
        }

        private func embreeSphere(center: Point, radius: FloatX) {
                guard let geometry = rtcNewGeometry(rtcDevice, RTC_GEOMETRY_TYPE_SPHERE_POINT) else {
                        embreeError()
                }
                let numberPoints = 1
                let slot: UInt32 = 0
                guard
                        let vertices = rtcSetNewGeometryBuffer(
                                geometry,
                                RTC_BUFFER_TYPE_VERTEX,
                                slot,
                                RTC_FORMAT_FLOAT4,
                                vec4fSize,
                                numberPoints)
                else {
                        embreeError()
                }
                vertices.storeBytes(of: center.x, toByteOffset: 0 * floatSize, as: Float.self)
                vertices.storeBytes(of: center.y, toByteOffset: 1 * floatSize, as: Float.self)
                vertices.storeBytes(of: center.z, toByteOffset: 2 * floatSize, as: Float.self)
                vertices.storeBytes(of: radius, toByteOffset: 3 * floatSize, as: Float.self)
                rtcCommitGeometry(geometry)
                rtcAttachGeometry(rtcScene, geometry)
                rtcReleaseGeometry(geometry)
        }

        private func embreeTriangle(
                ax: FloatX, ay: FloatX, az: FloatX,
                bx: FloatX, by: FloatX, bz: FloatX,
                cx: FloatX, cy: FloatX, cz: FloatX
        ) {
                guard let geometry = rtcNewGeometry(rtcDevice, RTC_GEOMETRY_TYPE_TRIANGLE) else {
                        embreeError()
                }
                let indexSlot: UInt32 = 0
                let numberVertices = 3
                guard
                        let vertices = rtcSetNewGeometryBuffer(
                                geometry,
                                RTC_BUFFER_TYPE_VERTEX,
                                indexSlot,
                                RTC_FORMAT_FLOAT3,
                                vec3fSize,
                                numberVertices)
                else {
                        embreeError()
                }

                vertices.storeBytes(of: ax, toByteOffset: 0 * floatSize, as: Float.self)
                vertices.storeBytes(of: ay, toByteOffset: 1 * floatSize, as: Float.self)
                vertices.storeBytes(of: az, toByteOffset: 2 * floatSize, as: Float.self)
                vertices.storeBytes(of: bx, toByteOffset: 3 * floatSize, as: Float.self)
                vertices.storeBytes(of: by, toByteOffset: 4 * floatSize, as: Float.self)
                vertices.storeBytes(of: bz, toByteOffset: 5 * floatSize, as: Float.self)
                vertices.storeBytes(of: cx, toByteOffset: 6 * floatSize, as: Float.self)
                vertices.storeBytes(of: cy, toByteOffset: 7 * floatSize, as: Float.self)
                vertices.storeBytes(of: cz, toByteOffset: 8 * floatSize, as: Float.self)

                let unsignedSize = MemoryLayout<UInt32>.size
                let indicesSize = 3 * unsignedSize
                let slot: UInt32 = 0
                let numberIndices = 1
                guard
                        let indices = rtcSetNewGeometryBuffer(
                                geometry,
                                RTC_BUFFER_TYPE_INDEX,
                                slot,
                                RTC_FORMAT_UINT3,
                                indicesSize,
                                numberIndices
                        )
                else {
                        embreeError()
                }
                indices.storeBytes(of: 0, toByteOffset: 0 * unsignedSize, as: UInt32.self)
                indices.storeBytes(of: 1, toByteOffset: 1 * unsignedSize, as: UInt32.self)
                indices.storeBytes(of: 2, toByteOffset: 2 * unsignedSize, as: UInt32.self)

                rtcCommitGeometry(geometry)
                rtcAttachGeometry(rtcScene, geometry)
                rtcReleaseGeometry(geometry)
        }

        private func embreeError(_ message: String = "") -> Never {
                print("embreeError: \(message)")
                exit(-1)
        }

        private var rtcDevice: OpaquePointer?
        private var rtcScene: OpaquePointer?

        private var materials = [UInt32: MaterialIndex]()
        private var mediumInterfaces = [UInt32: MediumInterface?]()
        private var areaLights = [UInt32: AreaLight]()
        private var triangleMeshIndices = [UInt32: Int]()
        private var triangleIndices = [UInt32: Int]()
        private var triangleUVs = [UInt32: (Vector2F, Vector2F, Vector2F)]()
        private var bounds = Bounds3f()

        private let floatSize = MemoryLayout<Float>.size
        private let unsignedIntSize = MemoryLayout<UInt32>.size
        private let vec4fSize = 4 * MemoryLayout<Float>.size
        private let vec3fSize = 3 * MemoryLayout<Float>.size
        private let vec3faSize = 16 * MemoryLayout<Float>.size

        private var geomID: UInt32 = 0
}
