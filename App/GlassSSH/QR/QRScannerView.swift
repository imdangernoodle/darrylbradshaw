import SwiftUI
import AVFoundation

/// A SwiftUI wrapper around an AVFoundation QR-scanning capture session.
///
/// Drives an `AVCaptureSession` with an `AVCaptureMetadataOutput` configured for
/// `.qr` symbols. Scanned strings are parsed to a `URL`; `onScan` fires only for
/// `glassssh://` URLs so the host UI can route them through `GlassSSHURLRouter`.
///
/// Camera permission is requested lazily, and environments without a usable
/// camera (notably the Simulator) fall back to a friendly placeholder instead of
/// crashing.
struct QRScannerView: UIViewControllerRepresentable {
    private let onScan: (URL) -> Void

    init(onScan: @escaping (URL) -> Void) {
        self.onScan = onScan
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        // Keep the coordinator's callback fresh if the closure identity changes.
        context.coordinator.onScan = onScan
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: (URL) -> Void
        /// Guards against firing repeatedly for the same code while it stays in frame.
        private var hasDelivered = false

        init(onScan: @escaping (URL) -> Void) {
            self.onScan = onScan
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasDelivered else { return }

            // Scan every detected code, not just the first — a valid glassssh QR
            // may share the frame with other (ignored) codes.
            let match = metadataObjects
                .compactMap { $0 as? AVMetadataMachineReadableCodeObject }
                .filter { $0.type == .qr }
                .compactMap { $0.stringValue }
                .compactMap { URL(string: $0) }
                .first { $0.scheme?.caseInsensitiveCompare("glassssh") == .orderedSame }

            guard let url = match else { return }

            hasDelivered = true
            DispatchQueue.main.async { [onScan] in
                onScan(url)
            }
        }
    }
}

/// UIKit controller that owns the capture session and preview layer. Kept simple
/// so the SwiftUI wrapper stays thin; it also renders the no-camera fallback.
final class ScannerViewController: UIViewController {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.darrylbradshaw.glassssh.qr.session")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccessAndConfigure()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - Permission + configuration

    private func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.showFallback(.permissionDenied)
                    }
                }
            }
        case .denied, .restricted:
            showFallback(.permissionDenied)
        @unknown default:
            showFallback(.permissionDenied)
        }
    }

    private func configureSession() {
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            // No usable camera — e.g. the Simulator.
            showFallback(.noCamera)
            return
        }

        session.beginConfiguration()
        session.addInput(input)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            session.commitConfiguration()
            showFallback(.noCamera)
            return
        }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(delegate, queue: .main)
        // Set available types only after the output is attached to the session.
        metadataOutput.metadataObjectTypes = metadataOutput.availableMetadataObjectTypes.contains(.qr)
            ? [.qr]
            : metadataOutput.availableMetadataObjectTypes
        session.commitConfiguration()

        installPreviewLayer()
        startRunning()
    }

    private func installPreviewLayer() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    // MARK: - Session lifecycle

    private func startRunning() {
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    private func stopRunning() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Fallback UI

    private enum FallbackReason {
        case noCamera
        case permissionDenied

        var symbol: String {
            switch self {
            case .noCamera: return "camera.metering.unknown"
            case .permissionDenied: return "lock.shield"
            }
        }

        var title: String {
            switch self {
            case .noCamera: return "Camera Unavailable"
            case .permissionDenied: return "Camera Access Needed"
            }
        }

        var message: String {
            switch self {
            case .noCamera:
                return "Scanning requires a camera. Try this on a physical iPad."
            case .permissionDenied:
                return "Allow camera access in Settings to scan a QR code."
            }
        }
    }

    private func showFallback(_ reason: FallbackReason) {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil

        let icon = UIImageView(image: UIImage(systemName: reason.symbol))
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .secondaryLabel
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = reason.title
        title.font = .preferredFont(forTextStyle: .headline)
        title.textColor = .label
        title.textAlignment = .center
        title.numberOfLines = 0

        let body = UILabel()
        body.text = reason.message
        body.font = .preferredFont(forTextStyle: .subheadline)
        body.textColor = .secondaryLabel
        body.textAlignment = .center
        body.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, title, body])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.backgroundColor = .systemBackground
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }
}
