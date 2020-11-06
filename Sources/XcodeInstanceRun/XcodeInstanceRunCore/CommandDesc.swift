//
//  CommandDesc.swift
//  XcodeInstanceRun
//
//  Created by Deng Jinlong on 2019/4/20.
//

import Foundation

protocol CommandDescription {
    /// project target
    var target: String { get set }
    /// command name
    var name: String { get set }
    /// command content
    var content: [String] { get set }
}

/// entity to store command description
class Command: Codable, CommandDescription {
    var target: String
    var name: String
    var content: [String] = []

    init(target: String, name: String, content: [String]) {
        self.target = target
        self.name = name
        self.content = prepare(content)
    }

    func execute(params: [String], done: (String?)->Void) {
        print("==== \(name) ====")
        let bash: CommandExecuting = Bash()
        guard let fileHandle = bash.execute(script: (params + content).joined(separator: ";")) else {
            done(nil)
            return
        }
        let output = readStringSync(fileHandle: fileHandle)
        if output == "" {
            done(nil)
        } else {
            done(output)
        }
    }

    func prepare(_ content: [String]) -> [String] {
        return content.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).count != 0 }
    }

    func equal(to: Command) -> Bool {
        return
            target == to.target &&
            name   == to.name
    }

    enum CodingKeys: String, CodingKey
    {
        case target
        case name
        case content
    }

    required init(from decoder: Decoder) throws
    {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.target = try values.decode(String.self, forKey: .target)
        self.name = try values.decode(String.self, forKey: .name)
        self.content = try values.decode([String].self, forKey: .content)
    }

    func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(name, forKey: .name)
        try container.encode(content, forKey: .content)
    }
}

class CommandCompileC: Command {
    var outputPath: String
    var inputPath: String
    var arch: String
    var lang: String

    required init?(desc: String, content: [String]) {
        let arr = desc.split(separator: " ")
        guard arr.count == 7 else { return nil }
        self.outputPath = String(arr[1])
        self.inputPath = String(arr[2])
        self.arch = String(arr[4])
        self.lang = String(arr[5])

        var _target = ""
        if let cmd = content.last {
            let results = matches(for: "-fmodule-name=(\\w+)", in: cmd)
            if let moduleName = results.first?.split(separator: "=")[1] {
                _target = String(moduleName)
            }
        }
        
        super.init(target: _target, name: String(arr[0]), content: content)
    }

    enum CompileCCodingKeys: String, CodingKey
    {
        case outputPath
        case inputPath
        case arch
        case lang
    }

    required init(from decoder: Decoder) throws
    {
        let values = try decoder.container(keyedBy: CompileCCodingKeys.self)
        self.outputPath = try values.decode(String.self, forKey: .outputPath)
        self.inputPath = try values.decode(String.self, forKey: .inputPath)
        self.arch = try values.decode(String.self, forKey: .arch)
        self.lang = try values.decode(String.self, forKey: .lang)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CompileCCodingKeys.self)
        try container.encode(outputPath, forKey: .outputPath)
        try container.encode(inputPath, forKey: .inputPath)
        try container.encode(arch, forKey: .arch)
        try container.encode(lang, forKey: .lang)
        try super.encode(to: encoder)
    }

    override func execute(params: [String], done: (String?) -> Void) {
        guard let filePath = params.first, let fileName = filePath.getFileNameWithoutType() else { return }
        let defines = ["FILEPATH=\(filePath)", "FILENAME=\(fileName)"]
        super.execute(params: defines, done: done)
    }

    override func prepare(_ content: [String]) -> [String] {
        guard let lastLine = content.last else { return [] }
        guard let fileName = inputPath.getFileNameWithoutType() else { return [] }
        let newLine = lastLine.replacingOccurrences(of: inputPath, with: "$FILEPATH")
            .replacingOccurrences(of: fileName, with: "$FILENAME")
        return super.prepare(content.dropLast() + [newLine])
    }

    override func equal(to: Command) -> Bool {
        if let to = to as? CommandCompileC {
            return arch == to.arch &&
                lang == to.lang &&
                super.equal(to: to)
        }
        return false
    }
}

class CommandCompileSwiftSources: Command {
    var arch: String
    var wholeModuleOptimization: Bool = false

    required init?(desc: String, content: [String]) {
        let arr = desc.split(separator: " ")
        guard arr.count == 4 else { return nil }
        self.arch = String(arr[2])
        var _target = ""
        if let cmd = content.last, let range = cmd.rangeOfOptionContent(option: "-module-name", reverse: false) {
            _target = String(cmd[range])
        }
        super.init(target: _target, name: String(arr[0]), content: content)
        if var lastLine = content.last, let range = lastLine.range(of: "-whole-module-optimization") {
            lastLine.replaceSubrange(range, with: "")
            self.wholeModuleOptimization = true
        }
        if let lastLine = content.last {
            cacheFileList(lastLine)
        }
    }

