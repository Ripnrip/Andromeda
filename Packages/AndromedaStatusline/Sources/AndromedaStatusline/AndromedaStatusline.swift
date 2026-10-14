import Foundation

@main
enum AndromedaStatusline {
    static func main() {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let payload: StatusPayload?
        switch StatusPayloadDecoder.evidence(data) {
        case let .success(decoded):
            payload = decoded
        case let .failure(failure):
            payload = nil
            FileHandle.standardError.write(Data("statusline: \(failure.evidence)\n".utf8))
        }
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
