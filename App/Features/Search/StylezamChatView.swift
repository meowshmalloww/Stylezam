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
    @FocusState private var composerFocused: Bool

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
                    LazyVStack(alignment: .leading, spacing: 18) {
                        itemContext
                        shoppingActions

                        if messages.isEmpty, pendingUserText == nil {
                            welcomeMessage
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

                        if let currentSearch, currentSearch.pipeline == .privateAIText {
                            searchResultPreview(currentSearch)
                        }

                        if let activeSearchIntent {
                            searchStatus(activeSearchIntent)
                        }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 2)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("chat-bottom")
                    }
                    .padding(.horizontal, StylezamDesign.pageInset)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: pendingUserText) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: activeSearchIntent) { _, _ in
                    scrollToBottom(proxy)
                }
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
        HStack(spacing: 13) {
            Group {
                if let garment, let url = model.library.cropURL(for: garment) {
                    LocalFileImage(url: url, contentMode: .fit)
                } else {
                    Color(uiColor: .secondarySystemBackground)
                        .overlay { Image(systemName: "tshirt") }
                }
            }
            .frame(width: 62, height: 70)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(StylezamDesign.hairline, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(garment?.title ?? "Selected piece")
                    .font(.headline)
                    .lineLimit(2)
                Text("Qwen keeps this crop in context throughout the conversation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var shoppingActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ForEach(AIShoppingSearchIntent.allCases) { intent in
                    Button {
                        runShoppingSearch(intent)
                    } label: {
                        Label(intent.title, systemImage: intent.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .stylezamGlassButton(prominent: intent == .similar)
                    .tint(intent == .similar ? StylezamDesign.cobalt : nil)
                    .disabled(isBusy)
                }
            }

            Text("Fireworks reads the piece and your conversation, then Serper performs one live keyword shopping search. Bright Data remains an image-search provider.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcomeMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask me anything about this piece.")
                .font(.headline)
            Text("I can help identify visible details, name the style, suggest outfits, explain fit and care, or turn the conversation into a live product search.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            StylezamDesign.cobalt.opacity(0.065),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func chatBubble(_ message: StylezamChatMessage) -> some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 48) }
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
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            if message.role == .assistant { Spacer(minLength: 32) }
        }
        .frame(maxWidth: .infinity)
    }

    private func pendingBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(
                    StylezamDesign.cobalt,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var assistantThinking: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
            Text("Reading the piece and our conversation…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var followUpQuestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(latestSuggestedQuestions, id: \.self) { question in
                    Button(question) { send(question) }
                        .stylezamGlassButton()
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    private func searchStatus(_ intent: AIShoppingSearchIntent) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
                Text(intent == .cheaper ? "Finding lower-priced options" : "Finding similar pieces")
                    .font(.subheadline.weight(.semibold))
                Text(searchProgress.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(15)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
    }

    private func searchResultPreview(_ search: SavedProductSearch) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(search.aiSearchIntent == .cheaper ? "Lower-priced options" : "Similar pieces")
                        .font(.headline)
                    Text("\(search.providerSummary) · \(search.results.count) results")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("View all") { dismiss() }
                    .font(.subheadline.weight(.semibold))
            }

            if let query = search.generatedQuery {
                Text(query)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
        .padding(.top, 2)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about this piece", text: $draft, axis: .vertical)
                .focused($composerFocused)
                .lineLimit(1...5)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .onSubmit { send(nil) }
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )

            Button { send(nil) } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .frame(width: 43, height: 43)
            }
            .stylezamGlassButton(prominent: true)
            .tint(StylezamDesign.cobalt)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, StylezamDesign.pageInset)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func send(_ suggestedQuestion: String?) {
        let question = (suggestedQuestion ?? draft)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy else { return }
        if suggestedQuestion == nil { draft = "" }
        composerFocused = false
        pendingUserText = question
        isSending = true
        errorMessage = nil

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
                if suggestedQuestion == nil, draft.isEmpty { draft = question }
            }
        }
    }

    private func runShoppingSearch(_ intent: AIShoppingSearchIntent) {
        guard !isBusy else { return }
        composerFocused = false
        activeSearchIntent = intent
        searchProgress = .preparing
        errorMessage = nil
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
            }
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

private struct ChatProductCard: View {
    let product: ProductResultDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ProductImage(url: product.imageURL)
                .frame(width: 132, height: 148)
                .padding(8)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(product.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(product.price?.formatted ?? product.merchant)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 148, alignment: .leading)
        .padding(8)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
    }
}
