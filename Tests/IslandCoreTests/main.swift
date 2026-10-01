import Foundation

@MainActor
func runAll() async -> Int32 {
    registerActivityManagerTests()
    registerPresentationTests()
    registerDisplayTests()
    registerSettingsTests()
    registerFeatureTests()
    return await TestKit.shared.run(filter: CommandLine.arguments.dropFirst().first)
}

let code = await runAll()
exit(code)
