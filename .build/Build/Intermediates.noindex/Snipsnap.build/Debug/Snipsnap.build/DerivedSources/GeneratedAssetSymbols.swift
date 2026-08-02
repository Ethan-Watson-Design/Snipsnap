import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "MenuBarIcon" asset catalog image resource.
    static let menuBarIcon = DeveloperToolsSupport.ImageResource(name: "MenuBarIcon", bundle: resourceBundle)

    /// The "RabbitHop0" asset catalog image resource.
    static let rabbitHop0 = DeveloperToolsSupport.ImageResource(name: "RabbitHop0", bundle: resourceBundle)

    /// The "RabbitHop1" asset catalog image resource.
    static let rabbitHop1 = DeveloperToolsSupport.ImageResource(name: "RabbitHop1", bundle: resourceBundle)

    /// The "RabbitHop2" asset catalog image resource.
    static let rabbitHop2 = DeveloperToolsSupport.ImageResource(name: "RabbitHop2", bundle: resourceBundle)

    /// The "RabbitHop3" asset catalog image resource.
    static let rabbitHop3 = DeveloperToolsSupport.ImageResource(name: "RabbitHop3", bundle: resourceBundle)

    /// The "RabbitHop4" asset catalog image resource.
    static let rabbitHop4 = DeveloperToolsSupport.ImageResource(name: "RabbitHop4", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "MenuBarIcon" asset catalog image.
    static var menuBarIcon: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .menuBarIcon)
#else
        .init()
#endif
    }

    /// The "RabbitHop0" asset catalog image.
    static var rabbitHop0: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .rabbitHop0)
#else
        .init()
#endif
    }

    /// The "RabbitHop1" asset catalog image.
    static var rabbitHop1: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .rabbitHop1)
#else
        .init()
#endif
    }

    /// The "RabbitHop2" asset catalog image.
    static var rabbitHop2: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .rabbitHop2)
#else
        .init()
#endif
    }

    /// The "RabbitHop3" asset catalog image.
    static var rabbitHop3: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .rabbitHop3)
#else
        .init()
#endif
    }

    /// The "RabbitHop4" asset catalog image.
    static var rabbitHop4: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .rabbitHop4)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "MenuBarIcon" asset catalog image.
    static var menuBarIcon: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .menuBarIcon)
#else
        .init()
#endif
    }

    /// The "RabbitHop0" asset catalog image.
    static var rabbitHop0: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .rabbitHop0)
#else
        .init()
#endif
    }

    /// The "RabbitHop1" asset catalog image.
    static var rabbitHop1: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .rabbitHop1)
#else
        .init()
#endif
    }

    /// The "RabbitHop2" asset catalog image.
    static var rabbitHop2: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .rabbitHop2)
#else
        .init()
#endif
    }

    /// The "RabbitHop3" asset catalog image.
    static var rabbitHop3: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .rabbitHop3)
#else
        .init()
#endif
    }

    /// The "RabbitHop4" asset catalog image.
    static var rabbitHop4: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .rabbitHop4)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

