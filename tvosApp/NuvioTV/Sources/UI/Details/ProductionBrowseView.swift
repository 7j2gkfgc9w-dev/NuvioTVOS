import SwiftUI

/// Full catalog of titles from a production company or network.
struct ProductionBrowseView: View {
    let company: MetaCompany
    let onSelect: (RelatedTitle) -> Void
    let onBack: () -> Void

    @State private var titles: [RelatedTitle] = []
    @State private var networkBrowse: TmdbNetworkBrowseData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @AppStorage(SettingsKey.amoled) private var amoled = false
    @AppStorage(SettingsKey.bodyColor) private var bodyColor = SettingsBackground.charcoal.rawValue

    var body: some View {
        ZStack {
            Color.nuvioBackground(amoled: amoled, body: bodyColor)
                .ignoresSafeArea()

            CompanyBrowseContent(
                company: company,
                data: networkBrowse,
                providedRails: company.kind == .network ? (networkBrowse?.rails ?? []) : productionRails,
                fallbackTitles: titles,
                isLoading: isLoading,
                errorMessage: errorMessage,
                onSelect: onSelect
            )

        }
        .onExitCommand(perform: onBack)
        .task(id: company.id) {
            await load()
        }
    }

    private var productionRails: [TmdbNetworkBrowseRail] {
        let series = titles.filter { $0.type == "series" }
        let movies = titles.filter { $0.type == "movie" }
        var rails: [TmdbNetworkBrowseRail] = []
        if !series.isEmpty {
            rails.append(TmdbNetworkBrowseRail(id: "series", title: L10n.string("details_series_popular", fallback: "Series • Popular"), items: series))
        }
        if !movies.isEmpty {
            rails.append(TmdbNetworkBrowseRail(id: "movies", title: L10n.string("details_movies_popular", fallback: "Movies • Popular"), items: movies))
        }
        if rails.isEmpty && !titles.isEmpty {
            rails.append(TmdbNetworkBrowseRail(id: "titles", title: L10n.string("details_titles_popular", fallback: "Titles • Popular"), items: titles))
        }
        return rails
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        networkBrowse = nil
        let results: [RelatedTitle]
        if company.kind == .network {
            let browse = await TmdbDetailsService.fetchNetworkBrowse(company: company)
            networkBrowse = browse
            if let browse, !browse.rails.isEmpty {
                results = browse.rails.flatMap(\.items)
            } else {
                results = await TmdbDetailsService.discoverTitles(company: company)
            }
        } else {
            results = await TmdbDetailsService.discoverTitles(company: company)
        }
        titles = results
        isLoading = false
    }
}

/// Company catalog presentation matching the Android TV layout: a cinematic
/// identity hero followed by horizontally scrolling title rails.
private struct CompanyBrowseContent: View {
    let company: MetaCompany
    let data: TmdbNetworkBrowseData?
    let providedRails: [TmdbNetworkBrowseRail]
    let fallbackTitles: [RelatedTitle]
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (RelatedTitle) -> Void

    @FocusState private var placeholderFocused: Bool
    @State private var scrollOffset: CGFloat = 0
    @AppStorage(SettingsKey.amoled) private var amoled = false
    @AppStorage(SettingsKey.bodyColor) private var bodyColor = SettingsBackground.charcoal.rawValue

    private var displayName: String { data?.name ?? company.name }
    private var logoURL: String? { data?.logoURL ?? company.logoURL }
    private var usesWhiteLogo: Bool {
        company.kind == .network && displayName.localizedCaseInsensitiveContains("apple")
    }

    private var rails: [TmdbNetworkBrowseRail] {
        if !providedRails.isEmpty { return providedRails }
        guard !fallbackTitles.isEmpty else { return [] }
        return [TmdbNetworkBrowseRail(
            id: "popular",
            title: company.kind == .network
                ? L10n.string("details_series_popular", fallback: "Series • Popular")
                : L10n.string("details_titles_popular", fallback: "Titles • Popular"),
            items: fallbackTitles
        )]
    }

    private var backdropURL: URL? {
        guard let item = rails.first?.items.first,
              let string = item.backdropURL ?? item.posterURL else { return nil }
        return URL(string: string)
    }

