import Foundation

struct CloudGarmentExport: Sendable {
    let recordID: String
    let scan: SavedScan
    let garment: SavedGarment
    let cropURL: URL?
}
struct CloudWardrobeExport: Sendable {
    let item: SavedWardrobeItem
    let cropURL: URL
}

struct CloudLibraryExport: Sendable {
    let garments: [CloudGarmentExport]
    let wardrobe: [CloudWardrobeExport]
    let searches: [SavedProductSearch]
    let products: [SavedProduct]
    let chats: [StylezamChatThread]

    var eligibleCropCount: Int {
        garments.lazy.filter { $0.cropURL != nil }.count + wardrobe.count
    }
}
