// The Swift Programming Language
// https://docs.swift.org/swift-book

import ArgumentParser
import FileProvider
import Foundation

@main
struct Configure: ParsableCommand {
    private var isProject = false
    @Option(name: .long, help: "Path to xcworkspace or xcodeproj.")
    var path: String?

    @Option(name: .shortAndLong, help: "The workspace scheme.")
    var scheme: String?

    @Option(name: .shortAndLong, help: "The project configuration.")
    var configuration: String?

    @Option(name: .shortAndLong, help: "The project name. Should include file extension.")
    var project: String

    @Option(name: .shortAndLong, help: "The workspace name. Should include file extension.")
    var workspace: String?

    @Flag(name: .shortAndLong, help: "Print status updates while counting.")
    var verbose = false

    private var projectPath: URL? {
        URL(string: CommandLine.arguments[0])?.deletingLastPathComponent()
    }

    mutating func runXCBuild() {
        let whatToBuild: String
        var command = ""
        if isProject {
            whatToBuild = "-project \(project)"
        } else {
            let workspace = self.workspace ?? getWorkspace(project: project)
            whatToBuild = "-workspace \(workspace)"
        }
        if let configuration {
            command = "-config \(configuration)"
        }
        if let scheme {
            command += " -scheme '\(scheme)'"
        }
        let cmd =
            """
            xcodebuild \(whatToBuild) -sdk ${command:ios-debug.targetSdk} -destination 'generic/platform=iOS Simulator' -scheme 'Kyivstar Debug'",
            """
    }

    mutating func run() throws {
        logs("Running with scheme: \(scheme ?? "nil")")
        logs("Running with configuration: \(configuration ?? "nil")")
        logs("Running with project: \(project)")
        logs("Running with workspace: \(workspace ?? "nil")")

        let buildDir = try getBuildDir()
        print("BUILD_DIR", buildDir)

        let appName: String?
        do {
            appName = try getAppName(appDir: getAppDir(buildDir: buildDir))
        } catch {
            if (error as NSError).code == 260 {
            } else {
                logs(error.localizedDescription)
                throw error
            }
        }
        guard let appName else {
            throw RuntimeError(
                "Can't get app name inside build dir. Run the app in simulator first. You can youse xcode to build the app."
            )
        }
        print("APP_NAME", appName)
        let bundleId = try getBundleId(buildDir: buildDir, appName: appName)
        guard let bundleId else {
            throw RuntimeError("Can't get bundle id from Info.plist")
        }
        print("BUNDLE_ID", bundleId)

        try run()
    }

    private func getAppName(appDir: String) throws -> String? {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(atPath: appDir)
        logs(files)
        guard let app = files.first(where: {
            $0.hasSuffix(".app")
        }) else {
            return nil
        }
        return "\(app)"
    }

    private func getBundleId(buildDir: String, appName: String) throws -> String? {
        struct BundleID: Codable {
            let CFBundleIdentifier: String
        }

        let plistPath = "\(buildDir)/\(appName)/Info.plist"
        let plistURL = URL(filePath: plistPath)
        do {
            let data = try Data(contentsOf: plistURL)
            let decoder = PropertyListDecoder()
            let bundle = try decoder.decode(BundleID.self, from: data)
            return bundle.CFBundleIdentifier
        } catch {
            throw RuntimeError("Error decoding Plist file: \(error)")
        }
    }

    private mutating func getBuildDir() throws -> String {
        let workspace = try self.workspace ?? getWorkspace(project: project)
        let command = try getCommand()
        let cmd = """
        xcodebuild -showBuildSettings -workspace '\(workspace)' \(command) | grep "\\bBUILD_DIR =" | head -1 | awk -F" = " '{{print $2}}' | tr -d '"'
        """
        let output = shell(cmd).split(separator: "\n").last!
        let cmdPath = try getCommandPath()
        return output + "/" + cmdPath + "-iphonesimulator"
    }

    private func getAppDir(buildDir: String) throws -> String {
        let cmdPath = try getCommandPath()
        return buildDir + "/" + cmdPath + "-iphonesimulator"
    }

    private func getCommand() throws -> String {
        guard let scheme = scheme ?? configuration else {
            throw RuntimeError("Can't get command. Please specify scheme or configuration.")
        }
        return "-scheme " + "'\(scheme)'"
    }

    private func getCommandPath() throws -> String {
        if isProject {
            return configuration ?? "Debug"
        } else {
            return scheme ?? "Debug"
        }
    }

    private mutating func getWorkspace(project: String?) throws -> String {
        let fileManager = FileManager.default

        if let project {
            isProject = true
            return project + "/project.xcworkspace"
        } else {
            let currentPath = fileManager.currentDirectoryPath

            let workspaces = try! fileManager.contentsOfDirectory(atPath: currentPath)
                .filter { $0.hasSuffix(".xcworkspace") }
            if workspaces.count > 1 {
                throw RuntimeError("there are multiple xcworkspace in pwd, please specify one")
            } else if let workspace = workspaces.first {
                return workspace
            }

            let projectDirs = try! fileManager.contentsOfDirectory(atPath: currentPath)
                .filter { $0.hasSuffix(".xcodeproj") }
            let projects = projectDirs.compactMap { dir in
                try? fileManager.contentsOfDirectory(atPath: "\(currentPath)/\(dir)")
                    .filter { $0.hasSuffix(".xcworkspace") }
            }

            if projects.count > 1 {
                throw RuntimeError("there are multiple xcodeproj in pwd, please specify one")
            } else if let project = projects.first {
                return project.first!
            }

            throw RuntimeError("there no xcworkspace or xcodeproj in pwd, please specify one")
        }
    }

    private func shell(_ command: String) -> String {
        guard let path else { return "Can't get path" }
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", "cd \(path)&&\(command)"]
        task.launchPath = "/bin/zsh"
        task.standardInput = nil
        task.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!

        return output
    }

    private func logs(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        if verbose {
            print(items, separator: separator, terminator: terminator)
        }
    }
}

extension MutableCollection {
    subscript(safe index: Index) -> Element? {
        get {
            indices.contains(index) ? self[index] : nil
        }

        set(newValue) {
            if let newValue, indices.contains(index) {
                self[index] = newValue
            }
        }
    }
}

struct RuntimeError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
