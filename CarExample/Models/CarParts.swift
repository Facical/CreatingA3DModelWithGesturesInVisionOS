import RealityKit
import simd

struct CarPart: Identifiable, Hashable {
    let id: String
    let entityName: String
    let title: String
    let detail: String
    let offset: SIMD3<Float>
}

// 계기판, 스티어링 휠, 후미등 빼고 다 지우기

enum CarParts {
    static let all: [CarPart] = [
        .init(id: "backLight", entityName: "BackLight101",
              title: "후미등", detail: "LED 테일라이트", offset: [0, 0.02, 0]),
        .init(id: "steering", entityName: "SteeringWheel374",
              title: "스티어링 휠", detail: "가죽 스티어링 휠", offset: [0, -0.06, 0]),
        .init(id: "cockpit", entityName: "HMICockpit34",
              title: "계기판", detail: "디지털 클러스터", offset: [0, -0.05, 0]),
        
    ]
}
