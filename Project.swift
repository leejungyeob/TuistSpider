import ProjectDescription

let project = Project(
    name: "TuistSpider",
    settings: .settings(
        base: [
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
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
            infoPlist: .extendingDefault(
                with: [
                    "LSApplicationCategoryType": "public.app-category.developer-tools",
                ]
            ),
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"]
        ),
        .target(
            name: "TuistSpiderTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.leejungyeob.TuistSpiderTests",
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "TuistSpider"),
            ]
        ),
    ]
)
