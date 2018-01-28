//
//  XMan.swift
//  XMan
//
//  Created by lincolnlaw on 2017/7/5.
//

import Foundation
import Yaml
import ColorizeSwift

final class XMan {
    static let version = "0.0.4"
    enum Platform: String {
        case iOS, Mac

        static func from(rawValue: String) -> Platform {
            let raw = rawValue.lowercased()
            let mac: Set<String> = ["mac", "macOS"]
            if mac.contains(raw) { return .Mac }
            return .iOS
        }

        var frameworksGroup: String {
            switch self {
            case .iOS: return "iOS"
            case .Mac: return "Mac"
            }
        }
    }
    
    var project: String = ""
    var carthageFolder: String = ""
    var deploymentTarget: String = ""
    var targetInfos: Set<TargetInfo> = []
    var frameworkCopyTool: String = "/usr/local/bin/carthage"

    init?(configFile path: String) {
        do {
            guard let currnetFolder = ProcessInfo.processInfo.environment["PWD"] else { return }
            let content = try String(contentsOfFile: path)
            let dict = try Yaml.load(content)
            //deploymentTarget
            if let value = dict["deployment_target"].string {
                deploymentTarget = value
            }

            //framework_copy_tool
            if let value = dict["framework_copy_tool"].string {
                frameworkCopyTool = value
            }
            //project
            var projectPath: String = ""
            if let value = dict["project"].string?.fixedShortcut {
                projectPath = value
            }
            if projectPath.isEmpty {
                Log.debug("no project provide, finding...")
                let fm = FileManager.default
                let list = try fm.contentsOfDirectory(atPath: currnetFolder)
                if let first = list.filter({$0.hasSuffix("xcodeproj")}).first {
                    projectPath = "\(currnetFolder)/\(first)"
                } else {
                    Log.error("Not Found any *.xcodeproj in directory:\(currnetFolder)")
                    exit(0)
                }
            }
            project = projectPath
            Log.info("processing project:\((project as NSString).lastPathComponent)")
            //carthageFolder
            if let carthage = dict["carthage_folder"].string?.fixedShortcut {
                carthageFolder = carthage
            } else {
                carthageFolder = "\(currnetFolder)/Carthage"
            }
            Log.info("carthage folder:\(carthageFolder)")

            var commonFrameworkMap: [String : [String]] = [:]
            //target_configuration
            var infos: Set<TargetInfo> = []
            if let targetConfigurations = dict["target_configuration"].array {
                let configs = targetConfigurations.flatMap({ $0.dictionary })
                for config in configs {
                    for (target, info) in config {
                        guard let name = target.string, let infoDict = info.dictionary else { continue }
                        //deployment_target
                        var targetDeploymentTarget: String = deploymentTarget
                        if let value = infoDict["deployment_target"]?.string {
                            targetDeploymentTarget = value
                        }
                        //tests_target
                        var testsTarget = ""
                        if let value = infoDict["tests_target"]?.string {
                            testsTarget = value
                        }

                        var addBuildNumberScript = false
                        if let value = infoDict["add_build_number_script"]?.bool {
                            addBuildNumberScript = value
                        }
                        //frameworks
                        var frameworks: Set<String> = []
                        if let commonFrameworksKey = infoDict["common_frameworks_key"]?.string {
                            if let commonFrameworks = commonFrameworkMap[commonFrameworksKey] {
                                for item in commonFrameworks {
                                    frameworks.insert(item)
                                }
                            } else {
                                if let array = dict[Yaml(stringLiteral: commonFrameworksKey)].array {
                                    let final = array.flatMap({$0.string})
                                    commonFrameworkMap[commonFrameworksKey] = final
                                    for item in final {
                                        frameworks.insert(item)
                                    }
                                }
                            }
                        }
                        if let orginalFrameworks = infoDict["frameworks"]?.array?.flatMap({$0.string}) {
                            frameworks = frameworks.union(orginalFrameworks)
                        }
                        
                        //dylibs
                        var totalDylibs: [String] = []
                        if let folder = infoDict["embeded_libs_folder"]?.string?.fixedShortcut {
                            do {
                                var items = try FileManager.default.contentsOfDirectory(atPath: folder)
                                items = items.map({ (folder as NSString).appendingPathComponent($0) })
                                totalDylibs.append(contentsOf: items)
                            } catch {
                                Log.error("can not read embeded_libs_folder: \(folder)")
                                exit(1)
                            }
                        }
                        if let dylibs = infoDict["embeded_libs"]?.array?.flatMap({$0.string?.fixedShortcut}) {
                            totalDylibs.append(contentsOf: dylibs)
                        }
                        let removePrefixedPath = (project as NSString).deletingLastPathComponent
                        let result = totalDylibs.flatMap({ (path) -> String? in
                            // not copy symbolic link
                            let ori = URL(fileURLWithPath: path)
                            var copy = ori
                            copy.resolveSymlinksInPath()
                            var toReturn: String?
                            if ori.lastPathComponent == copy.lastPathComponent {
                                if path.hasPrefix(removePrefixedPath) {
                                    let p = path.replacingOccurrences(of: removePrefixedPath, with: "")
                                    if p.hasPrefix("/") {
                                        var a = Array(p.utf8CString[1...])
                                        toReturn = String(cString: &a)
                                    } else { toReturn = p }
                                }
                            }
                            return toReturn
                        })
                        var dylibsSet: Set<String> = []
                        for item in result {
                            dylibsSet.insert(item)
                        }
                        Log.debug("dylibsSet: \(dylibsSet)")
                        //custom script
                        var scriptsSet: Set<String> = []
                        if let scripts = infoDict["custom_scripts"]?.array?.flatMap({$0.string?.fixedShortcut}) {
                            scriptsSet = scriptsSet.union(scripts)
                        }
                        
                        var targetInfo = TargetInfo(name: name, deploymentTarget: targetDeploymentTarget, frameworks: frameworks, embededLibs: dylibsSet, customScripts: scriptsSet, addBuildNumberScript: addBuildNumberScript, testsTarget: testsTarget)
                        if let value = infoDict["platform"]?.string {
                            targetInfo.platform = Platform.from(rawValue: value)
                        }
                        infos.insert(targetInfo)
                    }
                }
            }
            targetInfos = infos
        } catch {
            Log.error("init error:\(error.localizedDescription)")
            exit(0)
        }
    }

