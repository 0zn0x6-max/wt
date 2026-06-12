//
//  ContentView.swift
//  WorkoutTimer
//
//  MODIFIED: Added separate Kettlebell Pyramid Timer section.
//  The original Workout Timer UI is completely unchanged.
//  New tab: "Kettlebell" with the exact 30-set structure you specified.
//

import SwiftUI
import AVFoundation

// MARK: - Phase
enum Phase {
    case setup, countdown, rest, restDone, done
}

// MARK: - Audio (unchanged)
class AudioEngine {
    static let shared = AudioEngine()
    
    func prepare() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    
    func beep(freq: Double = 880, duration: Double = 0.15, volume: Float = 0.4) {
        DispatchQueue.global(qos: .userInteractive).async {
            let sr = 44100.0
            let count = Int(sr * duration)
            var data = [Float](repeating: 0, count: count)
            for i in 0..<count {
                let t = Double(i) / sr
                data[i] = sin(2.0 * .pi * freq * t) * volume
            }
            var format = AudioStreamBasicDescription(
                mSampleRate: sr,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kLinearPCMFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 4,
                mFramesPerPacket: 1,
                mBytesPerFrame: 4,
                mChannelsPerFrame: 1,
                mBitsPerChannel: 32,
                mReserved: 0
            )
            var buffer = AudioQueueBufferRef(bitPattern: 0)
            var queue: AudioQueueRef?
            AudioQueueNewOutput(&format, { _, _, _ in }, nil, nil, nil, 0, &queue)
            guard let q = queue else { return }
            AudioQueueAllocateBuffer(q, UInt32(count * 4), &buffer)
            buffer?.pointee.mAudioDataByteSize = UInt32(count * 4)
            buffer?.pointee.mAudioData.copyMemory(from: data, byteCount: count * 4)
            AudioQueueEnqueueBuffer(q, buffer!, 0, nil)
            AudioQueueStart(q, nil)
            Thread.sleep(forTimeInterval: duration + 0.05)
            AudioQueueDispose(q, true)
        }
    }
    
    func playTick(isLast: Bool) { beep(freq: isLast ? 1100 : 660, duration: 0.08) }
    func playDone() {
        beep(freq: 880, duration: 0.1)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { self.beep(freq: 1100, duration: 0.1) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { self.beep(freq: 1320, duration: 0.15) }
    }
    func playAlarm() {
        beep(freq: 660, duration: 0.3)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) { self.beep(freq: 660, duration: 0.3) }
    }
}

// MARK: - Original Workout ViewModel (UNCHANGED)
class WorkoutViewModel: ObservableObject {
    @Published var phase: Phase = .setup
    @Published var sessionMin = 30
    @Published var restMin = 1
    @Published var enableRest = true
    @Published var rounds = 0
    @Published var elapsed = 0
    @Published var sessionLeft = 30 * 60
    @Published var restCountdown = 1 * 60
    @Published var sessionFired = false
    
    private var startDate: Date?
    private var sessionEnd: Date?
    private var restEnd: Date?
    private var ticker: Timer?
    private var tickedSeconds = Set<Int>()
    
    var sessionPct: Double {
        let total = sessionMin * 60
        guard total > 0 else { return 0 }
        return Double(sessionLeft) / Double(total)
    }
    
    var restPct: Double {
        let total = restMin * 60
        guard total > 0 else { return 0 }
        return Double(restCountdown) / Double(total)
    }
    
    func startSession() {
        AudioEngine.shared.prepare()
        sessionFired = false
        rounds = 0
        elapsed = 0
        tickedSeconds = []
        let now = Date()
        startDate = now
        sessionEnd = now.addingTimeInterval(Double(sessionMin * 60))
        sessionLeft = sessionMin * 60
        cancelTicker()
        startTicker()
        phase = .countdown
    }
    
    func roundDone() {
        AudioEngine.shared.playDone()
        rounds += 1
        if enableRest {
            let now = Date()
            restEnd = now.addingTimeInterval(Double(restMin * 60))
            restCountdown = restMin * 60
            tickedSeconds = []
            phase = .rest
        } else {
            phase = .countdown
        }
    }
    