    private var scrollShadowProgress: CGFloat {
        min(max(scrollOffset / 120, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .top) {
            backdrop

            Color.black
                .opacity(0.78 * scrollShadowProgress)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: CompanyBrowseScrollOffsetKey.self,
                                value: geometry.frame(in: .named("company-browse-scroll")).minY
                            )
                    }
                    .frame(height: 0)

                    hero

                    if isLoading {
                        ProgressView()
                            .scaleEffect(1.6)
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 30, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else if rails.isEmpty {
                        Text(L10n.format("details_no_titles_found_for", fallback: "No titles found for %@", displayName))
                            .font(.system(size: 30, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ForEach(rails) { rail in
                            NetworkBrowseRail(rail: rail, onSelect: onSelect)
                        }
                    }
                }
                .padding(.bottom, 70)
            }
            .focusSection()
            .coordinateSpace(name: "company-browse-scroll")
            .modifier(CompanyBrowseScrollTracker(offset: $scrollOffset))

            CompanyBrowseScrollTransitionShadow(progress: scrollShadowProgress)

            if isLoading || rails.isEmpty {
                placeholderFocusAnchor
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var backdrop: some View {
        let backdropColor = Color.nuvioBackground(amoled: amoled, body: bodyColor)

        return ZStack {
            if let backdropURL {
                AsyncImage(url: backdropURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
                // Match TvDetailsBackdrop: the artwork fills the entire
                // screen layer, so its crop starts at the same vertical point
                // instead of being constrained to the hero's shorter frame.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                backdropColor
            }

            GeometryReader { proxy in
                LinearGradient(
                    stops: [
                        .init(color: backdropColor.opacity(0.95), location: 0),
                        .init(color: backdropColor.opacity(0.86), location: 0.25),
                        .init(color: backdropColor.opacity(0.64), location: 0.50),
                        .init(color: backdropColor.opacity(0.34), location: 0.70),
                        .init(color: backdropColor.opacity(0.10), location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: proxy.size.width * 0.76)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 50) {
            VStack(alignment: .leading, spacing: 12) {
                Text(company.kind == .network
                     ? L10n.string("tmdb_entity_kind_network", fallback: "Network")
                     : L10n.string("details_production", fallback: "Production"))
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))

                Text(displayName)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                let location = [data?.headquarters, data?.originCountry]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                if !location.isEmpty {
                    Text(location)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 20)

            if let logoURL, let url = URL(string: logoURL) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        if usesWhiteLogo {
                            image
                                .renderingMode(.template)
                                .resizable()
                                .foregroundColor(.white)
                                .scaledToFit()
                        } else {
                            image
                                .resizable()
                                .scaledToFit()
                        }
                    } else {
                        Text(displayName)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 520, height: 190)
            }
        }
        .padding(.horizontal, 80)
        .padding(.top, 72)
        .frame(maxWidth: .infinity, minHeight: 390, alignment: .bottom)
    }

    private var placeholderFocusAnchor: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .focusable(true)
            .focused($placeholderFocused)
            .focusEffectDisabledIfAvailable()
            .onAppear {
                DispatchQueue.main.async { placeholderFocused = true }
            }
    }
}

private struct CompanyBrowseScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CompanyBrowseScrollTracker: ViewModifier {
    @Binding var offset: CGFloat

    func body(content: Content) -> some View {
        if #available(tvOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newOffset in
                offset = max(0, newOffset)
            }
        } else {
            content.onPreferenceChange(CompanyBrowseScrollOffsetKey.self) { minY in
                offset = max(0, -minY)
            }
        }
    }
}

private struct CompanyBrowseScrollTransitionShadow: View {
    let progress: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .black.opacity(0.34 * progress),
                    .black.opacity(0.12 * progress),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 72)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct NetworkBrowseRail: View {
    let rail: TmdbNetworkBrowseRail
    let onSelect: (RelatedTitle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(rail.title)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: TmdbBrowseGridMetrics.posterGap) {
                    ForEach(rail.items) { title in
                        ProductionBrowseCard(title: title) {
                            onSelect(title)
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 12)
            }
            .scrollClipDisabledIfAvailable()
        }
    }
}

/// Movies and series associated with a TMDB actor, director, or creator.
struct PersonBrowseView: View {
    let person: TmdbPersonMetadata
    let onSelect: (RelatedTitle) -> Void
    let onBack: () -> Void

    @State private var detail: ScenePersonDetail? = nil
    @State private var isLoading: Bool = true
    @FocusState private var focusedCreditId: String?
    @FocusState private var placeholderFocused: Bool
    @AppStorage(SettingsKey.amoled) private var amoled = false
    @AppStorage(SettingsKey.bodyColor) private var bodyColor = SettingsBackground.charcoal.rawValue

    var body: some View {
        ZStack {
            Color.nuvioBackground(amoled: amoled, body: bodyColor)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    // Top Bar with Back Button
                    HStack {
                        Button(action: onBack) {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Back")
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
                        
                        Spacer()
                    }
                    .padding(.top, 24)

                    // Header Section: Large Portrait + Biography Metadata
                    headerSection

                    // Filmography Sections: Split into Movies & Series
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

                        if detail.movies.isEmpty && detail.series.isEmpty {
                            Text(L10n.format("details_no_titles_found_for_person", fallback: "No movies or series found for %@", person.name))
                                .font(.system(size: 26, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.top, 40)
                        }
                    } else if isLoading {
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

            if detail == nil && !isLoading {
                placeholderFocusAnchor
            }
        }
        .onExitCommand(perform: onBack)
        .task(id: person.id) {
            isLoading = true
            let provider = TmdbSceneCastProvider()
            detail = await provider.fetchPersonDetail(for: person)
            isLoading = false
            if let firstMovie = detail?.movies.first {
                focusedCreditId = firstMovie.id
            } else if let firstSeries = detail?.series.first {
                focusedCreditId = firstSeries.id
            }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(alignment: .top, spacing: 36) {
            // Actor Portrait Card
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 200, height: 280)

                let profileURL = detail?.profileURL ?? person.profileURL.flatMap(URL.init)
                if let profileURL {
                    AsyncImage(url: profileURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 200, height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        case .failure, .empty:
                            personFallback
                        @unknown default:
                            personFallback
                        }
                    }
                } else {
                    personFallback
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 20, y: 8)

            // Actor Bio Metadata
            VStack(alignment: .leading, spacing: 8) {
                Text(detail?.name ?? person.name)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let role = person.role, !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("as \(role)")
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
                } else if isLoading {
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

    @ViewBuilder
    private func creditsSection(
        title: String,
        count: Int,
        credits: [ScenePersonMediaCredit]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)

                Text("\(count)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(credits) { credit in
                        PersonCreditPosterCard(credit: credit) {
                            onSelect(credit.asRelatedTitle)
                        }
                        .focused($focusedCreditId, equals: credit.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 16)
            }
        }
    }

    private var personFallback: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 80, height: 80)
            .foregroundColor(.white.opacity(0.35))
    }

