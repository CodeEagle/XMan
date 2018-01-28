//
//  PBXGroup.swift
//  XMan
//
//  Created by lincolnlaw on 2017/7/14.
//

import Foundation
final class PBXGroup {
    private weak var _pbxproj: PBXproj?
    private(set) var key: String
    init(pbxproj: PBXproj, key: String) {
        self.key = key
        _pbxproj = pbxproj
    }
    
    func createSubGroup(for name: String) -> PBXGroup? {
        guard let project = _pbxproj else { return nil }
        guard var group = _pbxproj?.objects[key] as? [String : Any], var children = group["children"] as? [String] else { return nil }
        for child in children {
            guard let info = _pbxproj?.objects[child] as? [String : Any], let groupName = info["name"] as? String, name == groupName else { continue }
            return PBXGroup(pbxproj: project, key: child)
        }
        let singleGroup = PBXproj.group(for: name)
        let groupKey = PBXproj.uniqueId()
        children.append(groupKey)
        group["children"] = children
        _pbxproj?.objects[key] = group
        _pbxproj?.objects[groupKey] = singleGroup
        return PBXGroup(pbxproj: project, key: groupKey)
    }
    
    
    func addCopyDylibScript(dylibPaths: Set<String>, toTraget target: PBXNativeTarget, copyPaths: [String]) {
        guard var group = _pbxproj?.objects[key] as? [String : Any] else { return }
        guard var children = group["children"] as? [String] else { return }
        let type = "compiled.mach-o.dylib"
        let attributes = ["CodeSignOnCopy"]
        var keysToAdd = [String]()
        for item in dylibPaths {
            guard let (_, fileRef) = fileReferrenceForCommonFile(with: item, type: type) else { continue }
//            target.addFrameworkToFrameworkBuildPhase(buildFileKey: buildKey, fileRef: fileRef)
            guard let (toAddedKey, _) = fileReferrenceForCommonFile(with: item, type: type, customAttributes: attributes) else { continue }
            keysToAdd.append(toAddedKey)
            if children.contains(fileRef) == false {
                children.append(fileRef)
            }
        }
        target.addCopyDylibs(buildFileKeys: keysToAdd)
        group["children"] = children
        _pbxproj?.objects[key] = group
        //compiled.mach-o.dylib type
        //CodeSignOnCopy
    }
    
    @discardableResult private func fileReferrenceForCommonFile(with path: String, type: String, customAttributes: [String]? = nil) -> (String, String)? {
        guard let objects = _pbxproj?.objects else { return nil }
        var final: [String : Any] = [:]
        let name = (path as NSString).lastPathComponent
        let fileKey: String =  PBXproj.uniqueId()
        var fileRef: String = ""
        for (key, value) in objects {
            guard let object = value as? [String : Any], let isa = object["isa"] as? String, isa == "PBXFileReference", let lastKnownFileType = object["lastKnownFileType"] as? String, lastKnownFileType == type, let fname = object["name"] as? String, fname == name, let fpath = object["path"] as? String, path == fpath else { continue }
            final["isa"] = "PBXBuildFile"
            final["fileRef"] = key
            fileRef = key
        }
        if final.count == 0 {
            let id = PBXproj.uniqueId()
            //{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Alamofire.framework; path = Carthage/Build/iOS/Alamofire.framework; sourceTree = "<group>"; };
            var ref: [String : Any] = [:]
            ref["isa"] = "PBXFileReference"
            ref["lastKnownFileType"] = type
            ref["name"] = name
            ref["path"] = path
            ref["sourceTree"] = "<group>"
            _pbxproj?.objects[id] = ref
            fileRef = id
            
            //{isa = PBXBuildFile; fileRef = 2E30F32F7DEBB2FCA65776C3 /* Persistence.framework */; };
            final["isa"] = "PBXBuildFile"
            final["fileRef"] = id
        }
        if let attr = customAttributes {
            final["settings"] = ["ATTRIBUTES" : attr]
        }
        _pbxproj?.objects[fileKey] = final
        return (fileKey, fileRef)
    }
    