    func startNextRound() {
        restEnd = nil
        tickedSeconds = []
        phase = .countdown
    }
    
    func finishEarly() {
        cancelTicker()
        phase = .done
    }
    
    func reset() {
        cancelTicker()
        rounds = 0
        elapsed = 0
        sessionFired = false
        startDate = nil
        sessionEnd = nil
        restEnd = nil
        phase = .setup
    }
    
    private func startTicker() {
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }
    
    private func cancelTicker() {
        ticker?.invalidate()
        ticker = nil
    }
    
    private func tick() {
        let now = Date()
        if let start = startDate {
            elapsed = max(0, Int(now.timeIntervalSince(start)))
        }
        if let end = sessionEnd {
            let remaining = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
            sessionLeft = remaining
            if remaining == 0 && !sessionFired {
                sessionFired = true
                AudioEngine.shared.playAlarm()
            }
        }
        if phase == .rest, let end = restEnd {
            let remaining = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
            restCountdown = remaining
            if remaining > 0 && remaining <= 5 && !tickedSeconds.contains(remaining) {
                tickedSeconds.insert(remaining)
                AudioEngine.shared.playTick(isLast: remaining == 1)
            }
            if remaining == 0 {
                restEnd = nil
                phase = .countdown
            }
        }
    }
}

// MARK: - Helpers (unchanged)
func formatTime(_ s: Int) -> String {
    String(format: "%02d:%02d", s / 60, s % 60)
}

func formatElapsed(_ s: Int) -> String {
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    if h > 0 { return "\(h)h \(m)m \(sec)s" }
    if m > 0 { return "\(m)m \(sec)s" }
    return "\(sec)s"
}

// MARK: - Colors (unchanged)
extension Color {
    static let accent = Color(red: 1, green: 0.42, blue: 0.21)
    static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let bg = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let bg2 = Color(red: 0.09, green: 0.09, blue: 0.09)
    static let bg3 = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let ring = Color(red: 0.118, green: 0.118, blue: 0.118)
    static let dim = Color(white: 0.33)
    static let dimmer = Color(white: 0.2)
}

// MARK: - Reusable Components (unchanged)
struct NumberInputPad: View {
    let label: String
    let min: Int
    let max: Int
    @Binding var value: Int
    @Binding var isPresented: Bool
    @State private var input: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { isPresented = false }
                    .foregroundColor(.dim)
                Spacer()
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .bold)).kerning(3)
                    .foregroundColor(.dim)
                Spacer()
                Button("Done") { commit() }
                    .foregroundColor(.accent)
                    .font(.body.weight(.bold))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(input.isEmpty ? "—" : input)
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundColor(input.isEmpty ? .dimmer : .white)
                Text("min")
                    .font(.system(size: 20)).foregroundColor(.dim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color.bg2)
            
            let keys: [[String]] = [["1","2","3"],["4","5","6"],["7","8","9"],["","0","⌫"]]
            VStack(spacing: 1) {
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(row, id: \.self) { key in
                            Button { handleKey(key) } label: {
                                Text(key)
                                    .font(.system(size: 28, weight: key == "⌫" ? .regular : .medium))
                                    .foregroundColor(key.isEmpty ? .clear : .white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                    .background(key.isEmpty ? Color.bg : Color.bg3)
                            }
                            .disabled(key.isEmpty)
                        }
                    }
                }
            }
            .background(Color(white: 0.08))
        }
        .background(Color.bg)
        .onAppear { input = "\(value)" }
    }
    
    private func handleKey(_ key: String) {
        if key == "⌫" {
            if !input.isEmpty { input.removeLast() }
        } else {
            let next = input + key
            if let n = Int(next), n <= max {
                input = next
            }
        }
    }
    
    private func commit() {
        if let n = Int(input), n >= min && n <= max {
            value = n
        }
        isPresented = false
    }
}

struct SpinBox: View {
    let label: String
    @Binding var value: Int
    let min: Int
    let max: Int
    let step: Int
    @Binding var showPad: Bool
    
