import UIKit
import SwiftUI

extension ContentType {
    var badgeColor: UIColor {
        switch self {
        case .json:      return .systemOrange
        case .url:       return .systemBlue
        case .code:      return .systemPurple
        case .list:      return .systemGreen
        case .image:     return .systemTeal
        case .plainText: return .secondaryLabel
        }
    }

    var badgeColorSwiftUI: Color {
        Color(badgeColor)
    }
}
