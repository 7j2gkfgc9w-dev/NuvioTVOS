import SwiftUI

struct SceneDetailView: View {
    let item: SceneDetailItem
    let onDismiss: () -> Void
    
    @FocusState private var focusedButton: DetailButtonFocus?
    
    private enum DetailButtonFocus: Hashable {
        case primary
        case dismiss
    }
    
    init(item: SceneDetailItem, onDismiss: @escaping () -> Void) {
        self.item = item
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 24) {
                switch item {
                case .actor(let actor, let bio, _):
                    actorDetailContent(actor: actor, bio: bio)
                case .song(let song):
                    songDetailContent(song: song)
                }
            }
            .padding(40)
            .frame(maxWidth: 880)
            .background {
                if #available(tvOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 28))
                        .glassEffect(.regular, in: .rect(cornerRadius: 28))
                } else {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.black.opacity(0.40))
                        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 30, y: 10)
        }
        .onExitCommand {
            onDismiss()
        }
        .defaultFocus($focusedButton, .dismiss)
    }
    
    @ViewBuilder
    private func actorDetailContent(actor: SceneRecognizedActor, bio: String?) -> some View {
        HStack(alignment: .top, spacing: 32) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 160, height: 160)
                
                if let url = actor.profileURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 160, height: 160)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                } else {
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text(actor.name)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                
                if let character = actor.character, !character.isEmpty {
                    Text("as \(character)")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
                
                if let bio, !bio.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(bio)
                            .font(.system(size: 19, weight: .regular))
                            .foregroundColor(.white.opacity(0.85))
                            .lineSpacing(4)
                    }
                    .frame(maxHeight: 180)
                    .padding(.top, 4)
                } else if actor.tmdbId != nil {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading biography…")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 8)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Text("Done")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(minWidth: 140)
                        .padding(.vertical, 12)
                }
                .buttonStyle(PosterCardButtonStyle())
                .focused($focusedButton, equals: .dismiss)
            }
        }
        .frame(minHeight: 260)
    }
    
    @ViewBuilder
    private func songDetailContent(song: SceneRecognizedSong) -> some View {
        HStack(alignment: .top, spacing: 32) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 180, height: 180)
                
                if let url = song.artworkURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 180, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        } else {
                            Image(systemName: "music.note")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                } else {
                    Image(systemName: "music.note")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text(song.title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                
                Text(song.artist)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                
                if let genre = song.genres.first {
                    Text(genre)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    if let appleMusicURL = song.appleMusicURL {
                        Button(action: {
                            UIApplication.shared.open(appleMusicURL)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "applelogo")
                                Text("Open in Music")
                            }
                            .font(.system(size: 20, weight: .semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(PosterCardButtonStyle())
                        .focused($focusedButton, equals: .primary)
                    }
                    
                    Button(action: onDismiss) {
                        Text("Done")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(minWidth: 140)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(PosterCardButtonStyle())
                    .focused($focusedButton, equals: .dismiss)
                }
            }
        }
        .frame(minHeight: 240)
    }
}
