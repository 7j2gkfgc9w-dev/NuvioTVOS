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
            // Backdrop
            Color.black.opacity(0.88)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            switch item {
            case .actor(let actor, let detail):
                actorDetailView(actor: actor, detail: detail)
            case .song(let song):
                songDetailView(song: song)
            }
        }
        .onExitCommand {
            onDismiss()
        }
    }
    
    // MARK: - Actor Detail Layout
    
    @ViewBuilder
    private func actorDetailView(actor: SceneRecognizedActor, detail: ScenePersonDetail?) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                // Top Action Bar with Dismiss button
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                            Text("Done")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                    }
                    .buttonStyle(PosterCardButtonStyle())
                    .focused($focusedButton, equals: .dismiss)
                }
                .padding(.top, 24)
                
                // Top Header: Portrait + Bio metadata
                actorHeader(actor: actor, detail: detail)
                
                // Bottom Sections: Split into Movies & Series
                if let detail {
                    if !detail.movies.isEmpty {
                        creditsSection(
                            title: "Movies",
                            count: detail.movies.count,
                            credits: detail.movies
                        )
                    }
                    
                    if !detail.series.isEmpty {
                        creditsSection(
                            title: "Series",
                            count: detail.series.count,
                            credits: detail.series
                        )
                    }
                } else if actor.tmdbId != nil {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.9)
                        Text("Loading filmography…")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 16)
                }
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 60)
        }
    }
    
    @ViewBuilder
    private func actorHeader(actor: SceneRecognizedActor, detail: ScenePersonDetail?) -> some View {
        HStack(alignment: .top, spacing: 36) {
            // Actor Portrait Card
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 200, height: 280)
                
                let imageURL = detail?.profileURL ?? actor.profileURL
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 200, height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        case .failure, .empty:
                            actorPlaceholderAvatar
                        @unknown default:
                            actorPlaceholderAvatar
                        }
                    }
                } else {
                    actorPlaceholderAvatar
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 20, y: 8)
            
            // Actor Bio Metadata
            VStack(alignment: .leading, spacing: 8) {
                Text(detail?.name ?? actor.name)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let character = actor.character, !character.isEmpty {
                    Text("as \(character)")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
                
                if let birthInfo = detail?.birthInfo {
                    Text(birthInfo)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(1)
                }
                
                if let placeOfBirth = detail?.placeOfBirth, !placeOfBirth.isEmpty {
                    Text(placeOfBirth)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(1)
                }
                
                if let bio = detail?.biography, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(4)
                        .padding(.top, 6)
                } else if detail != nil {
                    Text("No biography available.")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 6)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var actorPlaceholderAvatar: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 80, height: 80)
            .foregroundColor(.white.opacity(0.35))
    }
    
    @ViewBuilder
    private func creditsSection(
        title: String,
        count: Int,
        credits: [ScenePersonMediaCredit]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section Header with count badge
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(count)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // Horizontal poster carousel with ample vertical padding against focus clipping
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(credits) { credit in
                        SceneCreditPosterCard(credit: credit)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 16)
            }
        }
    }
    
    // MARK: - Song Detail Layout
    
    @ViewBuilder
    private func songDetailView(song: SceneRecognizedSong) -> some View {
        VStack(spacing: 24) {
            songDetailContent(song: song)
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
        .defaultFocus($focusedButton, .dismiss)
    }
    
    @ViewBuilder
    private func songDetailContent(song: SceneRecognizedSong) -> some View {
        HStack(alignment: .top, spacing: 32) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 180, height: 180)
                
                if let url = song.artworkURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 180, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                
                if let desc = song.sceneDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(3)
                        .padding(.top, 2)
                } else if let genre = song.genres.first {
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

// MARK: - Scene Credit Poster Card

private struct SceneCreditPosterCard: View {
    let credit: ScenePersonMediaCredit
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Button(action: {}) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 140, height: 210)
                    
                    if let url = credit.posterURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 140, height: 210)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            case .failure, .empty:
                                placeholderImage
                            @unknown default:
                                placeholderImage
                            }
                        }
                    } else {
                        placeholderImage
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isFocused ? Color.white.opacity(0.9) : Color.white.opacity(0.12),
                            lineWidth: isFocused ? 2.5 : 1
                        )
                )
                .shadow(
                    color: isFocused ? Color.white.opacity(0.25) : Color.black.opacity(0.4),
                    radius: isFocused ? 14 : 6,
                    y: 3
                )
                
                Text(credit.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isFocused ? .white : .white.opacity(0.85))
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
        }
        .buttonStyle(PosterCardButtonStyle())
        .focused($isFocused)
        .focusEffectDisabledIfAvailable()
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.14), value: isFocused)
        .accessibilityLabel(credit.title)
    }
    
    private var placeholderImage: some View {
        ZStack {
            Color.white.opacity(0.06)
            Image(systemName: credit.mediaType == "tv" ? "tv" : "film")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundColor(.white.opacity(0.35))
        }
        .frame(width: 140, height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
