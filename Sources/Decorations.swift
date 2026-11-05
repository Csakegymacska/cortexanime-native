import SwiftUI

// MARK: - 6.8: avatar decorations, rebuilt
//
// The old set was a list of ids whose artwork came from an external CDN. That had three
// consequences the app actually showed: the images often did not load, nothing moved except a
// thin ring, and the picker's cells swallowed every drag gesture, so the grid could not be
// scrolled. This file replaces the whole thing with art drawn by SwiftUI itself:
//
//  · every decoration is a combination of rings, auras, glyph particles and light rays,
//  · the motion comes from a TimelineView clock, so it animates everywhere (and stops
//    when Reduce Motion or the Motion switch is on),
//  · nothing is downloaded — the same decoration looks identical offline.
//
// Ids of the old catalogue still resolve: an unknown `frame_*` picks the nearest ring, an
// unknown `glow_*` picks the nearest aura, so a saved profile never goes blank.

enum DecorationCategory: String, CaseIterable, Identifiable {
    case frame, aura, weather, cosmic, arcane, seasonal, treasure
    var id: String { rawValue }
    var title: String {
        switch self {
        case .frame: return "Frames"
        case .aura: return "Auras"
        case .weather: return "Weather"
        case .cosmic: return "Cosmic"
        case .arcane: return "Arcane"
        case .seasonal: return "Seasonal"
        case .treasure: return "Treasure"
        }
    }
    var symbol: String {
        switch self {
        case .frame: return "circle.dashed"
        case .aura: return "sun.max.fill"
        case .weather: return "cloud.snow.fill"
        case .cosmic: return "sparkles"
        case .arcane: return "flame.fill"
        case .seasonal: return "gift.fill"
        case .treasure: return "sparkles.rectangle.stack.fill"
        }
    }
}

enum DecorationSlot: String, CaseIterable, Identifiable {
    case frame, aura
    var id: String { rawValue }
    var title: String { self == .frame ? "Frame" : "Aura" }
    var symbol: String { self == .frame ? "circle.dashed" : "sparkles" }
}

enum DecorationStyle: String, Hashable {
    case ring, doubleRing, ticks, hex, starPoints, neonDash
    case auraGlow, auraRays, auraRibbons
    case orbit, twinkle, rise, fall
    case glyphOrbit
    case plasma, halo, crystal, confetti, waves, bolt
    // 1.0.0 — twelve hand drawn styles, each with its own motion
    case runes, constellation, bloom, clockwork, shards, ribbons
    case pixel, spiral, doubleHalo, crownArc, boltRing, snowRing
}

struct CortexDecoration: Identifiable, Hashable {
    let id: String
    let name: String
    let category: DecorationCategory
    let style: DecorationStyle
    let rarity: Int
    let price: Int
    let colors: [Color]
    var glyph: String? = nil

    var rarityName: String { ["Common", "Rare", "Epic", "Legendary"][min(rarity, 3)] }
    var rarityColor: Color {
        switch rarity {
        case 1: return .cyan
        case 2: return Color.cortexPurple
        case 3: return .yellow
        default: return Color(white: 0.62)
        }
    }
    var isFree: Bool { price <= 0 }
    var primary: Color { colors.first ?? Color.cortexPurple }
    var secondary: Color { colors.count > 1 ? colors[1] : primary }

