//
//  PBXNativeTarget.swift
//  XMan
//
//  Created by lincolnlaw on 2017/7/14.
//

import Foundation
final class PBXNativeTarget {
    private weak var _pbxproj: PBXproj?
    private(set) var key: String
    private(set) var name: String
    private lazy var productType: String = {
        let target = _pbxproj?.objects[self.key] as? [String : Any]
        return target?["productType"] as? String ?? ""
    }()
    lazy var isTests: Bool = {[unowned self] in
        return self.productType == "com.apple.product-type.bundle.unit-test"
    }()
    lazy var isApp: Bool = {[unowned self] in
        return self.productType == "com.apple.product-type.application"
    }()
    lazy var isFramework: Bool = {[unowned self] in
        return self.productType == "com.apple.product-type.framework"
    }()
    
    private lazy var _copyFrameworkName = "[XMan Copy Framework]"
    private lazy var _copyDylibsName = "[XMan Copy Dylibs]"
    
    init(pbxproj: PBXproj, key: String, name: String) {
        self.key = key
        self.name = name
        _pbxproj = pbxproj
    }
    
    func setDeploymentTarget(version: String, platform: XMan.Platform, carthageExtraPath: String) {
        guard let target = _pbxproj?.objects[key] as? [String : Any] else { return }
        guard let buildConfigurationListKey = target["buildConfigurationList"] as? String else { return }
        guard let buildConfigurationListObj = _pbxproj?.objects[buildConfigurationListKey] as? [String : Any] else { return }
        guard let buildConfigurationsKeys = buildConfigurationListObj["buildConfigurations"] as? [String] else { return }
        Log.debug("setDeploymentTarget for \(self)")
        let platformKey =  platform == .iOS ? "IPHONEOS_DEPLOYMENT_TARGET" : "MACOSX_DEPLOYMENT_TARGET"
        let frameworkSearchPath = "$(PROJECT_DIR)\(carthageExtraPath)/Build/\(platform.rawValue)"
        let frameworkSearchPathKey = "FRAMEWORK_SEARCH_PATHS"
        for key in buildConfigurationsKeys {
            guard var config = _pbxproj?.objects[key] as? [String : Any] else { continue }
            guard var buildSettings = config["buildSettings"] as? [String : Any] else { continue }
            if isTests == false {
                buildSettings[platformKey] = version
            }
            
            if var path = buildSettings[frameworkSearchPathKey] as? String {
                if path.range(of: frameworkSearchPath) == nil {
                    path = "\(path) \(frameworkSearchPath)"
                    buildSettings[frameworkSearchPathKey] = path
                }
            } else {
                buildSettings[frameworkSearchPathKey] = "$(inherited) \(frameworkSearchPath)"
            }
            config["buildSettings"] = buildSettings
            _pbxproj?.objects[key] = config
        }
    }
    
    func addCustomBuildScript(content: String, name: String) {
        guard var target = _pbxproj?.objects[key] as? [String : Any] else { return }
        guard var buildPhases = target["buildPhases"] as? [String] else { return }
        for (index, buildPhasesKey) in buildPhases.enumerated() {
            if let copyFilesBuildPhase = _pbxproj?.objects[buildPhasesKey] as? [String : Any], let fname = copyFilesBuildPhase["name"] as? String, fname == name {
                Log.debug("remomving old Script\(name):\(buildPhasesKey)")
                buildPhases.remove(at: index)
                target["buildPhases"] = buildPhases
                _pbxproj?.objects[key] = target
                _pbxproj?.objects.removeValue(forKey: buildPhasesKey)
                break
            }
        }
        let copyFrameworkScriptKey = PBXproj.uniqueId()
        let info: [String : Any] = [
            "isa" : "PBXShellScriptBuildPhase",
            "buildActionMask" : "2147483647",
            "dstPath" : "",
            "files" : [String](),
            "inputPaths" : [String](),
            "outputPaths" : [String](),
            "shellPath" : "/bin/bash",
            "shellScript" : content,
            "name": name,
            "runOnlyForDeploymentPostprocessing" : "0"
        ]
        buildPhases.append(copyFrameworkScriptKey)
        target["buildPhases"] = buildPhases
        _pbxproj?.objects[copyFrameworkScriptKey] = info
        _pbxproj?.objects[key] = target
    }
    
