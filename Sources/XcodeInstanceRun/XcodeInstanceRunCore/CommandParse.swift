//
//  CommandParse.swift
//  XcodeInstanceRun
//
//  Created by Deng Jinlong on 2019/4/19.
//

import Foundation

protocol LogSource {
    func getStreamReader() -> StreamReader?
}

struct FileSource: LogSource {
    var filePath: String
    func getStreamReader() -> StreamReader? {
        let pathURL = URL(fileURLWithPath: filePath)
        return StreamReader(url: pathURL, chunkSize: 40960)
    }
}

struct ScriptSource: LogSource {
    var shellCommand: String
    func getStreamReader() -> StreamReader? {
        if let fileHandle = Bash().execute(script: shellCommand) {
            return StreamReader(fileHandle: fileHandle, chunkSize: 40960)
        } else {
            return nil
        }
    }
}

struct StdinSource: LogSource {
    func getStreamReader() -> StreamReader? {
        return StreamReader(fileHandle: FileHandle.standardInput)
    }
}

let targets = getProjectTargets()
var orderedTargets: [String] = []

func addCommand(_ commands: inout [String: [Command]], _ command: Command) {
    guard targets.contains(command.target) else {
        return
    }
    var sameTargetCommands = commands[command.target] ?? []

    for exist in sameTargetCommands {
        if exist.equal(to: command) {
            return
        }
    }
    if !orderedTargets.contains(command.target) {
        orderedTargets.append(command.target)
    }
    sameTargetCommands.append(command)
    commands[command.target] = sameTargetCommands
    print("add: \(command.target) \(command.name)")
}

enum CommandNames: String, CaseIterable {
    case CompileSwift
    case CompileC
    case CompileSwiftSources
    case MergeSwiftModule
    case Ld
    case CodeSign
    case GenerateDSYMFile
    case CompileXIB
    case CopyPNGFile
    case PrecompileSwiftBridgingHeader
    case PBXCp
    case CpResource
    case PhaseScriptExecution
    case LinkStoryboards
}

func isCommand(_ text: String) -> Bool {
    if text.hasPrefix(" ") {
        return false
    }
    for name in CommandNames.allCases {
        if text.starts(with: name.rawValue) {
            return true
        }
    }
    return false
}

func createCommand(target: String, commandLines: [String]) -> Command? {
    guard commandLines.count > 1 else { return nil }
    // first line is command simple description
    guard let desc = commandLines.first, let commandIndex = desc.firstIndex(of: " ") else { return nil }
    let cmdPrefix = "    /Applications/Xcode.app/Contents/Developer"
    let content = Array(commandLines.dropFirst()).filterCmd(cmdPrefix)
    let command = CommandNames(rawValue: String(desc.prefix(upTo: commandIndex)))
    switch command {
    case .CompileSwift:
        return CommandCompileSwift(desc: desc, content: content, target: target)
    case .CompileC:
        return CommandCompileC(desc: desc, content: content, target: target)
    case .CopyPNGFile:
        return CommandCopyPNGFile(desc: desc, content: content, target: target)
    case .CompileXIB:
        return CommandCompileXIB(desc: desc, content: content, target: target)
    case .CompileSwiftSources:
        return CommandCompileSwiftSources(desc: desc, content: content, target: target)
    case .PrecompileSwiftBridgingHeader:
        return Command(target: target, name: "PrecompileSwiftBridgingHeader", content: content)
    case .MergeSwiftModule:
        return CommandMergeSwiftModule(desc: desc, content: content, target: target)
    case .PBXCp:
        return nil
        /*
        if desc.hasSuffix("framework") {
            return nil
        }
        // builtin-copy can't find by shell
        return CommandPBXCp(desc: desc, content: content.filterCmd("builtin-copy"), target: target)
        */
    case .Ld:
        return CommandLd(desc: desc, content: content, target: target)
    case .CodeSign:
        // embedded frameworks do code sign before app
        // we don't supportframework
        if desc.hasSuffix("framework") {
            return nil
        }
        let prefix = "    /usr/bin/codesign"
        return CommandCodeSign(desc: desc, content: content.filterCmd(prefix), target: target)
    case .GenerateDSYMFile:
        return Command(target: target, name: "GenerateDSYMFile", content: content)
    default:
        return nil
    }
}

func parse(_ logSource: LogSource, simulator: Bool) {

    let reader = logSource.getStreamReader()
    var commands: [String: [Command]] = [:]

    var tmpLines: [String] = []

    var currentTarget = ""

    func createCommandIfPossible() {
        guard tmpLines.count > 0 else { return }
        if let command = createCommand(target: currentTarget, commandLines: tmpLines) {
            addCommand(&commands, command)
        }
        tmpLines = []
    }

    while let line = reader?.nextLine() {
        let text = String(line)
        if text.hasPrefix("=== BUILD TARGET") {
            createCommandIfPossible()
            currentTarget = String(text.split(separator: " ")[3])
        } else if isCommand(text) {
            createCommandIfPossible()
            tmpLines.append(text)
        } else if text.hasBlankPrefix(count: 4) {
            tmpLines.append(text)
        }
    }
    createCommandIfPossible()
    if commands.count > 0 {
        storeCommands(commands)
        storeOrderedTargets(orderedTargets)
    }
}