    /// Every decoration the app knows about.
    static let all: [CortexDecoration] = [
        // ---- Frames (a ring around the avatar) ----
        d("frame_cosmic", "Cosmic Ring", .frame, .ring, 0, 0, [Color.cortexPurple, .cyan]),
        d("frame_royal", "Royal Frame", .frame, .ticks, 2, 300, [.yellow, Color(red: 0.85, green: 0.55, blue: 0.1)]),
        d("frame_ocean", "Ocean Frame", .frame, .doubleRing, 0, 0, [.cyan, Color(red: 0.15, green: 0.45, blue: 0.9)]),
        d("frame_sakura", "Sakura Frame", .frame, .doubleRing, 0, 0, [.pink, Color(red: 1, green: 0.78, blue: 0.86)]),
        d("frame_ember", "Ember Frame", .frame, .ring, 2, 450, [.orange, Color(red: 0.85, green: 0.15, blue: 0.1)]),
        d("frame_aurora", "Aurora Frame", .frame, .ring, 2, 450, [.mint, .cyan]),
        d("frame_galaxy", "Galaxy Frame", .frame, .starPoints, 3, 800, [Color.cortexPurple, .pink]),
        d("frame_legend", "Legendary Frame", .frame, .ticks, 3, 1400, [.yellow, .white]),
        d("frame_neon", "Neon Dash", .frame, .neonDash, 2, 500, [Color(red: 0.2, green: 1, blue: 0.75), .cyan]),
        d("frame_noir", "Noir Frame", .frame, .hex, 0, 0, [Color(white: 0.9), Color(white: 0.55)]),

        // ---- Auras (light around, no hard edge) ----
        d("glow_purple", "Purple Aura", .aura, .auraGlow, 0, 0, [Color.cortexPurple, .pink]),
        d("glow_cyan", "Cyan Aura", .aura, .auraGlow, 0, 0, [.cyan, .blue]),
        d("glow_pink", "Rose Aura", .aura, .auraGlow, 0, 0, [.pink, Color(red: 1, green: 0.55, blue: 0.8)]),
        d("glow_green", "Aurora Aura", .aura, .auraRibbons, 0, 0, [.mint, .teal]),
        d("glow_fire", "Fire Aura", .aura, .rise, 1, 350, [.orange, .yellow], glyph: "flame.fill"),
        d("glow_gold", "Golden Aura", .aura, .auraGlow, 2, 600, [.yellow, Color(red: 1, green: 0.85, blue: 0.4)]),
        d("glow_thunder", "Storm Aura", .aura, .twinkle, 2, 600, [Color(red: 0.7, green: 0.8, blue: 1), .white], glyph: "bolt.fill"),
        d("glow_fireflies", "Fireflies", .aura, .orbit, 3, 900, [Color(red: 0.75, green: 1, blue: 0.5), .yellow]),
        d("glow_divine", "Divine Light", .aura, .auraRays, 3, 1500, [.yellow, .white]),
        d("glow_bubble", "Bubbles", .aura, .rise, 0, 0, [.cyan, Color(white: 1)], glyph: "circle.fill"),

        // ---- Weather ----
        d("snow_silver", "Silver Snow", .weather, .fall, 0, 0, [.white, Color(red: 0.75, green: 0.85, blue: 1)], glyph: "snowflake"),
        d("snow_blue", "Winter Snow", .weather, .fall, 1, 250, [Color(red: 0.6, green: 0.8, blue: 1), .white], glyph: "snowflake"),
        d("petals_sakura", "Sakura Petals", .weather, .fall, 2, 400, [.pink, Color(red: 1, green: 0.85, blue: 0.9)], glyph: "leaf.fill"),
        d("petals_autumn", "Autumn Leaves", .weather, .fall, 1, 300, [.orange, Color(red: 0.7, green: 0.35, blue: 0.1)], glyph: "leaf.fill"),
        d("rain_neon", "Neon Rain", .weather, .fall, 2, 450, [Color(red: 0.2, green: 1, blue: 0.85), .cyan], glyph: "drop.fill"),
        d("storm_dark", "Thunderstorm", .weather, .twinkle, 2, 500, [Color(white: 0.85), Color(red: 0.55, green: 0.65, blue: 1)], glyph: "cloud.bolt.fill"),
        d("sun_rays", "Sunlight", .weather, .auraRays, 2, 550, [.yellow, .orange]),
        d("fog_mist", "Mist", .weather, .auraGlow, 1, 250, [Color(white: 0.75), Color(white: 0.5)]),

        // ---- Cosmic ----
        d("orbit_planet", "Planet Orbit", .cosmic, .orbit, 3, 900, [Color(red: 0.6, green: 0.8, blue: 1), .white], glyph: "circle.fill"),
        d("star_field", "Starfield", .cosmic, .twinkle, 2, 600, [.white, Color(red: 0.8, green: 0.85, blue: 1)], glyph: "star.fill"),
        d("moon_halo", "Moon Halo", .cosmic, .auraGlow, 2, 500, [Color(red: 0.9, green: 0.92, blue: 1), Color(white: 0.6)]),
        d("comet_trail", "Comet", .cosmic, .orbit, 3, 850, [.cyan, Color(white: 1)], glyph: "sparkle"),
        d("eclipse", "Eclipse", .cosmic, .ring, 3, 1000, [Color(red: 1, green: 0.75, blue: 0.3), Color(white: 0.2)]),
        d("constellation", "Constellation", .cosmic, .glyphOrbit, 3, 950, [Color(white: 0.95), Color(red: 0.7, green: 0.8, blue: 1)], glyph: "star"),

        // ---- Arcane ----
        d("runes_orbit", "Rune Circle", .arcane, .glyphOrbit, 3, 1200, [Color.cortexPurple, .pink], glyph: "seal"),
        d("bats_night", "Night Bats", .arcane, .glyphOrbit, 2, 700, [Color(red: 0.75, green: 0.6, blue: 1), Color(white: 0.85)], glyph: "moon.stars.fill"),
        d("pumpkin_glow", "Pumpkin Glow", .arcane, .auraGlow, 2, 650, [.orange, Color(red: 0.8, green: 0.3, blue: 0.05)]),
        d("ghost_wisp", "Ghost Wisp", .arcane, .twinkle, 2, 600, [Color(white: 0.95), Color(red: 0.7, green: 0.85, blue: 1)], glyph: "cloud.fill"),
        d("hearts_valentine", "Hearts", .arcane, .rise, 2, 650, [.pink, Color(red: 1, green: 0.45, blue: 0.6)], glyph: "heart.fill"),
        d("crown_gold", "Crown", .arcane, .auraRays, 3, 1100, [.yellow, Color(red: 1, green: 0.9, blue: 0.5)], glyph: "crown.fill"),
        d("skull_dark", "Skull", .arcane, .ring, 2, 700, [Color(white: 0.85), Color(red: 0.5, green: 0.5, blue: 0.6)], glyph: "skull.fill"),
        d("dice_luck", "Lucky Dice", .arcane, .orbit, 2, 750, [.mint, .yellow], glyph: "dice.fill"),

        // ---- Frames, second wave (7.0) ----
        d("frame_plasma", "Plasma Ring", .frame, .plasma, 3, 1600, [Color(red: 0.35, green: 0.95, blue: 1), Color.cortexPurple]),
        d("frame_halo", "Halo", .frame, .halo, 2, 700, [.yellow, .white]),
        d("frame_crystal", "Crystal Edge", .frame, .crystal, 3, 1300, [Color(red: 0.7, green: 0.9, blue: 1), .white]),
        d("frame_wave", "Wave Frame", .frame, .waves, 0, 0, [.cyan, .blue]),
        d("frame_bolt", "Voltage", .frame, .bolt, 3, 1200, [Color(red: 0.85, green: 0.9, blue: 1), .yellow]),
        d("frame_confetti", "Confetti Edge", .frame, .confetti, 2, 800, [.pink, .yellow]),
        d("frame_jade", "Jade Frame", .frame, .ring, 0, 0, [Color(red: 0.25, green: 0.85, blue: 0.55), Color(red: 0.1, green: 0.5, blue: 0.35)]),
        d("frame_ruby", "Ruby Frame", .frame, .ring, 2, 550, [Color(red: 0.95, green: 0.25, blue: 0.35), Color(red: 0.6, green: 0.05, blue: 0.15)]),
        d("frame_sapphire", "Sapphire Frame", .frame, .doubleRing, 2, 550, [Color(red: 0.25, green: 0.5, blue: 1), .cyan]),
        d("frame_amethyst", "Amethyst Frame", .frame, .doubleRing, 2, 550, [Color.cortexPurple, Color(red: 0.55, green: 0.3, blue: 0.9)]),
        d("frame_rose_gold", "Rose Gold", .frame, .ticks, 2, 600, [Color(red: 1, green: 0.75, blue: 0.7), Color(red: 0.9, green: 0.55, blue: 0.5)]),
        d("frame_obsidian", "Obsidian", .frame, .hex, 3, 1150, [Color(white: 0.35), Color(red: 0.55, green: 0.3, blue: 0.9)]),

        // ---- Auras, second wave ----
        d("glow_plasma", "Plasma Aura", .aura, .plasma, 3, 1500, [Color(red: 0.4, green: 0.95, blue: 1), .pink]),
        d("glow_halo", "Halo Aura", .aura, .halo, 3, 1400, [.yellow, .white]),
        d("glow_crystal", "Crystal Aura", .aura, .crystal, 2, 700, [Color(red: 0.65, green: 0.85, blue: 1), .white]),
        d("glow_ember", "Ember Sparks", .aura, .rise, 2, 600, [.orange, Color(red: 1, green: 0.85, blue: 0.4)], glyph: "flame.fill"),
        d("glow_mint", "Mint Aura", .aura, .auraGlow, 0, 0, [.mint, Color(red: 0.5, green: 1, blue: 0.85)]),
        d("glow_rose", "Rose Aura", .aura, .auraRibbons, 2, 450, [Color(red: 1, green: 0.4, blue: 0.55), .pink]),
        d("glow_lavender", "Lavender Aura", .aura, .auraGlow, 0, 0, [Color(red: 0.75, green: 0.7, blue: 1), .white]),
        d("glow_iridescent", "Iridescent", .aura, .crystal, 3, 1250, [.pink, .cyan]),
        d("glow_holy", "Holy Light", .aura, .auraRays, 3, 1700, [.yellow, Color(red: 1, green: 0.95, blue: 0.8)]),
        d("glow_void", "Void Aura", .aura, .plasma, 3, 1350, [Color(red: 0.4, green: 0.2, blue: 0.7), Color(white: 0.15)]),


        // ---- Free wave (7.1): a full starting kit, so a new account can look good on day one ----
        d("frame_simple", "Simple Ring", .frame, .ring, 0, 0, [Color(white: 0.92), Color(white: 0.62)]),
        d("frame_dashed", "Dashed Ring", .frame, .neonDash, 0, 0, [Color(white: 0.88), Color.cortexPurple]),
        d("frame_soft", "Soft Edge", .frame, .doubleRing, 0, 0, [Color(red: 0.7, green: 0.75, blue: 1), .white]),
        d("frame_starlight", "Starlight", .frame, .starPoints, 0, 0, [.white, .cyan]),
        d("glow_soft", "Soft Glow", .aura, .auraGlow, 0, 0, [Color(red: 1, green: 0.72, blue: 0.6), Color(red: 1, green: 0.9, blue: 0.86)]),
        d("glow_sunrise", "Sunrise", .aura, .auraRays, 0, 0, [.orange, .yellow]),
        d("glow_ocean", "Ocean Mist", .aura, .auraRibbons, 0, 0, [.teal, .cyan]),
        d("glow_candy", "Candy", .aura, .twinkle, 0, 0, [.pink, .mint]),
        d("glow_neon", "Neon Pulse", .aura, .plasma, 0, 0, [Color(red: 0.3, green: 1, blue: 0.7), .cyan]),
        d("glow_frost", "Frost Halo", .aura, .halo, 0, 0, [Color(red: 0.8, green: 0.92, blue: 1), .white]),
        d("glow_peach", "Peach", .aura, .auraGlow, 0, 0, [Color(red: 1, green: 0.6, blue: 0.45), .white]),
        d("glow_lime", "Lime Sparks", .aura, .orbit, 0, 0, [Color(red: 0.6, green: 1, blue: 0.2), .yellow]),
        d("glow_sky", "Sky", .aura, .auraGlow, 0, 0, [Color(red: 0.45, green: 0.8, blue: 1), .white]),
        d("glow_grape", "Grape", .aura, .auraGlow, 0, 0, [Color(red: 0.6, green: 0.35, blue: 1), .pink]),
        d("glow_rosegold", "Rose Gold Aura", .aura, .auraRibbons, 0, 0, [Color(red: 1, green: 0.7, blue: 0.65), Color(red: 0.95, green: 0.6, blue: 0.5)]),
        d("glow_spectrum", "Spectrum", .aura, .crystal, 0, 0, [.cyan, .pink]),
        d("petals_free", "Petal Drift", .weather, .fall, 0, 0, [Color(red: 1, green: 0.8, blue: 0.86), .pink], glyph: "leaf.fill"),
        d("stars_free", "Stardust", .cosmic, .twinkle, 0, 0, [.white, Color(red: 0.85, green: 0.9, blue: 1)], glyph: "star.fill"),

        // ---- Free wave, end ----
        // ---- Weather / effects ----
        d("petals_cherry", "Cherry Blossom", .weather, .fall, 2, 480, [Color(red: 1, green: 0.78, blue: 0.85), .pink], glyph: "leaf.fill"),
        d("snow_gold", "Golden Snow", .weather, .fall, 3, 950, [.yellow, Color(red: 1, green: 0.9, blue: 0.6)], glyph: "snowflake"),
        d("bubbles_blue", "Bubbles", .weather, .rise, 1, 260, [Color(red: 0.6, green: 0.85, blue: 1), .white], glyph: "circle.fill"),
        d("confetti_party", "Confetti", .weather, .confetti, 2, 620, [.pink, .yellow]),
        d("waves_ocean", "Ocean Waves", .weather, .waves, 2, 560, [.cyan, Color(red: 0.1, green: 0.4, blue: 0.7)]),
        d("aurora_borealis", "Aurora Borealis", .weather, .waves, 3, 1100, [.mint, Color(red: 0.4, green: 0.6, blue: 1)]),
        d("leaves_maple", "Maple Leaves", .weather, .fall, 1, 300, [Color(red: 0.8, green: 0.3, blue: 0.1), .orange], glyph: "leaf.fill"),
        d("sparks_weld", "Sparks", .weather, .rise, 2, 520, [.yellow, .orange], glyph: "sparkle"),
        d("fog_night", "Night Fog", .weather, .auraGlow, 2, 480, [Color(red: 0.55, green: 0.6, blue: 0.75), Color(white: 0.3)]),

        // ---- Cosmic, second wave ----
        d("saturn_rings", "Saturn", .cosmic, .halo, 3, 1200, [Color(red: 1, green: 0.85, blue: 0.6), Color(red: 0.8, green: 0.6, blue: 0.3)]),
        d("nebula_veil", "Nebula Veil", .cosmic, .waves, 3, 1180, [Color.cortexPurple, .pink]),
        d("meteor_shower", "Meteor Shower", .cosmic, .fall, 3, 1250, [Color(red: 1, green: 0.9, blue: 0.7), .cyan], glyph: "sparkle"),
        d("black_hole", "Black Hole", .cosmic, .plasma, 3, 1500, [Color(red: 0.3, green: 0.1, blue: 0.5), Color(white: 0.9)]),
        d("solar_flare", "Solar Flare", .cosmic, .auraRays, 3, 1300, [.orange, .yellow]),
        d("stardust", "Stardust", .cosmic, .twinkle, 2, 580, [Color(red: 0.9, green: 0.85, blue: 1), .white], glyph: "sparkle"),
        d("moon_crescent", "Crescent", .cosmic, .halo, 2, 640, [Color(red: 0.85, green: 0.9, blue: 1), Color(white: 0.7)]),
        d("galaxy_spiral", "Galaxy Spiral", .cosmic, .crystal, 3, 1400, [.pink, Color.cortexPurple]),

        // ---- Arcane, second wave ----
        d("pentagram", "Arcane Circle", .arcane, .glyphOrbit, 3, 1300, [Color(red: 1, green: 0.35, blue: 0.45), Color(red: 0.6, green: 0.1, blue: 0.3)], glyph: "seal"),
        d("lightning_magic", "Storm Sigil", .arcane, .bolt, 2, 700, [Color(red: 0.7, green: 0.85, blue: 1), .white]),
        d("crystal_ball", "Crystal Ball", .arcane, .crystal, 3, 1200, [Color(red: 0.7, green: 0.8, blue: 1), .white]),
        d("elixir_potion", "Elixir", .arcane, .rise, 2, 600, [.mint, Color(red: 0.4, green: 0.9, blue: 0.6)], glyph: "drop.fill"),
        d("feather_angel", "Angel Feather", .arcane, .fall, 2, 660, [Color(white: 0.98), Color(red: 0.85, green: 0.85, blue: 0.95)], glyph: "leaf.fill"),
        d("sword_glow", "Blade", .arcane, .bolt, 2, 720, [Color(red: 0.85, green: 0.9, blue: 1)], glyph: "bolt.fill"),
        d("clover_luck", "Four-leaf Clover", .arcane, .twinkle, 1, 320, [Color(red: 0.3, green: 0.85, blue: 0.5), .mint], glyph: "leaf.fill"),
        d("mask_spirit", "Spirit Mask", .arcane, .glyphOrbit, 2, 690, [Color(red: 1, green: 0.6, blue: 0.4), Color(red: 0.8, green: 0.3, blue: 0.2)], glyph: "theatermasks.fill"),

        // ---- Seasonal (7.0) ----
        d("season_winter", "Winter Wreath", .seasonal, .halo, 2, 700, [Color(red: 0.3, green: 0.8, blue: 0.5), Color(red: 0.9, green: 0.2, blue: 0.25)], glyph: "snowflake"),
        d("season_spring", "Spring Bloom", .seasonal, .confetti, 2, 700, [.pink, .mint], glyph: "leaf.fill"),
        d("season_summer", "Summer Sun", .seasonal, .auraRays, 2, 700, [.yellow, .orange]),
        d("season_autumn", "Autumn Harvest", .seasonal, .fall, 2, 700, [.orange, Color(red: 0.6, green: 0.3, blue: 0.1)], glyph: "leaf.fill"),
        d("season_newyear", "New Year", .seasonal, .confetti, 3, 1200, [.yellow, .white], glyph: "sparkles"),
        d("season_valentine", "Valentine", .seasonal, .rise, 2, 680, [Color(red: 1, green: 0.35, blue: 0.5), .pink], glyph: "heart.fill"),
        d("season_halloween", "Halloween", .seasonal, .glyphOrbit, 2, 750, [.orange, Color(red: 0.5, green: 0.2, blue: 0.7)], glyph: "moon.stars.fill"),
        d("season_birthday", "Birthday", .seasonal, .confetti, 2, 650, [.cyan, .pink], glyph: "birthday.cake.fill"),

        // ---- Treasure (rare drops) ----
        d("treasure_coin", "Gold Coin", .treasure, .orbit, 2, 800, [.yellow, Color(red: 0.85, green: 0.6, blue: 0.1)], glyph: "circle.fill"),
        d("treasure_gem", "Gem Shard", .treasure, .crystal, 3, 1350, [.cyan, .pink]),
        d("treasure_crown", "Royal Crown", .treasure, .halo, 3, 1600, [.yellow, .white], glyph: "crown.fill"),
        d("treasure_scroll", "Ancient Scroll", .treasure, .waves, 2, 780, [Color(red: 0.9, green: 0.8, blue: 0.6), Color(red: 0.6, green: 0.45, blue: 0.25)]),
        d("treasure_key", "Golden Key", .treasure, .twinkle, 2, 820, [.yellow, Color(red: 1, green: 0.9, blue: 0.6)], glyph: "key.fill"),
        d("treasure_chest", "Treasure Chest", .treasure, .confetti, 3, 1450, [Color(red: 0.6, green: 0.35, blue: 0.15), .yellow], glyph: "shippingbox.fill"),
        d("treasure_amethyst", "Amethyst Cluster", .treasure, .crystal, 3, 1250, [Color(red: 0.65, green: 0.4, blue: 0.95), .white]),
        d("treasure_star", "Lucky Star", .treasure, .twinkle, 3, 1150, [.yellow, .white], glyph: "star.fill"),

        // ---- 7.3 wave: eleven new pieces, four of them free ----
        d("frame_sunfire", "Sunfire Ring", .frame, .ring, 0, 0, [.orange, .yellow]),
        d("frame_lagoon", "Lagoon Frame", .frame, .waves, 0, 0, [.teal, .cyan]),
        d("glow_lavender_mist", "Lavender Mist", .aura, .auraGlow, 0, 0, [Color(red: 0.72, green: 0.62, blue: 1), .pink]),
        d("glow_ice", "Ice Aura", .aura, .auraGlow, 0, 0, [Color(red: 0.75, green: 0.92, blue: 1), .cyan]),
        d("frame_holo", "Holo Edge", .frame, .neonDash, 2, 900, [Color(red: 0.35, green: 0.95, blue: 1), Color(red: 1, green: 0.35, blue: 0.85)]),
        d("frame_ashen", "Ashen Frame", .frame, .crystal, 2, 750, [Color(white: 0.7), Color(red: 0.55, green: 0.35, blue: 0.25)]),
        d("glow_prism", "Prism Aura", .aura, .auraRibbons, 2, 800, [.cyan, .pink]),
        d("glow_verdant", "Verdant Aura", .aura, .auraRibbons, 1, 480, [Color(red: 0.35, green: 0.9, blue: 0.45), Color(red: 0.1, green: 0.5, blue: 0.3)]),
        d("petals_cherry_fall", "Cherry Fall", .weather, .fall, 1, 380, [Color(red: 1, green: 0.55, blue: 0.7), Color(red: 1, green: 0.85, blue: 0.9)], glyph: "leaf.fill"),
        d("rain_monsoon", "Monsoon", .weather, .fall, 1, 420, [Color(red: 0.5, green: 0.7, blue: 1), .white], glyph: "drop.fill"),
        d("star_shooting", "Shooting Star", .cosmic, .orbit, 3, 1050, [.white, .cyan], glyph: "sparkle"),
        d("nebula_veil_soft", "Nebula Veil Soft", .cosmic, .auraGlow, 2, 720, [Color(red: 0.55, green: 0.3, blue: 0.95), Color(red: 0.2, green: 0.35, blue: 0.9)]),
        d("glyph_kanji", "Ink Seal", .arcane, .glyphOrbit, 3, 1250, [Color(red: 1, green: 0.35, blue: 0.35), .white], glyph: "seal.fill"),
        d("crown_obsidian", "Obsidian Crown", .arcane, .halo, 3, 1500, [Color(white: 0.5), Color(red: 0.6, green: 0.3, blue: 0.95)], glyph: "crown.fill"),

        // ---- 1.0.0 wave: forty six pieces drawn for this release ----
        // Frames
        d("frame_runic", "Runic Ward", .frame, .runes, 3, 1500, [Color(red: 0.55, green: 0.85, blue: 1), Color(red: 0.75, green: 0.55, blue: 1)]),
        d("frame_starchart", "Star Chart", .frame, .constellation, 3, 1450, [Color(white: 0.95), Color(red: 0.6, green: 0.75, blue: 1)]),
        d("frame_clockwork", "Clockwork", .frame, .clockwork, 2, 850, [Color(red: 0.85, green: 0.7, blue: 0.45), Color(red: 0.45, green: 0.3, blue: 0.15)]),
        d("frame_shards", "Crystal Shards", .frame, .shards, 3, 1300, [Color(red: 0.7, green: 0.92, blue: 1), .white]),
        d("frame_ribbon", "Silk Ribbon", .frame, .ribbons, 1, 450, [Color(red: 1, green: 0.62, blue: 0.72), Color(red: 1, green: 0.85, blue: 0.9)]),
        d("frame_pixel", "Pixel Edge", .frame, .pixel, 1, 400, [Color(red: 0.45, green: 1, blue: 0.6), Color(red: 0.2, green: 0.7, blue: 0.45)]),
        d("frame_crown_arc", "Crown Arc", .frame, .crownArc, 3, 1650, [.yellow, Color(red: 1, green: 0.92, blue: 0.55)]),
        d("frame_storm_ring", "Storm Ring", .frame, .boltRing, 2, 900, [Color(red: 0.72, green: 0.82, blue: 1), .white]),
        d("frame_snow_crystal", "Snow Crystal", .frame, .snowRing, 2, 800, [Color(red: 0.82, green: 0.94, blue: 1), .white]),
        d("frame_twin_halo", "Twin Halo", .frame, .doubleHalo, 2, 950, [Color(red: 1, green: 0.88, blue: 0.6), Color(red: 1, green: 0.7, blue: 0.3)]),
        d("frame_bloom", "Petal Frame", .frame, .bloom, 0, 0, [Color(red: 1, green: 0.72, blue: 0.82), Color(red: 0.95, green: 0.5, blue: 0.68)]),
        d("frame_spiral", "Spiral Edge", .frame, .spiral, 0, 0, [Color(red: 0.6, green: 0.9, blue: 1), Color(red: 0.35, green: 0.6, blue: 1)]),

        // Auras
        d("glow_runic", "Ward Aura", .aura, .runes, 2, 700, [Color(red: 0.5, green: 0.85, blue: 1), Color(red: 0.7, green: 0.5, blue: 1)]),
        d("glow_bloom", "Bloom Aura", .aura, .bloom, 2, 750, [Color(red: 1, green: 0.6, blue: 0.75), Color(red: 1, green: 0.85, blue: 0.9)]),
        d("glow_ribbon", "Ribbon Weave", .aura, .ribbons, 2, 700, [Color(red: 1, green: 0.7, blue: 0.55), Color(red: 1, green: 0.9, blue: 0.75)]),
        d("glow_spiral", "Spiral Drift", .aura, .spiral, 3, 1200, [Color(red: 0.55, green: 0.8, blue: 1), Color.cortexPurple]),
        d("glow_snow", "Snow Aura", .aura, .snowRing, 1, 380, [Color(red: 0.85, green: 0.95, blue: 1), .white]),
        d("glow_pixel_dust", "Pixel Dust", .aura, .pixel, 1, 320, [Color(red: 0.5, green: 1, blue: 0.7), .cyan]),
        d("glow_starchart", "Star Chart Aura", .aura, .constellation, 3, 1150, [Color(white: 0.95), Color(red: 0.65, green: 0.8, blue: 1)]),
        d("glow_shard_halo", "Shard Halo", .aura, .shards, 2, 720, [Color(red: 0.75, green: 0.9, blue: 1), Color(red: 0.95, green: 0.8, blue: 1)]),
        d("glow_clock", "Time Aura", .aura, .clockwork, 2, 680, [Color(red: 0.9, green: 0.78, blue: 0.5), Color(red: 0.55, green: 0.4, blue: 0.2)]),
        d("glow_crown_light", "Crown Light", .aura, .crownArc, 3, 1400, [.yellow, .white]),
        d("glow_bolts", "Voltage Aura", .aura, .boltRing, 2, 640, [Color(red: 0.75, green: 0.85, blue: 1), .yellow]),
        d("glow_halo_twin", "Twin Halo Aura", .aura, .doubleHalo, 1, 420, [Color(red: 1, green: 0.85, blue: 0.7), .white]),

        // Weather
        d("weather_bloom", "Petal Bloom", .weather, .bloom, 1, 420, [Color(red: 1, green: 0.7, blue: 0.8), .pink]),
        d("weather_snowcrystal", "Crystal Snow", .weather, .snowRing, 2, 560, [Color(red: 0.85, green: 0.95, blue: 1), .white]),
        d("weather_bolts", "Chain Lightning", .weather, .boltRing, 3, 980, [Color(red: 0.8, green: 0.88, blue: 1), .yellow]),
        d("weather_pixels", "8-bit Rain", .weather, .pixel, 1, 300, [Color(red: 0.45, green: 0.95, blue: 0.75), .cyan]),
        d("weather_ribbons", "Aurora Ribbons", .weather, .ribbons, 3, 1050, [.mint, Color(red: 0.6, green: 0.55, blue: 1)]),
        d("weather_shards", "Ice Shards", .weather, .shards, 2, 620, [Color(red: 0.8, green: 0.95, blue: 1), .cyan]),
        d("weather_spiral", "Wind Spiral", .weather, .spiral, 2, 580, [Color(red: 0.9, green: 0.95, blue: 1), Color(red: 0.6, green: 0.8, blue: 1)]),

        // Cosmic
        d("cosmic_starchart", "Constellation Cage", .cosmic, .constellation, 3, 1250, [Color(white: 0.98), Color(red: 0.6, green: 0.7, blue: 1)]),
        d("cosmic_spiral", "Spiral Galaxy", .cosmic, .spiral, 3, 1350, [Color(red: 1, green: 0.7, blue: 0.9), Color.cortexPurple]),
        d("cosmic_twin_halo", "Binary Halo", .cosmic, .doubleHalo, 2, 800, [Color(red: 0.9, green: 0.85, blue: 1), .cyan]),
        d("cosmic_star_ring", "Star Ring", .cosmic, .constellation, 2, 720, [.white, .cyan]),
        d("cosmic_comet_chain", "Comet Chain", .cosmic, .spiral, 3, 1100, [Color(red: 1, green: 0.92, blue: 0.7), .cyan]),

        // Arcane
        d("arcane_runes", "Rune Ward", .arcane, .runes, 3, 1300, [Color(red: 1, green: 0.45, blue: 0.55), Color(red: 0.7, green: 0.2, blue: 0.5)]),
        d("arcane_crown", "Crown Sigil", .arcane, .crownArc, 3, 1500, [Color(red: 1, green: 0.85, blue: 0.45), Color(red: 0.8, green: 0.4, blue: 0.6)]),
        d("arcane_clock", "Fate Clock", .arcane, .clockwork, 3, 1150, [Color(red: 0.85, green: 0.8, blue: 1), Color(red: 0.45, green: 0.35, blue: 0.7)]),
        d("arcane_shards", "Arcane Shards", .arcane, .shards, 3, 1200, [Color(red: 0.85, green: 0.6, blue: 1), .pink]),
        d("arcane_bloom", "Soul Bloom", .arcane, .bloom, 3, 1250, [Color(red: 0.6, green: 0.95, blue: 0.85), Color(red: 0.4, green: 0.5, blue: 1)]),
        d("arcane_pixel", "Glyph Pixels", .arcane, .pixel, 1, 350, [Color(red: 1, green: 0.55, blue: 0.45), .yellow]),

        // Seasonal
        d("season_bloom_ring", "Spring Bloom Ring", .seasonal, .bloom, 2, 700, [Color(red: 1, green: 0.75, blue: 0.85), .mint]),
        d("season_winter_halo", "Winter Halo", .seasonal, .snowRing, 2, 700, [Color(red: 0.85, green: 0.95, blue: 1), Color(red: 0.55, green: 0.75, blue: 1)]),
        d("season_fireworks", "Fireworks", .seasonal, .spiral, 3, 1200, [Color(red: 1, green: 0.75, blue: 0.3), .pink]),
        d("season_storm", "Summer Storm", .seasonal, .boltRing, 2, 750, [Color(red: 0.75, green: 0.9, blue: 1), .white]),
        d("season_ribbon", "Festival Ribbon", .seasonal, .ribbons, 2, 700, [Color(red: 1, green: 0.55, blue: 0.5), .yellow]),

        // Treasure
        d("treasure_gears", "Golden Gears", .treasure, .clockwork, 3, 1400, [.yellow, Color(red: 0.8, green: 0.6, blue: 0.2)]),
        d("treasure_gem_ring", "Gem Ring", .treasure, .shards, 3, 1300, [Color(red: 0.5, green: 0.95, blue: 0.9), Color(red: 0.9, green: 0.5, blue: 0.95)]),
        d("treasure_pixel_coin", "Pixel Coin", .treasure, .pixel, 2, 600, [.yellow, Color(red: 0.85, green: 0.65, blue: 0.1)]),
        d("treasure_crown_arc", "Golden Crown Arc", .treasure, .crownArc, 3, 1600, [.yellow, .white]),
        d("treasure_spiral", "Golden Spiral", .treasure, .spiral, 3, 1500, [.yellow, Color(red: 1, green: 0.9, blue: 0.6)]),
        d("treasure_constellation", "Treasure Map", .treasure, .constellation, 2, 780, [Color(red: 1, green: 0.9, blue: 0.65), Color(red: 0.7, green: 0.5, blue: 0.2)]),
    ]

