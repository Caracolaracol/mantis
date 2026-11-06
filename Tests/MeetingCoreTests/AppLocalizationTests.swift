import XCTest
import MeetingCore

final class AppLocalizationTests: XCTestCase {
    func testLanguageDefaultsToEnglishAndPersistsExplicitChoiceInIsolatedDefaults() throws {
        let name = "AppLocalizationTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(AppLanguage.selected(defaults: defaults), .english)
        defaults.set("es", forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.selected(defaults: defaults), .spanish)
        defaults.set("invalid", forKey: AppLanguage.preferenceKey)
        XCTAssertEqual(AppLanguage.selected(defaults: defaults), .english)
    }

    func testEnglishAndSpanishLabels() {
        XCTAssertEqual(AppLocalization.text("Ajustes", language: .english), "Settings")
        XCTAssertEqual(AppLocalization.text("Ajustes", language: .spanish), "Ajustes")
        XCTAssertEqual(AppLocalization.text("Restablecer permiso de audio…", language: .english), "Reset audio permission…")
        XCTAssertGreaterThan(AppLocalization.english.count, 330)
        XCTAssertEqual(ModelCatalog.matching("Spanish").count, ModelCatalog.models.count)
        XCTAssertEqual(ModelCatalog.matching("español").count, ModelCatalog.models.count)
    }

    func testPersistedErrorsAndInterpolatedArgumentsCanBeReadInBothLanguages() {
        let source = "No se pudo cargar /some/file.gguf: Synthetic error 50%"
        let english = AppLocalization.message(source, language: .english)
        XCTAssertEqual(english, "Could not load /some/file.gguf: Synthetic error 50%")
        XCTAssertEqual(AppLocalization.message(english, language: .spanish), source)
        XCTAssertEqual(AppLocalization.message("Transcribiendo localmente… 42 %", language: .english), "Transcribing locally… 42 %")
    }

    func testTranslationsPreserveFormatPlaceholders() throws {
        let regex = try NSRegularExpression(pattern: "%@|%lld")
        for (source, translation) in AppLocalization.english {
            func placeholders(_ value: String) -> [String] {
                regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { String(value[Range($0.range, in: value)!]) }
            }
            XCTAssertEqual(placeholders(source), placeholders(translation), source)
        }
    }

    func testUserTitlesAndUnknownMessagesAreNotTranslated() throws {
        var meeting = Meeting(title: "Ajustes", mode: .microphone, audioFileName: "custom.m4a")
        XCTAssertEqual(meeting.title, "Ajustes")
        try meeting.rename(to: "Transcribir")
        XCTAssertEqual(meeting.title, "Transcribir")
        XCTAssertEqual(meeting.audioFileName, "custom.m4a")
        XCTAssertEqual(AppLocalization.message("A custom third-party error", language: .spanish), "A custom third-party error")
    }

    func testPermissionDetectionSupportsEnglishAndLegacySpanish() {
        XCTAssertEqual(CaptureErrorPresentation.permission(in: "macOS did not authorize access to computer audio."), .systemAudio)
        XCTAssertEqual(CaptureErrorPresentation.permission(in: "macOS did not authorize access to your microphone."), .microphone)
        XCTAssertEqual(CaptureErrorPresentation.permission(in: "macOS no autorizó el acceso al audio del computador"), .systemAudio)
    }
}
