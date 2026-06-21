import CoreText
import Foundation

enum FontRegistrar {
    static func registerBundledFonts() {
        guard let fontsDirectory = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
              let fontURLs = try? FileManager.default.contentsOfDirectory(
                at: fontsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for url in fontURLs where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if let error {
                NSLog("Gallaxy TTS font registration skipped \(url.lastPathComponent): \(error.takeRetainedValue().localizedDescription)")
            }
        }
    }
}