    private func getProject() -> PBXproj? {
        let path = "\(project)/project.pbxproj"
        do {
            let d = try Data(contentsOf: URL(fileURLWithPath: path))
            let dict = try PropertyListSerialization.propertyList(from: d, options: [], format: nil)
            guard let map = dict as? [String : Any] else { return nil }
            let pbxproj = PBXproj(source: map, path: project)
            return pbxproj
        } catch {
            Log.error("XMan down:\(error.localizedDescription)")
            exit(0)
        }
    }

    func backup() {
        guard let target = getProject() else { return }
        target.backup(force: true)
    }

    func restore() {
        PBXproj(source: [:], path: project).restore()
    }

    func processTarget() {
        guard targetInfos.count != 0 else {
            Log.debug("no config any target, end")
            exit(0)
        }
        guard let pbxproj = getProject() else { return }
        pbxproj.backup()
        let frameworksGroup = pbxproj.mainGroup?.createSubGroup(for: "Frameworks")
        Log.info("targets: \(targetInfos)")
        for targetInfo in targetInfos {
            let groupName = targetInfo.platform.frameworksGroup
            guard let target = pbxproj.target(for: targetInfo.name), let group = frameworksGroup?.createSubGroup(for: groupName) else { continue }
            let rawPlatform = targetInfo.platform.rawValue
            let base = (project as NSString).deletingLastPathComponent
            let extraPath = carthageFolder.replacingOccurrences(of: base, with: "")
            let frameworks = targetInfo.frameworks.flatMap({ Optional("\(carthageFolder)/Build/\(rawPlatform)/\($0).framework") })
            let copyPaths = targetInfo.frameworks.flatMap({ Optional("$(SRCROOT)\(extraPath)/Build/\(rawPlatform)/\($0).framework") })
            let isMac = targetInfo.platform == .Mac
            group.addFrameworks(infos: frameworks, toTraget: target, copyTool: frameworkCopyTool, copyPaths: copyPaths, isMac: isMac)
            if let testTarget = pbxproj.target(for: targetInfo.testsTarget) {
                group.addFrameworks(infos: frameworks, toTraget: testTarget, copyTool: frameworkCopyTool, copyPaths: copyPaths, isMac: isMac)
            }
            let dylibsCopyPaths = targetInfo.frameworks.flatMap({ Optional("$(SRCROOT)/\($0)") })
            if dylibsCopyPaths.count > 0 {
                group.addCopyDylibScript(dylibPaths: targetInfo.embededLibs, toTraget: target, copyPaths: dylibsCopyPaths)
            }
            
            if target.isApp || target.isFramework || target.isTests {
                target.setDeploymentTarget(version: targetInfo.deploymentTarget, platform: targetInfo.platform, carthageExtraPath: extraPath)
            }
            
            if target.isApp, targetInfo.addBuildNumberScript {
                target.addBuildNumberScript()
            }
            for path in targetInfo.customScripts {
                target.addCustomBuildScript(at: path)
            }
        }
        pbxproj.save()
        Log.info("XMan integrated frameworks success 🎉")
    }
}