    enum CompileSwiftSourcesKeys: String, CodingKey
    {
        case arch
        case opt
    }

    required init(from decoder: Decoder) throws
    {
        let values = try decoder.container(keyedBy: CompileSwiftSourcesKeys.self)
        self.arch = try values.decode(String.self, forKey: .arch)
        self.wholeModuleOptimization = try values.decode(Bool.self, forKey: .opt)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CompileSwiftSourcesKeys.self)
        try container.encode(arch, forKey: .arch)
        try container.encode(wholeModuleOptimization, forKey: .opt)
        try super.encode(to: encoder)
    }

    override func equal(to: Command) -> Bool {
        if let to = to as? CommandCompileSwiftSources {
            return arch == to.arch &&
                super.equal(to: to)
        }
        return false
    }

    func cacheFileList(_ compileCommand: String) {
        let splited = compileCommand.split(separator: " ")
        var fileList = ""
        for str in splited {
            if str.hasSuffix(".swift") {
                fileList.append(String(str))
                fileList.append("\n")
            }
        }
        do {
            try fileList.write(toFile: getSouceFilePath(target: target), atomically: true, encoding: .utf8)
        } catch _ {
            print("cache swift files error")
        }
    }
}

class CommandCompileSwift: Command {

    var arch: String
    var inputPath: String

    required init?(desc: String, content: [String]) {
        let arr = desc.split(separator: " ")
        if arr.count == 4 {
            self.arch = String(arr[2])
            self.inputPath = String(arr[3])
            
            var _target = ""
            if let cmd = content.last, let range = cmd.rangeOfOptionContent(option: "-module-name", reverse: false) {
                _target = String(cmd[range])
            }

            super.init(target: _target, name: String(arr[0]), content: content)
        } else { return nil }
    }

    enum CompileSwiftKeys: String, CodingKey
    {
        case arch
        case inputPath
    }

    required init(from decoder: Decoder) throws
    {
        let values = try decoder.container(keyedBy: CompileSwiftKeys.self)
        self.arch = try values.decode(String.self, forKey: .arch)
        self.inputPath = try values.decode(String.self, forKey: .inputPath)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CompileSwiftKeys.self)
        try container.encode(arch, forKey: .arch)
        try container.encode(inputPath, forKey: .inputPath)
        try super.encode(to: encoder)
    }

    override func execute(params: [String], done: (String?) -> Void) {
        guard params.count == 2 else { return }
        let sourceFileList = getSouceFilePath(target: target)
        guard let filePath = params.first, let fileName = filePath.getFileNameWithoutType() else { return }
        let defines = ["FILEPATH=\(filePath)", "FILENAME=\(fileName)", "SourceFileList=\(sourceFileList)", "ObjectsPATH=\(params[1])"]
        super.execute(params: defines, done: done)
    }

    override func prepare(_ content: [String]) -> [String] {
        guard let lastLine = content.last else { return [] }
        if !inputPath.isEmpty {
            guard let fileName = inputPath.getFileNameWithoutType() else { return [] }
            var newLine = lastLine
            newLine.replaceCommandLineParam(withPrefix: "-c", replaceString: "-c")
            newLine.replaceCommandLineParam(withPrefix: "-primary-file", replaceString: "-primary-file $FILEPATH")
            newLine = newLine.replacingOccurrences(of: fileName, with: "$FILENAME")
            //outputPath = outputPath.replacingOccurrences(of: fileName, with: "$FILENAME")
            

            if lastLine.contains("-filelist") {
                newLine.replaceCommandLineParam(withPrefix: "-filelist", replaceString: "-filelist $SourceFileList")
            } else {
                newLine.append(" -filelist $SourceFileList")
            }
            return super.prepare(content.dropLast() + [newLine])
        } else {
            let replaceText = "-primary-file $FILEPATH " +
                "-emit-module-path $ObjectsPATH/$FILENAME~partial.swiftmodule " +
                "-emit-module-doc-path $ObjectsPATH/$FILENAME~partial.swiftdoc " +
                "-serialize-diagnostics-path $ObjectsPATH/$FILENAME.dia " +
                "-emit-dependencies-path $ObjectsPATH/$FILENAME.d " +
                "-emit-reference-dependencies-path $ObjectsPATH/$FILENAME.swiftdeps "

            var newLine = lastLine
            newLine.replaceCommandLineParam(withPrefix: "-filelist", replaceString: "-filelist $SourceFileList")
            newLine.replaceCommandLineParam(withPrefix: "-supplementary-output-file-map", replaceString: replaceText)
            newLine.replaceCommandLineParam(withPrefix: "-output-filelist", replaceString: "-o $ObjectsPATH/$FILENAME.d")

            return super.prepare(content.dropLast() + [newLine])
        }
    }

    override func equal(to: Command) -> Bool {
        if let to = to as? CommandCompileSwift {
            return arch == to.arch &&
                super.equal(to: to)
        }
        return false
    }
}

