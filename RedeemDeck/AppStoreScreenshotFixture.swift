#if DEBUG
import Foundation
import SwiftData

enum AppStoreScreenshotFixture {
    static let modeArgument = "--app-store-screenshots"

    @MainActor
    static func seed(in container: ModelContainer) throws {
        let calendar = Calendar(identifier: .gregorian)
        let futureDate = calendar.date(from: DateComponents(year: 2027, month: 12, day: 31))!
        let expiredDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 30))!

        let pythonIDE = AppRecord(
            name: "PythonIDE",
            appStoreId: "6753987304",
            bundleId: "app.pythonide"
        )
        pythonIDE.iconURL = "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/d3/ee/17/d3ee1720-98a4-e730-2b36-bcc26d7fefe9/AppIcon-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.jpg"
        pythonIDE.appStoreURL = "https://apps.apple.com/app/id6753987304"
        pythonIDE.qrGreeting = localized(
            english: "A little gift for your next idea. Enjoy!",
            chinese: "送你一份小礼物，愿每个灵感都能实现！"
        )
        pythonIDE.metadataLastUpdated = Date()

        try insert(
            app: pythonIDE,
            categories: [
                category(
                    english: "50% Off · 3 Months",
                    chinese: "五折 · 3 个月",
                    product: localized(
                        english: "PythonIDE Pro Monthly",
                        chinese: "PythonIDE Pro 月度订阅"
                    ),
                    prefix: "RDPY50",
                    count: 240,
                    sent: 14,
                    expired: 6
                ),
                category(
                    english: "Launch Offer",
                    chinese: "新版发布优惠",
                    product: localized(
                        english: "PythonIDE Pro Annual",
                        chinese: "PythonIDE Pro 年度订阅"
                    ),
                    prefix: "RDPYLA",
                    count: 180,
                    sent: 15,
                    expired: 5
                ),
                category(
                    english: "Complimentary App",
                    chinese: "App 免费兑换",
                    product: "PythonIDE",
                    prefix: "RDPYAP",
                    count: 80,
                    sent: 10,
                    expired: 5
                ),
            ],
            futureDate: futureDate,
            expiredDate: expiredDate,
            context: container.mainContext
        )

        try insert(
            app: AppRecord(name: "FocusFlow", appStoreId: "demo.focusflow"),
            categories: [
                category(
                    english: "Creator Launch",
                    chinese: "创作者首发",
                    product: localized(english: "FocusFlow Pro", chinese: "FocusFlow 专业版"),
                    prefix: "RDFFCR",
                    count: 120,
                    sent: 12,
                    expired: 4
                ),
                category(
                    english: "Annual Gift",
                    chinese: "年度赠礼",
                    product: localized(english: "FocusFlow Annual", chinese: "FocusFlow 年度订阅"),
                    prefix: "RDFFYR",
                    count: 80,
                    sent: 10,
                    expired: 6
                ),
            ],
            futureDate: futureDate,
            expiredDate: expiredDate,
            context: container.mainContext
        )

        try insert(
            app: AppRecord(name: "StudioKit", appStoreId: "demo.studiokit"),
            categories: [
                category(
                    english: "Early Access",
                    chinese: "抢先体验",
                    product: localized(english: "StudioKit Plus", chinese: "StudioKit Plus"),
                    prefix: "RDSKEA",
                    count: 80,
                    sent: 4,
                    expired: 2
                ),
            ],
            futureDate: futureDate,
            expiredDate: expiredDate,
            context: container.mainContext
        )

        try container.mainContext.save()
    }

    private struct CategorySeed {
        let name: String
        let product: String
        let prefix: String
        let count: Int
        let sent: Int
        let expired: Int
    }

    private static func category(
        english: String,
        chinese: String,
        product: String,
        prefix: String,
        count: Int,
        sent: Int,
        expired: Int
    ) -> CategorySeed {
        CategorySeed(
            name: localized(english: english, chinese: chinese),
            product: product,
            prefix: prefix,
            count: count,
            sent: sent,
            expired: expired
        )
    }

    @MainActor
    private static func insert(
        app: AppRecord,
        categories: [CategorySeed],
        futureDate: Date,
        expiredDate: Date,
        context: ModelContext
    ) throws {
        context.insert(app)
        for categorySeed in categories {
            let category = CodeCategory(
                name: categorySeed.name,
                productName: categorySeed.product,
                app: app
            )
            let batch = CodeBatch(
                name: localized(english: "App Store Connect Export", chinese: "App Store Connect 导出"),
                source: .csv,
                expirationDate: futureDate
            )
            batch.app = app
            batch.category = category
            batch.codeKind = .customOffer
            context.insert(category)
            context.insert(batch)

            for index in 1...categorySeed.count {
                let value = "\(categorySeed.prefix)\(String(format: "%09d", index))"
                let isExpired = index > categorySeed.count - categorySeed.expired
                let code = OfferCode(
                    code: value,
                    redemptionURL: "https://apps.apple.com/redeem?ctx=offercodes&id=\(app.appStoreId)&code=\(value)",
                    expirationDate: isExpired ? expiredDate : futureDate
                )
                code.app = app
                code.batch = batch
                if index <= categorySeed.sent {
                    code.sentAt = Date(timeIntervalSince1970: 1_788_480_000 + Double(index))
                }
                context.insert(code)
            }
        }
    }

    private static func localized(english: String, chinese: String) -> String {
        isSimplifiedChinese ? chinese : english
    }

    private static var isSimplifiedChinese: Bool {
        let language = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        return language.lowercased().hasPrefix("zh-hans") || language.lowercased() == "zh"
    }
}
#endif
