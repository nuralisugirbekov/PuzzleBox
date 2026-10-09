import SwiftUI

struct AttentionView: View {
    @State private var engine: AttentionEngine
    @Environment(\.scenePhase) private var scenePhase
    init(mode: AttentionMode) { _engine = State(initialValue: AttentionEngine(mode: mode)) }
    var body: some View {
        GameContainerView(gameID: engine.mode.id,engine:engine,centersContent:true) {
            VStack(spacing:18) {
                HStack {
                    Label(String(format:"0:%02d",Int(ceil(engine.timeLeft))),systemImage:"timer")
                    Spacer(); Text(L10n.format("Lives: %d",engine.lives))
                }.font(.headline.monospacedDigit()).foregroundStyle(GameTheme.accent)
                if !engine.started {
                    Button(L10n.text("Tap to start")) { engine.start() }.buttonStyle(.borderedProminent).tint(GameTheme.accent).foregroundStyle(.white).frame(height:300)
                } else { board.frame(minHeight:300) }
                if !engine.feedback.isEmpty { Text(L10n.text(engine.feedback)).foregroundStyle(GameTheme.accent) }
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
            VStack(spacing:28) {
                Text(L10n.text(AttentionEngine.colorNames[engine.prompt])).font(.system(size:48,weight:.heavy)).foregroundStyle(AttentionEngine.colors[engine.ink])
                optionGrid(engine.options.map { L10n.text(AttentionEngine.colorNames[$0]) })
            }
        case .missingNumber:
            VStack(spacing:24) {
                Text(engine.items.enumerated().map { $0.offset == engine.prompt ? "?" : String($0.element) }.joined(separator:"  ·  "))
                    .font(.title2.bold().monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
                optionGrid(engine.options.map(String.init))
            }
        case .whichSide:
            HStack(spacing:12) {
                ForEach(0..<2,id:\.self) { side in
                    Button { engine.choose(side) } label: {
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:4),spacing:13) {
                            ForEach(0..<engine.items[side],id:\.self) { _ in Circle().fill(side == 0 ? Color.cyan : Color.pink).frame(width:17,height:17) }
                        }.frame(maxWidth:.infinity,minHeight:220).padding(8).background(GameTheme.surfaceHigh,in:RoundedRectangle(cornerRadius:16))
                    }
                }
            }
        case .fastSort:
            VStack(spacing:24) {
                Text(String(engine.prompt)).font(.system(size:80,weight:.bold,design:.rounded)).frame(maxWidth:.infinity,minHeight:190)
                    .background(GameTheme.surfaceHigh,in:RoundedRectangle(cornerRadius:20))
                    .gesture(DragGesture(minimumDistance:20).onEnded { v in
                        if abs(v.translation.width) > abs(v.translation.height) { engine.choose(v.translation.width < 0 ? 0 : 1) }
                    })
                HStack { Button(L10n.text("Even")) { engine.choose(0) }; Spacer(); Button(L10n.text("Odd")) { engine.choose(1) } }.buttonStyle(.bordered)
            }
        default:
            let columns = engine.mode == .ascending || engine.mode == .biggestNumber ? 3 : 4
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:columns),spacing:8) {
                ForEach(engine.items.indices,id:\.self) { i in
                    Button { engine.choose(i) } label: {
                        tile(i).frame(maxWidth:.infinity).frame(height:62)
                            .background(engine.marked.contains(i) ? GameTheme.accent.opacity(0.25) : GameTheme.surfaceHigh,in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func optionGrid(_ labels: [String]) -> some View {
        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
            ForEach(labels.indices,id:\.self) { i in
                Button { engine.choose(i) } label: { Text(labels[i]).font(.title3.bold()).frame(maxWidth:.infinity).frame(height:60).background(GameTheme.surfaceHigh,in:RoundedRectangle(cornerRadius:12)) }.foregroundStyle(GameTheme.ink)
            }
        }
    }
    @ViewBuilder private func tile(_ i: Int) -> some View {
        switch engine.mode {
        case .biggestNumber,.ascending: Text(String(engine.items[i])).font(.title.bold().monospacedDigit()).foregroundStyle(engine.marked.contains(i) ? GameTheme.accent : GameTheme.ink)
        case .memoryFlash:
            Image(systemName:(engine.showing && engine.targets.contains(i)) || engine.marked.contains(i) ? "circle.fill" : "circle")
                .font(.title).foregroundStyle((engine.showing && engine.targets.contains(i)) || engine.marked.contains(i) ? GameTheme.accent : GameTheme.stroke)
        case .dontTap: Image(systemName:engine.items[i] == 0 ? "circle.fill" : "triangle.fill").font(.title).foregroundStyle(.cyan).opacity(engine.marked.contains(i) ? 0.15 : 1)
        default: Image(systemName:AttentionEngine.symbols[engine.items[i]]).font(.system(size:29,weight:.medium)).foregroundStyle(.cyan)
        }
    }
}
