#!/usr/bin/env swift
import Foundation

let script = URL(fileURLWithPath: #filePath)
let root = script.deletingLastPathComponent().deletingLastPathComponent()
guard CommandLine.arguments.count == 2 else { fatalError("Usage: swift scripts/generate-localizations.swift <resources-directory>") }
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let data = try Data(contentsOf: root.appendingPathComponent("Sources/MeetingCore/Resources/English.json"))
let english = try JSONDecoder().decode([String: String].self, from: data)
func quote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
}
for language in ["en", "es"] {
    let folder = output.appendingPathComponent(language + ".lproj", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let lines = english.keys.sorted().map { key in "\(quote(key)) = \(quote(language == "en" ? english[key]! : key));" }
    try (lines.joined(separator: "\n") + "\n").write(to: folder.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
    let info: [String: String] = language == "en" ? [
        "NSMicrophoneUsageDescription": "Mantis needs access to the selected microphone or audio interface to save its channels in recordings you choose to start.",
        "NSScreenCaptureUsageDescription": "Mantis uses ScreenCaptureKit to capture audio from the computer or the app you select. It does not save images or video.",
        "NSAudioCaptureUsageDescription": "Mantis needs computer audio access to save and transcribe your recordings. No video is saved."
    ] : [
        "NSMicrophoneUsageDescription": "Mantis necesita acceso a la entrada seleccionada (micrófono o interfaz de audio) para guardar sus canales en las grabaciones que decidas iniciar.",
        "NSScreenCaptureUsageDescription": "Mantis usa ScreenCaptureKit para capturar el audio de todo el computador o de la aplicación que selecciones. No guarda imágenes ni video.",
        "NSAudioCaptureUsageDescription": "Mantis necesita capturar el audio del computador para guardar y transcribir tus reuniones. No se guarda video."
    ]
    try (info.keys.sorted().map { "\(quote($0)) = \(quote(info[$0]!));" }.joined(separator: "\n") + "\n")
        .write(to: folder.appendingPathComponent("InfoPlist.strings"), atomically: true, encoding: .utf8)
}
print("Generated English and Spanish localization tables (\(english.count) keys).")