    var body: some View {
        HStack {
            Button {
                if value - step >= min { value -= step }
                else { value = min }
            } label: {
                Text("−").font(.system(size: 24)).foregroundColor(.accent)
                    .frame(width: 52, height: 56)
            }
            Spacer()
            Button { showPad = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(label).font(.system(size: 12)).foregroundColor(.dim)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Color.bg2)
                .cornerRadius(8)
            }
            Spacer()
            Button {
                if value + step <= max { value += step }
                else { value = max }
            } label: {
                Text("+").font(.system(size: 24)).foregroundColor(.accent)
                    .frame(width: 52, height: 56)
            }
        }
    }
}

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Text(label).font(.system(size: 14))
            Spacer()
            Button(action: { isOn.toggle() }) {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isOn ? Color.green : Color(white: 0.22))
                        .frame(width: 51, height: 31)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 27, height: 27)
                        .padding(2)
                }
            }
        }
    }
}

struct TimerRing: View {
    let phase: Phase
    let rounds: Int
    let elapsed: Int
    let restCountdown: Int
    let restPct: Double
    let onTap: () -> Void
    
    private let size: CGFloat = 300
    private let radius: CGFloat = 138
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle().stroke(Color.ring, lineWidth: 14).frame(width: size, height: size)
                
                Circle()
                    .trim(from: 0, to: phase == .countdown ? 1.0 : CGFloat(phase == .rest ? restPct : 0))
                    .stroke(phase == .countdown ? Color.accent : Color.green,
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                
                Circle().fill(Color.bg2).frame(width: size - 28, height: size - 28)
                
                VStack(spacing: 6) {
                    switch phase {
                    case .countdown:
                        Text("Round \(rounds + 1)")
                            .font(.system(size: 11, weight: .bold)).kerning(3)
                            .textCase(.uppercase).foregroundColor(.accent)
                        Text(formatElapsed(elapsed))
                            .font(.system(size: 50, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("tap when done")
                            .font(.system(size: 12)).foregroundColor(Color(white: 0.2))
                        Text("✓").font(.system(size: 22)).foregroundColor(.green)
                    case .rest:
                        Text("Rest")
                            .font(.system(size: 12, weight: .bold)).kerning(3)
                            .textCase(.uppercase).foregroundColor(.green)
                        if restCountdown > 0 {
                            Text(formatTime(restCountdown))
                                .font(.system(size: 50, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("tap to skip")
                                .font(.system(size: 11)).foregroundColor(.dim)
                            Text("→").font(.system(size: 18)).foregroundColor(.dim)
                        } else {
                            Text("✓").font(.system(size: 40)).foregroundColor(.green)
                            Text("Rest complete")
                                .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                            Text("TAP TO START →")
                                .font(.system(size: 13, weight: .bold)).kerning(2)
                                .foregroundColor(.accent).padding(.top, 4)
                        }
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - ORIGINAL SETUP / ACTIVE / DONE VIEWS (UNCHANGED)
struct SetupView: View {
    @ObservedObject var vm: WorkoutViewModel
    @State private var showSessionPad = false
    @State private var showRestPad = false
    
    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 4) {
                Text("Workout Timer")
                    .font(.system(size: 11, weight: .bold)).kerning(3)
                    .textCase(.uppercase).foregroundColor(.accent)
                Text("Configure your session")
                    .font(.system(size: 12)).foregroundColor(.dim)
            }
            .padding(.top, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Session Duration")
                    .font(.system(size: 11, weight: .bold)).kerning(2)
                    .textCase(.uppercase).foregroundColor(.dim)
                SpinBox(label: "min", value: $vm.sessionMin, min: 5, max: 180, step: 5, showPad: $showSessionPad)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ToggleRow(label: "Rest between rounds", isOn: $vm.enableRest)
                if vm.enableRest {
                    SpinBox(label: "min", value: $vm.restMin, min: 1, max: 30, step: 1, showPad: $showRestPad)
                }
            }
            
            Spacer()
            
            Button(action: vm.startSession) {
                Text("Start Workout")
                    .font(.system(size: 14, weight: .heavy)).kerning(2)
                    .textCase(.uppercase).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color.accent).cornerRadius(16)
            }
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showSessionPad) {
            NumberInputPad(label: "Session Duration", min: 5, max: 180, value: $vm.sessionMin, isPresented: $showSessionPad)
        }
        .sheet(isPresented: $showRestPad) {
            NumberInputPad(label: "Rest Duration", min: 1, max: 30, value: $vm.restMin, isPresented: $showRestPad)
        }
    }
}

struct ActiveView: View {
    @ObservedObject var vm: WorkoutViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workout Timer")
                    .font(.system(size: 11, weight: .bold)).kerning(3)
                    .textCase(.uppercase).foregroundColor(.accent)
                Spacer()
                Button(action: vm.finishEarly) {
                    Text("Finish ✕")
                        .font(.system(size: 11, weight: .bold)).kerning(1)
                        .textCase(.uppercase)
                        .foregroundColor(Color(white: 0.53))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.bg3)
                        .cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.dimmer, lineWidth: 1))
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)
            
            VStack(spacing: 5) {
                HStack {
                    Text("Session").font(.system(size: 10, weight: .bold)).kerning(2)
                        .textCase(.uppercase).foregroundColor(.dim)
                    Spacer()
                    Text(vm.sessionFired ? "TIME'S UP" : formatTime(vm.sessionLeft))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(vm.sessionFired ? .red : Color(white: 0.67))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.13)).frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(vm.sessionFired ? Color.red : Color.accent)
                            .frame(width: geo.size.width * CGFloat(vm.sessionPct), height: 4)
                            .animation(.linear(duration: 0.25), value: vm.sessionPct)
                    }
                }.frame(height: 4)
            }
            .padding(.horizontal, 20).padding(.top, 10)
            
            HStack(spacing: 6) {
                ForEach(0..<vm.rounds, id: \.self) { _ in
                    Circle().fill(Color.accent).frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)
            
            Spacer()
            
            TimerRing(
                phase: vm.phase,
                rounds: vm.rounds,
                elapsed: vm.elapsed,
                restCountdown: vm.restCountdown,
                restPct: vm.restPct,
                onTap: {
                    if vm.phase == .countdown {
                        vm.roundDone()
                    } else if vm.phase == .rest {
                        vm.startNextRound()
                    }
                }
            )
            
            Spacer()
            
            HStack(spacing: 32) {
                StatView(label: "Rounds", value: "\(vm.rounds)")
                StatView(label: "Elapsed", value: formatElapsed(vm.elapsed))
                StatView(label: "Session", value: vm.sessionFired ? "00:00" : formatTime(vm.sessionLeft))
            }
            .padding(.horizontal, 24).padding(.bottom, 32)
            
            Button(action: vm.reset) {
                Text("New Workout").font(.system(size: 14, weight: .heavy)).kerning(2)
                    .textCase(.uppercase).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color.accent).cornerRadius(16)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }
}