class CommandMergeSwiftModule: Command {
    var arch: String
    var swiftmodulePath: String = ""

    init?(desc: String, content: [String]) {
        let arr = desc.split(separator: " ")
        guard arr.count == 4 else { return nil }
        self.arch = String(arr[2])
        let _target = arr.last!.split(separator: "/").last!.split(separator: ".").first!
        super.init(target: String(_target), name: String(arr[0]), content: content)
    }

    enum MergeSwiftModuleKeys: String, CodingKey
    {
        case arch
        case swiftmodulePath
    }

    required init(from decoder: Decoder) throws
    {
        let values = try decoder.container(keyedBy: MergeSwiftModuleKeys.self)
        self.arch = try values.decode(String.self, forKey: .arch)
        self.swiftmodulePath = try values.decode(String.self, forKey: .swiftmodulePath)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: MergeSwiftModuleKeys.self)
        try container.encode(arch, forKey: .arch)
        try container.encode(swiftmodulePath, forKey: .swiftmodulePath)
        try super.encode(to: encoder)
    }

    override func execute(params: [String], done: (String?) -> Void) {
        let moduleList = getModuleFilePath(target: target)
        let defines = ["ModuleList=\(moduleList)"]
        super.execute(params: defines, done: done)
    }

    override func prepare(_ content: [String]) -> [String] {
        guard let lastLine: String = content.last else { return [] }
        var newLine = lastLine
        newLine.replaceCommandLineParam(withPrefix: "-filelist", replaceString: "-filelist $ModuleList")

        if let range = lastLine.rangeOfOptionContent(option: "-o", reverse: true) {
            let modulePath = String(lastLine[range])
            self.swiftmodulePath = modulePath

            if let idx = modulePath.lastIndex(of: "/") {
                let dirPath = String(modulePath.prefix(upTo: idx))
                let mergedModule = String(modulePath.suffix(from: modulePath.index(after: idx)))
                assert(FileManager.default.fileExists(atPath: dirPath), "object folder not exist: \(dirPath)")

                var moduleList = ""
                let enumerator = FileManager.default.enumerator(atPath: dirPath)
                while let element = enumerator?.nextObject() as? String {
                    // mergedModule in the same folder, cannot include in file list
                    if element.hasSuffix(".swiftmodule") && !element.hasSuffix(mergedModule) {
                        moduleList.append(dirPath + "/" + element)
                        moduleList.append("\n")
                    }
                }
                do {
                    try moduleList.write(toFile: getModuleFilePath(target: target), atomically: true, encoding: .utf8)
                } catch _ {
                    print("cache swift module list err:")
                }
            }
        }
        return super.prepare(content.dropLast() + [newLine])
    }
}

class CommandLd: Command {
    var outputPath: String
    var arch: String

    init?(desc: String, content: [String]) {
        let arr = desc.split(separator: " ")
        guard arr.count == 4 else { return nil }
        self.outputPath = String(arr[1])
        self.arch = String(arr[3])
        let _target = self.outputPath.split(separator: "/").last ?? ""
        super.init(target: String(_target), name: String(arr[0]), content: content)
    }

    enum LdKeys: String, CodingKey
    {
        case arch
        case outputPath
    }

    required init(from decoder: Decoder) throws
    {
        let values = try decoder.container(keyedBy: LdKeys.self)
        self.arch = try values.decode(String.self, forKey: .arch)
        self.outputPath = try values.decode(String.self, forKey: .outputPath)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: LdKeys.self)
        try container.encode(arch, forKey: .arch)
        try container.encode(outputPath, forKey: .outputPath)
        try super.encode(to: encoder)
    }

    override func execute(params: [String], done: (String?) -> Void) {
        super.execute(params: params, done: done)
    }
}

class CommandCompileXIB: Command {
    var inputPath: String

    required init?(desc: String, content: [String]) {
        let arr = desc.split(separator: " ")
        guard arr.count == 5 else { return nil }
        self.inputPath = String(arr[1])
        let _target = arr.last!.replacingOccurrences(of: ")", with: "")
        super.init(target: _target, name: String(arr[0]), content: content)
    }

    enum CompileXIBKeys: String, CodingKey
    {
        case inputPath
    }

