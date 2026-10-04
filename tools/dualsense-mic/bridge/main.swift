import AppKit
import AVFoundation
import CoreAudio
import IOKit.hid

let deviceName = "VibeWand DualSense Mic"
let deviceUID = "local.vibewand.dualsense-mic.experimental"
func log(_ text: String) { print(text); fflush(stdout) }
struct Failure: Error, CustomStringConvertible { let description: String; init(_ s: String) { description=s } }
func check(_ status: OSStatus, _ action: String) throws { if status != noErr { throw Failure("\(action)：\(status)") } }

final class AudioPublisher {
    let ring = dsm_create()!
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 16384)
    let engine = AVAudioEngine()
    var source: AVAudioSourceNode?
    var tap: AudioObjectID = 0
    var aggregate: AudioObjectID = 0
    func prepare() throws {
        // A previous crashed instance can leave its public aggregate behind. The app's
        // process lock ensures this can never remove a live peer instance's device.
        var orphan:AudioObjectID=0
        var lookup=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyTranslateUIDToDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var ownUID=deviceUID as CFString
        var lookupSize=UInt32(MemoryLayout<AudioObjectID>.size)
        withUnsafePointer(to:&ownUID) { pointer in
            _=AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&lookup,UInt32(MemoryLayout<CFString>.size),pointer,&lookupSize,&orphan)
        }
        if orphan != 0 { try check(AudioHardwareDestroyAggregateDevice(orphan),"移除上次未退出的临时音频设备") }
        let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
        let ring=self.ring, scratch=self.scratch
        let source=AVAudioSourceNode(format:format) { _,_,frames,buffers in
            let count=Int(frames)
            let list=UnsafeMutableAudioBufferListPointer(buffers)
            guard count <= 16384 else { for b in list { if let p=b.mData { memset(p,0,Int(b.mDataByteSize)) } }; return noErr }
            dsm_render(ring,scratch,count)
            for b in list {
                guard let p=b.mData?.assumingMemoryBound(to:Float.self) else { continue }
                let channels=Int(b.mNumberChannels)
                for f in 0..<count { for c in 0..<channels { p[f*channels+c]=scratch[f] } }
            }
            return noErr
        }
        self.source=source; engine.attach(source); engine.connect(source,to:engine.mainMixerNode,format:format)
        try engine.start() // Silent until a successfully published, muted tap exists.
        var pid=getpid(), process:AudioObjectID=0
        var size=UInt32(MemoryLayout<AudioObjectID>.size)
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyTranslatePIDToProcessObject,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,UInt32(MemoryLayout<pid_t>.size),&pid,&size,&process),"查找本程序音频进程")
        let description=CATapDescription(stereoMixdownOfProcesses:[process])
        description.name=deviceName; description.uuid=UUID(); description.isPrivate=false; description.muteBehavior = .muted
        try check(AudioHardwareCreateProcessTap(description,&tap),"建立音频输入")
        address.mSelector=kAudioTapPropertyUID
        var uidReference:Unmanaged<CFString>?; size=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(tap,&address,0,nil,&size,&uidReference),"读取输入标识")
        guard let uidReference else { throw Failure("音频输入标识为空") }
        let uid=uidReference.takeRetainedValue()
        let composition:[String:Any]=[
            kAudioAggregateDeviceNameKey:deviceName,
            kAudioAggregateDeviceUIDKey:deviceUID,
            kAudioAggregateDeviceIsPrivateKey:false,
            kAudioAggregateDeviceIsStackedKey:false,
            kAudioAggregateDeviceTapAutoStartKey:true,
            kAudioAggregateDeviceTapListKey:[[
                kAudioSubTapUIDKey:uid as String,
                kAudioSubTapDriftCompensationKey:true
            ]]
        ]
        try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary,&aggregate),"发布麦克风")
        log("Published device=\(aggregate), tap=\(tap)")
    }
    func close() {
        dsm_enable(ring,false); engine.stop()
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate=0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap=0 }
    }
    deinit { close(); scratch.deallocate(); dsm_destroy(ring) }
}

