import Foundation  // exit

final class BoundingHierarchyBuilder {

        internal init(primitives: [Boundable]) {
                self.nodes = []
                self.cachedPrimitives = primitives.enumerated().map { index, primitive in
                        let bound = primitive.worldBound()
                        return CachedPrimitive(index: index, bound: bound, center: bound.center)
                }
                self.primitives = primitives
                buildHierarchy()
        }

        internal func getBoundingHierarchy() -> BoundingHierarchy {
                BoundingHierarchyBuilder.bhPrimitives += cachedPrimitives.count
                BoundingHierarchyBuilder.bhNodes += nodes.count
                let sortedPrimitives = cachedPrimitives.map {
                        primitives[$0.index] as! Intersectable
                }
                return BoundingHierarchy(primitives: sortedPrimitives, nodes: nodes)
        }

        internal static func statistics() {
                print("  BVH:")
                print("    Interior nodes:\t\t\t\t\t\t\t\(interiorNodes)")
                print("    Leaf nodes:\t\t\t\t\t\t\t\t\(leafNodes)")
                let ratio = String(format: " (%.2f)", Float(totalPrimitives) / Float(leafNodes))
                print("    Primitives per leaf node:\t\t\t\t\t", terminator: "")
                print("\(totalPrimitives) /    \(leafNodes)\(ratio)")
        }

        private struct CachedPrimitive {
                let index: Int
                let bound: Bounds3f
                let center: Point

                func centroid() -> Point {
                        return 0.5 * bound.pMin + 0.5 * bound.pMax
                }
        }

        private func buildHierarchy() {
                if cachedPrimitives.isEmpty { return }
                nodes = []
                let _ = build(range: 0..<cachedPrimitives.count)
        }

        private func growNodes(counter: Int) {
                let missing = counter - nodes.count + 1
                if missing > 0 {
                        nodes += Array(repeating: Node(), count: missing)
                }
        }

        private func appendAndInit(
                offset: Int,
                bounds: Bounds3f,
                range: Range<Int>,
                counter: Int
        ) {
                growNodes(counter: counter)
                nodes[counter].bounds = bounds
                assert(range.count > 0)
                nodes[counter].offset = offset
                nodes[counter].count = range.count
                BoundingHierarchyBuilder.leafNodes += 1
                offsetCounter += range.count
                BoundingHierarchyBuilder.totalPrimitives += range.count
                //print("appending leaf")
        }

        private func isSmaller(_ a: CachedPrimitive, _ pivot: FloatX, in dimension: Int) -> Bool {
                return a.center[dimension] < pivot
        }

        private func isSmaller(_ a: CachedPrimitive, _ b: CachedPrimitive, in dimension: Int)
                -> Bool
        {
                return isSmaller(a, b.center[dimension], in: dimension)
        }

        private func splitMiddle(bounds: Bounds3f, dimension: Int, range: Range<Int>)
                -> (start: Int, middle: Int, end: Int)
        {
                let pivot = (bounds.pMin[dimension] + bounds.pMax[dimension]) / 2
                let mid = cachedPrimitives[range].partition(by: {
                        isSmaller($0, pivot, in: dimension)
                })
                let start = range.first!
                let end = range.last! + 1
                guard mid != start && mid != end else {
                        return splitEqual(bounds: bounds, dimension: dimension, range: range)
                }
                return (start, mid, end)
        }

        private func splitEqual(bounds: Bounds3f, dimension: Int, range: Range<Int>)
                -> (start: Int, middle: Int, end: Int)
        {
                // There is no nth_element so let's sort for now
                cachedPrimitives[range].sort(by: { isSmaller($0, $1, in: dimension) })
                let start = range.first!
                let mid = start + cachedPrimitives[range].count / 2
                let end = range.last! + 1
                return (start, mid, end)
        }

        struct BVHSplitBucket {
                var count = 0
                var bounds = Bounds3f()
        }

