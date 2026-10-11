import SwiftUI

struct AttentionView: View {
    @State private var engine: AttentionEngine
    @Environment(\.scenePhase) private var scenePhase
    init(mode: AttentionMode) { _engine = State(initialValue: AttentionEngine(mode: mode)) }
    var body: some View {
        GameContainerView(gameID: engine.mode.id,engine:engine,resultSummary:L10n.format("Rounds: %d",engine.round),centersContent:true) {
            VStack(spacing:18) {
                HStack(spacing:10) {
                    Label(String(format:"0:%02d",Int(ceil(engine.timeLeft))),systemImage:"timer")
                        .foregroundStyle(engine.timeLeft < 6 ? .red : GameTheme.accent)
                    if engine.multiplier > 1 {
                        Label { Text(verbatim:"×\(engine.multiplier)") } icon: { Image(systemName:"flame.fill") }
                            .foregroundStyle(.orange).transition(.scale.combined(with:.opacity))
                    }
                    Spacer()
                    HStack(spacing:2) {
                        ForEach(0..<3,id:\.self) { i in
                            Image(systemName:i < engine.lives ? "heart.fill" : "heart").foregroundStyle(i < engine.lives ? Color.pink : GameTheme.textSecondary)
                        }
                    }
                    .accessibilityElement(children:.ignore).accessibilityLabel(L10n.format("Lives: %d",engine.lives))
                }
                .font(.headline.monospacedDigit()).foregroundStyle(GameTheme.accent)
                .animation(.snappy,value:engine.multiplier)
                if !engine.started {
                    Button(L10n.text("Tap to start")) { engine.start() }.buttonStyle(.borderedProminent).tint(GameTheme.accent).foregroundStyle(.white).frame(height:300)
                } else { board.frame(minHeight:300) }
                Text(engine.feedback.isEmpty ? " " : engine.feedback)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(engine.lastCorrect ? Color.green : Color.red)
                    .contentTransition(.numericText())
                    .animation(.snappy,value:engine.feedback)
                Text(L10n.text(engine.mode.hint)).font(.footnote).foregroundStyle(GameTheme.textSecondary).multilineTextAlignment(.center)
            }
        }
        .onAppear { engine.active = scenePhase == .active }.onDisappear { engine.active = false }
        .onChange(of:scenePhase) { _,phase in engine.active = phase == .active }
        .task {
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for:.milliseconds(30)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime; engine.advance(now-last); last = now
            }
        }
    }
    @ViewBuilder private var board: some View {
        switch engine.mode {
        case .findColor:
            VStack(spacing:22) {
                // The rule banner flips colour when the word is what counts.
                Label(L10n.text(engine.askWord ? "Tap the WORD" : "Tap the INK color"),
                      systemImage:engine.askWord ? "textformat" : "paintpalette.fill")
                    .font(.headline)
                    .padding(.horizontal,16).padding(.vertical,8)
                    .foregroundStyle(.white)
                    .background(engine.askWord ? Color.orange : GameTheme.accent,in:Capsule())
                Text(L10n.text(AttentionEngine.colorNames[engine.prompt])).font(.system(size:52,weight:.heavy,design:.rounded))
                    .foregroundStyle(AttentionEngine.colors[engine.ink])
                    .id(engine.round)
                    .transition(.scale.combined(with:.opacity))
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                    ForEach(engine.options.indices,id:\.self) { i in
                        let option = engine.options[i]
                        let inkIndex = engine.optionInks.indices.contains(i) ? engine.optionInks[i] : -1
                        Button { engine.choose(i) } label: {
                            Text(L10n.text(AttentionEngine.colorNames[option])).font(.title3.bold())
                                .frame(maxWidth:.infinity).frame(height:58)
                                .foregroundStyle(inkIndex >= 0 ? AttentionEngine.colors[inkIndex] : GameTheme.ink)
                                .background(GameTheme.surfaceHigh,in:RoundedRectangle(cornerRadius:14))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .animation(.spring(duration:0.3),value:engine.round)
        default:
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:engine.columns),spacing:8) {
                ForEach(engine.items.indices,id:\.self) { i in
                    Button { engine.choose(i) } label: {
                        let item = engine.items[i]
                        Image(systemName:AttentionEngine.symbols[item.symbol])
                            .font(.system(size:engine.columns == 5 ? 24 : 28,weight:.semibold))
                            .foregroundStyle(AttentionEngine.tileColors[item.color])
                            .frame(maxWidth:.infinity).frame(height:engine.columns == 5 ? 52 : 60)
                            .background(engine.marked.contains(i) ? GameTheme.accent.opacity(0.3) : GameTheme.surfaceHigh,in:RoundedRectangle(cornerRadius:12))
                            .overlay { if engine.marked.contains(i) { RoundedRectangle(cornerRadius:12).strokeBorder(GameTheme.accent,lineWidth:2) } }
                    }.buttonStyle(.plain)
                }
            }
            .id(engine.round)
            .transition(.opacity)
        }
    }
}