    required init(from decoder: Decoder) throws
    {
        let values = try decoder.container(keyedBy: CompileXIBKeys.self)
        self.inputPath = try values.decode(String.self, forKey: .inputPath)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CompileXIBKeys.self)
        try container.encode(inputPath, forKey: .inputPath)
        try super.encode(to: encoder)
    }

    override func execute(params: [String], done: (String?) -> Void) {
        guard let filePath = params.first, let fileName = filePath.getFileNameWithoutType() else { return }
        let defines = ["FILEPATH=\(filePath)", "FILENAME=\(fileName)"]
        super.execute(params: defines, done: done)
    }

    override func prepare(_ content: [String]) -> [String] {
        guard let lastLine = content.last else { return [] }
        guard let fileName = inputPath.getFileNameWithoutType() else { return [] }
        let newLine = lastLine.replacingOccurrences(of: inputPath, with: "$FILEPATH")
            .replacingOccurrences(of: fileName, with: "$FILENAME")
        return super.prepare(content.dropLast() + [newLine])
    }
}

class CommandCopyPNGFile: Command {
    var outputPath: String
    var inputPath: String

    required init?(desc: String, content: [String]) {
        let arr = desc.split(separator: " ")
        guard arr.count == 6 else { return nil }
        self.outputPath = String(arr[1])
        self.inputPath = String(arr[2])
        let _target = arr.last!.replacingOccurrences(of: ")", with: "")
        super.init(target: _target, name: String(arr[0]), content: content)
    }

    enum CopyPNGFileKeys: String, CodingKey
    {
        case inputPath
        case outputPath
    }

    required init(from decoder: Decoder) throws
    {
        let values = try decoder.container(keyedBy: CopyPNGFileKeys.self)
        self.inputPath = try values.decode(String.self, forKey: .inputPath)
         self.outputPath = try values.decode(String.self, forKey: .outputPath)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CopyPNGFileKeys.self)
        try container.encode(inputPath, forKey: .inputPath)
        try container.encode(outputPath, forKey: .outputPath)
        try super.encode(to: encoder)
    }

    override func execute(params: [String], done: (String?) -> Void) {
        guard let lastSlash = self.outputPath.lastIndex(of: "/") else { return }
        guard let fileNameSlash = params[0].lastIndex(of: "/") else { return }
        let fileName  = params[0].suffix(from: fileNameSlash)
        let output = self.outputPath.prefix(upTo: lastSlash) + fileName
        let defines = ["INPUT=\(params[0])", "OUTPUT=\(output)"]
        super.execute(params: defines, done: done)
    }

    override func prepare(_ content: [String]) -> [String] {
        guard let lastLine = content.last else { return [] }
        let newLine = lastLine.replacingOccurrences(of: inputPath, with: "$INPUT")
            .replacingOccurrences(of: outputPath, with: "$OUTPUT")
        return super.prepare(content.dropLast() + [newLine])
    }
}

class CommandCodeSign: Command {
    var outputPath: String

    required init?(desc: String, content: [String]) {
        let arr = desc.split(separator: " ")
        guard arr.count == 2 else { return nil }
        self.outputPath = String(arr[1])
        let _target = self.outputPath.split(separator: "/").last!.split(separator: ".").first!
        super.init(target: String(_target), name: String(arr[0]), content: content)
    }

    enum CodeSignKeys: String, CodingKey {
        case outputPath
    }

    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodeSignKeys.self)
        self.outputPath = try values.decode(String.self, forKey: .outputPath)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodeSignKeys.self)
        try container.encode(outputPath, forKey: .outputPath)
        try super.encode(to: encoder)
    }

    override func execute(params: [String], done: (String?) -> Void) {
        super.execute(params: params, done: done)
    }

    override func equal(to: Command) -> Bool {
        if let to = to as? CommandCodeSign {
            return outputPath == to.outputPath &&
                super.equal(to: to)
        }
        return false
    }
}

// copy embeded extension and framework
class CommandPBXCp: Command {
    
    required init?(desc: String, content: [String]) {
        let arr = desc.split(separator: " ")
        let _target = arr.last!.replacingOccurrences(of: ")", with: "")
        
        let input = arr[1]
        let output = arr[2]
        var newContent = Array(content.dropLast())
        
        // rsync用"/"区分目录和目录内容
        newContent.append("rsync -av --exclude=.DS_Store --exclude=CVS --exclude=.svn --exclude=.git --exclude=.hg --exclude=Headers --exclude=PrivateHeaders --exclude=Modules \(input + "/") \(output)")
        super.init(target: _target, name: String(arr[0]), content: newContent)
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
    
    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
    }
    
    override func execute(params: [String], done: (String?) -> Void) {
        super.execute(params: params, done: done)
    }
    
    override func equal(to: Command) -> Bool {
        return false
    }
}
