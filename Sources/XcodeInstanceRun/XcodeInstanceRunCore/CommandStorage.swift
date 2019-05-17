//
//  CommandStorage.swift
//  XcodeInstanceRun
//
//  Created by Deng Jinlong on 2019/4/27.
//

import Foundation

/// use wrapper to get class type
struct CommandStorage: Codable {
    var name: String
    var command: Command

    init(name: String, command: Command) {
        self.name = name
        self.command = command
    }

    enum CodingKeys: String, CodingKey
    {
        case name
        case command
    }

    init(from decoder: Decoder) throws
    {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try values.decode(String.self, forKey: .name)
        // FixMe: Lost class type
        // self.command = try values.decode(CommandStorage.commandType(self.name) as! Command.Type, forKey: .command)
        
        // get class type
        switch name {
        case "CompileSwift":
            self.command = try values.decode(CommandCompileSwift.self, forKey: .command)
        case "CompileC":
            self.command = try values.decode(CommandCompileC.self, forKey: .command)
        case "CopyPNGFile":
            self.command = try values.decode(CommandCopyPNGFile.self, forKey: .command)
        case "CompileXIB":
            self.command = try values.decode(CommandCompileXIB.self, forKey: .command)
        case "CompileSwiftSources":
            self.command = try values.decode(CommandCompileSwiftSources.self, forKey: .command)
        case "MergeSwiftModule":
            self.command = try values.decode(CommandMergeSwiftModule.self, forKey: .command)
        case "Ld":
            self.command = try values.decode(CommandLd.self, forKey: .command)
        case "CodeSign":
            self.command = try values.decode(CommandCodeSign.self, forKey: .command)
        default:
            self.command = try values.decode(Command.self, forKey: .command)
        }
    }

    func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(command, forKey: .command)
    }
    /*
    static func commandType(_ name: String) -> AnyClass {
        switch name {
        case "CompileSwift":
            return CommandCompileSwift.self
        case "CompileC":
            return CommandCompileC.self
        case "CopyPNGFile":
            return CommandCopyPNGFile.self
        case "CompileXIB":
            return CommandCompileXIB.self
        case "CompileSwiftSources":
            return CommandCompileSwiftSources.self
        case "MergeSwiftModule":
            return CommandMergeSwiftModule.self
        case "Ld":
            return CommandLd.self
        case "CodeSign":
            return CommandCodeSign.self
        default:
            return Command.self
        }
    } */
}

func storeOrderedTargets(_ targets: [String]) {
    do {
        let data = try JSONEncoder().encode(targets)
        try? data.write(to: URL(fileURLWithPath: orderedTargetsPath()))
    } catch let err {
        print(err)
    }
}

func restoreOrderedTargets() -> [String] {
    if let data = try? Data.init(contentsOf: URL(fileURLWithPath: orderedTargetsPath()), options: []),
        let storage = try? JSONDecoder().decode([String].self, from: data) {
        return storage
    } else {
        return []
    }
}

func storeCommands(_ commands: [String: [Command]]) {
    var storage = [String: [CommandStorage]]()
    for (target, commands) in commands {
        storage[target] = commands.map { CommandStorage(name: $0.name, command: $0) }
    }

    do {
        let data = try JSONEncoder().encode(storage)
        try? data.write(to: URL(fileURLWithPath: archivePath()))
    } catch let err {
        print(err)
    }
}

func restoreCommands() -> [String: [Command]]? {
    var storage = [String: [Command]]()
    if let data = try? Data.init(contentsOf: URL(fileURLWithPath: archivePath()), options: []),
        let commands = try? JSONDecoder().decode([String: [CommandStorage]].self, from: data) {
        for (target, commandStorages) in commands {
            storage[target] = commandStorages.map { $0.command }
        }
        return storage
    }
    
    return storage
}