    func addCustomBuildScript(at filePath: String) {
        let url = URL(fileURLWithPath: filePath)
        let name = url.lastPathComponent
        do {
            let content = try String.init(contentsOf: url)
            addCustomBuildScript(content: content, name: name)
        } catch {
            Log.error("can not read file at:\(filePath)")
            exit(1)
        }
    }
    
    func addBuildNumberScript() {
        guard var target = _pbxproj?.objects[key] as? [String : Any] else { return }
        guard var buildPhases = target["buildPhases"] as? [String] else { return }
        let name = "[Xman Build Number]"
        for (index, buildPhasesKey) in buildPhases.enumerated() {
            if let copyFilesBuildPhase = _pbxproj?.objects[buildPhasesKey] as? [String : Any], let fname = copyFilesBuildPhase["name"] as? String, fname == name {
                Log.debug("remomving old Script\(name):\(buildPhasesKey)")
                buildPhases.remove(at: index)
                target["buildPhases"] = buildPhases
                _pbxproj?.objects[key] = target
                _pbxproj?.objects.removeValue(forKey: buildPhasesKey)
                break
            }
        }
        let copyFrameworkScriptKey = PBXproj.uniqueId()
        let script = """
                    import Foundation
                    enum Keys: String {
                        case build = "CFBundleVersion"
                        case srcRoot = "SRCROOT"
                        case infoPlist = "INFOPLIST_FILE"
                        case user = "USER"
                        case configuration = "CONFIGURATION"
                        case buildNumberInfo = "buildNumberInfo"
                        case release = "Release"
                    }
                    guard let srcRoot = ProcessInfo.processInfo.environment[Keys.srcRoot.rawValue],
                    let infoplist = ProcessInfo.processInfo.environment[Keys.infoPlist.rawValue],
                    let user = ProcessInfo.processInfo.environment[Keys.user.rawValue],
                    let configuration = ProcessInfo.processInfo.environment[Keys.configuration.rawValue] else { exit(0) }
                    let infoPath = srcRoot + "/" + infoplist
                    var userInfo: [String : Any] = [:]
                    if let info = NSDictionary(contentsOfFile: infoPath) as? [String : Any] { userInfo = info }
                    var buildNumberInfo: [String : Int] = [:]
                    if let value = userInfo[Keys.buildNumberInfo.rawValue] as? [String : Int] {
                    buildNumberInfo = value
                    }
                    var old = buildNumberInfo[user] ?? 0
                    old += 1
                    buildNumberInfo[user] = old
                    if configuration == Keys.release.rawValue {
                    let total = buildNumberInfo.values.reduce(0, +)
                    userInfo[Keys.build.rawValue] = total
                    }
                    userInfo[Keys.buildNumberInfo.rawValue] = buildNumberInfo
                    (userInfo as NSDictionary).write(toFile: infoPath, atomically: true)
                    """
        let info: [String : Any] = [
            "isa" : "PBXShellScriptBuildPhase",
            "buildActionMask" : "2147483647",
            "dstPath" : "",
            "files" : [String](),
            "inputPaths" : [String](),
            "outputPaths" : [String](),
            "shellPath" : "/usr/bin/env xcrun -sdk macosx swift",
            "shellScript" : script,
            "name": name,
            "runOnlyForDeploymentPostprocessing" : "0"
        ]
        buildPhases.append(copyFrameworkScriptKey)
        target["buildPhases"] = buildPhases
        _pbxproj?.objects[copyFrameworkScriptKey] = info
        _pbxproj?.objects[key] = target
    }
    