extension XMan {
    static func initFile() {
        guard let currnetFolder = ProcessInfo.processInfo.environment["PWD"] else { return }
        let template = """
        # project: "path/to/your/*.xcodeproj" # if not config, will get first xcodeproj in directory
        # carthage_folder: "./Carthage" # if not config, will be the `Carthage` folder in directory
        framework_copy_tool: "/usr/local/bin/punic" # if not config, will using `/usr/local/bin/carthage`
        deployment_target: "8.0" # for project
        carthage_frameworks: # custom framework array
          # - Alamofire # framework name in `Carthage/Build/iOS` without `.framework`
        target_configuration:
          - Demo: # target name
              add_build_number_script: true
              tests_target: DemoTests
              embeded_libs:
                # - /path/to/your.dylib
              custom_scripts:
                # - /path/to/your script
              platform: iOS #Mac
              deployment_target: "9.0" # for target
              common_frameworks_key: "carthage_frameworks" # custom framework key
              frameworks:
                # - AlamofireImage # extra framewrok
        """
        let raw = "\(currnetFolder)/xman.yaml"
        let url = URL(fileURLWithPath: raw)
        do {
            try template.data(using: .utf8)?.write(to: url)
            Log.info("Created xman.yaml 🎉")
        } catch {
            Log.error(error.localizedDescription)
            exit(0)
        }
    }
}

extension XMan: CustomStringConvertible {
    var description: String {
        return """
        {
            project: \(project),
            carthageFolder: \(carthageFolder),
            deploymentTarget: \(deploymentTarget),
            targetInfos: \(targetInfos)
        }
        """
    }
}

struct TargetInfo: CustomStringConvertible, Hashable {
    var hashValue: Int { return name.hashValue }
    
    enum Key: String {
        case name
        case platform
        case testsTarget = "tests_target"
        case deploymentTarget = "deployment_target"
        case addBuildNumberScript = "add_build_number_script"
        case frameworks = "frameworks"
        case embededLibs = "embeded_libs"
        case customScripts = "custom_scripts"
        case commonFrameworksKey = "common_frameworks_key"
    }

