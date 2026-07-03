// swift-tools-version:6.1
import PackageDescription

// Camadas (docs/01_ARCHITECTURE.md):
//  - FluxDomain: entidades, value objects e protocolos. Sem dependências.
//  - FluxInfrastructure: implementações técnicas (SIP mock, logging). Depende só de FluxDomain.
//  - FluxWhiteLabel: configuração de marca declarativa (docs/02_WHITE_LABEL_SYSTEM.md).
//  - FluxSoftphone: executável — App + Presentation. Única camada que conhece SwiftUI de tela.
// A separação em targets torna violações de camada um erro de compilação.
let package = Package(
    name: "FluxSoftphone",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "FluxDomain"
        ),
        .target(
            name: "FluxInfrastructure",
            dependencies: ["FluxDomain"]
        ),
        .target(
            name: "FluxWhiteLabel",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "FluxSoftphone",
            dependencies: [
                "FluxDomain",
                "FluxInfrastructure",
                "FluxWhiteLabel"
            ]
        ),
        .testTarget(
            name: "FluxDomainTests",
            dependencies: ["FluxDomain"]
        ),
        .testTarget(
            name: "FluxInfrastructureTests",
            dependencies: ["FluxInfrastructure", "FluxDomain"]
        ),
        .testTarget(
            name: "FluxWhiteLabelTests",
            dependencies: ["FluxWhiteLabel"]
        )
    ]
)
