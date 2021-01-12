//
//  CommandRun.swift
//  XcodeInstanceRun
//
//  Created by Deng Jinlong on 2019/4/28.
//

import Foundation

let workingDir =  FileManager.default.currentDirectoryPath

func supportFile(_ line: String) -> Bool {
    return line.hasSuffix(".swift")
        || line.hasSuffix(".m")
        || line.hasSuffix(".mm")
        || line.hasSuffix(".c")
        || line.hasSuffix(".png")
        || line.hasSuffix(".xib")
}

let statusPrefixLength = 2

/// only support modified and added git files
func supportStatus(_ line: String) -> Bool {
    guard line.count > statusPrefixLength else { return false }
    let statusFlag = line.prefix(upTo: line.index(line.startIndex, offsetBy: statusPrefixLength))
    return statusFlag.contains("M") || statusFlag.contains("A")
}

// not support file path containing whitespace
func getModifiedFiles() -> [String] {
    if let output = readStringSync(fileHandle: Bash().execute(script: "cd \(workingDir);git status -s")) {
        return output.components(separatedBy: .newlines)
            .filter { supportStatus($0) && supportFile($0) } // filter support lines
            .map { String($0.suffix(from: $0.index($0.startIndex, offsetBy: statusPrefixLength + 1 /* one space */))) } // get file name
    } else {
        return []
    }
}

func getFileCommandName(_ file: String) -> String {
    guard let index = file.lastIndex(of: ".") else { return "" }
    let type = file.suffix(from: index)
    switch type {
    case ".swift":
        return CommandNames.CompileSwift.rawValue
    case ".c", ".m", ".mm":
        return CommandNames.CompileC.rawValue
    case ".png":
        return CommandNames.CopyPNGFile.rawValue
    case ".xib":
        return CommandNames.CompileXIB.rawValue
    default:
        return ""
    }
}

func getCommand(commands: [Command], commandName: String) -> Command? {
    for command in commands {
        if command.name == commandName {
            return command
        }
    }
    return nil
}

// run other command in order
func runOtherOtherCommand(_ commands: [Command]) {
    func execute(_ command: Command) {
        print("\(command.target) \(command.name)")
        command.execute(params: [], done: { (output) in
            if let output = output {
                print("output: \(output )")
            }
        })
    }

    commands
        .filter { $0.name == "MergeSwiftModule" }
        .forEach { execute($0) }
    commands
        .filter { $0.name == "PBXCp" }
        .forEach { execute($0) }
    commands
        .filter { $0.name == "Ld" }
        .forEach { execute($0) }
    commands
        .filter { $0.name == "GenerateDSYMFile" }
        .forEach { execute($0) }
    // code sign in same target coubld be more then one
    commands
        .filter { $0.name == "CodeSign" }
        .forEach { execute($0) }
}

func runCommand(target: String, simulator: Bool) {
    GloablSimulator = simulator

    let orderedTargets = restoreOrderedTargets()
    guard orderedTargets.count > 0 else { return }
    let modifiedFiles = getModifiedFiles()
    guard modifiedFiles.count > 0 else {
        print("Not find mofified files, exit build app")
        return
    }
    print("==== all targets ====")
    orderedTargets.forEach { print($0) }
    print("\n==== git modified files ====")
    modifiedFiles.forEach { print($0) }

    guard let allCommands = restoreCommands() else { return }

    print("\n==== run commands ====")
    orderedTargets.forEach { (target) in
        guard let sourceFileList = try? String.init(contentsOfFile: getSouceFilePath(target: target)) else {
            print("read [\(target)] source file list error")
            return
        }

        guard let commands = allCommands[target] else {
            print("restore comand error")
            return
        }

        var sourceChaned = false
        var objPath: String = ""
        for cmd in commands {
            if cmd is CommandMergeSwiftModule {
                objPath = (cmd as! CommandMergeSwiftModule).swiftmodulePath
            }
        }
        for file in modifiedFiles.filter({ sourceFileList.contains($0) }) {
            if let command = getCommand(commands: commands, commandName: getFileCommandName(file)) {
                print("\(command.target) \(command.name) \(file)")
                sourceChaned = true
                command.execute(params: [workingDir + "/" + file, objPath]) { (output) in
                    if let output = output {
                        print("output \(command.name): \(output)")
                    }
                }
            }
        }
        // assume last target is main target, copy png for it
        if orderedTargets.last == target {
            modifiedFiles
                .filter{ $0.hasSuffix(".png") || $0.hasSuffix(".xib") }
                .forEach({ (file) in
                    print(file)
                    if let command = getCommand(commands: commands, commandName: getFileCommandName(file)) {
                        print("\(command.target) \(command.name) \(file)")
                        command.execute(params: [workingDir + "/" + file]) { (output) in
                            if let output = output {
                                print("output \(command.name): \(output)")
                            }
                        }
                    }
                })
        }

        if sourceChaned {
            runOtherOtherCommand(commands)
        }
    } // end forEach
}

func bridgingHeader() {
    guard let commands = restoreCommands()?.values.first else { return }
    commands
        .filter { $0.name == "PrecompileSwiftBridgingHeader" }
        .forEach {
            print("build bridgingHeader")
            $0.execute(params: [], done: { (output) in
                print(output ?? "")
            })
    }
}

func copyAppBundle(to dest: String, isSimulator: Bool) {
    let folderName = isSimulator ? "Debug-iphonesimulator" : "Debug-iphoneos"
    let src = "\(workingDir)/DerivedData/Build/Products/\(folderName)"
    let app = "\(src)/*.app"
    let dsym = "\(src)/*.app.dSYM"

    let cmd = "cp -Rf \(app) \(dsym) \(dest)"

    _ = Bash().execute(script: cmd)
}

func iosDeploy(simulator: Bool) {
    let deployScript: String
    if simulator {
        let listDeviceScript = "xcrun simctl list devices booted -j | grep udid | awk -F'\"' '{print $4}'"
        guard let result = readStringSync(fileHandle: Bash().execute(script: listDeviceScript)) else { return }
        guard let fristDeviceUDID = result.components(separatedBy: .newlines).first else {
            print("Not Found Booted simulator device")
            return
        }
        let appDir = "\(workingDir)/DerivedData/Build/Products/Debug-iphonesimulator"
        guard let app = findFile(prefix: nil, suffix: ".app", inFolder: appDir).first else {
            print("Not Found app bundle")
            return
        }
        guard let bundleId = readPlist(key: "CFBundleIdentifier", plistPath: "\(appDir)/\(app)/Info.plist") else {
            print("Not Found app bundle id")
            return
        }

        let installScript = "xcrun simctl install \(fristDeviceUDID) \(appDir)/\(app)"
        let launchScript = "xcrun simctl launch \(fristDeviceUDID) \(bundleId)"
        deployScript = [installScript, launchScript].joined(separator: ";")
    } else {
        deployScript = "ios-deploy -b \(workingDir)/DerivedData/Build/Products/Debug-iphoneos/*.app -L"
    }

    print(deployScript)
    if let fileHandle = Bash().execute(script: deployScript) {
        let reader = StreamReader(fileHandle: fileHandle, chunkSize: 1024)
        while let line = reader?.nextLine() {
            print(line)
        }
    }
}

