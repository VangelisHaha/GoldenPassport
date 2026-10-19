import CoreImage
import Foundation

/// 图片导入与屏幕截图共用同一套二维码识别逻辑。
public enum QRCodeReader {
    public static func otpAuthURLs(in fileURL: URL) -> [String] {
        guard let image = CIImage(contentsOf: fileURL) else { return [] }
        return otpAuthURLs(in: image)
    }

    public static func otpAuthURLs(in image: CIImage) -> [String] {
        guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return [] }
        return detector.features(in: image)
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .filter { $0.lowercased().hasPrefix("otpauth://") || GoogleAuthMigration.isMigrationURL($0) }
    }
}