    func addCopyDylibs(buildFileKeys: [String]) {
        guard var target = _pbxproj?.objects[key] as? [String : Any] else { return }
        guard var buildPhases = target["buildPhases"] as? [String] else { return }
        
        let name = _copyDylibsName
        for (index, buildPhasesKey) in buildPhases.enumerated() {
            if let copyFilesBuildPhase = _pbxproj?.objects[buildPhasesKey] as? [String : Any], let fname = copyFilesBuildPhase["name"] as? String, fname == name {
                Log.debug("Copy Dylibs remomving:\(buildPhasesKey)")
                buildPhases.remove(at: index)
                target["buildPhases"] = buildPhases
                _pbxproj?.objects[key] = target
                _pbxproj?.objects.removeValue(forKey: buildPhasesKey)
                break
            }
        }
        let copyFilePhaseKey = PBXproj.uniqueId()
        let info: [String : Any] = [
            "isa" : "PBXCopyFilesBuildPhase",
            "buildActionMask" : "2147483647",
            "dstPath" : "",
            "dstSubfolderSpec" : "10",
            "files" : buildFileKeys,
            "name": name,
            "runOnlyForDeploymentPostprocessing" : "0"
        ]
        buildPhases.append(copyFilePhaseKey)
        target["buildPhases"] = buildPhases
        _pbxproj?.objects[copyFilePhaseKey] = info
        _pbxproj?.objects[key] = target
    }
    
    func addFrameworkToFrameworkBuildPhase(buildFileKey: String, fileRef: String) {
        guard let target = _pbxproj?.objects[key] as? [String : Any] else { return }
        guard let buildPhases = target["buildPhases"] as? [String] else { return }
        for key in buildPhases {
            guard var frameworkBuildPhase = _pbxproj?.objects[key] as? [String : Any] else { continue }
            guard let isa = frameworkBuildPhase["isa"] as? String, isa == "PBXFrameworksBuildPhase", var files = frameworkBuildPhase["files"] as? [String] else { continue }
            
            //remove old PBXBuildFile for same fileRef
            func remove(for key: String) {
                var needDealNext = false
                for (index, fkey) in files.enumerated() {
                    guard let file = _pbxproj?.objects[fkey] as? [String : Any] else { continue }
                    if let ref = file["fileRef"] as? String, ref == key {
                        files.remove(at: index)
                        _pbxproj?.objects.removeValue(forKey: fkey)
                        needDealNext = true
                        break
                    }
                }
                if needDealNext {
                    remove(for: key)
                }
            }
            remove(for: fileRef)
            files.append(buildFileKey)
            frameworkBuildPhase["files"] = files
            _pbxproj?.objects[key] = frameworkBuildPhase
            break
        }
    }
    
    
    func addFrameworkToCopyFilePhase(buildFileKeys: [String]) {
        guard var target = _pbxproj?.objects[key] as? [String : Any] else { return }
        guard var buildPhases = target["buildPhases"] as? [String] else { return }
        let name = _copyFrameworkName
        for (index, buildPhasesKey) in buildPhases.enumerated() {
            if let copyFilesBuildPhase = _pbxproj?.objects[buildPhasesKey] as? [String : Any], let fname = copyFilesBuildPhase["name"] as? String, fname == name {
                Log.debug("CopyFilePhase remomving:\(buildPhasesKey)")
                buildPhases.remove(at: index)
                target["buildPhases"] = buildPhases
                _pbxproj?.objects[key] = target
                _pbxproj?.objects.removeValue(forKey: buildPhasesKey)
                break
            }
        }
        let copyFilePhaseKey = PBXproj.uniqueId()
        let info: [String : Any] = [
            "isa" : "PBXCopyFilesBuildPhase",
            "buildActionMask" : "2147483647",
            "dstPath" : "",
            "dstSubfolderSpec" : "10",
            "files" : buildFileKeys,
            "name": name,
            "runOnlyForDeploymentPostprocessing" : "0"
        ]
        buildPhases.append(copyFilePhaseKey)
        target["buildPhases"] = buildPhases
        _pbxproj?.objects[copyFilePhaseKey] = info
        _pbxproj?.objects[key] = target
    }
    
