/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A view to load in a model of a car that people can manipulate with gestures.
*/

import SwiftUI
import RealityKit
import simd

// ===== 말풍선 목표 폭(미터) — 필요시 0.10~0.16 사이로 조절 =====
private let targetCalloutWidth: Float = 0.16    // 12cm

// ===== 디버그: 엔티티 이름 덤프 =====
func dumpEntityNames(_ entity: Entity, indent: String = "") {
    print("\(indent)ENTITY:", entity.name)
    for child in entity.children { dumpEntityNames(child, indent: indent + "  ") }
}

// ===== 유틸: 재귀 순회 / 월드 변환 =====
extension Entity {
    func forEachDescendant(_ body: (Entity) -> Void) {
        body(self)
        for c in children { c.forEachDescendant(body) }
    }
    
    var worldPosition: SIMD3<Float> {
        let m = transformMatrix(relativeTo: nil)
        return .init(m.columns.3.x, m.columns.3.y, m.columns.3.z)
    }
    
    func setWorldPosition(_ p: SIMD3<Float>) {
        var m = transformMatrix(relativeTo: nil)
        m.columns.3 = SIMD4<Float>(p.x, p.y, p.z, 1)
        setTransformMatrix(m, relativeTo: nil)
    }
    
    // 재귀적으로 이름으로 엔티티 찾기
    func findEntityRecursive(named name: String) -> Entity? {
        if self.name == name {
            return self
        }
        for child in children {
            if let found = child.findEntityRecursive(named: name) {
                return found
            }
        }
        return nil
    }
}

// ===== 유틸: 말풍선/텍스트를 목표 폭에 맞게 월드 스케일 보정 =====
@inline(__always)
func fitAttachmentWidth(_ e: Entity, targetWidth: Float) {
    // 현재 월드 폭(visualBounds extents.x * 2)
    let vb = e.visualBounds(relativeTo: nil)
    let current = max(0.0001, vb.extents.x * 2)
    let s = targetWidth / current
    // 현재 월드 스케일에 비율 곱해 적용 → 매 프레임 적용해도 안정
    e.setScale(e.scale * SIMD3<Float>(repeating: s), relativeTo: e.parent)
}

struct CarView: View {
    @State var initialPosition: SIMD3<Float>? = nil
    @State var initialScale: SIMD3<Float>? = nil

    @State private var carEntity: Entity?
    @State private var showCallouts: Bool = true
    @State private var didDumpNames = false
    @State private var updateSub: EventSubscription?   // 리더라인 업데이트 구독

