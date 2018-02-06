//
//  PBXproj.swift
//  XMan
//
//  Created by lincolnlaw on 2017/7/14.
//

import Foundation

final class PBXproj {
    private var _projectPath: String
    var source: [String : Any]
    
    var objects: [String : Any] {
        get { return source["objects"] as? [String : Any] ?? [:] }
        set { source["objects"] = newValue }
    }
    
    lazy var mainGroup: PBXGroup? = {
        if let mainGroupKey = _project["mainGroup"] as? String {
            return PBXGroup(pbxproj: self, key: mainGroupKey)
        }
        return nil
    }()
    
    private var _objectVersion: String? {
        return source["objectVersion"] as? String
    }
    
    private var _projectKey: String = ""
    private var _project: [String : Any] {
        if _projectKey.isEmpty == false {
            return objects[_projectKey] as? [String : Any] ?? [:]
        }
        for (key, value) in objects {
            guard let dict = value as? [String : Any], let isa = dict["isa"] as? String, isa == "PBXProject" else { continue }
            _projectKey = key
            return dict
        }
        return [:]
    }
    
    public func isTargetRef(for key: String) -> Bool {
        var nativeTargetKeys: [String] = []
        if let key = _project["productRefGroup"] as? String, let info = objects[key] as? [String : Any], let children = info["children"] as? [String] {
            nativeTargetKeys = children
        }
        if let info = objects[key] as? [String : Any], let ref = info["fileRef"] as? String {
            let result = nativeTargetKeys.contains(ref)
            return result
        }
        return false
    }
   
    private var _targets: [PBXNativeTarget] {
        guard let targetsKeys = _project["targets"] as? [String] else { return [] }
        var targets: [PBXNativeTarget] = []
        for key in targetsKeys {
            guard let info = objects[key] as? [String : Any], let name = info["name"] as? String else { continue }
            targets.append(PBXNativeTarget(pbxproj: self, key: key, name: name))
        }
        return targets
    }
    
    init(source: [String : Any], path: String) {
        self.source = source
        _projectPath = path
    }
}

extension PBXproj {
    func target(for name: String) -> PBXNativeTarget? {
        return _targets.filter { $0.name == name }.first
    }
}

// MARK: Save
extension PBXproj {
    