    func addFrameworkToEmbededFrameworkCopyFilePhase(buildFileKeys: [String]) {
        guard var target = _pbxproj?.objects[key] as? [String : Any] else { return }
        guard var buildPhases = target["buildPhases"] as? [String] else { return }
        let name = "Embed Frameworks"
        var filesBuildPhase: [String : Any] = [:]
        var filesBuildPhaseKey = PBXproj.uniqueId()
        
        var find = false
        for buildPhasesKey in buildPhases {
            if var copyFilesBuildPhase = _pbxproj?.objects[buildPhasesKey] as? [String : Any], let fname = copyFilesBuildPhase["name"] as? String, fname == name {
                var files: [String] = []
                if let values = copyFilesBuildPhase["files"] as? [String] {
                    
                    files = values.filter({ (key) -> Bool in
                        return _pbxproj?.isTargetRef(for: key) == true
                    })
                }
                files.append(contentsOf: buildFileKeys)
                copyFilesBuildPhase["files"] = files
                filesBuildPhaseKey = buildPhasesKey
                filesBuildPhase = copyFilesBuildPhase
                find = true
                break
            }
        }
        
        if find == false {
            let info: [String : Any] = [
                "isa" : "PBXCopyFilesBuildPhase",
                "buildActionMask" : "2147483647",
                "dstPath" : "",
                "dstSubfolderSpec" : "10",
                "files" : buildFileKeys,
                "name": name,
                "runOnlyForDeploymentPostprocessing" : "0"
            ]
            filesBuildPhase = info
            buildPhases.append(filesBuildPhaseKey)
            target["buildPhases"] = buildPhases
            _pbxproj?.objects[key] = target
        }
        _pbxproj?.objects[filesBuildPhaseKey] = filesBuildPhase
        
    }
    
    func addCopyFrameworkScriptForApp(with frameworks: [String], tool: String) {
        guard var target = _pbxproj?.objects[key] as? [String : Any] else { return }
        guard var buildPhases = target["buildPhases"] as? [String] else { return }
        let name = _copyFrameworkName
        for (index, buildPhasesKey) in buildPhases.enumerated() {
            if let copyFilesBuildPhase = _pbxproj?.objects[buildPhasesKey] as? [String : Any], let fname = copyFilesBuildPhase["name"] as? String, fname == name {
                Log.debug("remomving old Script\(name):\(buildPhasesKey)")
                buildPhases.remove(at: index)
                target["buildPhases"] = buildPhases
                _pbxproj?.objects[key] = target
                _pbxproj?.objects.removeValue(forKey: buildPhasesKey)
                break
            }
        }
        let copyFrameworkScriptKey = PBXproj.uniqueId()
        let info: [String : Any] = [
            "isa" : "PBXShellScriptBuildPhase",
            "buildActionMask" : "2147483647",
            "dstPath" : "",
            "dstSubfolderSpec" : "10",
            "files" : [String](),
            "inputPaths" : frameworks,
            "outputPaths" : [String](),
            "shellPath" : "/bin/sh",
            "shellScript" : "\(tool) copy-frameworks\n#$(SRCROOT)/Carthage/Build/iOS/<name>.framework",
            "name": name,
            "runOnlyForDeploymentPostprocessing" : "0"
        ]
        buildPhases.append(copyFrameworkScriptKey)
        target["buildPhases"] = buildPhases
        _pbxproj?.objects[copyFrameworkScriptKey] = info
        _pbxproj?.objects[key] = target
    }
}