struct DoneView: View {
    @ObservedObject var vm: WorkoutViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workout Timer")
                    .font(.system(size: 11, weight: .bold)).kerning(3)
                    .textCase(.uppercase).foregroundColor(.accent)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 8)
            
            Spacer()
            
            VStack(spacing: 24) {
                HStack(spacing: 6) {
                    ForEach(0..<vm.rounds, id: \.self) { _ in
                        Circle().fill(Color.accent).frame(width: 10, height: 10)
                    }
                }
                
                VStack(spacing: 18) {
                    ResultCard(label: "Rounds", value: "\(vm.rounds)", accent: Color.accent)
                    ResultCard(label: "Total Time", value: formatElapsed(vm.elapsed), accent: Color.accent)
                    ResultCard(label: "Avg / Round", value: vm.rounds > 0 ? formatElapsed(vm.elapsed / vm.rounds) : "—", accent: Color(red: 0.69, green: 0.32, blue: 0.87))
                }
                .padding(.horizontal, 24)
            }
            
            Spacer()
            
            Button(action: vm.reset) {
                Text("New Workout").font(.system(size: 14, weight: .heavy)).kerning(2)
                    .textCase(.uppercase).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color.accent).cornerRadius(16)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }
}

struct StatView: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 10, weight: .bold)).kerning(2)
                .textCase(.uppercase).foregroundColor(.dim)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(.white)
        }
    }
}

