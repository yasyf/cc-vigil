public enum LogTail {
    public static let defaultLineCount = 10

    public static func lastLines(of text: String, count: Int) -> [String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return Array(lines.suffix(count))
    }
}
