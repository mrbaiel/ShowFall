import AppKit
import SceneKit

func v3(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNVector3 {
    return SCNVector3(x: x, y: y, z: z)
}

/// Лента сугроба: X-координаты столбцов и высота в каждом
struct SnowStrip {
    var xs: [CGFloat]
    var hs: [CGFloat]
}

/// Строит 3D-сетку сугроба. Вид спереди: гребень выше всего, к зрителю склон спускается,
/// а толщина вглубь растёт вместе с высотой, как у настоящего намёта.
enum SnowMesh {
    /// Сечение: (смещение по глубине, доля высоты)
    private static let rows: [(CGFloat, CGFloat)] = [
        (-0.9, 0.0), (-0.5, 0.85), (-0.1, 1.0), (0.35, 0.55), (0.7, 0.15), (0.85, 0.0)
    ]

    static let material: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = NSColor(calibratedWhite: 0.98, alpha: 1)
        m.emission.contents = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: 1)
        m.isDoubleSided = true
        return m
    }()

    static func make(strips: [SnowStrip]) -> SCNGeometry? {
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        let rc = rows.count

        for strip in strips {
            let n = strip.xs.count
            guard n >= 2, strip.hs.count == n else { continue }
            let base = positions.count

            func pos(_ i: Int, _ r: Int) -> SCNVector3 {
                let h = strip.hs[i]
                let depth = 1 + SnowTuning.drift3DDepth * h
                return v3(strip.xs[i], rows[r].1 * h, rows[r].0 * depth)
            }

            for i in 0..<n {
                for r in 0..<rc {
                    positions.append(pos(i, r))
                }
            }

            // Нормали по соседним вершинам: n = tz x tx
            for i in 0..<n {
                for r in 0..<rc {
                    let tx = sub(pos(min(i + 1, n - 1), r), pos(max(i - 1, 0), r))
                    let tz = sub(pos(i, min(r + 1, rc - 1)), pos(i, max(r - 1, 0)))
                    normals.append(unit(cross(tz, tx)))
                }
            }

            for i in 0..<(n - 1) {
                for r in 0..<(rc - 1) {
                    let a = Int32(base + i * rc + r)
                    let b = Int32(base + (i + 1) * rc + r)
                    let c = a + 1
                    let d = b + 1
                    indices.append(contentsOf: [a, c, b, b, c, d])
                }
            }
        }

        guard !positions.isEmpty else { return nil }
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals)
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.firstMaterial = material
        return geometry
    }

    private static func sub(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        return v3(a.x - b.x, a.y - b.y, a.z - b.z)
    }

    private static func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        return v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    private static func unit(_ v: SCNVector3) -> SCNVector3 {
        let len = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        if len < 0.000001 { return v3(0, 1, 0) }
        return v3(v.x / len, v.y / len, v.z / len)
    }
}