struct ResultCard: View {
    let label: String
    let value: String
    let accent: Color
    var body: some View {
        VStack(spacing: 6) {
            Text(label).font(.system(size: 10, weight: .bold)).kerning(2)
                .textCase(.uppercase).foregroundColor(.dim)
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(.white)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Color.bg3).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.dimmer, lineWidth: 1))
        .overlay(Rectangle().fill(accent).frame(height: 3), alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - KETTLEBELL SECTION (NEW - Separate from original UI)

// Define the exact 30-set structure
struct KettlebellSet {
    let number: Int
    let reps: Int
    let phase: String
}

private let kettlebellSets: [KettlebellSet] = {
    var sets: [KettlebellSet] = []
    // Sets 1-5: 5 reps each
    for i in 1...5 { sets.append(KettlebellSet(number: i, reps: 5, phase: "Foundation")) }
    // Sets 6-15: 6→15 reps (pyramid up)
    for i in 6...15 { sets.append(KettlebellSet(number: i, reps: i, phase: "Pyramid Up")) }
    // Sets 16-20: 15 reps each
    for i in 16...20 { sets.append(KettlebellSet(number: i, reps: 15, phase: "Peak")) }
    // Sets 21-25: 14→10 reps (pyramid down)
    for i in 21...25 { sets.append(KettlebellSet(number: i, reps: 25 - i + 10, phase: "Pyramid Down")) }
    // Sets 26-30: 10 reps each
    for i in 26...30 { sets.append(KettlebellSet(number: i, reps: 10, phase: "Finisher")) }
    return sets
}()

// Kettlebell specific view model
class KettlebellViewModel: ObservableObject {
    @Published var phase: Phase = .setup
    @Published var currentIndex = 0
    @Published var elapsed = 0
    @Published var restCountdown = 60
    @Published var enableRest = true
    
    private var startDate: Date?
    private var restEnd: Date?
    private var ticker: Timer?
    private var tickedSeconds = Set<Int>()
    
    var currentSet: KettlebellSet { kettlebellSets[currentIndex] }
    var totalSets: Int { kettlebellSets.count }
    var totalReps: Int { kettlebellSets.reduce(0) { $0 + $1.reps } }
    
    var restPct: Double {
        return Double(restCountdown) / 60.0
    }
    
    func start() {
        AudioEngine.shared.prepare()
        currentIndex = 0
        elapsed = 0
        restCountdown = 60
        tickedSeconds = []
        startDate = Date()
        cancelTicker()
        startTicker()
        phase = .countdown
    }
    
    func completeSet() {
        AudioEngine.shared.playDone()
        if currentIndex < kettlebellSets.count - 1 {
            currentIndex += 1
            if enableRest {
                let now = Date()
                restEnd = now.addingTimeInterval(60)
                restCountdown = 60
                tickedSeconds = []
                phase = .rest
            } else {
                phase = .countdown
            }
        } else {
            phase = .done
        }
    }
    
    func skipRest() {
        restEnd = nil
        tickedSeconds = []
        phase = .countdown
    }
    
    func finishEarly() {
        cancelTicker()
        phase = .done
    }
    
    func reset() {
        cancelTicker()
        currentIndex = 0
        elapsed = 0
        restCountdown = 60
        startDate = nil
        restEnd = nil
        phase = .setup
    }
    
    private func startTicker() {
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }
    
    private func cancelTicker() {
        ticker?.invalidate()
        ticker = nil
    }
    
    private func tick() {
        let now = Date()
        if let start = startDate {
            elapsed = max(0, Int(now.timeIntervalSince(start)))
        }
        if phase == .rest, let end = restEnd {
            let remaining = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
            restCountdown = remaining
            if remaining > 0 && remaining <= 5 && !tickedSeconds.contains(remaining) {
                tickedSeconds.insert(remaining)
                AudioEngine.shared.playTick(isLast: remaining == 1)
            }
            if remaining == 0 {
                restEnd = nil
                phase = .countdown
            }
        }
    }
}

// Kettlebell Setup View (matches original style)
struct KettlebellSetupView: View {
    @ObservedObject var vm: KettlebellViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Kettlebell")
                    .font(.system(size: 11, weight: .bold)).kerning(3)
                    .textCase(.uppercase).foregroundColor(.accent)
                Text("30-set pyramid challenge")
                    .font(.system(size: 12)).foregroundColor(.dim)
            }
            .padding(.top, 8)
            
            // Structure cards
            VStack(spacing: 6) {
                ForEach([
                    ("Foundation", "1-5", "5 reps each"),
                    ("Pyramid Up", "6-15", "6→15 reps"),
                    ("Peak", "16-20", "15 reps each"),
                    ("Pyramid Down", "21-25", "14→10 reps"),
                    ("Finisher", "26-30", "10 reps each")
                ], id: \.0) { phase, sets, reps in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(phase).font(.system(size: 13, weight: .semibold)).foregroundColor(.accent)
                            Text("Sets \(sets)").font(.system(size: 11)).foregroundColor(.dim)
                        }
                        Spacer()
                        Text(reps).font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.bg2)
                    .cornerRadius(10)
                }
            }
            
            HStack {
                Text("Total").foregroundColor(.white)
                Spacer()
                Text("\(vm.totalSets) sets · \(vm.totalReps) reps")
                    .foregroundColor(.white.opacity(0.7))
            }
            .font(.system(size: 13))
            .padding(.horizontal, 4)
            
            ToggleRow(label: "Rest between sets (60s)", isOn: $vm.enableRest)
            
            Spacer()
            
            Button(action: vm.start) {
                Text("Start Kettlebell Challenge")
                    .font(.system(size: 14, weight: .heavy)).kerning(2)
                    .textCase(.uppercase).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color.accent).cornerRadius(16)
            }
        }
        .padding(.horizontal, 24)
    }
}