    private static func d(_ id: String, _ name: String, _ category: DecorationCategory,
                          _ style: DecorationStyle, _ rarity: Int, _ price: Int,
                          _ colors: [Color], glyph: String? = nil) -> CortexDecoration {
        CortexDecoration(id: id, name: name, category: category, style: style,
                         rarity: rarity, price: price, colors: colors, glyph: glyph)
    }

    /// 7.0: a decoration belongs to one of two layers. Frames sit on the avatar's edge, every
    /// other set floats around it — so a frame and an aura can be worn at the same time.
    var slot: DecorationSlot { category == .frame ? .frame : .aura }

    /// Resolves a stored value that may hold one decoration ("frame_galaxy") or a stack
    /// ("frame_galaxy|glow_fireflies"). Unknown ids are approximated, never dropped.
    static func list(_ raw: String) -> [CortexDecoration] {
        raw.split(separator: "|")
            .compactMap { named(String($0).trimmingCharacters(in: .whitespaces)) }
    }

    /// The value to store for a two-layer combination.
    static func encode(frame: String?, aura: String?) -> String {
        [frame, aura].compactMap { value in
            guard let value, !value.isEmpty, value != "none" else { return nil }
            return value
        }.joined(separator: "|")
    }

    static func matching(_ category: DecorationCategory?) -> [CortexDecoration] {
        guard let category else { return all }
        return all.filter { $0.category == category }
    }