    /// addFrameworks
    ///
    /// - Parameter info: [FrameworkPath]
    func addFrameworks(infos: [String], toTraget target: PBXNativeTarget, copyTool: String, copyPaths: [String], isMac: Bool) {
        // 1 search framework, if not have, add, if has, create referrence
        // 2 search buildPhases of target, get `PBXFrameworksBuildPhase`, add step 1 file reference to `files`
        // 3 update key of `PBXFrameworksBuildPhase` in objects
        // 4 add buildkey to children
        
        guard var group = _pbxproj?.objects[key] as? [String : Any] else { return }
        guard var children = group["children"] as? [String] else { return }
        var testsTargetKeys: [String] = []
        let isTests = target.isTests
        for item in infos {
            guard let (buildKey, fileRef) = fileRefForFramework(for: item, isTestTarget: false) else { continue }
            target.addFrameworkToFrameworkBuildPhase(buildFileKey: buildKey, fileRef: fileRef)
            if isTests || isMac {
                guard let (buildKey, _) = fileRefForFramework(for: item, isTestTarget: true) else { continue }
                testsTargetKeys.append(buildKey)
            }
            if children.contains(fileRef) == false {
                children.append(fileRef)
            }
        }
        if isTests {
            target.addFrameworkToCopyFilePhase(buildFileKeys: testsTargetKeys)
        }
        if target.isApp {
            if isMac {
                target.addFrameworkToEmbededFrameworkCopyFilePhase(buildFileKeys: testsTargetKeys)
            } else {
                target.addCopyFrameworkScriptForApp(with: copyPaths, tool: copyTool)
            }
            
        }
        group["children"] = children
        _pbxproj?.objects[key] = group
        
        // 96FD81F0B67B803FF6257521 /* Alamofire.framework */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = wrapper.framework; name = Alamofire.framework; path = /Luoo/NetCore/Carthage/Build/iOS/Alamofire.framework; sourceTree = "<group>"; };
        
    }
    
    /// fileRefForFramework
    ///
    /// - Parameter path: framework path
    /// - Returns: PBXBuildFile's key and PBXFileReference'key
    private func fileRefForFramework(for path: String, isTestTarget: Bool) -> (String, String)? {
        guard let objects = _pbxproj?.objects else { return nil }
        var final: [String : Any] = [:]
        let name = (path as NSString).lastPathComponent
        let fileKey: String =  PBXproj.uniqueId()
        var fileRef: String = ""
        for (key, value) in objects {
            guard let object = value as? [String : Any], let isa = object["isa"] as? String, isa == "PBXFileReference", let lastKnownFileType = object["lastKnownFileType"] as? String, lastKnownFileType == "wrapper.framework", let fname = object["name"] as? String, fname == name, let fpath = object["path"] as? String, path == fpath else { continue }
            final["isa"] = "PBXBuildFile"
            final["fileRef"] = key
            fileRef = key
        }
        if final.count == 0 {
            let id = PBXproj.uniqueId()
            //{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Alamofire.framework; path = Carthage/Build/iOS/Alamofire.framework; sourceTree = "<group>"; };
            var ref: [String : Any] = [:]
            ref["isa"] = "PBXFileReference"
            ref["lastKnownFileType"] = "wrapper.framework"
            ref["name"] = name
            ref["path"] = path
            ref["sourceTree"] = "<group>"
            _pbxproj?.objects[id] = ref
            fileRef = id
            
            //{isa = PBXBuildFile; fileRef = 2E30F32F7DEBB2FCA65776C3 /* Persistence.framework */; };
            final["isa"] = "PBXBuildFile"
            final["fileRef"] = id
        }
        if isTestTarget {
            final["settings"] = ["ATTRIBUTES" : ["CodeSignOnCopy", "RemoveHeadersOnCopy"]]
        }
        _pbxproj?.objects[fileKey] = final
        return (fileKey, fileRef)
    }
}
