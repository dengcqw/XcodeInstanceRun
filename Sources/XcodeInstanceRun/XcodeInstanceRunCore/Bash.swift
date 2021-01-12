import Foundation

protocol CommandExecuting {
    func execute(script: String) -> FileHandle?
}


func readStringSync(fileHandle: FileHandle?) -> String? {
    guard let fileHandle = fileHandle  else { return nil }
    let data = fileHandle.readDataToEndOfFile()
    let output = String(data: data, encoding: String.Encoding.utf8)
    return output
}

final class Bash: CommandExecuting {

    // MARK: - CommandExecuting

    func execute(script: String) -> FileHandle? {
        guard let scriptFilePath = tempFilePath() else { return nil }
        let data = script.data(using: .utf8)
        if FileManager.default.createFile(atPath: scriptFilePath, contents: data, attributes: nil) {
            return execute(command: "/bin/bash", arguments: [scriptFilePath])
        } else {
            return nil
        }
    }

    // MARK: Private

    private func execute(command: String, arguments: [String] = []) -> FileHandle {
        let process = Process()
        process.launchPath = command
        process.arguments = arguments
        process.terminationHandler = { ps in
            let status = ps.terminationStatus
            if status != 0 {
                print("output: Shell script failed. \(status) \(status == 127 ? " command not found" : "")")
                print(arguments)
                exit(status)
            }
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.launch()
        return pipe.fileHandleForReading
    }
}
