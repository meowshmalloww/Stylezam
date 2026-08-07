import SwiftUI

struct StylezamChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let scanID: UUID
    let garmentID: String
    @Binding var currentSearch: SavedProductSearch?

    @State private var draft = ""
    @State private var pendingUserText: String?
    @State private var isSending = false
    @State private var activeSearchIntent: AIShoppingSearchIntent?
    @State private var searchProgress: ProductSearchProgress = .preparing
    @State private var errorMessage: String?
    @State private var retryRequest: ChatRetryRequest?
    @FocusState private var composerFocused: Bool

    private let starterQuestions = [
        "What style is this?",
        "How would you wear it?",
        "What details stand out?",
    ]

    private var scan: SavedScan? {
        model.library.scans.first { $0.id == scanID }
    }

    private var garment: SavedGarment? {
        scan?.items.first { $0.id == garmentID }
    }

    private var garmentKey: String {
        "\(scanID.uuidString):\(garmentID)"
    }

    private var messages: [StylezamChatMessage] {
        model.library.chatMessages(for: garmentKey)
    }

    private var latestSuggestedQuestions: [String] {
        messages.last(where: { $0.role == .assistant })?.suggestedQuestions ?? []
    }

    private var latestConversationRequest: String? {
        messages.last(where: { $0.role == .user })?.text
    }

    private var isBusy: Bool {
        isSending || activeSearchIntent != nil
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        itemContext
                        shoppingActions

                        if messages.isEmpty, pendingUserText == nil {
                            conversationWelcome
                        }

                        ForEach(messages) { message in
                            chatBubble(message)
                                .id(message.id)
                        }

                        if let pendingUserText {
                            pendingBubble(pendingUserText)
                            assistantThinking
                        }

                        if !latestSuggestedQuestions.isEmpty, !isBusy {
                            followUpQuestions
                        }

                        if let activeSearchIntent {
                            searchStatus(activeSearchIntent)
                        } else if let currentSearch, currentSearch.pipeline == .privateAIText {
                            searchResultPreview(currentSearch)
                        }

                        if let errorMessage {
                            errorPanel(errorMessage)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("chat-bottom")
                    }
                    .padding(.horizontal, StylezamDesign.pageInset)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: pendingUserText) { _, _ in scrollToBottom(proxy) }
                .onChange(of: activeSearchIntent) { _, _ in scrollToBottom(proxy) }
                .onChange(of: errorMessage) { _, _ in scrollToBottom(proxy) }
            }
            .background(StylezamDesign.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .navigationTitle("Stylezam AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !messages.isEmpty {
                            Button("Clear conversation", systemImage: "trash", role: .destructive) {
                                model.library.clearChat(for: garmentKey)
                                errorMessage = nil
                                retryRequest = nil
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .disabled(messages.isEmpty)
                    .accessibilityLabel("Conversation options")
                }
            }
            .navigationDestination(for: ProductResultDTO.self) { product in
                ProductDetailView(product: product)
            }
        }
    }

    private var itemContext: some View {
        HStack(spacing: 16) {
            Group {
                if let garment, let url = model.library.cropURL(for: garment) {
                    LocalFileImage(url: url, contentMode: .fit)
                } else {
                    Color(uiColor: .tertiarySystemFill)
                        .overlay { Image(systemName: "tshirt").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 92, height: 108)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(StylezamDesign.cobalt)
                    Text("SELECTED PIECE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.05)
                        .foregroundStyle(.secondary)
                }
                Text(garment?.title.capitalized ?? "Selected piece")
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text("AI keeps this crop in context for every answer and shopping request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(uiColor: .secondarySystemBackground), StylezamDesign.cobalt.opacity(0.055)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.75)
        }
    }

    private var shoppingActions: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("Shop this look")
                    .font(.headline)
                Spacer()
                Text("1 LIVE SEARCH")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(AIShoppingSearchIntent.allCases) { intent in
                    Button {
                        runShoppingSearch(intent)
                    } label: {
                        ChatShoppingAction(intent: intent)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .opacity(isBusy && activeSearchIntent != intent ? 0.48 : 1)
                }
            }
        }
    }

    private var conversationWelcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 11) {
                assistantMark
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ask about this piece")
                        .font(.headline)
                    Text("I can identify the style, explain visible details, suggest outfits, or help refine what to shop for.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(starterQuestions.enumerated()), id: \.element) { index, question in
                    Button {
                        send(question)
                    } label: {
                        HStack(spacing: 12) {
                            Text(question)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(StylezamDesign.cobalt)
                        }
                        .frame(minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < starterQuestions.count - 1 {
                        EditorialRule()
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }

    private func chatBubble(_ message: StylezamChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 9) {
            if message.role == .assistant {
                assistantMark
            } else {
                Spacer(minLength: 54)
            }

            Text(message.text)
                .font(.body)
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(
                    message.role == .user
                        ? AnyShapeStyle(StylezamDesign.cobalt)
                        : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)),
                    in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                )

            if message.role == .assistant {
                Spacer(minLength: 26)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pendingBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 54)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(
                    StylezamDesign.cobalt,
                    in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var assistantThinking: some View {
        HStack(spacing: 9) {
            assistantMark
            ChatThinkingIndicator(
                statuses: [
                    "Looking closely at the crop",
                    "Reading visible details",
                    "Composing a useful answer",
                ]
            )
            Spacer()
        }
    }

    private var followUpQuestions: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("YOU COULD ALSO ASK")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(latestSuggestedQuestions, id: \.self) { question in
                        Button(question) { send(question) }
                            .font(.subheadline.weight(.medium))
                            .stylezamGlassButton()
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.leading, 39)
    }

    private func searchStatus(_ intent: AIShoppingSearchIntent) -> some View {
        HStack(spacing: 13) {
            ChatThinkingDots()
            VStack(alignment: .leading, spacing: 3) {
                Text(intent == .cheaper ? "Finding lower prices" : "Finding similar pieces")
                    .font(.subheadline.weight(.semibold))
                Text(searchProgress.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
    }

    private func searchResultPreview(_ search: SavedProductSearch) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: search.aiSearchIntent == .cheaper ? "tag.fill" : "square.stack.3d.up.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(StylezamDesign.cobalt, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(search.aiSearchIntent == .cheaper ? "Lower-priced options" : "Similar pieces")
                        .font(.headline)
                    Text("\(search.results.count) live matches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("See all") { dismiss() }
                    .font(.subheadline.weight(.semibold))
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(search.results.prefix(6)) { product in
                        NavigationLink(value: product) {
                            ChatProductCard(product: product)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func errorPanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("That didn’t finish", systemImage: "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 15) {
                if retryRequest != nil {
                    Button("Try again") { retryLastRequest() }
                        .font(.subheadline.weight(.semibold))
                }
                Button("Dismiss") {
                    errorMessage = nil
                    retryRequest = nil
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color.red.opacity(0.065),
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField("Message Stylezam", text: $draft, axis: .vertical)
                .focused($composerFocused)
                .lineLimit(1...5)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .onSubmit { send(nil) }
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 21, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(StylezamDesign.hairline, lineWidth: 0.75)
                }

            Button { send(nil) } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(StylezamDesign.cobalt, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy ? 0.34 : 1)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, StylezamDesign.pageInset)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var assistantMark: some View {
        Image(systemName: "sparkles")
            .font(.caption.weight(.bold))
            .foregroundStyle(StylezamDesign.cobalt)
            .frame(width: 30, height: 30)
            .background(StylezamDesign.cobalt.opacity(0.1), in: Circle())
            .accessibilityHidden(true)
    }

    private func send(_ suppliedQuestion: String?) {
        let question = (suppliedQuestion ?? draft)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy else { return }
        if suppliedQuestion == nil { draft = "" }
        composerFocused = false
        pendingUserText = question
        isSending = true
        errorMessage = nil
        retryRequest = nil

        Task { @MainActor in
            defer {
                pendingUserText = nil
                isSending = false
            }
            do {
                _ = try await model.askStylezamAI(
                    scanID: scanID,
                    garmentID: garmentID,
                    question: question
                )
            } catch {
                errorMessage = error.localizedDescription
                retryRequest = .question(question)
            }
        }
    }

    private func runShoppingSearch(_ intent: AIShoppingSearchIntent) {
        guard !isBusy else { return }
        composerFocused = false
        activeSearchIntent = intent
        searchProgress = .preparing
        errorMessage = nil
        retryRequest = nil
        let request = intent.refinementPrompt(conversationContext: latestConversationRequest)

        Task { @MainActor in
            defer { activeSearchIntent = nil }
            do {
                currentSearch = try await model.productSearch(
                    scanID: scanID,
                    garmentID: garmentID,
                    refinement: request,
                    aiSearchIntent: intent,
                    progress: { searchProgress = $0 }
                )
            } catch {
                errorMessage = error.localizedDescription
                retryRequest = .search(intent)
            }
        }
    }

    private func retryLastRequest() {
        guard let retryRequest, !isBusy else { return }
        switch retryRequest {
        case let .question(question): send(question)
        case let .search(intent): runShoppingSearch(intent)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }
}

private struct ChatThinkingIndicator: View {
    let statuses: [String]
    @State private var statusIndex = 0

    var body: some View {
        HStack(spacing: 10) {
            ChatThinkingDots()
            Text(statuses[statusIndex % max(1, statuses.count)])
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.interpolate)
                .animation(.easeInOut(duration: 0.25), value: statusIndex)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: Capsule()
        )
        .task {
            guard statuses.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1_050))
                guard !Task.isCancelled else { return }
                statusIndex = (statusIndex + 1) % statuses.count
            }
        }
    }
}

private struct ChatThinkingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(StylezamDesign.cobalt)
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase == index ? 1.35 : 0.75)
                    .opacity(phase == index ? 1 : 0.35)
            }
        }
        .frame(width: 30, height: 20)
        .animation(.spring(response: 0.34, dampingFraction: 0.68), value: phase)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(330))
                guard !Task.isCancelled else { return }
                phase = (phase + 1) % 3
            }
        }
        .accessibilityLabel("AI is working")
    }
}

private enum ChatRetryRequest {
    case question(String)
    case search(AIShoppingSearchIntent)
}

private struct ChatShoppingAction: View {
    let intent: AIShoppingSearchIntent

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: intent.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(StylezamDesign.cobalt)
                    .frame(width: 34, height: 34)
                    .background(StylezamDesign.cobalt.opacity(0.1), in: Circle())
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(intent.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(intent == .similar ? "Same visual language" : "Lower live prices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .padding(13)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 0.75)
        }
        .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct ChatProductCard: View {
    let product: ProductResultDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                ProductImage(url: product.imageURL)
                    .frame(width: 132, height: 148)
                    .padding(8)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(product.matchSummaryLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(7)
            }
            Text(product.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(product.price?.formatted ?? product.merchant)
                .font(.caption2.weight(product.price == nil ? .regular : .semibold))
                .foregroundStyle(product.price == nil ? .secondary : .primary)
                .lineLimit(1)
        }
        .frame(width: 148, alignment: .leading)
        .padding(8)
        .background(
            Color(uiColor: .tertiarySystemBackground),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
    }
}
