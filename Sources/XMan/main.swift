//
//  main.swift
//  Carthelper
//
//  Created by lincolnlaw on 2017/7/5.
//
import Foundation
func main() {
    if CommandLine.argc < 2 {
        getXMan()?.processTarget()
    } else {
        let path = CommandLine.arguments[1]
        switch path {
        case "version": print("Carthelper version \(XMan.version)")
        case "help": Log.usage()
        case "init": XMan.initFile()
        case "restore": getXMan()?.restore()
        case "backup": getXMan()?.backup()
        default: break
        }
    }
}

func getXMan() -> XMan? {
    let target = "xman.yaml"
    guard let currnetFolder = ProcessInfo.processInfo.environment["PWD"] else { return nil }
    let contents = try? FileManager.default.contentsOfDirectory(atPath: currnetFolder)
    if contents?.contains(target) == true {
        let filePath = currnetFolder.appending("/\(target)")
        let xman = XMan(configFile: filePath)
        return xman
    } else {
        Log.error("Not Found \(target) in \(currnetFolder)")
        exit(0)
    }
}

main()
