import Foundation
import AU05Device
import Darwin

// No CGEvent or Accessibility API: this tool never emits business shortcuts.
@MainActor
func runCapture() {
    if CommandLine.arguments.contains("--list") {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(HIDInventory.interfaces()) { FileHandle.standardOutput.write(data + Data([10])) }
        return
    }
    let client: any HIDEventSource
    if let index = CommandLine.arguments.firstIndex(of: "--profile"), CommandLine.arguments.count > index + 1 {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            guard data.count <= 65536 else { throw HIDDeviceProfile.ProfileError.invalid }
            client = try GenericHIDClient(profile: JSONDecoder().decode(HIDDeviceProfile.self, from: data))
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(2)
        }
    } else { client = AU05HIDClient() }
    client.onConnection = { state in
        FileHandle.standardError.write(Data((state.title + "\n").utf8))
    }
    client.onEvent = { event in
        if let data = try? JSONEncoder().encode(event) {
            FileHandle.standardOutput.write(data + Data([10]))
        }
    }
    var signals: [DispatchSourceSignal] = []
    for number in [SIGINT, SIGTERM] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler { client.stop(); exit(0) }; source.resume(); signals.append(source)
    }
    client.start()
    if let index = CommandLine.arguments.firstIndex(of: "--duration"), CommandLine.arguments.count > index + 1,
       let seconds = Double(CommandLine.arguments[index + 1]), seconds > 0 {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { client.stop(); exit(0) }
    }
    withExtendedLifetime((client, signals)) { RunLoop.main.run() }
}
MainActor.assumeIsolated { runCapture() }
