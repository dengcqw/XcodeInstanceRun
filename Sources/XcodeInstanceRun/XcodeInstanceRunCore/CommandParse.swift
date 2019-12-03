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
}

func isCommand(_ text: String) -> Bool {
    return text.starts(with: "CompileSwift")
        || text.starts(with: "CompileC")
        || text.starts(with: "CompileSwiftSources")
        || text.starts(with: "MergeSwiftModule")
        || text.starts(with: "Ld")
        || text.starts(with: "CodeSign")
        || text.starts(with: "GenerateDSYMFile")
}

func createCommand(commandLines: [String]) -> Command? {
    guard commandLines.count > 1 else { return nil }
    guard let desc = commandLines.first, let commandIndex = desc.firstIndex(of: " ") else { return nil }
    let content = Array(commandLines.dropFirst())
    let command = desc.prefix(upTo: commandIndex)
    let prefix = "    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
    print(command)
    switch command {
    case "CompileSwift":
        return CommandCompileSwift(desc: desc, content: content.filterCmd(prefix))
    case "CompileC":
        return CommandCompileC(desc: desc, content: content.filterCmd(prefix))
    case "CopyPNGFile":
        return CommandCopyPNGFile(desc: desc, content: content)
    case "CompileXIB":
        return CommandCompileXIB(desc: desc, content: content)
    case "CompileSwiftSources":
        return CommandCompileSwiftSources(desc: desc, content: content.filterCmd(prefix))
    case "PrecompileSwiftBridgingHeader":
        let target = desc.split(separator: " ").last!.replacingOccurrences(of: ")", with: "")
        return Command(target: target, name: "PrecompileSwiftBridgingHeader", content: content)
    case "MergeSwiftModule":
        return CommandMergeSwiftModule(desc: desc, content: content.filterCmd(prefix))
    case "PBXCp":
        return CommandPBXCp(desc: desc, content: content.filterCmd("builtin-copy"))
    case "Ld":
        return CommandLd(desc: desc, content: content.filterCmd(prefix))
    case "CodeSign":
        let prefix = "    /usr/bin/codesign"
        return CommandCodeSign(desc: desc, content: content.filterCmd(prefix))
    case "GenerateDSYMFile":
        let target = desc.split(separator: " ").last!.replacingOccurrences(of: ")", with: "")
        return Command(target: target, name: "GenerateDSYMFile", content: content)
    default:
        return nil
    }
}

func parse(_ logSource: LogSource, simulator: Bool) {
    GloablSimulator = simulator
    
    let reader = logSource.getStreamReader()
    var commands: [String: [Command]] = [:]
    
    var tmpStack: [String] = []
    
    while let line = reader?.nextLine() {
        let text = String(line)
        if isCommand(text) {
            if tmpStack.count != 0 { // save old command
                if let command = createCommand(commandLines: tmpStack) {
                    addCommand(&commands, command)
                }
            }
            tmpStack = [] // start new command
            tmpStack.append(text)
        } else if text.hasBlankPrefix(count: 4) {
            tmpStack.append(text)
        }
    }
    if tmpStack.count > 1 {
        if let command = createCommand(commandLines: tmpStack) {
            addCommand(&commands, command)
        }
    }
    if commands.count > 0 {
        storeCommands(commands)
        storeOrderedTargets(orderedTargets)
    }
}