    // ===== 제스처: 항상 루트(carEntity)만 조작 =====
    var translationGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { v in
                guard let car = carEntity else { return }
                if initialPosition == nil { initialPosition = car.position }
                let move = v.convert(v.translation3D, from: .global, to: .scene)
                car.position = (initialPosition ?? .zero) + move.grounded
            }
            .onEnded { _ in initialPosition = nil }
    }

    var scaleGesture: some Gesture {
        MagnifyGesture()
            .targetedToAnyEntity()
            .onChanged { v in
                guard let car = carEntity else { return }
                if initialScale == nil { initialScale = car.scale }
                car.scale = (initialScale ?? .one) * Float(v.gestureValue.magnification)
            }
            .onEnded { _ in initialScale = nil }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityView { content, attachments in
                let fileName = "Huracan-EVO-RWD-Spyder-opt-22"

                // 1) 모델 1회 로드
                if carEntity == nil {
                    guard let car = try? await Entity(named: fileName) else {
                        assertionFailure("Failed to load model: \(fileName)")
                        return
                    }

                    // 계층 전체 충돌/입력 활성화
                    car.generateCollisionShapes(recursive: true)
                    car.forEachDescendant { $0.components.set(InputTargetComponent()) }

                    // 배치
                    let bounds = car.visualBounds(relativeTo: nil)
                    car.position.y -= bounds.min.y
                    car.position.z += bounds.min.z
                    car.position.x += bounds.min.x
                    car.scale /= 1.5

                    // 루트에 큰 충돌박스(히트 안정화)
                    let size = bounds.extents
                    let boxShape = ShapeResource.generateBox(size: size)
                    car.components.set(CollisionComponent(shapes: [boxShape]))

                    content.add(car)
                    carEntity = car
                    print("✅ Car loaded and added to scene:", fileName)
                }

                guard let car = carEntity else { return }

                // 2) 실제 하위 엔티티 이름 덤프(1회)
                if !didDumpNames {
                    print("——— ENTITY NAME DUMP START ———")
                    dumpEntityNames(car)
                    print("——— ENTITY NAME DUMP END ———")
                    didDumpNames = true
                }

                // 3) 루트 테스트 말풍선(월드 좌표)
                if #available(visionOS 2.0, *) {
                    if let rootCallout = attachments.entity(for: "root") {
                        if rootCallout.parent == nil { car.addChild(rootCallout) }
                        let vbW = car.visualBounds(relativeTo: nil)
                        let worldPos = vbW.center + SIMD3<Float>(0, vbW.extents.y * 0.7, 0)
                        rootCallout.setWorldPosition(worldPos)
                        rootCallout.components.set(BillboardComponent())
                        // ★ 크기 자동 보정
                        fitAttachmentWidth(rootCallout, targetWidth: targetCalloutWidth)
                        rootCallout.isEnabled = showCallouts
                        print("✅ attachments root created & added @", worldPos)
                    } else {
                        print("❌ attachments.entity(for: root) == nil")
                    }
                }

                // 4) 각 파트 말풍선 + 리더라인 + 프로브(월드 좌표 기반)
                for part in CarParts.all {
                    // findEntityRecursive 사용하여 중첩된 구조에서도 찾기
                    guard let host = car.findEntityRecursive(named: part.entityName) else {
                        print("❌ Cannot find entity:", part.entityName)
                        continue
                    }
                    
                    print("\n🔍 ===== \(part.id) (\(part.entityName)) 디버그 =====")
                    
                    // 1. 부품의 로컬 position (Transform 기반)
                    let localPos = host.position
                    print("📍 Local Position (Transform): \(localPos)")
                    
                    // 2. 부품의 월드 position (Transform 기반)
                    let transformWorldPos = host.position(relativeTo: nil)
                    print("📍 World Position (Transform): \(transformWorldPos)")
                    
                    // 3. 부품의 로컬 바운딩 박스
                    let localBounds = host.visualBounds(relativeTo: host)
                    print("📦 Local Bounds:")
                    print("   - Center: \(localBounds.center)")
                    print("   - Min: \(localBounds.min)")
                    print("   - Max: \(localBounds.max)")
                    print("   - Extents: \(localBounds.extents)")
                    
                    // 4. 부품의 월드 바운딩 박스
                    let worldBounds = host.visualBounds(relativeTo: nil)
                    print("🌍 World Bounds:")
                    print("   - Center: \(worldBounds.center)")
                    print("   - Min: \(worldBounds.min)")
                    print("   - Max: \(worldBounds.max)")
                    print("   - Extents: \(worldBounds.extents)")
                    
                    // 5. 부모 정보
                    if let parent = host.parent {
                        print("👆 Parent: \(parent.name)")
                        print("   - Parent World Pos: \(parent.position(relativeTo: nil))")
                    }
                    
                    // 6. Transform Matrix 정보
                    let matrix = host.transformMatrix(relativeTo: nil)
                    print("📐 Transform Matrix (columns 3 - position):")
                    print("   - x: \(matrix.columns.3.x)")
                    print("   - y: \(matrix.columns.3.y)")
                    print("   - z: \(matrix.columns.3.z)")
                    
                    // ✅ visualBounds.center로 부품의 실제 월드 위치 가져오기
                    let hostWorldPos = worldBounds.center  // 실제 부품의 3D 중심 위치
                    
                    // 말풍선 위치: 부품 실제 중심 위치 + 위쪽 오프셋 + 개별 오프셋
                    let worldTarget = hostWorldPos +
                        SIMD3<Float>(0, worldBounds.extents.y * 0.5 + 0.1, 0) +
                        part.offset
                    
                    print("🎯 최종 Attachment 위치: \(worldTarget)")
                    print("=======================================\n")
                    
                    // (디버그) 위치 확인용: 빨간 구
                    let probeName = "Probe:\(part.id)"
                    if car.findEntity(named: probeName) == nil {
                        let probe = ModelEntity(
                            mesh: .generateSphere(radius: 0.02),
                            materials: [SimpleMaterial(color: .red, isMetallic: false)]
                        )
                        probe.name = probeName
                        car.addChild(probe)
                    }
                    if let probe = car.findEntity(named: probeName) {
                        probe.setWorldPosition(worldTarget)
                        probe.isEnabled = showCallouts
                    }
                    
                    // (A) visionOS 2: attachments 말풍선
                    if #available(visionOS 2.0, *), let callout = attachments.entity(for: part.id) {
                        callout.name = "Attachment:\(part.id)"
                        if callout.parent == nil { car.addChild(callout) }
                        callout.setWorldPosition(worldTarget)
                        callout.components.set(BillboardComponent())
                        // ★ 크기 자동 보정
                        fitAttachmentWidth(callout, targetWidth: targetCalloutWidth)
                        callout.isEnabled = showCallouts
                    } else {
                        // (B) 폴백: 3D 텍스트(월드 좌표)
                        let labelName = "FallbackLabel:\(part.id)"
                        if car.findEntity(named: labelName) == nil {
                            let mesh = try? MeshResource.generateText(
                                "\(part.title)",
                                extrusionDepth: 0.002,
                                font: .systemFont(ofSize: 0.06),
                                containerFrame: .zero,
                                alignment: .left,
                                lineBreakMode: .byWordWrapping
                            )
                            let textE = ModelEntity(mesh: mesh ?? .generateBox(size: .one * 0.05),
                                                                materials: [UnlitMaterial(color: .white)])
                            textE.name = labelName
                            car.addChild(textE)
                        }
                        if let textE = car.findEntity(named: labelName) {
                            textE.setWorldPosition(worldTarget)
                            // ★ 크기 자동 보정
                            fitAttachmentWidth(textE, targetWidth: targetCalloutWidth)
                            textE.isEnabled = showCallouts
                        }
                    }

                    // 리더라인(막대+화살표) 생성(루트 자식)
                    if car.findEntity(named: "Leader:\(part.id)") == nil {
                        let stick = ModelEntity(
                            mesh: .generateBox(size: [0.002, 0.002, 1.0]), // 얇게
                            materials: [SimpleMaterial(color: .white, isMetallic: false)]
                        )
                        stick.name = "Leader:\(part.id)"
                        car.addChild(stick)

                        let tipMesh: MeshResource = (try? .generateCone(height: 0.02, radius: 0.008))
                            ?? .generateSphere(radius: 0.009)
                        let tip = ModelEntity(mesh: tipMesh,
                                              materials: [SimpleMaterial(color: .white, isMetallic: false)])
                        tip.name = "Arrow:\(part.id)"
                        car.addChild(tip)
                    }
                }

                // 5) 매 프레임 리더라인 정렬 + 말풍선 크기 재보정(차 크기 바뀔 때 대비)
                if updateSub == nil {
                    updateSub = content.subscribe(to: SceneEvents.Update.self) { _ in
                        guard let car = carEntity else { return }

                        // 루트/파트 말풍선 크기 유지
                        if #available(visionOS 2.0, *) {
                            if let root = car.children.first(where: { $0.name == "Attachment:root" }) {
                                fitAttachmentWidth(root, targetWidth: targetCalloutWidth)
                            }
                            for part in CarParts.all {
                                if let callout = car.children.first(where: { $0.name == "Attachment:\(part.id)" }) {
                                    fitAttachmentWidth(callout, targetWidth: targetCalloutWidth)
                                }
                                if let fallback = car.findEntity(named: "FallbackLabel:\(part.id)") {
                                    fitAttachmentWidth(fallback, targetWidth: targetCalloutWidth)
                                }
                            }
                        }

                        // 리더라인 정렬
                        for part in CarParts.all {
                            // findEntityRecursive 사용
                            guard let host = car.findEntityRecursive(named: part.entityName) else { continue }
                            
                            // ✅ visualBounds.center 사용해서 부품의 실제 중심점 가져오기
                            let worldBounds = host.visualBounds(relativeTo: nil)
                            let A = worldBounds.center  // 부품의 실제 중심점

                            // 말풍선 위치
                            var b: SIMD3<Float>?
                            if #available(visionOS 2.0, *) {
                                if let callout = car.children.first(where: { $0.name == "Attachment:\(part.id)" }) {
                                    b = callout.worldPosition
                                }
                            }
                            if b == nil, let fallback = car.findEntity(named: "FallbackLabel:\(part.id)") {
                                b = fallback.worldPosition
                            }
                            guard let B = b else { continue }

                            guard
                                let stick = car.findEntity(named: "Leader:\(part.id)") as? ModelEntity,
                                let tip   = car.findEntity(named: "Arrow:\(part.id)") as? ModelEntity
                            else { continue }

                            let mid = (A + B) * 0.5
                            stick.setWorldPosition(mid)
                            stick.look(at: B, from: mid, relativeTo: nil)
                            let len = max(simd_length(B - A), 0.05)
                            stick.scale = [1, 1, len]

                            let dir = simd_normalize(B - A)
                            tip.setWorldPosition(B - dir * 0.015)
                            tip.look(at: B, from: tip.worldPosition, relativeTo: nil)
                        }
                    }
                }
            } attachments: {
                // (visionOS 2) 루트 테스트용
                Attachment(id: "root") {
                    CalloutBubble(title: "차량", detail: "루트 Callout (테스트)")
                        .frame(minWidth: 200) // 프레임은 커도 스케일로 12cm에 맞춰짐
                        .padding(4)
                }
                // (visionOS 2) 파트별 말풍선
                ForEach(CarParts.all) { part in
                    Attachment(id: part.id) {
                        CalloutBubble(title: part.title, detail: part.detail)
                            .frame(minWidth: 200)
                            .padding(4)
                    }
                }
            }
            // 제스처 동시 인식
            .gesture(translationGesture)
            .simultaneousGesture(scaleGesture)

            // 토글
            Toggle("부품 설명", isOn: $showCallouts)
                .toggleStyle(.switch)
                .padding()
        }
    }
}
