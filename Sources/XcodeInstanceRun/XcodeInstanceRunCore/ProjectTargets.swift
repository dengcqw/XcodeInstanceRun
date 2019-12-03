//
//  ProjectTargets.swift
//  XcodeInstanceRun
//
//  Created by Deng Jinlong on 2019/5/11.
//

import Foundation


private let getProjectInfo = "xcodebuild -list -json -project"

func getProjectTargets() -> [String] {
    let dirPath =  "/Users/dengjinlong/Documents/8-tvguo/2-TVGuoiOSApp"//FileManager.default.currentDirectoryPath
    if let projectFile = findFile(prefix: nil, suffix: ".xcodeproj", inFolder: dirPath).first {
        let handle = Bash().execute(script: "\(getProjectInfo) \(dirPath)/\(projectFile)")
        if let result = readStringSync(fileHandle: handle),
            let data = result.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data, options: []),
            let dict = obj as? [String: Any],
            let prj = dict["project"] as? [String: Any],
            let targets = prj["targets"] as? [String] {
            return targets
        } else{
            return []
        }
    } else {
        return []
    }
}




