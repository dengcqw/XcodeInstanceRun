//
//  CommandLine.swift
//  Commandant
//
//  Created by Deng Jinlong on 2019/5/13.
//

import Foundation
import Commandant

struct CopyCommand: CommandProtocol {
    typealias ClientError = CommandError
    typealias Options = CopyOptions
    let verb = "copy"
    let function = "copy app bundle and dsym to specified path"
    
    func run(_ options: Options) -> Result<(), CommandError> {
        if options.copyTo == "" {
            return .failure(.unknown)
        }
        copyAppBundle(to: options.copyTo, isSimulator: options.simulator)
        return .success(())
    }
    struct CopyOptions: OptionsProtocol {
        let simulator: Bool
        let copyTo: String
        
        static func create(_ simulator: Bool) -> (String) -> CopyOptions {
            return  { copyTo in CopyOptions(simulator: simulator, copyTo: copyTo) }
        }
        
        static func evaluate(_ m: CommandMode) -> Result<CopyOptions, CommandantError<CommandError>> {
            return create
                <*> m <| Switch(flag: "s", key: "simulator", usage: "copy simulator product")
                <*> m <| Option(key: "to", defaultValue: "", usage: "copy to")
        }
    }
}

struct BuildBridgingheaderCommand: CommandProtocol {
    typealias ClientError = CommandError
    typealias Options = NoOptions<CommandError>
    let verb = "bridgingHeader"
    let function = "build bridgingHeader for objc and swift mix project"
    
    func run(_ options: Options) -> Result<(), CommandError> {
        bridgingHeader()
        return .success(())
    }
}

struct DeployCommand: CommandProtocol {
    typealias ClientError = CommandError
    typealias Options = DeployOptions
    let verb = "deploy"
    let function = "deploy to simulator or iphoneos"
    
    func run(_ options: Options) -> Result<(), CommandError> {
        iosDeploy(simulator: options.simulator)
        return .success(())
    }
    struct DeployOptions: OptionsProtocol {
        let simulator: Bool
        
        static func create(_ simulator: Bool) -> DeployOptions {
            return DeployOptions(simulator: simulator)
        }
        
        static func evaluate(_ m: CommandMode) -> Result<DeployOptions, CommandantError<CommandError>> {
            return create
                <*> m <| Switch(flag: "s", key: "simulator", usage: "copy simulator product")
        }
    }
}

struct RunCommand: CommandProtocol {
    typealias ClientError = CommandError
    typealias Options = RunOptions
    let verb = "compile"
    let function = "compile modified objc or swift files, copy pngs"
    
    func run(_ options: Options) -> Result<(), CommandError> {
        runCommand(target: options.target, simulator: options.simulator)
        return .success(())
    }
    
    struct RunOptions: OptionsProtocol {
        let simulator: Bool
        let target: String
        
        static func create(_ simulator: Bool) -> (String) -> RunOptions {
            return  { target in RunOptions(simulator: simulator, target: target) }
        }
        
        static func evaluate(_ m: CommandMode) -> Result<RunOptions, CommandantError<CommandError>> {
            return create
                <*> m <| Switch(flag: "s", key: "simulator", usage: "copy simulator product")
                <*> m <| Option(key: "target", defaultValue: "", usage: "run given target")
        }
    }
}

struct BuildCommand: CommandProtocol {
    typealias ClientError = CommandError
    typealias Options = BuildOptions
    let verb = "build"
    let function = "build project and generate cache files for fast compile"
    
    func run(_ options: Options) -> Result<(), CommandError> {
        print(options)
        
        GloablSimulator = options.simulator
        
        var logSource: LogSource?
        if options.xcode != "" {
            // TODO: how to clean only one target
            // NOTE: open xcode and clean project, then xcodebuild fail
            /*
             Build system information
             error: unable to attach DB: error: accessing build database "~/Library/Developer/Xcode/DerivedData/TVGuor-fomvyhexvtnxgiapyrtldmbgjnod/Build/Intermediates.noindex/XCBuildData/build.db": database is locked Possibly there are two concurrent builds running in the same filesystem location.
             */
            /*
             whole module building cause symbol mixed
             */
            // -workspace TVGuor.xcworkspace -scheme TVGuor -configuration Debug -arch arm64
            
            // let cleancmd = "xcodebuild clean \(options.xcode)  -derivedDataPath \(workingDir)/DerivedData"
            let orderedTargets = restoreOrderedTargets()
            let cleancmd = orderedTargets.reduce([]) { (result, target) -> [String] in
                return result + ["rm -r \(productBundlePath())/\(target)*"]
            }
            let buildcmd = "xcodebuild build \(options.xcode) SWIFT_COMPILATION_MODE=singlefile SWIFT_WHOLE_MODULE_OPTIMIZATION=NO -derivedDataPath \(workingDir)/DerivedData | tee  \(cacheDir())/lastbuild.log"
            let scriptCmd = (cleancmd + [buildcmd]).joined(separator: ";")
            if options.buildonly {
                _ = Bash().execute(script: scriptCmd)
                return .success(())
            } else {
                logSource = ScriptSource.init(shellCommand: scriptCmd)
            }
        } else if options.stdin {
            logSource = StdinSource.init()
        } else if options.logPath.count > 0 {
            print(options.logPath)
            logSource = FileSource.init(filePath: options.logPath)
        }
        if logSource != nil {
            parse(logSource!, simulator: options.simulator)
            return .success(())
        } else {
            return .failure(.invalidArgument(description: "not set compile source"))
        }
    }
    
    struct BuildOptions: OptionsProtocol {
        let xcode: String
        let stdin: Bool
        let logPath: String
        let simulator: Bool
        let buildonly: Bool
        
        static func create(_ xcode: String) -> (Bool) -> (String) -> (Bool) -> (Bool) -> BuildOptions {
            return { stdin in { logPath in { simulator in { buildonly in BuildOptions(xcode: xcode, stdin: stdin, logPath: logPath, simulator: simulator, buildonly: buildonly) } } } }
        }
        
        static func evaluate(_ m: CommandMode) -> Result<BuildOptions, CommandantError<CommandError>> {
            return create
                <*> m <| Option(key: "xcode", defaultValue: "", usage: "xcodebuild params to generate cache files\nXcodeInstanceRun build --xcode \"\\-workspace TVGuor.xcworkspace \\-scheme TVGuor \\-configuration Debug \\-arch arm64\"")
                <*> m <| Option(key: "stdin", defaultValue: false, usage: "generate from standard pipe")
                <*> m <| Option(key: "logPath", defaultValue: "", usage: "log file to generate cache files")
                <*> m <| Switch(flag: "s", key: "simulator", usage: "generate for simulator")
                <*> m <| Switch(flag: "b", key: "buildonly", usage: "build only and not parse log, valid when use --xcode")
        }
    }
}

enum CommandError: Error, CustomStringConvertible {
    case invalidArgument(description: String)
    case unknown
    case other(Error)
    
    /// An error message corresponding to this error.
    var description: String {
        switch self {
        case .invalidArgument(let description): return description
        case .other(let e): return "\(e)"
        default: return "An unknown error occured"
        }
    }
}