        private func splitSurfaceAreaHeuristic(
                bounds: Bounds3f,
                dimension: Int,
                range: Range<Int>,
                counter: Int
        )
                -> (start: Int, middle: Int, end: Int, bounds: Bounds3f)
        {
                var mid = 0
                if cachedPrimitives[range].count <= 2 {
                        mid = cachedPrimitives[range].count / 2
                        cachedPrimitives[range].sort(by: { isSmaller($0, $1, in: dimension) })
                } else {
                        let nBuckets = 12
                        var buckets = Array(repeating: BVHSplitBucket(), count: nBuckets)
                        for prim in cachedPrimitives[range] {
                                let offset: Vector = bounds.offset(point: prim.centroid())
                                var b = Int(Float(nBuckets) * offset[dimension])
                                if b == nBuckets {
                                        b = nBuckets - 1
                                }
                                assert(b >= 0)
                                assert(b < nBuckets)
                                buckets[b].count += 1
                                buckets[b].bounds = union(
                                        first: buckets[b].bounds,
                                        second: prim.bound)
                                //print("b: ", b, " count: ", buckets[b].count, " bounds: ", buckets[b].bounds)
                        }
                        let nSplits = nBuckets - 1
                        var costs = Array(repeating: FloatX(0.0), count: nSplits)
                        var countBelow = 0
                        var boundBelow = Bounds3f()
                        for i in 0..<nSplits {
                                boundBelow = union(first: boundBelow, second: buckets[i].bounds)
                                countBelow += buckets[i].count
                                costs[i] = costs[i] + FloatX(countBelow) * boundBelow.surfaceArea()
                                //print("boundBelow: ", boundBelow)
                                //print("countBelow: ", countBelow)
                                //print("costs[i]: ", costs[i])
                        }
                        var countAbove = 0
                        var boundAbove = Bounds3f()
                        for i in (1...nSplits).reversed() {
                                boundAbove = union(first: boundAbove, second: buckets[i].bounds)
                                countAbove += buckets[i].count
                                costs[i - 1] =
                                        costs[i - 1] + FloatX(countAbove) * boundAbove.surfaceArea()
                                //print("boundAbove: ", boundAbove)
                                //print("countAbove: ", countAbove)
                                //print("costs[i-1]: ", costs[i-1])
                        }
                        var minCostSplitBucket = -1
                        var minCost = FloatX.infinity
                        for i in 0..<nSplits {
                                if costs[i] < minCost {
                                        minCost = costs[i]
                                        minCostSplitBucket = i
                                }
                        }
                        let leafCost = FloatX(cachedPrimitives[range].count)
                        minCost = 1.0 / 2.0 + minCost / bounds.surfaceArea()
                        //print("minCost: ", minCost)

                        //print("before")
                        if cachedPrimitives[range].count > primitivesPerNode || minCost < leafCost {
                                mid = cachedPrimitives[range].partition(by: {
                                        let offset = bounds.offset(point: $0.centroid())[dimension]
                                        var b = Int(FloatX(nBuckets) * offset)
                                        if b == nBuckets {
                                                b = nBuckets + 1
                                        }
                                        //print("offset: ", offset)
                                        //print("b: ", b)
                                        //print("minCostSplitBucket: ", minCostSplitBucket)
                                        return b <= minCostSplitBucket
                                })
                                //print("mid: ", mid)
                                //exit(0)
                        } else {
                                //print("leaf")
                                //exit(0)
                                appendAndInit(
                                        offset: offsetCounter,
                                        bounds: bounds,
                                        range: range,
                                        counter: counter)
                                return (0, 0, 0, bounds)
                        }
                }
                let start = range.first!
                let end = range.last! + 1
                return (start, mid, end, Bounds3f())
        }

        private func build(range: Range<Int>) -> Bounds3f {
                let counter = totalNodes
                totalNodes += 1
                if range.isEmpty { return Bounds3f() }
                let bounds = cachedPrimitives[range].reduce(
                        Bounds3f(),
                        {
                                union(first: $0, second: $1.bound)
                        })
                if range.count < primitivesPerNode {
                        appendAndInit(
                                offset: offsetCounter,
                                bounds: bounds,
                                range: range,
                                counter: counter)
                        return bounds
                }
                let centroidBounds = cachedPrimitives[range].reduce(
                        Bounds3f(),
                        {
                                union(
                                        bound: $0,
                                        point: $1.center)
                        })

                //print("Centroid Bound: ", centroidBounds)
                //print("range: ", range)

                let dim = centroidBounds.maximumExtent()
                if centroidBounds.pMax[dim] == centroidBounds.pMin[dim] {
                        appendAndInit(
                                offset: offsetCounter,
                                bounds: bounds,
                                range: range,
                                counter: counter)
                        return bounds
                }

                //let (start, mid, end) = splitEqual(
                //        bounds: centroidBounds,
                //        dimension: dim,
                //        range: range)

                //let (start, mid, end) = splitMiddle(
                //        bounds: centroidBounds,
                //        dimension: dim,
                //        range: range)

                let (start, mid, end, blaBounds) = splitSurfaceAreaHeuristic(
                        bounds: centroidBounds,
                        dimension: dim,
                        range: range,
                        counter: counter)
                if start == 0 && mid == 0 && end == 0 {
                        return blaBounds
                }

                //print("recursion: ", start, mid, end)
                let leftBounds = build(range: start..<mid)
                let beforeRight = totalNodes
                let rightBounds = build(range: mid..<end)
                let combinedBounds = union(first: leftBounds, second: rightBounds)

                addInterior(
                        counter: counter,
                        combinedBounds: combinedBounds,
                        dim: dim,
                        beforeRight: beforeRight)
                return combinedBounds
        }

        func addInterior(counter: Int, combinedBounds: Bounds3f, dim: Int, beforeRight: Int) {
                growNodes(counter: counter)
                nodes[counter].bounds = combinedBounds
                nodes[counter].axis = dim
                nodes[counter].count = 0
                nodes[counter].offset = beforeRight
                BoundingHierarchyBuilder.interiorNodes += 1
                //print("appending interior")
        }

        private let primitivesPerNode = 4

        private static var interiorNodes = 0
        private static var leafNodes = 0
        private static var totalPrimitives = 0
        private static var callsToPartition = 0
        private static var bhNodes = 0
        private static var bhPrimitives = 0

        private var totalNodes = 0
        private var offsetCounter = 0
        private var nodes: [Node]
        private var cachedPrimitives: [CachedPrimitive]
        private var primitives: [Boundable]
}