    /// Resolves a stored id — including ids from the old catalogue — to a decoration that can
    /// actually be drawn. Never returns nil for a non-“none” id: an unknown one is approximated,
    /// so an old profile keeps a visible, animated decoration instead of an empty circle.
    static func named(_ id: String) -> CortexDecoration? {
        if id == "none" || id.isEmpty { return nil }
        if let exact = all.first(where: { $0.id == id }) { return exact }
        let lower = id.lowercased()
        let tint: [Color]
        if lower.contains("gold") || lower.contains("royal") || lower.contains("legend") || lower.contains("divine") { tint = [.yellow, .white] }
        else if lower.contains("cyan") || lower.contains("ocean") || lower.contains("ice") { tint = [.cyan, .blue] }
        else if lower.contains("pink") || lower.contains("sakura") || lower.contains("heart") { tint = [.pink, Color(red: 1, green: 0.8, blue: 0.9)] }
        else if lower.contains("fire") || lower.contains("ember") || lower.contains("flame") { tint = [.orange, .yellow] }
        else if lower.contains("green") || lower.contains("aurora") || lower.contains("mint") { tint = [.mint, .teal] }
        else if lower.contains("halloween") || lower.contains("pumpkin") || lower.contains("spooky") { tint = [.orange, Color(red: 0.8, green: 0.3, blue: 0.05)] }
        else { tint = [Color.cortexPurple, .pink] }
        let isFrame = lower.hasPrefix("frame") || lower.contains("ring") || lower.contains("border")
        return CortexDecoration(id: id, name: id.replacingOccurrences(of: "_", with: " ").capitalized,
                                category: isFrame ? .frame : .aura,
                                style: isFrame ? .ring : .auraGlow,
                                rarity: 1, price: 0, colors: tint)
    }
}

