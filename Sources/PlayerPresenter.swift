import SwiftUI

/// 7.4.1 — a lejátszó egyetlen, stabil házigazdája.
///
/// A hibát az okozta, hogy a `PlayerScreen` a shell belsejéből kapott
/// `fullScreenCover`-t, a shell viszont fordításnál (álló ↔ fekvő) kicserélődik
/// (`NativeRoot` ↔ `CortexWidePhoneShell`). A bemutató konténer ilyenkor megtartotta
/// a korábbi irány méretét: fekvőből állóba fordítva az egész lejátszó egy 852 pt
/// széles vászonra rendeződött, a 393 pt-os képernyőn ezért lógott ki a fejléc, a
/// csúszka és a jobb oldali gomb (
/// a felhasználó két képernyőképe).
///
/// A megoldás: a lejátszót a gyökér (`CortexRoot5`) mutatja be, ami nem cserélődik
/// el forgatáskor, így a konténer mindig a valódi képernyőméretet követi. Minden
/// hívó ide adja át az útvonalat.
@MainActor
final class PlayerPresenter: ObservableObject {
    static let shared = PlayerPresenter()
    @Published var route: PlaybackRoute?

    private init() {}

    /// Egy epizód megnyitása — a gyökér mutatja be (7.6).
    func open(_ route: PlaybackRoute) {
        self.route = route
    }

    func close() {
        route = nil
    }
}

extension View {
    /// A képernyő saját `@State` útvonalát átadja a gyökér-lejátszónak.
    ///
    /// A hívó oldal továbbra is ugyanúgy állítja be a `route`-ot, csak nem maga
    /// mutatja be: így a lejátszó konténere nem kerül a forgatáskor cserélődő
    /// shell alá. A helyi érték azonnal nullázódik, hogy ne maradjon dupla
    /// bemutatás.
    func handOffPlayerRoute(_ route: Binding<PlaybackRoute?>) -> some View {
        onChange(of: route.wrappedValue?.id) { _, _ in
            guard let value = route.wrappedValue else { return }
            route.wrappedValue = nil
            PlayerPresenter.shared.open(value)
        }
    }
}
