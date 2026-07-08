import Foundation

let usage = "usage: cc-vigil <status | --version>"

@main
enum CLIMain {
    static func main() {
        switch CommandLine.arguments.dropFirst().first {
        case "status"?:
            // TODO: query the daemon over cli.sock with WireRequest.status.
            print("idle (daemon not wired)")
        case "--version"?:
            print("cc-vigil 0.0.0-dev")
        default:
            print(usage)
            exit(2)
        }
    }
}
