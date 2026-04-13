import ProjectDescription

let project = Project(
    name: "FixtureApp",
    targets: [
        .target(
            name: "FixtureApp",
            destinations: [.iPhone],
            product: .app,
            bundleId: "com.example.fixture",
            infoPlist: .default,
            sources: ["Sources/App/**"],
            dependencies: [
                .target(name: "FeatureA"),
                .target(name: "FeatureB"),
            ]
        ),
        .target(
            name: "FeatureA",
            destinations: [.iPhone],
            product: .framework,
            bundleId: "com.example.featureA",
            infoPlist: .default,
            sources: ["Sources/FeatureA/**"],
            dependencies: [
                .target(name: "Core"),
            ]
        ),
        .target(
            name: "FeatureB",
            destinations: [.iPhone],
            product: .framework,
            bundleId: "com.example.featureB",
            infoPlist: .default,
            sources: ["Sources/FeatureB/**"],
            dependencies: [
                .target(name: "Core"),
            ]
        ),
        .target(
            name: "Core",
            destinations: [.iPhone],
            product: .framework,
            bundleId: "com.example.core",
            infoPlist: .default,
            sources: ["Sources/Core/**"]
        ),
    ]
)