// MARK: - The drawing

/// Draws one decoration around (and behind) the avatar. `size` is the avatar's side length;
/// the art extends about 25 % beyond it, so the caller should leave room.
struct DecorationArt: View {
    let decoration: CortexDecoration
    let size: CGFloat
    /// Grids of 40 previews run with this off: they show the artwork in a fixed pose instead of
    /// starting forty animation clocks at once.
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motionSettings = MotionSettings.shared

    private var still: Bool { !animated || reduceMotion || !motionSettings.cardTilt }

    var body: some View {
        TimelineView(.animation(minimumInterval: still ? 1 : 1.0 / 24.0, paused: still)) { timeline in
            let t = still ? 12.0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                switch decoration.style {
                case .ring: ring(t, thick: true)
                case .doubleRing: doubleRing(t)
                case .ticks: ticks(t)
                case .hex: hexagon(t)
                case .starPoints: starPoints(t)
                case .neonDash: neonDash(t)
                case .auraGlow: auraGlow(t)
                case .auraRays: auraRays(t)
                case .auraRibbons: auraRibbons(t)
                case .orbit: orbit(t, rising: false)
                case .twinkle: twinkle(t)
                case .rise: orbit(t, rising: true)
                case .fall: fall(t)
                case .glyphOrbit: glyphOrbit(t)
                case .plasma: plasma(t)
                case .halo: halo(t)
                case .crystal: crystal(t)
                case .confetti: confetti(t)
                case .waves: waves(t)
                case .bolt: bolt(t)
                default: MegaDecorationArt(decoration: decoration, size: size, t: t)
                }
            }
            .frame(width: size, height: size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // ---- helpers ----

    private func random(_ i: Int, _ salt: Int) -> Double {
        let v = sin(Double(i) * 127.1 + Double(salt) * 311.7) * 43758.5453
        return v - floor(v)
    }

    private var radius: CGFloat { size * 0.5 }

    private func angular(_ colors: [Color]) -> AngularGradient {
        AngularGradient(colors: colors + [colors[0]], center: .center)
    }

    // ---- frames ----

    private func ring(_ t: Double, thick: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(angular([decoration.primary, decoration.secondary, decoration.primary]),
                              lineWidth: max(5, size * 0.075))
                .rotationEffect(.degrees(t * 14))
            Circle()
                .stroke(decoration.secondary.opacity(0.25), lineWidth: 1)
                .padding(size * 0.045)
            Circle()
                .stroke(decoration.primary.opacity(0.35), lineWidth: 1)
                .padding(-size * 0.035)
                .scaleEffect(1 + CGFloat(sin(t / 2.2)) * 0.02)
                .blur(radius: 2)
        }
        .shadow(color: decoration.primary.opacity(0.55), radius: size * 0.09)
    }

    private func doubleRing(_ t: Double) -> some View {
        ZStack {
            Circle().strokeBorder(angular([decoration.primary, decoration.secondary, decoration.primary]), lineWidth: max(4, size * 0.055))
                .rotationEffect(.degrees(t * 12))
            Circle().stroke(decoration.secondary.opacity(0.8), lineWidth: max(1.5, size * 0.014))
                .padding(-size * 0.06)
                .rotationEffect(.degrees(-t * 22))
            ForEach(0..<16, id: \.self) { i in
                Capsule().fill(decoration.primary.opacity(0.7))
                    .frame(width: max(1, size * 0.012), height: size * 0.05)
                    .offset(y: -radius - size * 0.06)
                    .rotationEffect(.degrees(Double(i) / 16 * 360 + t * 22))
            }
        }
        .shadow(color: decoration.primary.opacity(0.5), radius: size * 0.08)
    }

    private func ticks(_ t: Double) -> some View {
        ZStack {
            Circle().strokeBorder(angular([decoration.primary, decoration.secondary, decoration.primary]), lineWidth: max(4, size * 0.05))
            ForEach(0..<24, id: \.self) { i in
                let big = i % 6 == 0
                Capsule()
                    .fill(big ? decoration.secondary : decoration.primary.opacity(0.75))
                    .frame(width: max(1, size * (big ? 0.02 : 0.012)), height: size * (big ? 0.09 : 0.05))
                    .offset(y: -radius - size * 0.02)
                    .rotationEffect(.degrees(Double(i) / 24 * 360 + t * 8))
            }
        }
        .shadow(color: decoration.primary.opacity(0.6), radius: size * 0.08)
    }

    private func hexagon(_ t: Double) -> some View {
        ZStack {
            PolygonShape(sides: 6)
                .stroke(angular([decoration.primary, decoration.secondary, decoration.primary]), lineWidth: max(3, size * 0.045))
                .frame(width: size * 1.02, height: size * 1.02)
                .rotationEffect(.degrees(t * 10))
            PolygonShape(sides: 6)
                .stroke(decoration.secondary.opacity(0.45), lineWidth: 1)
                .frame(width: size * 1.18, height: size * 1.18)
                .rotationEffect(.degrees(-t * 14))
        }
        .shadow(color: decoration.primary.opacity(0.5), radius: size * 0.08)
    }

    private func starPoints(_ t: Double) -> some View {
        ZStack {
            Circle().stroke(decoration.primary.opacity(0.5), lineWidth: max(2, size * 0.02))
            StarShape(points: 8).stroke(angular([decoration.primary, decoration.secondary]), lineWidth: max(2.5, size * 0.03))
                .frame(width: size * 1.16, height: size * 1.16)
                .rotationEffect(.degrees(t * 6))
                .shadow(color: decoration.primary.opacity(0.7), radius: size * 0.06)
        }
    }

    private func neonDash(_ t: Double) -> some View {
        ZStack {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: max(4, size * 0.05), dash: [size * 0.12, size * 0.06]))
                .foregroundStyle(decoration.primary)
                .rotationEffect(.degrees(t * 26))
                .shadow(color: decoration.primary.opacity(0.9), radius: size * 0.07)
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: max(2, size * 0.02), dash: [size * 0.04, size * 0.05]))
                .foregroundStyle(decoration.secondary.opacity(0.8))
                .padding(-size * 0.05)
                .rotationEffect(.degrees(-t * 18))
        }
    }

    // ---- auras ----

    private func auraGlow(_ t: Double) -> some View {
        let pulse = 1 + CGFloat(sin(t / 1.9)) * 0.06
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [decoration.primary.opacity(0.55), decoration.secondary.opacity(0.18), .clear],
                                     center: .center, startRadius: size * 0.28, endRadius: size * 0.72))
                .scaleEffect(pulse)
            Circle().stroke(decoration.primary.opacity(0.7), lineWidth: max(2, size * 0.02))
                .blur(radius: size * 0.02)
                .scaleEffect(pulse)
        }
    }

    private func auraRays(_ t: Double) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [decoration.primary.opacity(0.35), .clear], center: .center,
                                     startRadius: size * 0.3, endRadius: size * 0.7))
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [decoration.primary.opacity(0.85), .clear], startPoint: .bottom, endPoint: .top))
                    .frame(width: max(1.5, size * 0.02), height: size * (0.22 + 0.08 * CGFloat(random(i, 3))))
                    .offset(y: -radius - size * 0.16)
                    .rotationEffect(.degrees(Double(i) / 12 * 360 + t * 12))
            }
        }
    }

    private func auraRibbons(_ t: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .trim(from: CGFloat(random(i, 1) * 0.4), to: CGFloat(random(i, 1) * 0.4 + 0.45))
                    .stroke(LinearGradient(colors: [decoration.primary.opacity(0.85), decoration.secondary.opacity(0.35)],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: max(2, size * 0.035), lineCap: .round))
                    .padding(-size * CGFloat(0.02 + Double(i) * 0.045))
                    .rotationEffect(.degrees(t * (10 + Double(i) * 7)))
                    .blur(radius: i == 2 ? size * 0.02 : 0)
            }
        }
    }

    // ---- particles ----

    private func orbit(_ t: Double, rising: Bool) -> some View {
        ZStack {
            if rising {
                Circle().fill(RadialGradient(colors: [decoration.primary.opacity(0.3), .clear], center: .center,
                                             startRadius: size * 0.25, endRadius: size * 0.7))
            }
            ForEach(0..<12, id: \.self) { i in
                let base = random(i, 1) * 2 * Double.pi
                let speed = 0.30 + random(i, 2) * 0.55
                let bob = sin(t * 0.8 + Double(i)) * 0.05
                let r = size * (0.50 + CGFloat(random(i, 4)) * 0.14 + CGFloat(bob))
                let angle = base + t * speed
                let dot = max(3, size * CGFloat(0.035 + random(i, 5) * 0.05))
                let fade = rising ? (0.35 + 0.65 * abs(sin(t * 0.6 + Double(i)))) : 1.0
                Group {
                    if let glyph = decoration.glyph {
                        Image(systemName: glyph)
                            .font(.system(size: dot * 1.3, weight: .bold))
                            .foregroundStyle(decoration.primary.opacity(fade))
                    } else {
                        Circle().fill(decoration.primary.opacity(fade))
                            .frame(width: dot, height: dot)
                            .shadow(color: decoration.primary.opacity(0.9), radius: dot * 0.8)
                    }
                }
                .offset(x: CGFloat(cos(angle)) * r, y: CGFloat(sin(angle)) * r)
            }
        }
    }

    private func twinkle(_ t: Double) -> some View {
        ZStack {
            Circle().stroke(decoration.primary.opacity(0.35), lineWidth: max(1.5, size * 0.015))
            ForEach(0..<10, id: \.self) { i in
                let angle = random(i, 1) * 2 * Double.pi
                let r = size * (0.52 + CGFloat(random(i, 2)) * 0.16)
                let tw = 0.25 + 0.75 * pow(abs(sin(t * (0.7 + random(i, 3)) + Double(i))), 2)
                let dot = max(2, size * CGFloat(0.02 + random(i, 4) * 0.03))
                Group {
                    if let glyph = decoration.glyph {
                        Image(systemName: glyph)
                            .font(.system(size: dot * 1.5, weight: .bold))
                            .foregroundStyle(decoration.primary.opacity(tw))
                    } else {
                        Circle().fill(decoration.secondary.opacity(tw))
                            .frame(width: dot, height: dot)
                    }
                }
                .offset(x: CGFloat(cos(angle)) * r, y: CGFloat(sin(angle)) * r)
                .shadow(color: decoration.primary.opacity(tw * 0.9), radius: dot)
            }
        }
    }

    private func fall(_ t: Double) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [decoration.primary.opacity(0.16), .clear], center: .center,
                                     startRadius: size * 0.3, endRadius: size * 0.68))
            ForEach(0..<10, id: \.self) { i in
                let speed = 0.18 + random(i, 1) * 0.22
                let x = (random(i, 2) - 0.5) * Double(size) * 1.5
                let startY = random(i, 3) * Double(size)
                let span = Double(size) * 1.3
                let y = ((startY + t * speed * 60).truncatingRemainder(dividingBy: span)) - Double(size) * 0.65
                let drift = sin(t * 0.9 + Double(i)) * Double(size) * 0.05
                let dot = max(3, size * CGFloat(0.03 + random(i, 4) * 0.04))
                Group {
                    if let glyph = decoration.glyph {
                        Image(systemName: glyph)
                            .font(.system(size: dot * 1.25, weight: .semibold))
                            .foregroundStyle(decoration.primary.opacity(0.9))
                            .rotationEffect(.degrees(sin(t + Double(i)) * 25))
                    } else {
                        Circle().fill(decoration.primary.opacity(0.9)).frame(width: dot, height: dot)
                    }
                }
                .offset(x: CGFloat(x + drift), y: CGFloat(y))
            }
        }
    }

    // ---- 7.0 styles ----

    /// A liquid, uneven ring: many short arcs at slightly different radii, so the edge reads
    /// as plasma instead of a stroke.
    private func plasma(_ t: Double) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.clear, decoration.primary.opacity(0.28), .clear],
                                     center: .center, startRadius: size * 0.30, endRadius: size * 0.55))
            ForEach(0..<36, id: \.self) { i in
                let wobble = 0.5 + 0.5 * sin(t * 1.6 + Double(i) * 0.55)
                Capsule()
                    .fill(i % 3 == 0 ? decoration.secondary : decoration.primary)
                    .frame(width: max(1.5, size * 0.018), height: size * (0.03 + 0.05 * CGFloat(wobble)))
                    .offset(y: -radius - size * CGFloat(0.005 + 0.02 * wobble))
                    .rotationEffect(.degrees(Double(i) / 36 * 360 + t * 20))
                    .opacity(0.5 + 0.5 * wobble)
            }
            Circle()
                .strokeBorder(angular([decoration.primary.opacity(0.9), .clear, decoration.secondary.opacity(0.8), .clear]),
                              lineWidth: max(3, size * 0.04))
                .rotationEffect(.degrees(t * 32))
                .blur(radius: size * 0.01)
        }
        .shadow(color: decoration.primary.opacity(0.7), radius: size * 0.10)
    }

    /// A thin, bright disc floating above the avatar, with a soft light cone under it.
    private func halo(_ t: Double) -> some View {
        let tilt = 18.0 + sin(t / 3.0) * 3.0
        return ZStack {
            Capsule()
                .fill(LinearGradient(colors: [.clear, decoration.primary.opacity(0.35), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.55, height: size * 0.5)
                .offset(y: -size * 0.28)
                .blur(radius: size * 0.06)
            Ellipse()
                .strokeBorder(decoration.primary, lineWidth: max(3, size * 0.035))
                .frame(width: size * 0.56, height: size * 0.16)
                .offset(y: -size * 0.40)
                .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0))
                .shadow(color: decoration.primary.opacity(0.9), radius: size * 0.05)
            Ellipse()
                .strokeBorder(decoration.secondary.opacity(0.55), lineWidth: 1)
                .frame(width: size * 0.70, height: size * 0.20)
                .offset(y: -size * 0.40)
                .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0))
        }
    }

    /// Sixteen hard facets, each a triangle from the centre to the rim, with a bright outline.
    private func crystal(_ t: Double) -> some View {
        ZStack {
            ForEach(0..<16, id: \.self) { i in
                TriangleFacet()
                    .fill(LinearGradient(colors: [decoration.primary.opacity(i % 2 == 0 ? 0.55 : 0.22),
                                                  decoration.secondary.opacity(0.10)],
                                         startPoint: .top, endPoint: .bottom))
                    .rotationEffect(.degrees(Double(i) / 16 * 360 + t * 6))
                    .frame(width: size * 1.02, height: size * 1.02)
            }
            Circle()
                .strokeBorder(angular([decoration.primary, .white.opacity(0.9), decoration.secondary, decoration.primary]),
                              lineWidth: max(2.5, size * 0.028))
                .rotationEffect(.degrees(-t * 12))
        }
        .shadow(color: decoration.primary.opacity(0.55), radius: size * 0.08)
    }

    /// Coloured paper pieces spinning outward from the rim.
    private func confetti(_ t: Double) -> some View {
        ZStack {
            ForEach(0..<22, id: \.self) { i in
                let angle = random(i, 1) * 2 * Double.pi
                let outward = (t * (0.12 + random(i, 2) * 0.10) + random(i, 3)).truncatingRemainder(dividingBy: 1)
                let r = size * (0.40 + CGFloat(outward) * 0.30)
                let colors = [decoration.primary, decoration.secondary, decoration.primary.opacity(0.65)]
                RoundedRectangle(cornerRadius: 1.2)
                    .fill(colors[i % colors.count])
                    .frame(width: size * CGFloat(0.020 + random(i, 4) * 0.02),
                           height: size * CGFloat(0.012 + random(i, 5) * 0.018))
                    .rotationEffect(.degrees(t * 120 + Double(i) * 37))
                    .offset(x: CGFloat(cos(angle)) * r, y: CGFloat(sin(angle)) * r)
                    .opacity(1 - outward * 0.85)
            }
        }
    }

    /// Two ribbons of light sliding around the rim, out of phase.
    private func waves(_ t: Double) -> some View {
        ZStack {
            ForEach(0..<2, id: \.self) { layer in
                Circle()
                    .trim(from: CGFloat((t * 0.10 + Double(layer) * 0.5).truncatingRemainder(dividingBy: 1)),
                          to: CGFloat((t * 0.10 + Double(layer) * 0.5).truncatingRemainder(dividingBy: 1)) + 0.55)
                    .stroke(LinearGradient(colors: [decoration.primary, decoration.secondary.opacity(0.2)],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: max(3, size * (0.05 - CGFloat(layer) * 0.015)), lineCap: .round))
                    .padding(-size * CGFloat(0.01 + Double(layer) * 0.04))
                    .rotationEffect(.degrees(t * 8 * (layer == 0 ? 1 : -0.7)))
                    .blur(radius: layer == 0 ? 0 : size * 0.02)
            }
            Circle()
                .stroke(decoration.primary.opacity(0.20), lineWidth: max(1, size * 0.012))
                .padding(-size * 0.075)
                .scaleEffect(1 + CGFloat(sin(t * 1.4)) * 0.015)
        }
        .shadow(color: decoration.primary.opacity(0.5), radius: size * 0.06)
    }

    /// Four short electric arcs that jump around the rim at irregular intervals.
    private func bolt(_ t: Double) -> some View {
        ZStack {
            Circle().stroke(decoration.secondary.opacity(0.30), lineWidth: max(1.5, size * 0.015))
            ForEach(0..<4, id: \.self) { i in
                let step = floor(t * 1.4 + Double(i) * 0.7)
                let jitter = random(i, Int(step)) * 40 - 20
                let start = Double(i) * 90 + jitter + t * 12
                Image(systemName: "bolt.fill")
                    .font(.system(size: max(8, size * 0.11), weight: .black))
                    .foregroundStyle(decoration.primary)
                    .shadow(color: decoration.secondary.opacity(0.9), radius: size * 0.03)
                    .rotationEffect(.degrees(90))
                    .offset(y: -radius - size * 0.02)
                    .rotationEffect(.degrees(start))
                    .opacity(0.55 + 0.45 * (0.5 + 0.5 * sin(t * 9 + Double(i))))
            }
        }
    }

    private func glyphOrbit(_ t: Double) -> some View {
        ZStack {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: max(1.5, size * 0.012), dash: [2, size * 0.05]))
                .foregroundStyle(decoration.primary.opacity(0.55))
                .padding(-size * 0.02)
                .rotationEffect(.degrees(t * 8))
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 2 * Double.pi + t * 0.35
                let r = size * (0.56 + CGFloat(sin(t * 0.7 + Double(i)) * 0.03))
                Image(systemName: decoration.glyph ?? "sparkle")
                    .font(.system(size: max(6, size * 0.075), weight: .bold))
                    .foregroundStyle(decoration.primary.opacity(0.95))
                    .rotationEffect(.degrees(t * 30 + Double(i) * 45))
                    .shadow(color: decoration.secondary.opacity(0.8), radius: size * 0.02)
                    .offset(x: CGFloat(cos(angle)) * r, y: CGFloat(sin(angle)) * r)
            }
        }
    }
}

