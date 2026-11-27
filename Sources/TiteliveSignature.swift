import SwiftUI
import AppKit

// MARK: - Signature Titelive (v2) — carte Liquid Glass en bas à gauche
//
// Une seule pièce compacte : icône de l'app sur un halo de sa couleur, nom de l'app,
// « par [avatar] Titelive », et un bouton café rond qui s'ouvre en « Offrir un café » au survol.
// Clic sur la carte : titelive.me. Menu contextuel : site de l'app, titelive.me, café.
//
// Barre latérale :   List { … }.titeliveSignature(appName: "Vitrail")
// Ailleurs :         TiteliveSignatureCard(appName: "AltDelete").frame(width: 240)
// Fichier identique dans toutes les apps Titelive.

enum SignatureLinks {
    static let site = URL(string: "https://titelive.me")!
    static let coffee = URL(string: "https://buymeacoffee.com/titelive")!
}

// Summer Drop est traduite : les textes passent par L() (Resources/Translations).
enum SignatureText {
    static var by: String { L("by") }
    static var coffee: String { L("Buy me a coffee") }
    static var coffeeHelp: String { L("Support {0} on Buy Me a Coffee", "Titelive") }
    static func appSite(_ app: String) -> String { L("Summer Drop on GitHub") }
}

extension View {
    /// Pose la carte en pied FIXE d'une liste ou d'une zone qui défile : le contenu reste au-dessus
    /// (safeAreaInset) et s'efface en fondu sur ~24 pt juste avant la carte. Rien n'est jamais recouvert.
    /// `cardWidth` : largeur fixe, carte calée à gauche (fenêtres sans barre latérale).
    func titeliveSignature(appName: String, appSite: URL? = nil, showsCoffee: Bool = true,
                           cardWidth: CGFloat? = nil) -> some View {
        modifier(SignatureFooterModifier(appName: appName, appSite: appSite, showsCoffee: showsCoffee,
                                         cardWidth: cardWidth, above: EmptyView()))
    }

    /// Variante avec un pied existant (`above`, par ex. un profil) posé juste au-dessus de la carte.
    func titeliveSignature<Above: View>(appName: String, appSite: URL? = nil, showsCoffee: Bool = true,
                                        @ViewBuilder above: () -> Above) -> some View {
        modifier(SignatureFooterModifier(appName: appName, appSite: appSite, showsCoffee: showsCoffee,
                                         cardWidth: nil, above: above()))
    }
}

private struct SignatureFooterModifier<Above: View>: ViewModifier {
    let appName: String
    let appSite: URL?
    let showsCoffee: Bool
    let cardWidth: CGFloat?
    let above: Above
    @State private var bottomInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                    Color.clear.frame(height: bottomInset)
                }
                .ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    above
                    TiteliveSignatureCard(appName: appName, appSite: appSite, showsCoffee: showsCoffee)
                        .frame(width: cardWidth)
                        .padding(10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
    }
}

// MARK: - Aperçu (captures) : force l'état « survol »

private struct SignatureForceHoverKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var signatureForceHover: Bool {
        get { self[SignatureForceHoverKey.self] }
        set { self[SignatureForceHoverKey.self] = newValue }
    }
}

// MARK: - Carte

struct TiteliveSignatureCard: View {
    let appName: String
    var appSite: URL? = nil
    var showsCoffee: Bool = true

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.signatureForceHover) private var forceHover
    @State private var hovering = false
    @State private var coffeeOpen = false

    var body: some View {
        // Le café s'ouvre vers la gauche par-dessus la carte (le nom s'estompe) :
        // la carte garde sa taille, rien ne se tasse ni ne se tronque.
        ZStack(alignment: .trailing) {
            Button { openURL(SignatureLinks.site) } label: { identity }
                .buttonStyle(.plain)
                .padding(.trailing, showsCoffee ? 36 : 0)
                .opacity(coffeeOpen ? 0.18 : 1)
                .help("titelive.me")
                .accessibilityLabel("\(appName), \(SignatureText.by) Titelive")
                .accessibilityHint("Ouvre titelive.me")
                .accessibilityAddTraits(.isLink)

            if showsCoffee {
                SignatureCoffeeButton(open: $coffeeOpen)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 11)
        .frame(height: 50)
        .frame(maxWidth: .infinity, alignment: .leading)
        .signatureCardGlass()
        .shadow(color: .black.opacity(hovering ? 0.16 : 0.07), radius: hovering ? 14 : 6, y: hovering ? 6 : 2)
        .scaleEffect(hovering && !reduceMotion ? 1.01 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .onAppear { if forceHover { hovering = true } }
        .contextMenu {
            if let appSite {
                Button(SignatureText.appSite(appName)) { openURL(appSite) }
            }
            Button("titelive.me") { openURL(SignatureLinks.site) }
            if showsCoffee {
                Button(SignatureText.coffee) { openURL(SignatureLinks.coffee) }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var identity: some View {
        HStack(spacing: 10) {
            SignatureAppIcon(hovering: hovering)
            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text(SignatureText.by)
                    SignatureAvatar(size: 14)
                    Text("Titelive").fontWeight(.medium)
                }
                .font(.system(size: 11))
                // Primaire atténué plutôt que .secondary : ≥ 4,5:1 sur le verre, en clair comme en sombre
                .foregroundStyle(.primary.opacity(0.72))
            }
            .lineLimit(1)
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Icône de l'app sur halo

private struct SignatureAppIcon: View {
    let hovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [SignatureAppColor.color, SignatureAppColor.color.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 22))
                .frame(width: 44, height: 44)
                .blur(radius: 6)
                .opacity(hovering ? 0.6 : 0.35)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .rotationEffect(.degrees(hovering && !reduceMotion ? -6 : 0))
                .scaleEffect(hovering && !reduceMotion ? 1.08 : 1)
        }
        .frame(width: 28, height: 28)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.6), value: hovering)
        .accessibilityHidden(true)
    }
}

