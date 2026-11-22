import Foundation
import PetalCLI
import SwiftUI

/// `Petal.app/Contents/MacOS/petal transcribe …` runs the CLI inside the app bundle, so it uses the bundled MLX Metal library and the app's settings.
@main
@MainActor
enum PetalMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard CLICommand.isInvocation(arguments) else {
            PetalApp.main()
            return
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        PetalCLI.runAndExit(arguments, version: version)
    }
}