final class GameModeLease {
    var previous:String?
    var restorationError:String?
    let candidates=["/Applications/Xcode-beta.app/Contents/Developer/usr/bin/gamepolicyctl","/Applications/Xcode.app/Contents/Developer/usr/bin/gamepolicyctl","/Library/Developer/CommandLineTools/usr/bin/gamepolicyctl"]
    var path:String?
    func run(_ arguments:[String]) throws -> String {
        guard let path else { throw Failure("未找到 Xcode 的游戏模式工具") }
        let process=Process(); process.executableURL=URL(fileURLWithPath:path); process.arguments=arguments
        let pipe=Pipe(); process.standardOutput=pipe; process.standardError=pipe
        try process.run(); let data=pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let output=String(decoding:data,as:UTF8.self)
        guard process.terminationStatus==0 else { throw Failure("游戏模式操作失败：\(output)") }
        return output
    }
    func acquire() throws {
        restorationError=nil
        path=candidates.first { FileManager.default.isExecutableFile(atPath:$0) }
        let status=try run(["game-mode","status"])
        if status.contains("currently automatic") { previous="auto" }
        else if status.contains("forced always on") { previous="on" }
        else if status.contains("forced always off") { previous="off" }
        else { throw Failure("无法确定游戏模式原设置，未改变设置") }
        _=try run(["game-mode","set","on"])
        log("Game Mode enabled; original=\(previous!)")
    }
    func release() {
        guard let old=previous else { return }
        do { _=try run(["game-mode","set",old]); log("Game Mode restored to \(old)"); previous=nil }
        catch { restorationError="游戏模式恢复失败：\(error)"; log("RESTORE FAILED: \(error)") }
    }
}

