import Foundation

@main
enum AndromedaStatusline {
    static func main() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let payload = StatusPayloadDecoder.decode(data)
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let directory = payload?.workspace?.currentDir ?? FileManager.default.currentDirectoryPath

        let rendered = Statusline.line(
            model: payload?.model?.displayName ?? "…",
            directory: Statusline.shortenedPath(directory, home: home),
            branch: GitBranch.current(in: directory)
        )
        FileHandle.standardOutput.write(Data(rendered.utf8))
    }
}