    private var placeholderFocusAnchor: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .focusable(true)
            .focused($placeholderFocused)
            .focusEffectDisabledIfAvailable()
            .onAppear {
                DispatchQueue.main.async { placeholderFocused = true }
            }
    }
}

// MARK: - Person Credit Poster Card

private struct PersonCreditPosterCard: View {
    let credit: ScenePersonMediaCredit
    let onSelect: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
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
        .titleActionsContextMenu(
            meta: credit.asRelatedTitle.asMeta,
            onOpenDetails: onSelect
        )
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

private enum TmdbBrowseGridMetrics {
    static let posterWidth: CGFloat = 210
    static let posterHeight: CGFloat = 315
    static let posterGap: CGFloat = 28

    static var columns: [GridItem] {
        [GridItem(
            .adaptive(minimum: posterWidth, maximum: posterWidth),
            spacing: posterGap,
            alignment: .top
        )]
    }
}

private struct ProductionBrowseCard: View {
    let title: RelatedTitle
    let alwaysShowLabels: Bool
    let onSelect: () -> Void

    @FocusState private var isFocused: Bool
    @AppStorage(SettingsKey.posterLabels) private var posterLabels = false
    @AppStorage(SettingsKey.smoothFocus) private var smoothFocus = true
    @AppStorage(SettingsKey.focusHighlighter) private var focusHighlighter = false
    @AppStorage(SettingsKey.cardCornerRadius) private var cardCornerRadiusSetting = AppCardStyle.defaultCornerRadiusRaw
    @AppStorage(SettingsKey.liquidGlassCards) private var liquidGlassCards = true

    private var cardCornerRadius: CGFloat {
        AppCardStyle.cornerRadius(for: cardCornerRadiusSetting, fallback: 16)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }

    init(
        title: RelatedTitle,
        alwaysShowLabels: Bool = false,
        onSelect: @escaping () -> Void
    ) {
        self.title = title
        self.alwaysShowLabels = alwaysShowLabels
        self.onSelect = onSelect
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    shape
                        .fill(Color.white.opacity(0.08))
                    if let poster = title.posterURL, let url = URL(string: poster) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                        .frame(width: TmdbBrowseGridMetrics.posterWidth, height: TmdbBrowseGridMetrics.posterHeight)
                        .clipped()
                    } else {
                        Image(systemName: "film")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(width: TmdbBrowseGridMetrics.posterWidth, height: TmdbBrowseGridMetrics.posterHeight)
                .clipShape(shape)
                .modifier(
                    LiquidGlassCardModifier(
                        cornerRadius: cardCornerRadius,
                        isFocused: isFocused,
                        isEnabled: liquidGlassCards
                    )
                )
                .overlay(
                    shape.stroke(
                        isFocused ? AppFocusOutline.color : .clear,
                        lineWidth: focusHighlighter ? AppFocusOutline.emphasizedWidth : AppFocusOutline.width
                    )
                )
                .shadow(
                    color: .black.opacity(isFocused ? 0.5 : 0.2),
                    radius: isFocused ? 16 : 6
                )

                if posterLabels || alwaysShowLabels {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title.name)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isFocused ? .white : .white.opacity(0.78))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                    .frame(width: TmdbBrowseGridMetrics.posterWidth, alignment: .leading)
                }
            }
        }
        .buttonStyle(PosterCardButtonStyle())
        .focused($isFocused)
        .focusEffectDisabledIfAvailable()
        .titleActionsContextMenu(
            meta: title.asMeta,
            onOpenDetails: onSelect
        )
        .scaleEffect(isFocused ? 1.06 : 1)
        .animation(smoothFocus ? .spring(response: 0.28, dampingFraction: 0.75) : nil, value: isFocused)
        .zIndex(isFocused ? 1 : 0)
    }

    private var subtitle: String {
        var parts = [title.type == "series" ? "Series" : "Movie"]
        if let year = title.year { parts.append(year) }
        if let rating = title.rating, rating > 0 {
            parts.append(String(format: "★ %.1f", rating))
        }
        return parts.joined(separator: "  ·  ")
    }
}
