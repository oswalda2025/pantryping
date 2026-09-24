//
//  ScanBarcodeView.swift
//  Pantry Ping
//

import AVFoundation
import SwiftData
import SwiftUI
import Vision
import VisionKit

// Scan (or type) a barcode, then:
// - a product you've saved before → Buy Again with its details
// - found in USDA / Open Food Facts → New Product, pre-filled for you to check
// - not found → New Product with the barcode attached, so next time it's recognized
struct ScanBarcodeView: View {
    // Called when a package has been saved, so the presenter can close.
    var onSaved: (GroceryItem) -> Void

    @Query private var products: [Product]
    @AppStorage(FoodLookup.usdaKeyStorageKey) private var usdaKey = ""

    @State private var typedCode = ""
    @State private var isLookingUp = false
    @State private var lookupTask: Task<Void, Never>?
    // Where to go once the barcode is resolved. Setting it pushes the next screen.
    @State private var route: Route?
    @State private var message: String?
    @State private var camera = CameraState.checking

    // The live scanner needs camera permission. VisionKit reports it as unavailable until
    // access is granted, so the app asks first and then checks again.
    enum CameraState {
        case checking, ready, denied, unavailable
    }

    enum Route: Hashable {
        case buyAgain(Product)
        case newProduct(FoodLookupResult?, barcode: String)
    }

    var body: some View {
        List {
            switch camera {
            case .checking:
                EmptyView()
            case .ready:
                Section {
                    // Paused while another screen is on top, so the camera isn't left running.
                    BarcodeCamera(isActive: route == nil) { code in handle(code) }
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())
                        .overlay {
                            if isLookingUp { lookupOverlay }
                        }
                } footer: {
                    Text("Point the camera at the barcode on the package.")
                }
            case .denied:
                Section {
                    Label("Camera access is off for Pantry Ping, so it can't scan. Type the number under the barcode, or turn the camera on in Settings.",
                          systemImage: "camera.badge.ellipsis")
                        .foregroundStyle(.secondary)
                    if let settings = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: settings)
                    }
                }
            case .unavailable:
                Section {
                    Label("This device can't scan barcodes with the camera (for example, the Simulator). Type the number under the barcode instead.",
                          systemImage: "barcode.viewfinder")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    TextField("Barcode number", text: $typedCode)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Barcode number")
                    Button("Look Up") { handle(typedCode.filter(\.isNumber)) }
                        .disabled(typedCode.filter(\.isNumber).count < 8 || isLookingUp)
                }
                if isLookingUp && camera != .ready {
                    HStack {
                        ProgressView()
                        Text("Looking up…").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Or Type It")
            } footer: {
                Text("Looks up USDA FoodData Central, then Open Food Facts. Only the barcode number is sent.")
            }

            if let message {
                Section {
                    Text(message).foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Scan Barcode")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .navigationDestination(item: $route) { route in
            switch route {
            case .buyAgain(let product):
                BuyAgainView(product: product, onSaved: onSaved)
            case .newProduct(let lookup, let barcode):
                NewGroceryView(lookup: lookup, barcode: barcode, onSaved: onSaved)
            }
        }
        .onDisappear { lookupTask?.cancel() }
        .task { camera = await Self.checkCamera() }
    }

    // Asks for camera access the first time, then decides what the screen can offer.
    static func checkCamera() async -> CameraState {
        guard DataScannerViewController.isSupported else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted && DataScannerViewController.isAvailable ? .ready : .denied
        case .authorized:
            return DataScannerViewController.isAvailable ? .ready : .unavailable
        default:
            return .denied
        }
    }

    private var lookupOverlay: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Looking up…")
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // Product barcodes (EAN-8, UPC-A, EAN-13, GTIN-14) are 8, 12, 13, or 14 digits.
    private static let barcodeLengths: Set<Int> = [8, 12, 13, 14]

    private func handle(_ rawCode: String) {
        // Only digits count; anything else (like a lot-number label) isn't a product barcode.
        let trimmed = rawCode.trimmingCharacters(in: .whitespaces)
        guard trimmed.allSatisfy(\.isNumber) else { return }
        let code = trimmed
        guard Self.barcodeLengths.contains(code.count), !isLookingUp, route == nil else {
            if !Self.barcodeLengths.contains(code.count) && !code.isEmpty {
                message = "That doesn't look like a product barcode. They have 8, 12, 13, or 14 digits."
            }
            return
        }
        message = nil

        // Already saved? Buying again needs no lookup at all.
        let canonical = FoodLookup.canonical(code)
        if let saved = products.first(where: { $0.barcode.map(FoodLookup.canonical) == canonical }) {
            route = .buyAgain(saved)
            return
        }

        isLookingUp = true
        // A Task runs async work (the network lookup) started from a button or callback.
        lookupTask = Task {
            let outcome = await FoodLookup.lookup(code, usdaKey: usdaKey)
            guard !Task.isCancelled else { return }
            isLookingUp = false
            switch outcome {
            case .found(let result):
                route = .newProduct(result, barcode: code)
            case .notFound:
                route = .newProduct(nil, barcode: code)
            case .offline:
                message = "Couldn't reach the food databases. Check your connection, or add the product by hand."
            }
        }
    }
}

// Apple's live barcode scanner (VisionKit), wrapped for SwiftUI.
// UIViewControllerRepresentable is the bridge that lets a UIKit screen appear in SwiftUI.
struct BarcodeCamera: UIViewControllerRepresentable {
    // Scans only while true (e.g. not while the next screen is showing).
    let isActive: Bool
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        // Grocery barcodes only (UPC/EAN), so lot-number or shipping labels aren't picked up.
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        // Keep the coordinator's callback current with this render's closure.
        context.coordinator.onScan = onScan
        if isActive && !scanner.isScanning {
            try? scanner.startScanning()
        } else if !isActive && scanner.isScanning {
            scanner.stopScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    // The scanner reports what it sees through a delegate object.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue {
                    onScan(code)
                    return
                }
            }
        }
    }
}