final class Microphone {
    let ring:OpaquePointer
    let gameMode=GameModeLease()
    let writer=DispatchQueue(label:"VibeWandMic.output")
    let receiver=DispatchQueue(label:"VibeWandMic.input",qos:.userInteractive)
    let legacyInput=CommandLine.arguments.contains("--legacy-main-input")
    // Owned by the input queue while activated, or by main in the legacy test.
    private var acceptingInput=false
    func snapshot()->(frames:Int,missing:Int,lastArrival:Double,level:Float) {
        let read={ (self.frames,self.missing,self.lastArrival,self.level) }
        return legacyInput ? read() : receiver.sync(execute:read)
    }
    var manager:IOHIDManager?
    var device:IOHIDDevice?
    let buffer=UnsafeMutablePointer<UInt8>.allocate(capacity:4096)
    var decoder:OpaquePointer?
    var active=false, stopping=false
    var timer:DispatchSourceTimer?
    var sequence:UInt32=0
    var frames=0, missing=0, duplicates=0, invalid=0, discontinuities=0
    var previous:Int?, lastArrival:Double=0
    var startedAt:Double=0
    var level:Float=0
    var pcm=[Int16](repeating:0,count:5760)
    var floats=[Float](repeating:0,count:5760)
    var wav:FileHandle?, wavSamples:UInt32=0
    var onFailure:((String)->Void)?
    var stopWaiters:[()->Void]=[]
    init(ring:OpaquePointer) { self.ring=ring }
    func start(record:URL? = nil) throws {
        guard !active else { return }
        if !CommandLine.arguments.contains("--no-game-mode") { try gameMode.acquire() }
        do {
            let m=IOHIDManagerCreate(kCFAllocatorDefault,IOHIDManagerOptions.independentDevices.rawValue); manager=m
            IOHIDManagerSetDeviceMatching(m,[kIOHIDVendorIDKey:0x054c,kIOHIDProductIDKey:0x0ce6,kIOHIDTransportKey:"Bluetooth"] as CFDictionary)
            let matches=IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> ?? []
            guard matches.count==1, let d=matches.first else { throw Failure("需要连接一只蓝牙 DualSense（USB 请拔出）") }
            try check(IOHIDDeviceOpen(d,IOOptionBits(kIOHIDOptionsTypeSeizeDevice)),"打开手柄")
            device=d
            var error:Int32=0; decoder=opus_decoder_create(48000,1,&error)
            guard decoder != nil,error==0 else { throw Failure("Opus 初始化失败") }
            if let record {
                guard FileManager.default.createFile(atPath:record.path,contents:Data(count:44)) else { throw Failure("无法创建本地测试录音") }
                wav=try FileHandle(forWritingTo:record); try wav?.seekToEnd(); wavSamples=0
            }
            frames=0; missing=0; duplicates=0; invalid=0; discontinuities=0; previous=nil; lastArrival=0
            stopping=false; active=true; startedAt=ProcessInfo.processInfo.systemUptime; sequence=0; dsm_enable(ring,true)
            IOHIDDeviceRegisterInputReportCallback(d,buffer,4096,{ context,result,_,_,id,bytes,count in
                guard let context,result==0,count>0 else { return }
                Unmanaged<Microphone>.fromOpaque(context).takeUnretainedValue().receive(id:id,bytes:bytes,count:Int(count))
            },Unmanaged.passUnretained(self).toOpaque())
            acceptingInput=true
            if legacyInput {
                IOHIDDeviceScheduleWithRunLoop(d,CFRunLoopGetMain(),CFRunLoopMode.commonModes.rawValue)
            } else {
                IOHIDDeviceSetDispatchQueue(d,receiver)
                IOHIDDeviceSetCancelHandler(d) { [weak self] in self?.completeStopOnMain() }
                IOHIDDeviceActivate(d)
            }
            writer.async { [self] in
                do {
                    try self.state(on:true)
                    try self.control(on:true)
                    let timer=DispatchSource.makeTimerSource(queue:self.writer)
                    timer.schedule(deadline:.now()+0.5,repeating:0.5)
                    timer.setEventHandler { [weak self] in
                        guard let self else { return }
                        do { try self.control(on:true) }
                        catch { DispatchQueue.main.async { self.onFailure?("麦克风写入失败：\(error)") } }
                    }
                    self.timer=timer; timer.resume()
                } catch { DispatchQueue.main.async { self.onFailure?("启用失败：\(error)") } }
            }
        } catch {
            if let d=device { IOHIDDeviceClose(d,0) }; device=nil; manager=nil
            if let decoder { opus_decoder_destroy(decoder); self.decoder=nil }
            gameMode.release(); throw error
        }
    }
    private func send(_ bytes:[UInt8]) throws {
        guard let d=device else { throw Failure("手柄已断开") }
        let r=bytes.withUnsafeBufferPointer { IOHIDDeviceSetReport(d,kIOHIDReportTypeOutput,CFIndex(bytes[0]),$0.baseAddress!,bytes.count) }
        try check(r,"发送音频状态")
    }
    private func state(on:Bool) throws {
        var p=[UInt8](repeating:0,count:78); p[0]=0x31; p[1]=UInt8((sequence&15)<<4); sequence+=1; p[2]=0x10
        p[3]=0xc0; p[4]=0x82; p[9]=on ? 0x40 : 0; p[10]=9; p[12]=on ? 0 : 0x10; p[40]=1
        let crc=p.withUnsafeBufferPointer { ds_crc(0xa2,$0.baseAddress,74) }
        for i in 0..<4 { p[74+i]=UInt8(truncatingIfNeeded:crc >> (8*i)) }; try send(p)
    }
    private func control(on:Bool) throws {
        var p=[UInt8](repeating:0,count:142)
        p.withUnsafeMutableBufferPointer { ds_mic_control($0.baseAddress,sequence,on) }
        p[10]=UInt8(sequence&15); p[11]=0x92; p[12]=0x40; sequence+=1
        let crc=p.withUnsafeBufferPointer { ds_crc(0xa2,$0.baseAddress,138) }
        for i in 0..<4 { p[138+i]=UInt8(truncatingIfNeeded:crc >> (8*i)) }; try send(p)
    }
    private func receive(id:UInt32,bytes:UnsafeMutablePointer<UInt8>,count:Int) {
        guard acceptingInput,let decoder else { return }
        var packet=Array(UnsafeBufferPointer(start:bytes,count:count))
        if count==77,id==0x31 { packet.insert(0x31,at:0) }
        let kind=packet.withUnsafeBufferPointer { ds_classify($0.baseAddress,$0.count) }
        if kind==DS_INVALID { invalid+=1; return }
        if kind==DS_STATE,CommandLine.arguments.contains("--headless") {
            log("CONTROL " + Data(packet).base64EncodedString())
        }
        guard kind==DS_MIC else { return }
        let now=ProcessInfo.processInfo.systemUptime, seq=Int(packet[2])
        if let previous {
            let delta=(seq-previous)&255
            if delta==0,now-lastArrival<0.5 { duplicates+=1; return }
            if delta>0,delta<=20,now-lastArrival<0.5 {
                if delta>1 {
                    missing+=delta-1
                    for _ in 1..<delta { let n=opus_decode(decoder,nil,0,&pcm,480,0); if n>0 { deliver(Int(n)) } }
                }
            } else { discontinuities+=1 }
        }
        previous=seq; lastArrival=now
        let n=packet.withUnsafeBufferPointer { opus_decode(decoder,$0.baseAddress!.advanced(by:3),71,&pcm,5760,0) }
        if n>0 { if frames==0 { log("Audio stream ready") }; frames+=1; deliver(Int(n)) } else { invalid+=1 }
    }
    private func deliver(_ count:Int) {
        var square:Float=0
        for i in 0..<count { let f=max(-1,min(1,Float(pcm[i])/32768)); floats[i]=f; square+=f*f }
        level=sqrt(square/Float(count))
        floats.withUnsafeBufferPointer { _=dsm_push(ring,$0.baseAddress,count) }
        if let wav {
            let amplified=(0..<count).map { Int16(max(-32768,min(32767,Int(floats[$0]*32767)))) }
            let data=amplified.withUnsafeBytes { Data($0) }
            do { try wav.write(contentsOf:data); wavSamples+=UInt32(count) } catch { DispatchQueue.main.async { self.onFailure?("录音写入失败") } }
        }
    }
    func stop(completion:@escaping()->Void) {
        stopWaiters.append(completion)
        guard !stopping else { return }
        stopping=true; active=false
        if legacyInput { acceptingInput=false } else { receiver.sync { acceptingInput=false } }
        writer.async { [self] in
            self.timer?.cancel(); self.timer=nil
            if self.device != nil {
                for _ in 0..<3 { do { try self.control(on:false) } catch { log("Disable failed: \(error)") }; usleep(100000) }
                do { try self.state(on:false) } catch { log("Mute failed: \(error)") }
            }
            if let d=self.device,!self.legacyInput { IOHIDDeviceCancel(d) }
            else { self.completeStopOnMain() }
        }
    }
    private func completeStopOnMain() {
        // Run-loop scheduling also works during AppKit's deferred termination.
        CFRunLoopPerformBlock(CFRunLoopGetMain(),CFRunLoopMode.commonModes.rawValue) {
            if let d=self.device {
                if self.legacyInput { IOHIDDeviceUnscheduleFromRunLoop(d,CFRunLoopGetMain(),CFRunLoopMode.commonModes.rawValue) }
                IOHIDDeviceClose(d,0)
            }
            dsm_enable(self.ring,false)
            self.device=nil; self.manager=nil
            if let decoder=self.decoder { opus_decoder_destroy(decoder); self.decoder=nil }
            self.finishWav(); self.gameMode.release(); self.stopping=false
            log("frames=\(self.frames) missing=\(self.missing) duplicates=\(self.duplicates) invalid=\(self.invalid) resets=\(self.discontinuities) underruns=\(dsm_underruns(self.ring)) overflows=\(dsm_overflows(self.ring))")
            let waiters=self.stopWaiters;self.stopWaiters=[]
            for waiter in waiters { waiter() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
    private func finishWav() {
        guard let wav else { return }
        var data=Data()
        func tag(_ s:String) { data.append(s.data(using:.ascii)!) }
        func u32(_ n:UInt32) { var v=n.littleEndian; withUnsafeBytes(of:&v) { data.append(contentsOf:$0) } }
        func u16(_ n:UInt16) { var v=n.littleEndian; withUnsafeBytes(of:&v) { data.append(contentsOf:$0) } }
        tag("RIFF");u32(36+wavSamples*2);tag("WAVEfmt ");u32(16);u16(1);u16(1);u32(48000);u32(96000);u16(2);u16(16);tag("data");u32(wavSamples*2)
        do { try wav.seek(toOffset:0); try wav.write(contentsOf:data); try wav.close() } catch { log("WAV finalize failed: \(error)") }
        self.wav=nil
    }
}

final class TapCheck {
    let device:AudioObjectID
    let queue=DispatchQueue(label:"VibeWandMic.check")
    var proc:AudioDeviceIOProcID?
    var sampleCount=0
    var square:Double=0
    var peak:Float=0
    var recording=false
    var recorded:[Float]=[]
    init(device:AudioObjectID,recording:Bool=false) { self.device=device;self.recording=recording;if recording {recorded.reserveCapacity(48000*125)} }
    func start() throws {
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc,device,queue) { [self] _,input,_,_,_ in
            let buffers=UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating:input))
            if recording,let first=buffers.first,let p=first.mData?.assumingMemoryBound(to:Float.self),recorded.count<48000*125 {
                let channels=max(1,Int(first.mNumberChannels))
                for i in stride(from:0,to:Int(first.mDataByteSize)/4,by:channels) { recorded.append(p[i]) }
            }
            for buffer in buffers {
                guard let p=buffer.mData?.assumingMemoryBound(to:Float.self) else { continue }
                for i in 0..<Int(buffer.mDataByteSize)/4 {
                    let v=p[i]; if v.isFinite { sampleCount+=1;square+=Double(v*v);peak=max(peak,abs(v)) }
                }
            }
        },"建立系统输入验证")
        try check(AudioDeviceStart(device,proc),"读取系统麦克风")
    }
    func snapshot()->(Int,Double,Float) { queue.sync { (sampleCount,sampleCount>0 ? sqrt(square/Double(sampleCount)):0,peak) } }
    func stop() { if let proc { AudioDeviceStop(device,proc);AudioDeviceDestroyIOProcID(device,proc);self.proc=nil } }
    func save(_ url:URL) {
        let values=queue.sync { recorded }
        var data=Data()
        func tag(_ s:String){data.append(s.data(using:.ascii)!)}
        func u32(_ n:UInt32){var v=n.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
        func u16(_ n:UInt16){var v=n.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
        tag("RIFF");u32(36+UInt32(values.count)*2);tag("WAVEfmt ");u32(16);u16(1);u16(1);u32(48000);u32(96000);u16(2);u16(16);tag("data");u32(UInt32(values.count)*2)
        let pcm=values.map { Int16(max(-32768,min(32767,Int(($0.isFinite ? $0 : 0)*32767)))) }
        pcm.withUnsafeBytes { data.append(contentsOf:$0) }
        do {try data.write(to:url);log("System recording samples=\(values.count)")}catch{log("System recording failed: \(error)")}
    }
    deinit { stop() }
}

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window:NSWindow!
    let label=NSTextField(wrappingLabelWithString:"正在准备系统麦克风…")
    let metrics=NSTextField(labelWithString:"")
    let button=NSButton(title:"开始",target:nil,action:nil)
    let publisher=AudioPublisher()
    lazy var mic=Microphone(ring:publisher.ring)
    var ticker:Timer?
    var quitting=false
    var lastFailure:String?
    var tapCheck:TapCheck?
    var verificationProcess:Process?
    var captureRecorder:TapCheck?
    var toneTimer:Timer?
    var stressTimer:Timer?
    var checkStart:Double=0
    var phase:Double=0
    var signals:[DispatchSourceSignal]=[]
    let verifyButton=NSButton(title:"验证系统输入",target:nil,action:nil)
    func applicationDidFinishLaunching(_ notification:Notification) {
        let menu=NSMenu();let appItem=NSMenuItem();let submenu=NSMenu()
        submenu.addItem(withTitle:"停止并退出",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appItem.submenu=submenu;menu.addItem(appItem);NSApp.mainMenu=menu
        if !CommandLine.arguments.contains("--headless") {
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:480,height:285),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="DualSense 蓝牙麦克风 · 实验版"; window.center();window.delegate=self
        let title=NSTextField(labelWithString:deviceName);title.font = .boldSystemFont(ofSize:22)
        let note=NSTextField(wrappingLabelWithString:"在语音应用中选择此麦克风。启用期间暂停手柄导航，并临时开启游戏模式；停止后恢复。不会修改默认麦克风。")
        label.font = .systemFont(ofSize:13);metrics.font = .monospacedDigitSystemFont(ofSize:12,weight:.regular)
        button.target=self;button.action=#selector(toggle); button.bezelStyle = .rounded;button.isEnabled=false
        verifyButton.target=self;verifyButton.action=#selector(verifyTap);verifyButton.bezelStyle = .rounded
        let stack=NSStackView(views:[title,label,metrics,button,verifyButton,note]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=16
        stack.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:24)])
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        }
        mic.onFailure={ [weak self] message in
            guard let self else { return }
            self.lastFailure=message; self.label.stringValue=message; self.stop()
            if CommandLine.arguments.contains("--headless") { NSApp.terminate(nil) }
        }
        for number in [SIGTERM,SIGINT,SIGHUP] {
            signal(number,SIG_IGN)
            let source=DispatchSource.makeSignalSource(signal:number,queue:.main)
            source.setEventHandler { RunLoop.main.perform { NSApp.terminate(nil) } };source.resume();signals.append(source)
        }
        do { try publisher.prepare(); label.stringValue="已发布麦克风，尚未采集声音"; button.isEnabled=true }
        catch { publisher.close();label.stringValue="准备失败：\(error)";log("Prepare failed: \(error)")
            if CommandLine.arguments.contains("--headless") { NSApp.terminate(nil) }
        }
        if CommandLine.arguments.contains("--headless"),publisher.aggregate != 0 {
            do { try mic.start(); log("BRIDGE_READY") }
            catch { log("Start failed: \(error)"); NSApp.terminate(nil) }
        }
        ticker=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in
            guard let self else{return};let stats=self.mic.snapshot();let total=stats.frames+stats.missing
            if self.mic.active && ProcessInfo.processInfo.systemUptime-max(self.mic.startedAt,stats.lastArrival)>3 {
                self.lastFailure="手柄没有继续上报声音，已停止；请按 PS 键重新连接";self.stop()
            }
            self.metrics.stringValue=String(format:"音频帧 %d   补帧 %.1f%%   电平 %.3f",stats.frames,total>0 ? Double(stats.missing)*100/Double(total):0,stats.level)
        }
        if let index=CommandLine.arguments.firstIndex(of:"--test-seconds"),index+1<CommandLine.arguments.count,let seconds=Double(CommandLine.arguments[index+1]),seconds>0,seconds<=120 {
            DispatchQueue.main.asyncAfter(deadline:.now()+2) { [self] in
                let url=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("microphone-test.wav")
                do {
                    if CommandLine.arguments.contains("--capture-system") {
                        let recorder=TapCheck(device:publisher.aggregate,recording:true);try recorder.start();captureRecorder=recorder
                    }
                    try mic.start(record:url)
                    if CommandLine.arguments.contains("--stress-ui") {
                        stressTimer=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { _ in Thread.sleep(forTimeInterval:0.25) }
                    }
                    label.stringValue="本地测试录音中：\(Int(seconds)) 秒";button.title="停止" }
                catch { captureRecorder?.stop();captureRecorder=nil;label.stringValue="启动失败：\(error)";log("Start failed: \(error)");return }
                DispatchQueue.main.asyncAfter(deadline:.now()+seconds) { [self] in stop() }
            }
        }
    }
    @objc func verifyTap() {
        guard !mic.active,!mic.stopping,verificationProcess==nil,publisher.aggregate != 0 else { return }
        // Core Audio input startup can stall on this macOS beta. Isolate the
        // diagnostic consumer so it cannot freeze the UI or own the HID device.
        let process=Process(),output=Pipe()
        process.executableURL=URL(fileURLWithPath:CommandLine.arguments[0])
        process.arguments=["--verify-system-input"]
        process.standardOutput=output;process.standardError=output
        do { try process.run() } catch { label.stringValue="验证启动失败：\(error)";return }
        verificationProcess=process;button.isEnabled=false;verifyButton.isEnabled=false
        label.stringValue="正在验证系统输入…"
        checkStart=ProcessInfo.processInfo.systemUptime;phase=0;dsm_enable(publisher.ring,true)
        toneTimer=Timer.scheduledTimer(withTimeInterval:0.01,repeats:true) { [weak self] _ in
            guard let self else{return}
            var wave=[Float](repeating:0,count:480)
            for i in wave.indices {wave[i]=Float(sin(self.phase)*0.03);self.phase+=2*Double.pi*440/48000}
            wave.withUnsafeBufferPointer { _=dsm_push(self.publisher.ring,$0.baseAddress,wave.count) }
            let timeout=ProcessInfo.processInfo.systemUptime-self.checkStart>10
            if !process.isRunning || timeout {
                self.toneTimer?.invalidate();self.toneTimer=nil;dsm_enable(self.publisher.ring,false)
                if process.isRunning {process.terminate()}
                let text=timeout ? "verification timed out" : String(data:output.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""
                self.verificationProcess=nil;self.button.isEnabled=true;self.verifyButton.isEnabled=true
                let passed=text.contains("tapCheck passed=true")
                self.label.stringValue=passed ? "系统输入验证通过，语音应用可以读取声音" : "系统输入验证未完成；可停止并重新打开实验版后重试"
                log(text)
            }
        }
    }
    @objc func toggle() {
        if mic.active { stop() } else {
            lastFailure=nil
            do { try mic.start();label.stringValue="采集中，请在语音应用中选择此麦克风";button.title="停止" }
            catch { label.stringValue="启动失败：\(error)";log("Start failed: \(error)") }
        }
    }
    func stop() {
        stressTimer?.invalidate();stressTimer=nil
        button.isEnabled=false
        mic.stop { [weak self] in
            guard let self else{return}
            if let recorder=self.captureRecorder {
                recorder.stop()
                recorder.save(URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("system-microphone-test.wav"))
                self.captureRecorder=nil
            }
            self.button.title="开始";self.button.isEnabled=true;self.label.stringValue=self.mic.gameMode.restorationError ?? self.lastFailure ?? "已停止采集，系统设置已恢复"
        }
    }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if quitting { return .terminateNow }; quitting=true;button.isEnabled=false
        stressTimer?.invalidate();stressTimer=nil
        if let process=verificationProcess,process.isRunning {process.terminate()};verificationProcess=nil
        toneTimer?.invalidate();toneTimer=nil;tapCheck?.stop();tapCheck=nil;captureRecorder?.stop();captureRecorder=nil
        mic.stop { [self] in publisher.close();NSApp.reply(toApplicationShouldTerminate:true) }
        return .terminateLater
    }
    func windowShouldClose(_ sender:NSWindow)->Bool { NSApp.terminate(nil);return false }
}
// Bounded verification runs in a separate consumer process, before the app's
// single-instance lock. It never opens HID or changes Game Mode/default input.
if CommandLine.arguments.contains("--verify-system-input") {
    do {
        // AudioObjectIDs belong to the resolving process; pass identity via UID.
        var id:AudioObjectID=0,uid=deviceUID as CFString
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyTranslateUIDToDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var size=UInt32(MemoryLayout<AudioObjectID>.size)
        let status=withUnsafePointer(to:&uid) { pointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,UInt32(MemoryLayout<CFString>.size),pointer,&size,&id)
        }
        try check(status,"查找实验麦克风")
        guard id != 0 else {throw Failure("实验麦克风不存在")}

        let reader=TapCheck(device:id);try reader.start()
        Thread.sleep(forTimeInterval:2)
        let (count,rms,peak)=reader.snapshot()
        let passed=count>=48000 && rms>0.005 && peak<0.04
        log("tapCheck passed=\(passed) count=\(count) rms=\(rms) peak=\(peak)")
        // Process exit releases the diagnostic input even if a HAL stop stalls.
        exit(passed ? 0 : 2)
    } catch { log("tapCheck failed: \(error)");exit(2) }
}
let lockPath=NSTemporaryDirectory()+"local.vibewand.dualsense-mic.experimental.lock"
let instanceLock=open(lockPath,O_CREAT|O_RDWR,0o600)
guard instanceLock>=0,flock(instanceLock,LOCK_EX|LOCK_NB)==0 else {
    fputs("VibeWand Mic is already running; refusing a second audio owner.\n",stderr);exit(1)
}
let application=NSApplication.shared
application.setActivationPolicy(CommandLine.arguments.contains("--headless") ? .prohibited : .regular)
let delegate=App();application.delegate=delegate
application.run()
