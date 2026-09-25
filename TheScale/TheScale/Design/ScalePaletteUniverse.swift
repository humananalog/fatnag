import SwiftUI

/// Two gender-linked design universes for home haze, Progress atmosphere, and related chrome.
///
/// **Default when sex is missing:** `.glacierForge` (male). Matches `UserBodyProfile`’s stored
/// default and onboarding’s `sex ?? .male` — cool steel is the safer neutral until gender is set.
///
/// Universes are obviously different at a glance (background + haze), not a tiny accent swap.
/// Band semantics stay intact: green = on track, lime = ahead, coral = at risk.
enum ScalePaletteUniverse: String, CaseIterable, Equatable, Sendable {
    /// Male — cool graphite void, teal–cyan athletic steel haze.
    case glacierForge
    /// Female — warm rose-quartz dusk, champagne-copper haze (not cream/terracotta).
    case bloomCopper

    /// Resolves profile sex → universe. `nil` / unknown → glacierForge.
    static func resolve(sex: UserBodyProfile.Sex?) -> ScalePaletteUniverse {
        switch sex {
        case .female: return .bloomCopper
        case .male, .none: return .glacierForge
        }
    }

    var displayName: String {
        switch self {
        case .glacierForge: return "Glacier Forge"
        case .bloomCopper: return "Bloom Copper"
        }
    }

    // MARK: - Shared ink (readable in both night modes)

    fileprivate static let deepInk = Color(red: 0.04, green: 0.05, blue: 0.07)
    fileprivate static let deepMuted = Color(red: 0.12, green: 0.13, blue: 0.16)
    fileprivate static let ivory = Color(red: 0.96, green: 0.95, blue: 0.92)
    fileprivate static let ivoryMuted = Color(red: 0.72, green: 0.74, blue: 0.78)

    // MARK: - Void bases (night)

    /// Cool blue-black void — Glacier Forge night.
    fileprivate static let glacierVoidTop = Color(red: 0.04, green: 0.07, blue: 0.10)
    fileprivate static let glacierVoidMid = Color(red: 0.05, green: 0.08, blue: 0.12)
    fileprivate static let glacierVoidBottom = Color(red: 0.03, green: 0.05, blue: 0.08)

    /// Warm rose-black void — Bloom Copper night.
    fileprivate static let bloomVoidTop = Color(red: 0.08, green: 0.05, blue: 0.07)
    fileprivate static let bloomVoidMid = Color(red: 0.10, green: 0.06, blue: 0.08)
    fileprivate static let bloomVoidBottom = Color(red: 0.06, green: 0.04, blue: 0.05)

    /// Paywall / luxury gold biased to the active universe (continuity with sex-aware heroes).
    var paywallGold: Color {
        switch self {
        case .glacierForge:
            // Cooler champagne-steel gold
            return Color(red: 0.78, green: 0.72, blue: 0.52)
        case .bloomCopper:
            // Warmer champagne-copper (existing paywall gold family)
            return Color(red: 0.82, green: 0.66, blue: 0.40)
        }
    }

    var paywallGoldDeep: Color {
        switch self {
        case .glacierForge:
            return Color(red: 0.42, green: 0.40, blue: 0.22)
        case .bloomCopper:
            return Color(red: 0.48, green: 0.36, blue: 0.18)
        }
    }

    var paywallInk: Color {
        switch self {
        case .glacierForge:
            return Color(red: 0.04, green: 0.055, blue: 0.075)
        case .bloomCopper:
            return Color(red: 0.05, green: 0.045, blue: 0.055)
        }
    }
}

extension WeeklyGoalAtmosphere {
    /// Builds band atmosphere tinted by the gender universe.
    static func forBand(
        _ band: WeeklyTrackBand,
        colorScheme: ColorScheme = .light,
        sex: UserBodyProfile.Sex? = nil
    ) -> WeeklyGoalAtmosphere {
        forBand(band, colorScheme: colorScheme, universe: .resolve(sex: sex))
    }

    static func forBand(
        _ band: WeeklyTrackBand,
        colorScheme: ColorScheme = .light,
        universe: ScalePaletteUniverse
    ) -> WeeklyGoalAtmosphere {
        switch universe {
        case .glacierForge:
            return glacierForge(band: band, dark: colorScheme == .dark)
        case .bloomCopper:
            return bloomCopper(band: band, dark: colorScheme == .dark)
        }
    }

    // MARK: Glacier Forge (male)

