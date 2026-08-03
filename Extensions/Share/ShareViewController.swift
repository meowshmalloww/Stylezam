import UIKit
import UniformTypeIdentifiers

private final class AttachmentAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var imageName: String?
    private var text: String?

    var needsImage: Bool {
        lock.withLock { imageName == nil }
    }

    func storeImageName(_ value: String) {
        lock.withLock {
            if imageName == nil {
                imageName = value
            }
        }
    }

    func storeText(_ value: String) {
        lock.withLock {
            if text == nil {
                text = value
            }
        }
    }

    func snapshot() -> (imageName: String?, text: String?) {
        lock.withLock { (imageName, text) }
    }
}

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let openButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        importAttachments()
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground
        statusLabel.text = "Adding to Stylezam…"
        statusLabel.font = .systemFont(ofSize: 24, weight: .bold)
        statusLabel.numberOfLines = 0

        detailLabel.text = "The image stays in the shared app container until Stylezam imports it."
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        spinner.startAnimating()

        var openConfiguration = UIButton.Configuration.filled()
        openConfiguration.title = "Open Stylezam"
        openConfiguration.image = UIImage(systemName: "arrow.up.right")
        openConfiguration.imagePadding = 8
        openConfiguration.baseBackgroundColor = UIColor(
            red: 0.078,
            green: 0.361,
            blue: 1,
            alpha: 1
        )
        openConfiguration.cornerStyle = .capsule
        openButton.configuration = openConfiguration
        openButton.isHidden = true
        openButton.addTarget(self, action: #selector(openStylezam), for: .touchUpInside)

        closeButton.setTitle("Done", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        closeButton.isHidden = true
        closeButton.addTarget(self, action: #selector(closeExtension), for: .touchUpInside)

        let actions = UIStackView(arrangedSubviews: [openButton, closeButton])
        actions.axis = .horizontal
        actions.spacing = 12
        actions.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel, detailLabel, actions])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            openButton.heightAnchor.constraint(equalToConstant: 52),
            closeButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func importAttachments() {
        let providers: [NSItemProvider] = (extensionContext?.inputItems ?? []).flatMap { item in
            (item as? NSExtensionItem)?.attachments ?? []
        }
        guard !providers.isEmpty else {
            finish(success: false, detail: "No image or text was attached.")
            return
        }

        let group = DispatchGroup()
        let accumulator = AttachmentAccumulator()

        for provider in providers {
            if provider.canLoadObject(ofClass: UIImage.self), accumulator.needsImage {
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { group.leave() }
                    guard let image = object as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.92),
                          let container = StylezamShared.containerURL
                    else { return }
                    let directory = container.appending(path: "Pending", directoryHint: .isDirectory)
                    try? FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                    let relative = "Pending/\(UUID().uuidString).jpg"
                    let destination = container.appending(path: relative)
                    guard (try? data.write(to: destination, options: .atomic)) != nil else { return }
                    accumulator.storeImageName(relative)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    defer { group.leave() }
                    let value = (item as? String) ?? (item as? URL)?.absoluteString
                    guard let value else { return }
                    accumulator.storeText(value)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    defer { group.leave() }
                    guard let value = (item as? URL)?.absoluteString else { return }
                    accumulator.storeText(value)
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            let (storedImageName, storedText) = accumulator.snapshot()
            if let storedImageName {
                StylezamShared.defaults.set(
                    storedImageName,
                    forKey: StylezamShared.pendingImageKey
                )
            }
            if let storedText {
                StylezamShared.defaults.set(storedText, forKey: StylezamShared.pendingTextKey)
            }
            let success = storedImageName != nil || storedText != nil
            self?.finish(
                success: success,
                detail: success
                    ? "Ready to search. Open Stylezam to continue."
                    : "Stylezam could not read this attachment."
            )
        }
    }

    private func finish(success: Bool, detail: String) {
        spinner.stopAnimating()
        statusLabel.text = success ? "Ready for Stylezam" : "Couldn’t import"
        detailLabel.text = detail
        openButton.isHidden = !success
        closeButton.isHidden = false
    }

    @objc private func openStylezam() {
        guard let url = URL(string: "stylezam://import") else { return }
        extensionContext?.open(url, completionHandler: nil)
        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func closeExtension() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
