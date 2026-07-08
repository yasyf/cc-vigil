import CCVigilShared
import Foundation

let usage = "usage: cc-vigil <status | --version>"

@main
enum CLIMain {
    static func main() {
        switch CommandLine.arguments.dropFirst().first {
        case "status"?:
            print(Verdict.allowSleep.rawValue)
        case "--version"?:
            print("cc-vigil 0.0.0-dev")
        default:
            print(usage)
            exit(2)
        }
    }
}
