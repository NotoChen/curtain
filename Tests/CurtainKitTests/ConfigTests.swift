import Foundation
import Testing
@testable import CurtainKit

@Suite("Config")
struct ConfigTests {
    @Test("Decoded values are clamped")
    func decodedValuesAreClamped() throws {
        let data = Data(#"""
        {
          "holdToAuthSeconds": -3,
          "doubleEscapeSeconds": 9,
          "curtainColor": "#12abEF",
          "safetyTimeoutSeconds": 9999999,
          "hideCursorDuringCurtain": false
        }
        """#.utf8)

        let config = try JSONDecoder().decode(CurtainConfig.self, from: data)
        #expect(config.holdToAuthSeconds == 1.0)
        #expect(config.doubleEscapeSeconds == 1.5)
        #expect(config.curtainColor == "#12ABEF")
        #expect(config.safetyTimeoutSeconds == 86_400)
        #expect(!config.hideCursorDuringCurtain)
    }

    @Test("Missing and unknown fields use defaults")
    func unknownFieldsUseDefaults() throws {
        let data = Data(#"{"unknown":true,"holdToAuthSeconds":3.5}"#.utf8)
        let config = try JSONDecoder().decode(CurtainConfig.self, from: data)
        #expect(config.holdToAuthSeconds == 3.5)
        #expect(config.doubleEscapeSeconds == 0.7)
        #expect(config.curtainColor == "#000000")
        #expect(config.safetyTimeoutSeconds == 0)
        #expect(config.hideCursorDuringCurtain)
    }

    @Test("Invalid curtain colors fall back to black")
    func invalidColorFallsBack() throws {
        let data = Data(#"{"curtainColor":"not-a-color"}"#.utf8)
        let config = try JSONDecoder().decode(CurtainConfig.self, from: data)
        #expect(config.curtainColor == "#000000")
    }

    @Test("Invalid hotkey falls back to the default binding")
    func invalidHotkeyFallsBack() throws {
        let data = Data(#"{"hotkeyKeyCode":8,"hotkeyModifiers":0}"#.utf8)
        let config = try JSONDecoder().decode(CurtainConfig.self, from: data)
        #expect(config.hotkeyKeyCode == HotkeyPolicy.keyCode)
        #expect(config.hotkeyModifiers == HotkeyPolicy.modifiers.rawValue)
    }

    @Test("Scene hotkeys have unique defaults and round-trip")
    func sceneHotkeysRoundTrip() throws {
        var config = try JSONDecoder().decode(
            CurtainConfig.self,
            from: Data("{}".utf8)
        )
        #expect(CurtainScene.allCases.map {
            config.sceneHotkey(for: $0).displayString
        } == ["⌃⌥⌘1", "⌃⌥⌘2", "⌃⌥⌘3", "⌃⌥⌘4"])
        let defaults = CurtainScene.allCases.map {
            config.sceneHotkey(for: $0)
        }
        #expect(Set(defaults.map {
            "\($0.keyCode):\($0.modifiers)"
        }).count == CurtainScene.allCases.count)

        config.sceneHotkeys["away"] = SceneHotkey(
            keyCode: 0,
            modifiers: [.maskControl, .maskAlternate]
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CurtainConfig.self, from: data)
        #expect(decoded.sceneHotkey(for: .away).keyCode == 0)
        #expect(decoded.sceneHotkey(for: .meeting) ==
            CurtainScene.meeting.defaultHotkey)
    }

    @Test("Invalid stored scene hotkeys fall back to that scene default")
    func invalidSceneHotkeyFallsBack() throws {
        let data = Data(#"""
        {
          "sceneHotkeys": {
            "away": {
              "keyCode": 8,
              "modifiers": 0
            },
            "meeting": {
              "keyCode": 19,
              "modifiers": 1835008
            }
          }
        }
        """#.utf8)
        let config = try JSONDecoder().decode(CurtainConfig.self, from: data)
        #expect(config.sceneHotkey(for: .away) ==
            CurtainScene.away.defaultHotkey)
        #expect(config.sceneHotkey(for: .meeting).keyCode == 19)
    }

    @Test("Presentation mode defaults to off")
    func presentationDefaultsOff() throws {
        let config = try JSONDecoder().decode(CurtainConfig.self, from: Data("{}".utf8))
        #expect(!config.presentationModeEnabled)
        #expect(config.presentationImagePath.isEmpty)
        #expect(config.presentationClockStyle == "digital")
        #expect(!config.hasShownOnboarding)
    }

    @Test("Invalid presentation clock style falls back to digital")
    func invalidPresentationClockFallsBack() throws {
        let data = Data(#"{"presentationClockStyle":"sundial"}"#.utf8)
        let config = try JSONDecoder().decode(CurtainConfig.self, from: data)
        #expect(config.presentationClockStyle == PresentationClockStyle.digital.rawValue)
    }

    @Test("Automation and display settings use safe defaults")
    func automationDefaults() throws {
        let config = try JSONDecoder().decode(CurtainConfig.self, from: Data("{}".utf8))
        #expect(!config.idleAutoCurtainEnabled)
        #expect(config.idleAutoCurtainSeconds == 600)
        #expect(!config.scheduleEnabled)
        #expect(!config.scheduleAutoExit)
        #expect(config.defaultProtectionMinutes == 0)
        #expect(!config.clamshellModeEnabled)
        #expect(config.mainDisplayRole == CurtainDisplayRole.presentation.rawValue)
        #expect(config.secondaryDisplayRole == CurtainDisplayRole.presentation.rawValue)
        #expect(config.presentationFocusX == 0.5)
        #expect(config.presentationZoom == 1)
        #expect(config.presentationDim == 0)
    }

    @Test("Automation values are clamped and display roles are validated")
    func automationClamps() throws {
        let data = Data(#"""
        {
          "idleAutoCurtainSeconds": 5,
          "scheduleWeekdays": 999,
          "scheduleStartMinutes": -4,
          "scheduleEndMinutes": 99999,
          "defaultProtectionMinutes": 99999,
          "presentationZoom": 9,
          "presentationDim": -1,
          "presentationFocusX": 2,
          "mainDisplayRole": "broken",
          "secondaryDisplayRole": "black"
        }
        """#.utf8)
        let config = try JSONDecoder().decode(CurtainConfig.self, from: data)
        #expect(config.idleAutoCurtainSeconds == 60)
        #expect(config.scheduleWeekdays == 0b1111111)
        #expect(config.scheduleStartMinutes == 0)
        #expect(config.scheduleEndMinutes == 1439)
        #expect(config.defaultProtectionMinutes == 1440)
        #expect(config.presentationZoom == 2)
        #expect(config.presentationDim == 0)
        #expect(config.presentationFocusX == 1)
        #expect(config.mainDisplayRole == CurtainDisplayRole.presentation.rawValue)
        #expect(config.secondaryDisplayRole == CurtainDisplayRole.black.rawValue)
    }

    @Test("An empty weekday selection is preserved for a disabled schedule")
    func emptyWeekdaySelection() throws {
        let data = Data(#"{"scheduleEnabled":false,"scheduleWeekdays":0}"#.utf8)
        let config = try JSONDecoder().decode(CurtainConfig.self, from: data)
        #expect(config.scheduleWeekdays == 0)
        #expect(!config.scheduleEnabled)
    }

    @Test("Output-layer mode overrides display roles")
    func rolesRequirePresentationMode() {
        var config = CurtainConfig.default
        config.mainDisplayRole = CurtainDisplayRole.presentation.rawValue
        #expect(config.displayRole(isMain: true) == .black)
        config.presentationModeEnabled = true
        #expect(config.displayRole(isMain: true) == .presentation)
        config.mainDisplayRole = CurtainDisplayRole.black.rawValue
        #expect(config.displayRole(isMain: true) == .black)
    }

    @Test("Scene profiles use defaults and sanitize overrides")
    func sceneProfiles() throws {
        let data = Data(#"""
        {
          "sceneProfiles": {
            "away": {
              "protectionMinutes": 15,
              "usesPresentation": true,
              "message": "离开中"
            },
            "meeting": {
              "protectionMinutes": 99999,
              "usesPresentation": false
            },
            "guest": {
              "protectionMinutes": -3,
              "usesPresentation": true
            },
            "unknown": {
              "protectionMinutes": 20
            }
          }
        }
        """#.utf8)
        let config = try JSONDecoder().decode(CurtainConfig.self, from: data)

        #expect(config.protectionMinutes(for: .away) == 15)
        #expect(config.protectionMinutes(for: .meeting) == 1440)
        #expect(config.protectionMinutes(for: .guest) == 0)
        #expect(config.protectionMinutes(for: .focus) ==
            CurtainScene.focus.defaultProtectionMinutes)
        #expect(config.sceneProfiles["unknown"] == nil)
        #expect(config.sceneProfile(for: .away).usesPresentation)
        #expect(!config.sceneProfile(for: .meeting).usesPresentation)
    }

    @Test("Scene profiles round-trip without changing defaults")
    func sceneProfileRoundTrip() throws {
        var config = CurtainConfig.default
        config.sceneProfiles = [
            "away": CurtainSceneProfile(
                protectionMinutes: 180,
                usesPresentation: true,
                message: "离开中"
            )
        ]
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CurtainConfig.self, from: data)

        #expect(decoded.protectionMinutes(for: .away) == 180)
        #expect(decoded.sceneProfile(for: .away).message == "离开中")
        #expect(decoded.protectionMinutes(for: .meeting) ==
            CurtainScene.meeting.defaultProtectionMinutes)
        #expect(CurtainScene.durationText(minutes: 120) == "2 小时")
        #expect(CurtainScene.durationText(minutes: 45) == "45 分钟")
        #expect(CurtainScene.durationText(minutes: 0) == "不限时")
    }

    @Test("Legacy scene minute overrides become full profiles")
    func legacySceneMinutesBecomeProfiles() throws {
        let data = Data(#"""
        {
          "sceneProtectionMinutes": {
            "away": 45,
            "meeting": 120
          }
        }
        """#.utf8)
        let config = try JSONDecoder().decode(CurtainConfig.self, from: data)
        #expect(config.protectionMinutes(for: .away) == 45)
        #expect(config.protectionMinutes(for: .meeting) == 120)
        #expect(config.sceneProfile(for: .meeting).usesPresentation == false)
    }

    @Test("Scene roles can override the global display roles")
    func sceneRoleOverrides() {
        var config = CurtainConfig.default
        config.presentationModeEnabled = true
        config.mainDisplayRole = CurtainDisplayRole.presentation.rawValue
        config.secondaryDisplayRole = CurtainDisplayRole.presentation.rawValue
        var profile = CurtainScene.away.defaultProfile
        profile.mainDisplayRole = CurtainDisplayRole.black.rawValue
        profile.secondaryDisplayRole = CurtainDisplayRole.presentation.rawValue
        config.sceneProfiles["away"] = profile

        #expect(config.displayRole(for: .away, isMain: true) == .black)
        #expect(config.displayRole(for: .away, isMain: false) == .presentation)
        #expect(config.displayRole(for: .guest, isMain: true) == .presentation)
    }
}
