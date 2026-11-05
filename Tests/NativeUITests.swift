import XCTest
import CoreGraphics

final class NativeUITests: XCTestCase {
    @MainActor private func launch(player: Bool = false) -> XCUIApplication {
        let app = XCUIApplication();app.launchArguments = ["--ui-fixture"]+(player ? ["--player-fixture"] : []);app.launch();return app
    }
    override func tearDown() async throws {
        await MainActor.run { XCUIApplication().terminate() }
        try await super.tearDown()
    }
    @MainActor private func revealControls(_ app: XCUIApplication) {
        let video = app.descendants(matching:.any).matching(identifier:"player.video").firstMatch.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        // Re-arm the real timer rather than acting on an almost-expired snapshot.
        if app.buttons["player.options"].isHittable { video.tap() }
        video.tap()
    }
    @MainActor private func openSubtitleSize(_ app: XCUIApplication) {
        revealControls(app)
        app.buttons["player.options"].tap()
        let slider = app.sliders["player.subtitleSize"]
        for _ in 0..<5 { if slider.isHittable { break };app.swipeUp() }
        XCTAssertTrue(slider.isHittable)
    }
    @MainActor func testBetaPurchaseIsLocalNoChargeAndCanBeCanceled() {
        let app = XCUIApplication();app.launchArguments = ["--plus-beta-qa","--beta-reset"];app.launch()
        XCTAssertTrue(app.buttons["beta.open"].waitForExistence(timeout:12));app.buttons["beta.open"].tap()
        XCTAssertTrue(app.buttons["beta.simulate"].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["beta.disclosure"].exists)
        XCTAssertTrue(app.staticTexts["beta.testCardsOnly"].exists)
        XCTAssertFalse(app.textFields.firstMatch.exists,"Card numbers may only be entered on Stripe, never this native beta screen.")
        capture("beta-summary-no-charge")
        app.buttons["beta.close"].tap()
        XCTAssertTrue(app.staticTexts["beta.lobby.status"].label.contains("inactive"),"Closing checkout must not activate even a demo.")
        app.buttons["beta.open"].tap();app.buttons["beta.simulate"].tap()
        XCTAssertTrue(app.staticTexts["beta.success"].waitForExistence(timeout:5));capture("beta-demo-complete")
        app.buttons["beta.done"].tap();app.terminate()
        app.launchArguments = ["--plus-beta-qa"];app.launch()
        XCTAssertTrue(app.buttons["beta.open"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts["beta.lobby.status"].label,"Demo preview active")
        app.buttons["beta.open"].tap();XCTAssertTrue(app.buttons["beta.cancel"].waitForExistence(timeout:5));app.buttons["beta.cancel"].tap()
        XCTAssertTrue(app.buttons["beta.simulate"].waitForExistence(timeout:5));app.buttons["beta.close"].tap()
        XCTAssertTrue(app.staticTexts["beta.lobby.status"].label.contains("inactive"))
    }
    @MainActor func testDownloadOptionsAreOnAnimeDetailNotInPlayer() {
        let app = launch()
        let watch = app.buttons["home.watch"];XCTAssertTrue(watch.waitForExistence(timeout:12));watch.tap()
        let download = app.buttons["detail.download"]
        XCTAssertTrue(download.waitForExistence(timeout:12));download.tap()
        XCTAssertTrue(app.buttons["download.episode"].waitForExistence(timeout:8))
        XCTAssertTrue(app.buttons["download.season"].exists)
        capture("Anime detail Download sheet with episode, full season and subtitle language")
        app.buttons["download.done"].tap();app.terminate()
        let player = launch(player:true);XCTAssertTrue(player.buttons["player.options"].waitForExistence(timeout:15));revealControls(player);player.buttons["player.options"].tap()
        XCTAssertFalse(player.buttons["Save episode offline"].exists)
    }
    @MainActor func testControlsAutoHideTapRevealAndPauseKeepsVisible() {
        let app = launch(player:true),toggle = app.buttons["player.togglePlayback"]
        XCTAssertTrue(toggle.waitForExistence(timeout:15))
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:toggle);waitForExpectations(timeout:15)
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:toggle);waitForExpectations(timeout:9)
        XCTAssertFalse(app.buttons["player.options"].exists)
        XCTAssertTrue(app.staticTexts["player.caption"].waitForExistence(timeout:4),"Auto-hide must not remove captions.")
        capture("Playing with chrome hidden and authored captions retained")
        revealControls(app);XCTAssertTrue(toggle.isHittable);toggle.tap()
        XCTAssertEqual(toggle.label,"Resume playback")
        Thread.sleep(forTimeInterval:4)
        XCTAssertTrue(toggle.isHittable,"Paused playback must keep controls visible.")
        capture("Controls restored by tap and retained while paused")
    }
    @MainActor func testSubtitleSizeChangesActualCaptionAndPersistsAcrossLaunch() {
        var app = launch(player:true)
        let toggle = app.buttons["player.togglePlayback"]
        XCTAssertTrue(toggle.waitForExistence(timeout:15))
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:toggle);waitForExpectations(timeout:15)
        revealControls(app);toggle.tap()
        XCTAssertTrue(app.staticTexts["player.caption"].waitForExistence(timeout:5))
        openSubtitleSize(app)
        app.buttons["player.resetSubtitleSize"].tap()
        app.buttons["player.settingsDone"].tap()
        let caption = app.staticTexts["player.caption"]
        XCTAssertEqual(caption.value as? String,"Subtitle size 20 points")
        let normalHeight = caption.frame.height
        capture("Actual authored caption at 20 points")
        openSubtitleSize(app)
        app.sliders["player.subtitleSize"].adjust(toNormalizedSliderPosition:1)
        XCTAssertEqual(app.staticTexts["player.subtitleSizeValue"].label,"40 pt")
        capture("Subtitle size control and preview at 40 points")
        app.buttons["player.settingsDone"].tap()
        XCTAssertEqual(caption.value as? String,"Subtitle size 40 points")
        XCTAssertGreaterThan(caption.frame.height,normalHeight*1.3,"The rendered caption must grow, not only the stored setting.")
        capture("Actual authored caption enlarged to 40 points")
        app.terminate();app = launch(player:true)
        XCTAssertTrue(app.staticTexts["player.caption"].waitForExistence(timeout:15))
        XCTAssertEqual(app.staticTexts["player.caption"].value as? String,"Subtitle size 40 points")
        openSubtitleSize(app)
        XCTAssertEqual(app.staticTexts["player.subtitleSizeValue"].label,"40 pt")
        app.buttons["player.resetSubtitleSize"].tap()
        XCTAssertEqual(app.staticTexts["player.subtitleSizeValue"].label,"20 pt")
        app.buttons["player.settingsDone"].tap()
    }
    @MainActor private func capture(_ name: String) {
        let image = XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name = name;image.lifetime = .keepAlways;add(image)
    }
    @MainActor private func checkRealDetailCaptions(id: Int,episode: Int,english: Bool) {
        let app = XCUIApplication();app.launchArguments = ["--caption-detail-qa","--qa-anime=\(id)"];app.launch()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"detail.episodeSummary").firstMatch.waitForExistence(timeout:35))
        if english {
            let language = app.segmentedControls.buttons["English"]
            for _ in 0..<6 { if language.isHittable { break };app.swipeUp() }
            guard language.isHittable else { XCTFail("Production subtitle-language picker was not visible.");return };language.tap()
        }
        let episodeButton = app.buttons["episode.\(episode)"]
        for _ in 0..<8 { if episodeButton.isHittable { break };app.swipeUp() }
        guard episodeButton.isHittable else { capture("Production episode navigation failed");XCTFail("Production episode button was unavailable.");return }
        episodeButton.tap()
        let toggle = app.buttons["player.togglePlayback"]
        guard toggle.waitForExistence(timeout:65) else { capture("Production player failed to open");XCTFail("Production Detail-to-player route did not open.");return }
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:toggle);waitForExpectations(timeout:25)
        for _ in 0..<4 { if app.buttons["player.forward"].isHittable { app.buttons["player.forward"].tap() } }
        let caption = app.staticTexts["player.caption"]
        guard caption.waitForExistence(timeout:35) else { capture("Production route caption missing");XCTFail("No caption appeared through the actual detail/episode route.");return }
        XCTAssertGreaterThan(caption.label.trimmingCharacters(in:.whitespacesAndNewlines).count,2)
        capture(english ? "Actual English captions through production episode UI" : "Actual Hungarian captions through production episode UI")
    }
    @MainActor func testProductionHungarianDetailCaptions() { checkRealDetailCaptions(id:185874,episode:9,english:false) }
    @MainActor func testProductionEnglishDetailCaptions() { checkRealDetailCaptions(id:208025,episode:2,english:true) }
    @MainActor func testLiveHungarianSubtitleActuallyAppears() {
        let app = XCUIApplication();app.launchArguments = ["--live-hu-qa"];app.launch()
        let toggle = app.buttons["player.togglePlayback"]
        guard toggle.waitForExistence(timeout:65) else { capture("HU startup failure");XCTFail("Real HU playback did not open. "+(app.staticTexts["qa.error"].exists ? app.staticTexts["qa.error"].label : "No startup diagnostic."));return }
        let enabled = NSPredicate(format:"enabled == true")
        expectation(for:enabled,evaluatedWith:toggle);waitForExpectations(timeout:30)
        for _ in 0..<4 { if app.buttons["player.forward"].isHittable { app.buttons["player.forward"].tap() } }
        let caption = app.staticTexts["player.caption"]
        guard caption.waitForExistence(timeout:35) else { capture("HU caption failure");XCTFail("A real Hungarian caption did not appear after seeking past the opening.");return }
        XCTAssertGreaterThan(caption.label.trimmingCharacters(in:.whitespacesAndNewlines).count,2)
        capture("Actual native Hungarian caption — live BLEACH episode 9")
    }
    @MainActor func testZOfflineLibraryOpensAndPlaysSavedFixture() {
        for launch in 1...2 {
            let app = XCUIApplication();app.launchArguments = ["--offline-qa"];app.launch()
            XCTAssertTrue(app.staticTexts["offline.banner"].waitForExistence(timeout:15))
            let play = app.buttons["download.play.999999.1"]
            XCTAssertTrue(play.waitForExistence(timeout:10),"The actual HTTPS download must survive a cold launch.")
            play.tap()
            XCTAssertTrue(app.staticTexts["player.caption"].waitForExistence(timeout:15))
            let video = app.descendants(matching:.any).matching(identifier:"player.video").firstMatch
            XCTAssertTrue((video.value as? String ?? "").contains("Local file"))
            expectation(for:NSPredicate(format:"value CONTAINS 'playing'"),evaluatedWith:video);waitForExpectations(timeout:15)
            capture("Offline local video and saved captions after cold launch \(launch); remote authored source stopped")
            app.terminate()
        }
    }
    @MainActor func testAllFiveNativeTabsAndEmailForm() {
        XCUIDevice.shared.orientation = .portrait
        let app = launch();XCTAssertTrue(app.staticTexts["home.hero.title"].waitForExistence(timeout:12));capture("Native Home — recorded metadata")
        XCTAssertEqual(app.tabBars.count,0,"Only the custom native navigation may render; no system TabView bar.")
        for index in 0..<5 { XCTAssertEqual(app.buttons.matching(identifier:"tab.\(index)").count,1) }
        for tab in [1,2,3,4] {
            let button = app.buttons["tab.\(tab)"];XCTAssertTrue(button.isHittable);button.tap()
            XCTAssertEqual(app.tabBars.count,0)
            XCTAssertEqual(app.otherElements.matching(identifier:"navigation.bottom").count,1)
            for index in 0..<5 {
                let buttons = app.buttons.matching(identifier:"tab.\(index)")
                XCTAssertEqual(buttons.count,1)
                XCTAssertTrue(buttons.element.isHittable)
                XCTAssertGreaterThanOrEqual(buttons.element.frame.width,44)
                XCTAssertGreaterThanOrEqual(buttons.element.frame.height,44)
            }
        }
        capture("Native Profile")
        let login = app.buttons["profile.signin"];XCTAssertTrue(login.waitForExistence(timeout:5));login.tap()
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout:5));XCTAssertTrue(app.secureTextFields["auth.password"].exists)
        capture("Native email sign-in form — no submission")
    }
    /// 6.4: the wide-phone shell (unfolded foldable / landscape iPhone) proven on a normal
    /// simulator through the QA argument, so CI covers the layout real hardware cannot reach yet.
    @MainActor func testWidePhoneRailLayoutKeepsHomeAndProfileUsable() {
        let app = XCUIApplication();app.launchArguments = ["--ui-fixture","--wide-phone-qa"];app.launch()
        XCTAssertTrue(app.staticTexts["home.hero.title"].waitForExistence(timeout:15))
        // The identifier sits on a ScrollView, so match on any element type rather than otherElements.
        let rail = app.descendants(matching:.any).matching(identifier:"rail.container")
        XCTAssertGreaterThanOrEqual(rail.count,1,"The wide layout must render the icon rail.")
        XCTAssertEqual(app.otherElements.matching(identifier:"navigation.bottom").count,0,"The bottom tab bar must not appear in the wide layout.")
        for section in ["Home","For You","Search","HU Subs","Seasonal","Subtitles","Alerts","Downloads","Profile"] {
            XCTAssertEqual(app.buttons.matching(identifier:"rail.\(section)").count,1,"Missing rail button for \(section)")
        }
        XCTAssertGreaterThanOrEqual(app.buttons["rail.Home"].frame.width,44)
        XCTAssertGreaterThanOrEqual(app.buttons["rail.Home"].frame.height,44)
        capture("Native wide phone — Home with icon rail")
        app.buttons["rail.Profile"].tap()
        XCTAssertTrue(app.buttons["profile.signin"].waitForExistence(timeout:10))
        // The List is lazy: the Layout section only exists once it has been scrolled into view.
        let mode = app.staticTexts["settings.layoutMode"]
        for _ in 0..<8 { if mode.exists { break };app.swipeUp() }
        XCTAssertTrue(mode.exists,"Profile must show which layout is running.")
        XCTAssertTrue(mode.label.contains("Wide phone"))
        capture("Native wide phone — Profile layout row")
        app.buttons["rail.Search"].tap()
        XCTAssertGreaterThanOrEqual(app.descendants(matching:.any).matching(identifier:"rail.container").count,1)
    }
    @MainActor func testBottomNavigationAcceptsDraggingAsWellAsTaps() {
        let app = launch();XCTAssertTrue(app.staticTexts["home.hero.title"].waitForExistence(timeout:12))
        let home = app.buttons["tab.0"],profile = app.buttons["tab.4"]
        home.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:0.1,thenDragTo:profile.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)))
        XCTAssertTrue(app.buttons["profile.signin"].waitForExistence(timeout:5))
        XCTAssertEqual(app.tabBars.count,0);XCTAssertEqual(app.otherElements.matching(identifier:"navigation.bottom").count,1)
        profile.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:0.1,thenDragTo:home.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)))
        XCTAssertTrue(app.staticTexts["home.hero.title"].waitForExistence(timeout:5))
        capture("Single dark-purple native navigation — drag regression")
    }
    @MainActor func testBleachDetailShowsNineOfTen() {
        let app = launch();let watch = app.buttons["home.watch"];XCTAssertTrue(watch.waitForExistence(timeout:12));watch.tap()
        XCTAssertTrue(app.staticTexts["9 / 10"].waitForExistence(timeout:8));capture("Native BLEACH detail — recorded metadata")
        for _ in 0..<5 { if app.buttons["detail.latest"].isHittable { break };app.swipeUp() }
        XCTAssertTrue(app.buttons["detail.latest"].exists)
        for _ in 0..<5 { if app.buttons["episode.9"].exists { break };app.swipeUp() }
        XCTAssertTrue(app.buttons["episode.9"].exists)
    }
    @MainActor func testNativePlayerControlsPortraitAndLandscape() {
        let app = launch(player:true);let toggle = app.buttons["player.togglePlayback"]
        XCTAssertTrue(toggle.waitForExistence(timeout:15))
        let playing = NSPredicate(format:"enabled == true");expectation(for:playing,evaluatedWith:toggle);waitForExpectations(timeout:15)
        capture("Native CortexPlayer portrait — authored fixture")
        revealControls(app);toggle.tap();XCTAssertEqual(toggle.label,"Resume playback");toggle.tap()
        app.buttons["player.forward"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        revealControls(app)
        XCTAssertTrue(app.buttons["player.close"].waitForExistence(timeout:5));capture("Native CortexPlayer landscape — authored fixture")
        app.buttons["player.close"].tap();XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["tab.0"].waitForExistence(timeout:5))
    }
}
