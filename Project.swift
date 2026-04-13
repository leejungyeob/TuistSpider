import ProjectDescription

let project = Project(
    name: "TuistSpider",
    settings: .settings(
        base: [
            "CODE_SIGNING_ALLOWED": "NO",
            "CODE_SIGNING_REQUIRED": "NO",
            "CODE_SIGN_IDENTITY": "",
        ]
    ),
    targets: [
        .target(
            name: "TuistSpider",
            destinations: [.mac],
            product: .app,
            bundleId: "com.leejungyeob.TuistSpider",
            infoPlist: .default,
            sources: ["App/Sources/**"]
        ),
    ]
)
