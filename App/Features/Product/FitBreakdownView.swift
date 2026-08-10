import SwiftUI

// MARK: - Product fit section (embedded in the product page)

/// Measurement breakdown and size recommendation for one product. Reads the
/// merchant page once, extracts the per-size dimensions, and compares every
/// size against the user's saved body measurements.
struct ProductFitSection: View {
    @Environment(AppModel.self) private var model
    let product: ProductResultDTO

    @State private var selectedSize: String?
    @State private var isEditingMeasurements = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            EditorialSectionHeader(title: "Fit & measurements", detail: headerDetail)
            EditorialRule()

            switch model.sizeChartStates[product.id] {
            case nil:
                introState
            case .loading:
                loadingState
            case let .notPublished(reason):
                notPublishedState(reason)
            case let .failed(message):
                failedState(message)
            case let .loaded(chart):
                chartContent(chart)
            }
        }
        .sheet(isPresented: $isEditingMeasurements) {
            BodyMeasurementsEditor()
        }
    }

    private var headerDetail: String? {
        if case let .loaded(chart) = model.sizeChartStates[product.id] {
            return "\(chart.sizes.count) sizes"
        }
        return nil
    }

    // MARK: States

    private var introState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stylezam can read the merchant page, pull the exact dimensions of every size, and compare each one to your measurements before you buy.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.fitProfile.measurements.hasAnyValue {
                measurementsPrompt
            }

            Button {
                Task { await model.loadSizeChart(for: product) }
            } label: {
                HStack {
                    Text("Check my fit")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "ruler")
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .stylezamGlassButton()
        }
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Reading the merchant's size chart…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 54)
    }

    private func notPublishedState(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "ruler")
                    .foregroundStyle(.secondary)
            }
            Link(destination: product.productURL) {
                Label("Check sizing at \(product.merchant)", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func failedState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Button("Try again") {
                Task { await model.loadSizeChart(for: product, force: true) }
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: Loaded chart

    @ViewBuilder
    private func chartContent(_ chart: GarmentSizeChart) -> some View {
        let measurements = model.fitProfile.measurements
        let recommendation: SizeRecommendation? = measurements.hasAnyValue
            ? FitEngine.recommendation(
                chart: chart,
                body: measurements,
                category: product.category,
                title: product.title
            )
            : nil
        // A re-checked chart can drop a previously selected label; fall back
        // to the recommendation instead of pointing at a size that no longer exists.
        let validSelection = selectedSize.flatMap { label in
            chart.sizes.contains { $0.label == label } ? label : nil
        }
        let currentSize = validSelection
            ?? recommendation?.recommendedSizeLabel
            ?? chart.sizes.first?.label

        VStack(alignment: .leading, spacing: 16) {
            if !measurements.hasAnyValue {
                measurementsPrompt
            } else if let recommended = recommendation?.recommendedSizeLabel,
                      let assessment = recommendation?.assessment(for: recommended)
            {
                recommendationBanner(size: recommended, assessment: assessment)
            }

            if let note = recommendation?.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            sizeChips(
                chart: chart,
                recommendation: recommendation,
                currentSize: currentSize
            )

            if let currentSize {
                selectedSizeDetail(
                    chart: chart,
                    recommendation: recommendation,
                    sizeLabel: currentSize
                )
            }

            chartFooter(chart)
        }
    }

    private func recommendationBanner(size: String, assessment: SizeFitAssessment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(StylezamDesign.cobalt)
            VStack(alignment: .leading, spacing: 2) {
                Text("Stylezam recommends size \(size)")
                    .font(.subheadline.weight(.semibold))
                Text("\(assessment.confidencePercent)% measurement match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(StylezamDesign.cobalt.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var measurementsPrompt: some View {
        Button {
            isEditingMeasurements = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.arms.open")
                    .font(.title3)
                    .foregroundStyle(StylezamDesign.cobalt)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add your measurements")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Saved on this iPhone only. Unlocks a personal size recommendation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sizeChips(
        chart: GarmentSizeChart,
        recommendation: SizeRecommendation?,
        currentSize: String?
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chart.sizes) { size in
                    let isSelected = size.label == currentSize
                    let isRecommended = size.label == recommendation?.recommendedSizeLabel
                    let assessment = recommendation?.assessment(for: size.label)

                    Button {
                        selectedSize = size.label
                    } label: {
                        VStack(spacing: 3) {
                            HStack(spacing: 4) {
                                if isRecommended {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2)
                                }
                                Text(size.label)
                                    .font(.subheadline.weight(.semibold))
                            }
                            if let assessment, assessment.verdict != nil {
                                Text("\(assessment.confidencePercent)% match")
                                    .font(.caption2.weight(.medium))
                                    .opacity(0.8)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? StylezamDesign.cobalt : Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .overlay {
                            if isRecommended, !isSelected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(StylezamDesign.cobalt.opacity(0.6), lineWidth: 1.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Size \(size.label)\(isRecommended ? ", recommended" : "")"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func selectedSizeDetail(
        chart: GarmentSizeChart,
        recommendation: SizeRecommendation?,
        sizeLabel: String
    ) -> some View {
        let size = chart.sizes.first { $0.label == sizeLabel }
        let assessment = recommendation?.assessment(for: sizeLabel)

        VStack(alignment: .leading, spacing: 12) {
            if let assessment {
                HStack(alignment: .firstTextBaseline) {
                    if let verdict = assessment.verdict {
                        FitRatingPill(rating: verdict)
                    }
                    Spacer()
                    unitToggle
                }
                Text(assessment.summary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if let recommended = recommendation?.recommendedSizeLabel, recommended != sizeLabel {
                    Text("Stylezam still recommends \(recommended). The breakdown below shows exactly what changes in \(sizeLabel).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    Text("SIZE \(sizeLabel) MEASUREMENTS")
                        .font(.caption2.weight(.bold))
                        .tracking(0.9)
                        .foregroundStyle(.secondary)
                    Spacer()
                    unitToggle
                }
            }

            if let assessment {
                VStack(spacing: 0) {
                    ForEach(assessment.dimensionFits) { fit in
                        dimensionRow(fit)
                        if fit.id != assessment.dimensionFits.last?.id {
                            EditorialRule()
                        }
                    }
                }
            } else if let size {
                VStack(spacing: 0) {
                    ForEach(GarmentDimension.allCases.filter { size.measurements[$0] != nil }) { dimension in
                        plainMeasurementRow(dimension: dimension, valueCm: size.measurements[dimension]!)
                        EditorialRule()
                    }
                }
            }
        }
        .padding(13)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var unitToggle: some View {
        @Bindable var fitProfile = model.fitProfile
        return Picker("Units", selection: $fitProfile.displayUnit) {
            ForEach(MeasurementDisplayUnit.allCases) { unit in
                Text(unit.title).tag(unit)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 110)
    }

    private func dimensionRow(_ fit: DimensionFit) -> some View {
        let unit = model.fitProfile.displayUnit
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: fit.dimension.symbolName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(fit.dimension.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let rating = fit.rating {
                        FitRatingPill(rating: rating)
                    }
                }
                Text(measurementLine(fit: fit, unit: unit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !fit.note.isEmpty {
                    Text(fit.note)
                        .font(.caption)
                        .foregroundStyle(fit.rating == .tooTight ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 9)
    }

    private func measurementLine(fit: DimensionFit, unit: MeasurementDisplayUnit) -> String {
        var parts = ["Garment \(unit.formatted(cm: fit.garmentValueCm))"]
        if let body = fit.bodyValueCm {
            parts.append("You \(unit.formatted(cm: body))")
        }
        return parts.joined(separator: " · ")
    }

    private func plainMeasurementRow(dimension: GarmentDimension, valueCm: Double) -> some View {
        HStack(spacing: 11) {
            Image(systemName: dimension.symbolName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(dimension.title)
                .font(.subheadline)
            Spacer()
            Text(model.fitProfile.displayUnit.formatted(cm: valueCm))
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 9)
    }

    private func chartFooter(_ chart: GarmentSizeChart) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chart.measurementExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Link(destination: chart.sourceURL) {
                    Label("Source: \(product.merchant)", systemImage: "arrow.up.right")
                        .font(.caption.weight(.medium))
                }
                Button("Re-check") {
                    Task { await model.loadSizeChart(for: product, force: true) }
                }
                .font(.caption.weight(.medium))
                if model.fitProfile.measurements.hasAnyValue {
                    Button("Edit measurements") {
                        isEditingMeasurements = true
                    }
                    .font(.caption.weight(.medium))
                }
            }
        }
    }
}

// MARK: - Rating pill

struct FitRatingPill: View {
    let rating: FitRating

    var body: some View {
        Text(rating.title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch rating {
        case .tooTight: .red
        case .snug: .orange
        case .ideal: StylezamDesign.cobalt
        case .relaxed: .teal
        case .oversized: .orange
        }
    }
}

// MARK: - Fit sheet (used from Try On)

struct ProductFitSheet: View {
    @Environment(\.dismiss) private var dismiss
    let product: ProductResultDTO

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let brand = product.brand {
                            EditorialKicker(text: brand)
                        }
                        Text(product.title)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ProductFitSection(product: product)
                }
                .padding(StylezamDesign.pageInset)
            }
            .background(StylezamDesign.paper)
            .navigationTitle("Fit check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Fit profile (Settings)

struct FitProfileSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isEditing = false

    var body: some View {
        List {
            Section {
                if model.fitProfile.measurements.hasAnyValue {
                    ForEach(savedRows, id: \.0) { title, value in
                        HStack {
                            Text(title)
                            Spacer()
                            Text(value)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No measurements saved yet.")
                        .foregroundStyle(.secondary)
                }
                Button(model.fitProfile.measurements.hasAnyValue ? "Edit measurements" : "Add measurements") {
                    isEditing = true
                }
            } footer: {
                Text("Stylezam compares these numbers to merchant size charts to recommend a size and rate how every other size would fit. They are stored on this iPhone only and never uploaded.")
            }
        }
        .navigationTitle("Fit profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditing) {
            BodyMeasurementsEditor()
        }
    }

    private var savedRows: [(String, String)] {
        let measurements = model.fitProfile.measurements
        let unit = model.fitProfile.displayUnit
        let entries: [(String, Double?)] = [
            ("Height", measurements.heightCm),
            ("Chest / bust", measurements.chestCm),
            ("Waist", measurements.waistCm),
            ("Hips", measurements.hipsCm),
            ("Shoulders", measurements.shouldersCm),
            ("Sleeve", measurements.sleeveCm),
            ("Inseam", measurements.inseamCm),
        ]
        return entries.compactMap { title, cm in
            guard let cm else { return nil }
            return (title, unit.formatted(cm: cm))
        }
    }
}

// MARK: - Body measurements editor

struct BodyMeasurementsEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var height = ""
    @State private var chest = ""
    @State private var waist = ""
    @State private var hips = ""
    @State private var shoulders = ""
    @State private var sleeve = ""
    @State private var inseam = ""
    @State private var unit: MeasurementDisplayUnit = .centimeters
    @State private var isLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Units", selection: $unit) {
                        ForEach(MeasurementDisplayUnit.allCases) { unit in
                            Text(unit == .centimeters ? "Centimeters" : "Inches").tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: unit) { oldUnit, newUnit in
                        convertFields(from: oldUnit, to: newUnit)
                    }
                } footer: {
                    Text("Measurements stay on this iPhone. Stylezam compares them to merchant size charts locally — they are never uploaded.")
                }

                Section("Body") {
                    measurementField("Height", text: $height, hint: "Head to floor")
                    measurementField("Chest / bust", text: $chest, hint: "Around the fullest part")
                    measurementField("Waist", text: $waist, hint: "Around the natural waistline")
                    measurementField("Hips", text: $hips, hint: "Around the fullest part")
                }

                Section("For precise fits (optional)") {
                    measurementField("Shoulders", text: $shoulders, hint: "Shoulder seam to shoulder seam")
                    measurementField("Sleeve", text: $sleeve, hint: "Shoulder to wrist")
                    measurementField("Inseam", text: $inseam, hint: "Crotch to ankle")
                }

                if model.fitProfile.measurements.hasAnyValue {
                    Section {
                        Button("Clear all measurements", role: .destructive) {
                            model.fitProfile.clear()
                            loadFields()
                        }
                    }
                }
            }
            .navigationTitle("My measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !isLoaded else { return }
                isLoaded = true
                unit = model.fitProfile.displayUnit
                loadFields()
            }
        }
    }

    private func measurementField(_ title: String, text: Binding<String>, hint: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 74)
            Text(unit.title)
                .foregroundStyle(.secondary)
        }
    }

    private func loadFields() {
        let measurements = model.fitProfile.measurements
        height = fieldText(measurements.heightCm)
        chest = fieldText(measurements.chestCm)
        waist = fieldText(measurements.waistCm)
        hips = fieldText(measurements.hipsCm)
        shoulders = fieldText(measurements.shouldersCm)
        sleeve = fieldText(measurements.sleeveCm)
        inseam = fieldText(measurements.inseamCm)
    }

    private func fieldText(_ cm: Double?) -> String {
        guard let cm else { return "" }
        let value = unit.displayValue(fromCm: cm)
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    private func convertFields(from old: MeasurementDisplayUnit, to new: MeasurementDisplayUnit) {
        guard old != new else { return }
        for binding in [$height, $chest, $waist, $hips, $shoulders, $sleeve, $inseam] {
            guard let value = parse(binding.wrappedValue) else { continue }
            let cm = old.cmValue(fromDisplay: value)
            let converted = new.displayValue(fromCm: cm)
            let rounded = (converted * 10).rounded() / 10
            binding.wrappedValue = rounded == rounded.rounded()
                ? String(Int(rounded))
                : String(format: "%.1f", rounded)
        }
    }

    private func parse(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private func save() {
        let toCm: (String) -> Double? = { text in
            guard let value = parse(text) else { return nil }
            return unit.cmValue(fromDisplay: value)
        }
        var measurements = BodyMeasurements(
            heightCm: toCm(height),
            chestCm: toCm(chest),
            waistCm: toCm(waist),
            hipsCm: toCm(hips),
            shouldersCm: toCm(shoulders),
            sleeveCm: toCm(sleeve),
            inseamCm: toCm(inseam)
        )
        measurements.updatedAt = .now
        model.fitProfile.measurements = measurements
        model.fitProfile.displayUnit = unit
    }
}