/// Couleur propre de l'app, tirée de son icône (moyenne saturée), calculée une fois.
@MainActor
enum SignatureAppColor {
    static let color: Color = {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)
        guard let rep, let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return .accentColor }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        // Le centre de l'icône : évite que le fond ou les bords ne délavent la teinte
        NSApp.applicationIconImage.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1),
                                        from: NSRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6).scaled(to: NSApp.applicationIconImage.size),
                                        operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let c = rep.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else { return .accentColor }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.12 { return .accentColor }   // icône grise : couleur d'accent du système
        return Color(nsColor: NSColor(hue: h, saturation: max(s, 0.65), brightness: max(b, 0.75), alpha: 1))
    }()
}

private extension NSRect {
    func scaled(to size: NSSize) -> NSRect {
        NSRect(x: minX * size.width, y: minY * size.height, width: width * size.width, height: height * size.height)
    }
}

// MARK: - Bouton café

/// Rond jaune Buy Me a Coffee ; au survol il s'ouvre en capsule « Offrir un café »,
/// la tasse fait un clin et un peu de vapeur monte.
struct SignatureCoffeeButton: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.signatureForceHover) private var forceHover
    @Binding var open: Bool
    @State private var wink = false
    private var hovering: Bool { open }

    private static let yellow = Color(red: 1, green: 0xDD / 255, blue: 0)
    private static let ink = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255)

    var body: some View {
        Button { openURL(SignatureLinks.coffee) } label: {
            HStack(spacing: 5) {
                ZStack(alignment: .top) {
                    if hovering && !reduceMotion { SignatureSteam().offset(y: -9) }
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(wink ? -12 : 0), anchor: .bottom)
                }
                .frame(width: 16, height: 16)
                if hovering {
                    Text(SignatureText.coffee)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(Self.ink)
            .padding(.horizontal, hovering ? 10 : 6)
            .frame(minWidth: 28, minHeight: 28)
            .background(Capsule().fill(Self.yellow))
            .shadow(color: Self.yellow.opacity(hovering ? 0.55 : 0.35), radius: hovering ? 8 : 4, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { inside in
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.72)) {
                open = inside
            }
            guard inside, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.12)) { wink = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { wink = false }
            }
        }
        .onAppear { if forceHover { open = true } }
        .help(SignatureText.coffeeHelp)
        .accessibilityLabel(SignatureText.coffeeHelp)
        .accessibilityHint("Ouvre buymeacoffee.com/titelive")
    }
}

/// Trois filets de vapeur qui montent en boucle.
private struct SignatureSteam: View {
    @State private var rise = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: 1.6, height: 4.5)
                    .offset(y: rise ? -5 : 1)
                    .opacity(rise ? 0 : 0.9)
                    .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false).delay(Double(i) * 0.18), value: rise)
            }
        }
        .onAppear { rise = true }
        .accessibilityHidden(true)
    }
}

// MARK: - Avatar

/// Avatar de Titelive (avatar.png / Avatar.png dans les ressources de l'app), sinon un « T ».
struct SignatureAvatar: View {
    var size: CGFloat = 14

    private static let image: NSImage? = {
        for name in ["avatar", "Avatar"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png") { return NSImage(contentsOf: url) }
        }
        return nil
    }()

    var body: some View {
        Group {
            if let img = Self.image {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Text("T")
                    .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255))
            }
        }
        .frame(width: size, height: size)
        .background(Color(red: 0.85, green: 0.98, blue: 0.55), in: Circle())
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Verre

private struct SignatureFlatGlassKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Rendus hors écran uniquement : le verre natif ne s'y dessine pas, on peint son équivalent.
    var signatureFlatGlass: Bool {
        get { self[SignatureFlatGlassKey.self] }
        set { self[SignatureFlatGlassKey.self] = newValue }
    }
}

private struct SignatureCardGlass: ViewModifier {
    @Environment(\.signatureFlatGlass) private var flat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if flat {
            content
                .background(shape.fill(scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.72)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.25 : 0.9), .clear],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1).padding(0.5))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
    }
}

private extension View {
    /// Liquid Glass natif sur macOS 26 ; sinon matériau ultra fin, liseré 0,5 pt et ombre douce.
    func signatureCardGlass() -> some View { modifier(SignatureCardGlass()) }
}