    private func backupPath() -> String {
        let user = ProcessInfo.processInfo.environment["USER"]
        let backup = "/Users/\(String(describing: user!))/Documents/XMan"
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: backup) == false {
                try fm.createDirectory(atPath: backup, withIntermediateDirectories: false, attributes: nil)
            }
            let final = "\(_projectPath)/project.pbxproj"
            let name = final.replacingOccurrences(of: "/", with: "_")
            let backupFile = "\(backup)/\(name)"
            return backupFile
        } catch {
            Log.error("XMan create backup path fail:\(error.localizedDescription)")
            exit(0)
        }
    }
    private func write(object: [String : Any], to path: String) {
        guard let objectVersion = object["objectVersion"] as? String else { return }
        let raw = (object as NSDictionary).description
        let url = URL(fileURLWithPath: path)
        var final = raw
        if objectVersion > "46" {
            final = "// !$*UTF8*$!\n\(raw)"
            final = replacingQuoteForKey(in: final)
            final = dealLines(in: final)
            let data = final.data(using: .utf8)
            do {
                try data?.write(to: url)
            } catch {
                print(error)
            }
        } else {
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
                let d = fix(data: data)
                try d.write(to: url)
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    private func write(to path: String) {
        write(object: source, to: path)
    }
    
    func restore() {
        do {
            let d = try Data(contentsOf: URL(fileURLWithPath: backupPath()))
            let dict = try PropertyListSerialization.propertyList(from: d, options: [], format: nil)
            if let map = dict as? [String : Any] {
                Log.debug("write to:\(_projectPath)/project.pbxproj")
                write(object: map, to: "\(_projectPath)/project.pbxproj")
                Log.info("XMan Success restore project 🎉")
            } else {
                Log.warning("no backup value")
            }
        } catch {
            Log.error("XMan restore error:\(error.localizedDescription)")
        }   
    }
    
    func backup(force: Bool = false) {
        let backupFile = backupPath()
        if force  {
            Log.info("backup project.pbxproj for first time, at \(backupFile)")
            write(to: backupFile)
            return
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: backupFile) {
            Log.debug("backup file exists, skip backup")
            return
        }
        Log.info("backup project.pbxproj for first time, at \(backupFile)")
        write(to: backupFile)
    }
    
    func save() {
        write(to: "\(_projectPath)/project.pbxproj")
    }
    
    private func fix(data: Data) -> Data {
        guard let source = String(data: data, encoding: .utf8) else { return data }
        var destination = ""
        
        for c in source.unicodeScalars {
            let raw = c.value
            if raw < 128 {
                let value = String(format: "%c", raw)
                destination += value
            } else {
                let value = String(format: "&#%u;", raw)
                destination += value
            }
        }
        return destination.data(using: .utf8)!
    }
    
    
    private func replacingQuoteForKey(in content: String) -> String {
        let keys = ["ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES", "ASSETCATALOG_COMPILER_APPICON_NAME","DEVELOPMENT_TEAM", "INFOPLIST_FILE", "LD_RUNPATH_SEARCH_PATHS","PRODUCT_BUNDLE_IDENTIFIER", "PRODUCT_NAME", "SWIFT_VERSION", "TARGETED_DEVICE_FAMILY","ALWAYS_SEARCH_USER_PATHS", "CLANG_ANALYZER_NONNULL", "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION", "CLANG_CXX_LANGUAGE_STANDARD", "CLANG_CXX_LIBRARY", "CLANG_ENABLE_MODULES", "CLANG_ENABLE_OBJC_ARC", "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING", "CLANG_WARN_BOOL_CONVERSION", "CLANG_WARN_COMMA", "CLANG_WARN_CONSTANT_CONVERSION", "CLANG_WARN_DIRECT_OBJC_ISA_USAGE", "CLANG_WARN_DOCUMENTATION_COMMENTS", "CLANG_WARN_EMPTY_BODY", "CLANG_WARN_ENUM_CONVERSION", "CLANG_WARN_INFINITE_RECURSION", "CLANG_WARN_INT_CONVERSION", "CLANG_WARN_OBJC_ROOT_CLASS", "CLANG_WARN_RANGE_LOOP_ANALYSIS", "CLANG_WARN_STRICT_PROTOTYPES", "CLANG_WARN_SUSPICIOUS_MOVE", "CLANG_WARN_UNGUARDED_AVAILABILITY", "CLANG_WARN_UNREACHABLE_CODE", "CLANG_WARN__DUPLICATE_METHOD_MATCH", "CODE_SIGN_IDENTITY", "COPY_PHASE_STRIP", "CURRENT_PROJECT_VERSION", "DEBUG_INFORMATION_FORMAT", "ENABLE_STRICT_OBJC_MSGSEND", "ENABLE_TESTABILITY", "GCC_C_LANGUAGE_STANDARD", "GCC_DYNAMIC_NO_PIC", "GCC_NO_COMMON_BLOCKS", "GCC_OPTIMIZATION_LEVEL", "GCC_PREPROCESSOR_DEFINITIONS", "GCC_WARN_64_TO_32_BIT_CONVERSION", "GCC_WARN_ABOUT_RETURN_TYPE", "GCC_WARN_UNDECLARED_SELECTOR", "GCC_WARN_UNINITIALIZED_AUTOS", "GCC_WARN_UNUSED_FUNCTION", "GCC_WARN_UNUSED_VARIABLE", "IPHONEOS_DEPLOYMENT_TARGET", "MTL_ENABLE_DEBUG_INFO", "ONLY_ACTIVE_ARCH", "SWIFT_ACTIVE_COMPILATION_CONDITIONS", "SWIFT_OPTIMIZATION_LEVEL", "VERSIONING_SYSTEM", "VERSION_INFO_PREFIX", "DEFINES_MODULE", "DYLIB_COMPATIBILITY_VERSION", "DYLIB_CURRENT_VERSION","DYLIB_INSTALL_NAME_BASE","INFOPLIST_FILE","INSTALL_PATH", "LD_RUNPATH_SEARCH_PATHS", "PRODUCT_BUNDLE_IDENTIFIER", "PRODUCT_NAME", "SKIP_INSTALL", "BUILT_PRODUCTS_DIR", "FRAMEWORK_SEARCH_PATHS", "XMAN_ADD_FRAMEWORK_KEYS", "MACOSX_DEPLOYMENT_TARGET", "CLANG_WARN_NON_LITERAL_NULL_CONVERSION", "CLANG_WARN_OBJC_LITERAL_CONVERSION", "COMBINE_HIDPI_IMAGES", "FRAMEWORK_VERSION", "ENABLE_NS_ASSERTIONS", "VALIDATE_PRODUCT"];
        let values = ["sourcecode.c.h", "sourcecode.c.objc", "wrapper.framework", "text.plist.strings", "sourcecode.cpp.objcpp", "sourcecode.cpp.cpp", "file.xib", "image.png", "wrapper.cfbundle", "archive.ar", "text.html", "text", "wrapper.pb-project", "folder", "folder.assetcatalog", "sourcecode.swift", "wrapper.application", "file.playground", "text.script.sh", "net.daringfireball.markdown", "text.plist.xml", "file.storyboard", "text.xcconfig", "wrapper.xcconfig", "wrapper.xcdatamodel", "file.strings"]
        let totalKeys = keys + values
        var final = content
        for key in totalKeys {
            let finalKey = "\"\(key)\""
            final = final.replacingOccurrences(of: finalKey, with: key)
        }
        return final
    }
    
    private func dealLines(in content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        let prefixed = ["path", "GCC_WARN_ABOUT_RETURN_TYPE", "GCC_WARN_UNINITIALIZED_AUTOS", "IPHONEOS_DEPLOYMENT_TARGET", "CLANG_WARN_UNGUARDED_AVAILABILITY", "CLANG_WARN_OBJC_ROOT_CLASS", "CLANG_WARN_DIRECT_OBJC_ISA_USAGE", "PRODUCT_BUNDLE_IDENTIFIER", "SWIFT_VERSION", "INFOPLIST_FILE", "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION", "CreatedOnToolsVersion", "MACOSX_DEPLOYMENT_TARGET"]
        var parsedLines: [String] = []
        for line in lines {
            let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let needParseName = raw.hasPrefix("name = \"") && ( raw.hasSuffix(".storyboard\";") || raw.hasSuffix(".framework\";"))
            let needParsePath = raw.hasPrefix("path = \"") && raw.hasSuffix("\";")
            var needDeal = false
            for key in prefixed {
                let finalKey = "\(key) = \""
                if needDeal == false {
                    needDeal = raw.hasSuffix(finalKey) && raw.hasSuffix("\";")
                    if needDeal {
                        break
                    }
                }
            }
            if needParseName || needParsePath || needDeal {
                var final = line
                if raw.hasPrefix("path") || raw.hasPrefix("name") || raw.hasPrefix("INFOPLIST_FILE") {
                    let left = raw.replacingOccurrences(of: " = ", with: "")
                    if left.contains("+") || left.contains("-") || left.contains(" ") {
                        if raw.contains(" = \"") == false {
                            final = line.replacingOccurrences(of: " = ", with: " = \"")
                            final = line.replacingOccurrences(of: ";", with: "\";")
                        }
                    }
                } else {
                    final = line.replacingOccurrences(of: "\"", with: "")
                    print("final:\(final)")
                    final = final.replacingOccurrences(of: "\"", with: "")
                    print("final after:\(final)")
                }
                parsedLines.append(final)
            } else {
                parsedLines.append(line)
            }
        }
        return parsedLines.joined(separator: "\n")
    }
}



extension PBXproj {
    static func uniqueId() -> String {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let final = (raw as NSString).substring(to: 24)
        return final
    }
    
    static func group(for name: String) -> [String : Any] {
        var info: [String : Any] = [:]
        info["children"] = [String]()
        info["isa"] = "PBXGroup"
        info["name"] = name
        info["sourceTree"] = "<group>"
        return info
    }
}