    static func ==(lhs: TargetInfo, rhs: TargetInfo) -> Bool {
        return lhs.name == rhs.name
    }

    let name: String
    let deploymentTarget: String
    let frameworks: Set<String>
    let embededLibs: Set<String>
    let customScripts: Set<String>
    var platform: XMan.Platform = .iOS
    let testsTarget: String
    let addBuildNumberScript: Bool
    init(name: String, deploymentTarget: String, frameworks: Set<String>, embededLibs: Set<String> = [], customScripts: Set<String> = [],  addBuildNumberScript: Bool = false, testsTarget: String = "") {
        self.name = name
        self.embededLibs = embededLibs
        self.customScripts = customScripts
        self.deploymentTarget = deploymentTarget
        self.frameworks = frameworks
        self.addBuildNumberScript = addBuildNumberScript
        self.testsTarget = testsTarget
    }

    var description: String {
        return """
        {
            name: \(name),
            testsTarget: \(testsTarget),
            deploymentTarget: \(deploymentTarget),
            addBuildNumberScript: \(addBuildNumberScript),
            frameworks: \(frameworks),
            embededLibs: \(embededLibs),
            customScripts: \(customScripts)
        }
        """
    }

}

struct Log {
    private enum Mode { case info, warning, error, debug }
    static func info(_ messag: CustomStringConvertible) { _log(messag, mode: .info) }
    static func debug(_ messag: CustomStringConvertible) { _log(messag, mode: .debug) }
    static func warning(_ messag: CustomStringConvertible) { _log(messag, mode: .warning) }
    static func error(_ messag: CustomStringConvertible) { _log(messag, mode: .error) }
    private static func _log(_ messag: CustomStringConvertible, mode: Mode) {
        let item = messag.description
        switch mode {
        case .debug:
            #if DEBUG
                print("[Debug]".lightMagenta(), " ", item.darkGray())
            #endif
        case .info: print("[Info]".green(), "  ", item.lightGray())
        case .warning: print("[Waring]".lightYellow(), item.lightGray())
        case .error: print("[Error]".red(), " ", item.red())
        }
    }

    static func usage() {
        print("usage:\n\tcd [the folder where xman.yaml file located] && ".darkGray(), "xman".white())
        let version = "\t\tDisplay the current version of XMan"
        let help = "\t\t\tusage of XMan"
        let initialize = "\t\t\tinit a xman.yaml in current folder"
        let restore = "\t\trestore project.pbxproj"
        let backup = "\t\t\tbackup project.pbxproj"
        print("Available commands:".darkGray(), "\n\tversion".white(), version.darkGray(), "\n\thelp".white(), help.darkGray(), "\n\tinit".white(), initialize.darkGray(), "\n\trestore".white(), restore.darkGray(), "\n\tbackup".white(), backup.darkGray())
    }
}

extension String {
    var fixedShortcut: String {
        let currnetShortcut = "./"
        let upperShortcut = "../"
        let hasCurrent = hasPrefix(currnetShortcut)
        let hasUpper = hasPrefix(upperShortcut)
        guard (hasCurrent || hasUpper) else { return self }
        guard let currnetFolder = ProcessInfo.processInfo.environment["PWD"] else { return self }
        if hasCurrent {
            return replacingOccurrences(of: currnetShortcut, with: "\(currnetFolder)/")
        } else if hasUpper {
            return rightPathIn(absolutPath: currnetFolder)
        }
        return self
    }
    
    func rightPathIn(absolutPath: String) -> String {
        if hasPrefix("../") {
            let total = (absolutPath as NSString).deletingLastPathComponent
            let final = replacingOccurrences(of: "../", with: "")
            if final.hasPrefix("../") {
                return final.rightPathIn(absolutPath: total)
            } else {
                return (total as NSString).appendingPathComponent(final)
            }
        } else {
            return (absolutPath as NSString).appendingPathComponent(self)
        }
    }
}
