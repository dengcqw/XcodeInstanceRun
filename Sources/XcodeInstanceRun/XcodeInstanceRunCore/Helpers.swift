//
//  Helpers.swift
//  XcodeInstanceRun
//
//  Created by Deng Jinlong on 2019/5/20.
//

import Foundation

func productBundlePath() -> String {
    let appDir = GloablSimulator ? "Debug-iphonesimulator" : "Debug-iphoneos"
    return "\(workingDir)/DerivedData/Build/Products/\(appDir)"
}

func readPlist(key: String, plistPath: String) -> String? {
    if let data = try? Data.init(contentsOf: URL(fileURLWithPath: plistPath), options: []),
        let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
        let plist = obj as? [String: Any] {
        return plist[key] as? String
    } else {
        return nil
    }
}


func findFile(prefix: String?, suffix: String?, inFolder dirPath: String) -> [String] {
    var result = [String]()
    let enumerator = FileManager.default.enumerator(atPath: dirPath)
    while let element = enumerator?.nextObject() as? String {
        if element.hasPrefix(prefix ?? "") && element.hasSuffix(suffix ?? "") {
            result.append(element)
        }
    }
    return result
}


func matches(for regex: String, in text: String) -> [String] {
    do {
        let regex = try NSRegularExpression(pattern: regex)
        let results = regex.matches(in: text,
                                    range: NSRange(text.startIndex..., in: text))
        return results.map {
            String(text[Range($0.range, in: text)!])
        }
    } catch let error {
        print("invalid regex: \(error.localizedDescription)")
        return []
    }
}

func tempFilePath() -> String? {
    let temporaryDirectoryURL = URL(string: NSTemporaryDirectory())
    let temporaryFileURL = temporaryDirectoryURL?.appendingPathComponent(UUID().uuidString)
    return temporaryFileURL?.absoluteString
}


func getSouceFilePath(target: String) -> String {
    return "\(cacheDir())/\(target)-swiftfiles"
}

func getModuleFilePath(target: String) -> String {
    return "\(cacheDir())/\(target)-swiftmodules"
}

func archivePath() -> String {
    return cacheDir() + "/archivedCommands.json"
}

func orderedTargetsPath() -> String {
    return cacheDir() + "/orderedTargets.json"
}

var GloablSimulator: Bool = false

func cacheDir() -> String {
    let dir = workingDir + "/.FastCompile" + (GloablSimulator ? "/simulator" : "/iphoneos")
    if !FileManager.default.fileExists(atPath:  dir) {
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
            return dir
        } catch _ {
            assert(false, "create working dir fail")
        }
        return ""
    } else {
        return dir
    }
}


extension Array where Element == String {
    /// 命令后会有多余的编译warning信息，需要清除
    func filterCmd(_ prefix: String) -> [String] {
        for (index, value) in self.enumerated() {
            if value.hasPrefix(prefix) {
                return self.dropLast(self.count - 1 - index)
            }
        }
        return self
    }
}

public extension String {
    func getFileNameWithoutType() -> String? {
        guard let slashIndex = lastIndex(of: "/") else { return nil }
        let fileName = suffix(from: self.index(after: slashIndex))
        if let ret = fileName.split(separator: ".").first {
            return String(ret)
        } else {
            return nil
        }
    }

    // replace option and content
    mutating func replaceCommandLineParam(withPrefix prefix: String, replaceString: String) {
        guard let range = self.range(of: prefix) else { return }
        var preChar: Character = Character.init("-")
        var distance: Int = 0
        for (index, char) in self.suffix(from: range.upperBound).enumerated() {
            if char == "-" && preChar == " " { // end to next option
                distance = index - 1
                break
            } else {
                preChar = char
            }
        }
        guard distance != 0 else { return }
        let upperBound = self.index(range.upperBound, offsetBy: distance)
        self.replaceSubrange(range.lowerBound..<upperBound, with: replaceString)
    }

    func hasBlankPrefix(count: Int) -> Bool {
        var _count = 0
        for char in self {
            if char != " " {
                break
            }
            _count = _count + 1
        }
        return count == _count
    }

    /// find content range of option
    ///
    /// - parameters
    ///    option   an command option which has content, like   "-o filepath",  filepath range will return
    ///    reverse    if enumrate chars from endIndex
    func rangeOfOptionContent(option: String, reverse: Bool) -> Range<String.Index>? {
        if reverse {
            var idx = endIndex
            while(idx != startIndex) {
                var blankIdx = idx
                repeat {
                    if blankIdx == startIndex { break }
                    blankIdx = index(blankIdx, offsetBy: -1)
                } while(self[blankIdx] != " ")
                if index(blankIdx, offsetBy: -option.count) >= startIndex &&
                    option == self[index(blankIdx, offsetBy: -option.count)..<blankIdx] {
                    return index(blankIdx, offsetBy: 1) ..< idx
                } else {
                    idx = blankIdx // not need -1, is open upper bound
                }
            }
        } else {
            var idx = startIndex
            while(idx != endIndex) {
                var blankIdx = idx
                repeat { // find blank
                    blankIdx = index(blankIdx, offsetBy: 1)
                    if blankIdx == endIndex { break }
                } while(self[blankIdx] != " ")

                if distance(from: idx, to: blankIdx) == option.count && self[idx..<blankIdx] == option {
                    idx = index(blankIdx, offsetBy: 1) // content start index
                    repeat {  // find next blank
                        blankIdx = index(blankIdx, offsetBy: 1)
                        if blankIdx == endIndex { break }
                    } while(self[blankIdx] != " ")
                    return idx..<blankIdx
                } else {
                    idx = index(blankIdx, offsetBy: 1)
                }
            }
        }
        return nil
    }

    func or(_ defaultValue: String) -> String {
        return self == "" ? defaultValue : self
    }
}
