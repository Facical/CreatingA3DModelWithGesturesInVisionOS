import RealityKit
import simd

struct CarPart: Identifiable, Hashable {
    let id: String
    let entityName: String      // USDZ 내부 엔티티 이름(덤프와 동일)
    let title: String
    let detail: String
    let offset: SIMD3<Float>    // 말풍선 추가 오프셋(미터)
}

enum CarParts {
    static let all: [CarPart] = [
        .init(id: "mirror",     entityName: "MirrorGlass10",
              title: "미러 글래스",   detail: "사이드 미러 유리.", offset: [0, 0.10, 0]),
        .init(id: "frontLight", entityName: "FrontLight85",
              title: "전조등",       detail: "프론트 라이트 어셈블리.", offset: [0, 0.12, 0.03]),
        .init(id: "steering",   entityName: "SteeringWheel374",
              title: "스티어링 휠",  detail: "조향 장치.", offset: [0, 0.10, 0])
    ]
}