// Kettlebell Active View
struct KettlebellActiveView: View {
    @ObservedObject var vm: KettlebellViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kettlebell")
                    .font(.system(size: 11, weight: .bold)).kerning(3)
                    .textCase(.uppercase).foregroundColor(.accent)
                Spacer()
                Button(action: vm.finishEarly) {
                    Text("Finish ✕")
                        .font(.system(size: 11, weight: .bold)).kerning(1)
                        .textCase(.uppercase)
                        .foregroundColor(Color(white: 0.53))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.bg3)
                        .cornerRadius(20)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)
            
            // Progress
            VStack(spacing: 5) {
                HStack {
                    Text(vm.currentSet.phase.uppercased())
                        .font(.system(size: 10, weight: .bold)).kerning(2)
                        .foregroundColor(.dim)
                    Spacer()
                    Text("Set \(vm.currentSet.number)/\(vm.totalSets)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.67))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.13)).frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accent)
                            .frame(width: geo.size.width * CGFloat(Double(vm.currentIndex + 1) / Double(vm.totalSets)), height: 4)
                    }
                }.frame(height: 4)
            }
            .padding(.horizontal, 20).padding(.top, 10)
            
            // Dots
            HStack(spacing: 6) {
                ForEach(0..<vm.currentIndex, id: \.self) { _ in
                    Circle().fill(Color.accent).frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)
            
            Spacer()
            
            // Big Ring - customized for kettlebell
            Button(action: {
                if vm.phase == .countdown {
                    vm.completeSet()
                } else if vm.phase == .rest {
                    vm.skipRest()
                }
            }) {
                ZStack {
                    Circle().stroke(Color.ring, lineWidth: 14).frame(width: 300, height: 300)
                    
                    if vm.phase == .rest {
                        Circle()
                            .trim(from: 0, to: CGFloat(vm.restPct))
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .frame(width: 300, height: 300)
                            .rotationEffect(.degrees(-90))
                    } else {
                        Circle()
                            .trim(from: 0, to: 1.0)
                            .stroke(Color.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .frame(width: 300, height: 300)
                            .rotationEffect(.degrees(-90))
                    }
                    
                    Circle().fill(Color.bg2).frame(width: 272, height: 272)
                    
                    VStack(spacing: 4) {
                        if vm.phase == .countdown {
                            Text("SET \(vm.currentSet.number)")
                                .font(.system(size: 11, weight: .bold)).kerning(3)
                                .foregroundColor(.accent)
                            Text("\(vm.currentSet.reps) reps")
                                .font(.system(size: 42, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text(vm.currentSet.phase)
                                .font(.system(size: 14)).foregroundColor(.dim)
                            Text("✓").font(.system(size: 22)).foregroundColor(.green).padding(.top, 4)
                        } else {
                            Text("Rest")
                                .font(.system(size: 12, weight: .bold)).kerning(3)
                                .foregroundColor(.green)
                            Text(formatTime(vm.restCountdown))
                                .font(.system(size: 50, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("tap to skip")
                                .font(.system(size: 11)).foregroundColor(.dim)
                        }
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 32) {
                StatView(label: "Set", value: "\(vm.currentSet.number)/\(vm.totalSets)")
                StatView(label: "Reps", value: "\(vm.currentSet.reps)")
                StatView(label: "Phase", value: vm.currentSet.phase)
            }
            .padding(.horizontal, 24).padding(.bottom, 32)
        }
    }
}

// Kettlebell Done View
struct KettlebellDoneView: View {
    @ObservedObject var vm: KettlebellViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kettlebell")
                    .font(.system(size: 11, weight: .bold)).kerning(3)
                    .textCase(.uppercase).foregroundColor(.accent)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 8)
            
            Spacer()
            
            VStack(spacing: 16) {
                Text("🏋️").font(.system(size: 52))
                Text("Challenge Complete!")
                    .font(.system(size: 22, weight: .bold))
                Text("All 30 sets • \(vm.totalReps) reps")
                    .foregroundColor(.dim)
            }
            
            VStack(spacing: 12) {
                ResultCard(label: "Sets Completed", value: "\(vm.currentIndex + 1)", accent: Color.accent)
                ResultCard(label: "Total Time", value: formatElapsed(vm.elapsed), accent: Color.accent)
                ResultCard(label: "Total Reps", value: "\(vm.totalReps)", accent: Color(red: 0.69, green: 0.32, blue: 0.87))
            }
            .padding(.horizontal, 24).padding(.top, 32)
            
            Spacer()
            
            Button(action: vm.reset) {
                Text("New Challenge").font(.system(size: 14, weight: .heavy)).kerning(2)
                    .textCase(.uppercase).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color.accent).cornerRadius(16)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }
}

// MARK: - MAIN CONTENT VIEW (MODIFIED TO INCLUDE TABS)
struct ContentView: View {
    @StateObject private var workoutVM = WorkoutViewModel()
    @StateObject private var kettlebellVM = KettlebellViewModel()
    
    @State private var selectedTab: Tab = .workout
    
    enum Tab {
        case workout, kettlebell
    }
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Tab Bar - iOS style
                HStack(spacing: 0) {
                    Button(action: { selectedTab = .workout }) {
                        Text("Workout Timer")
                            .font(.system(size: 11, weight: .bold)).kerning(3)
                            .textCase(.uppercase)
                            .foregroundColor(selectedTab == .workout ? .accent : .dim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background(selectedTab == .workout ? Color.bg2 : Color.clear)
                    
                    Button(action: { selectedTab = .kettlebell }) {
                        Text("Kettlebell")
                            .font(.system(size: 11, weight: .bold)).kerning(3)
                            .textCase(.uppercase)
                            .foregroundColor(selectedTab == .kettlebell ? .accent : .dim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background(selectedTab == .kettlebell ? Color.bg2 : Color.clear)
                }
                .background(Color.bg3)
                
                // Content
                switch selectedTab {
                case .workout:
                    switch workoutVM.phase {
                    case .setup:
                        SetupView(vm: workoutVM)
                    case .countdown, .rest, .restDone:
                        ActiveView(vm: workoutVM)
                    case .done:
                        DoneView(vm: workoutVM)
                    }
                    
                case .kettlebell:
                    switch kettlebellVM.phase {
                    case .setup:
                        KettlebellSetupView(vm: kettlebellVM)
                    case .countdown, .rest:
                        KettlebellActiveView(vm: kettlebellVM)
                    case .done:
                        KettlebellDoneView(vm: kettlebellVM)
                    case .restDone:
                        KettlebellActiveView(vm: kettlebellVM)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