    private static func glacierForge(band: WeeklyTrackBand, dark: Bool) -> WeeklyGoalAtmosphere {
        let ink = dark ? ScalePaletteUniverse.ivory : ScalePaletteUniverse.deepInk
        let muted = dark ? ScalePaletteUniverse.ivoryMuted : ScalePaletteUniverse.deepMuted
        let panel = dark ? Color.white.opacity(0.06) : Color.clear
        let voidT = ScalePaletteUniverse.glacierVoidTop
        let voidM = ScalePaletteUniverse.glacierVoidMid
        let voidB = ScalePaletteUniverse.glacierVoidBottom

        switch band {
        case .onTrack:
            if dark {
                return WeeklyGoalAtmosphere(
                    top: voidT, mid: voidM, bottom: voidB,
                    hazeA: Color(red: 0.12, green: 0.58, blue: 0.52).opacity(0.44),
                    hazeB: Color(red: 0.22, green: 0.72, blue: 0.78).opacity(0.30),
                    ink: ink, muted: muted,
                    accent: Color(red: 0.38, green: 0.88, blue: 0.78),
                    panel: panel
                )
            }
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.86, green: 0.95, blue: 0.93),
                mid: Color(red: 0.52, green: 0.84, blue: 0.74),
                bottom: Color(red: 0.32, green: 0.70, blue: 0.64),
                hazeA: Color(red: 0.18, green: 0.62, blue: 0.52).opacity(0.38),
                hazeB: Color(red: 0.36, green: 0.80, blue: 0.78).opacity(0.40),
                ink: ink, muted: muted,
                accent: Color(red: 0.06, green: 0.42, blue: 0.36),
                panel: panel
            )
        case .ahead, .crushed:
            if dark {
                return WeeklyGoalAtmosphere(
                    top: voidT, mid: voidM, bottom: voidB,
                    hazeA: Color(red: 0.48, green: 0.86, blue: 0.32).opacity(0.40),
                    hazeB: Color(red: 0.62, green: 0.92, blue: 0.48).opacity(0.26),
                    ink: ink, muted: muted,
                    accent: Color(red: 0.72, green: 0.96, blue: 0.42),
                    panel: panel
                )
            }
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.90, green: 0.97, blue: 0.80),
                mid: Color(red: 0.74, green: 0.92, blue: 0.42),
                bottom: Color(red: 0.56, green: 0.80, blue: 0.30),
                hazeA: Color(red: 0.58, green: 0.86, blue: 0.28).opacity(0.38),
                hazeB: Color(red: 0.78, green: 0.94, blue: 0.48).opacity(0.36),
                ink: ink, muted: muted,
                accent: Color(red: 0.28, green: 0.48, blue: 0.10),
                panel: panel
            )
        case .atRisk:
            if dark {
                return WeeklyGoalAtmosphere(
                    top: voidT, mid: voidM, bottom: voidB,
                    hazeA: Color(red: 0.78, green: 0.36, blue: 0.32).opacity(0.40),
                    hazeB: Color(red: 0.88, green: 0.52, blue: 0.40).opacity(0.26),
                    ink: ink, muted: muted,
                    accent: Color(red: 0.96, green: 0.58, blue: 0.48),
                    panel: panel
                )
            }
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.96, green: 0.90, blue: 0.90),
                mid: Color(red: 0.88, green: 0.68, blue: 0.64),
                bottom: Color(red: 0.78, green: 0.48, blue: 0.46),
                hazeA: Color(red: 0.76, green: 0.34, blue: 0.32).opacity(0.34),
                hazeB: Color(red: 0.90, green: 0.60, blue: 0.54).opacity(0.36),
                ink: ink, muted: muted,
                accent: Color(red: 0.48, green: 0.16, blue: 0.14),
                panel: panel
            )
        case .unknown:
            if dark {
                return WeeklyGoalAtmosphere(
                    top: voidT, mid: voidM, bottom: voidB,
                    hazeA: Color(red: 0.32, green: 0.46, blue: 0.56).opacity(0.36),
                    hazeB: Color(red: 0.48, green: 0.60, blue: 0.70).opacity(0.24),
                    ink: ink, muted: muted,
                    accent: Color(red: 0.68, green: 0.78, blue: 0.86),
                    panel: panel
                )
            }
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.90, green: 0.93, blue: 0.96),
                mid: Color(red: 0.74, green: 0.80, blue: 0.86),
                bottom: Color(red: 0.56, green: 0.64, blue: 0.74),
                hazeA: Color(red: 0.36, green: 0.48, blue: 0.58).opacity(0.32),
                hazeB: Color(red: 0.62, green: 0.72, blue: 0.82).opacity(0.36),
                ink: ink, muted: muted,
                accent: Color(red: 0.18, green: 0.26, blue: 0.34),
                panel: panel
            )
        }
    }

    // MARK: Bloom Copper (female)

    private static func bloomCopper(band: WeeklyTrackBand, dark: Bool) -> WeeklyGoalAtmosphere {
        let ink = dark ? ScalePaletteUniverse.ivory : ScalePaletteUniverse.deepInk
        let muted = dark ? ScalePaletteUniverse.ivoryMuted : ScalePaletteUniverse.deepMuted
        let panel = dark ? Color.white.opacity(0.06) : Color.clear
        let voidT = ScalePaletteUniverse.bloomVoidTop
        let voidM = ScalePaletteUniverse.bloomVoidMid
        let voidB = ScalePaletteUniverse.bloomVoidBottom

        switch band {
        case .onTrack:
            if dark {
                return WeeklyGoalAtmosphere(
                    top: voidT, mid: voidM, bottom: voidB,
                    // Warm sage + rose copper — on-track still reads “alive green,” base stays rose void.
                    hazeA: Color(red: 0.42, green: 0.68, blue: 0.48).opacity(0.40),
                    hazeB: Color(red: 0.86, green: 0.52, blue: 0.48).opacity(0.30),
                    ink: ink, muted: muted,
                    accent: Color(red: 0.72, green: 0.90, blue: 0.68),
                    panel: panel
                )
            }
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.99, green: 0.93, blue: 0.94),
                mid: Color(red: 0.94, green: 0.78, blue: 0.80),
                bottom: Color(red: 0.88, green: 0.60, blue: 0.66),
                hazeA: Color(red: 0.46, green: 0.72, blue: 0.52).opacity(0.36),
                hazeB: Color(red: 0.92, green: 0.62, blue: 0.50).opacity(0.38),
                ink: ink, muted: muted,
                accent: Color(red: 0.28, green: 0.44, blue: 0.30),
                panel: panel
            )
        case .ahead, .crushed:
            if dark {
                return WeeklyGoalAtmosphere(
                    top: voidT, mid: voidM, bottom: voidB,
                    hazeA: Color(red: 0.88, green: 0.72, blue: 0.28).opacity(0.40),
                    hazeB: Color(red: 0.94, green: 0.82, blue: 0.42).opacity(0.26),
                    ink: ink, muted: muted,
                    accent: Color(red: 0.96, green: 0.86, blue: 0.48),
                    panel: panel
                )
            }
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.99, green: 0.95, blue: 0.86),
                mid: Color(red: 0.96, green: 0.84, blue: 0.52),
                bottom: Color(red: 0.90, green: 0.68, blue: 0.36),
                hazeA: Color(red: 0.90, green: 0.70, blue: 0.28).opacity(0.38),
                hazeB: Color(red: 0.96, green: 0.82, blue: 0.48).opacity(0.36),
                ink: ink, muted: muted,
                accent: Color(red: 0.48, green: 0.34, blue: 0.08),
                panel: panel
            )
        case .atRisk:
            if dark {
                return WeeklyGoalAtmosphere(
                    top: voidT, mid: voidM, bottom: voidB,
                    hazeA: Color(red: 0.90, green: 0.32, blue: 0.40).opacity(0.42),
                    hazeB: Color(red: 0.94, green: 0.48, blue: 0.42).opacity(0.28),
                    ink: ink, muted: muted,
                    accent: Color(red: 0.98, green: 0.62, blue: 0.58),
                    panel: panel
                )
            }
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.99, green: 0.90, blue: 0.90),
                mid: Color(red: 0.94, green: 0.66, blue: 0.66),
                bottom: Color(red: 0.86, green: 0.44, blue: 0.48),
                hazeA: Color(red: 0.86, green: 0.30, blue: 0.38).opacity(0.34),
                hazeB: Color(red: 0.94, green: 0.58, blue: 0.54).opacity(0.38),
                ink: ink, muted: muted,
                accent: Color(red: 0.54, green: 0.14, blue: 0.20),
                panel: panel
            )
        case .unknown:
            if dark {
                return WeeklyGoalAtmosphere(
                    top: voidT, mid: voidM, bottom: voidB,
                    hazeA: Color(red: 0.56, green: 0.40, blue: 0.46).opacity(0.36),
                    hazeB: Color(red: 0.72, green: 0.56, blue: 0.50).opacity(0.24),
                    ink: ink, muted: muted,
                    accent: Color(red: 0.86, green: 0.74, blue: 0.70),
                    panel: panel
                )
            }
            return WeeklyGoalAtmosphere(
                top: Color(red: 0.97, green: 0.93, blue: 0.94),
                mid: Color(red: 0.88, green: 0.80, blue: 0.82),
                bottom: Color(red: 0.74, green: 0.64, blue: 0.68),
                hazeA: Color(red: 0.62, green: 0.48, blue: 0.52).opacity(0.30),
                hazeB: Color(red: 0.82, green: 0.70, blue: 0.66).opacity(0.36),
                ink: ink, muted: muted,
                accent: Color(red: 0.32, green: 0.22, blue: 0.26),
                panel: panel
            )
        }
    }
}