/// A regular polygon, used by the hex frame.
struct PolygonShape: Shape {
    let sides: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<sides {
            let angle = -Double.pi / 2 + Double(i) / Double(sides) * 2 * Double.pi
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// A star outline with pointed rays, used by the galaxy frame.
struct StarShape: Shape {
    let points: Int
    var innerRatio: CGFloat = 0.72
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        for i in 0..<(points * 2) {
            let ratio = i % 2 == 0 ? outer : outer * innerRatio
            let angle = -Double.pi / 2 + Double(i) / Double(points * 2) * 2 * Double.pi
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * ratio, y: center.y + CGFloat(sin(angle)) * ratio)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - The avatar itself

/// The avatar plus its decoration. Same API as before, so every call site keeps working.
struct NativeAvatar: View {
    let raw: String?
    var decoration = "none"
    var animated = true

    private var image: UIImage? {
        guard let raw, raw.hasPrefix("data:image/"), let comma = raw.firstIndex(of: ","),
              let data = Data(base64Encoded: String(raw[raw.index(after: comma)...])), data.count <= 600_000 else { return nil }
        return UIImage(data: data)
    }

    @ViewBuilder private var avatarImage: some View {
        if let image { Image(uiImage: image).resizable().scaledToFill() }
        else if let url = Anime.imageURL(raw) { AnimeArtwork(url: url) }
        else {
            Color.cortexPanel.overlay {
                Image(systemName: "person.fill").font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.cortexPurple.opacity(0.85))
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let layers = CortexDecoration.list(decoration)
                .sorted { ($0.slot == .frame ? 1 : 0) < ($1.slot == .frame ? 1 : 0) }
            ZStack {
                ForEach(layers) { layer in
                    DecorationArt(decoration: layer,
                                  size: side * (layer.slot == .frame ? 0.86 : 0.96),
                                  animated: animated)
                        .frame(width: side, height: side)
                }
                avatarImage
                    .frame(width: side * 0.80, height: side * 0.80)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// One facet of the crystal decoration: a thin wedge from the centre to the rim.
struct TriangleFacet: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let a1 = -Double.pi / 2 - 0.10
        let a2 = -Double.pi / 2 + 0.10
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + CGFloat(cos(a1)) * r, y: center.y + CGFloat(sin(a1)) * r))
        path.addLine(to: CGPoint(x: center.x + CGFloat(cos(a2)) * r, y: center.y + CGFloat(sin(a2)) * r))
        path.closeSubpath()
        return path
    }
}
