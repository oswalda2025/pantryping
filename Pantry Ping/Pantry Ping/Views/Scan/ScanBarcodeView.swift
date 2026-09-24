//
//  ScanBarcodeView.swift
//  Pantry Ping
//

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

    enum Route: Hashable {
        case buyAgain(Product)
        case newProduct(FoodLookupResult?, barcode: String)
    }

    var body: some View {
        List {
            if BarcodeCamera.isAvailable {
                Section {
                    BarcodeCamera { code in handle(code) }
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())
                        .overlay {
                            if isLookingUp { lookupOverlay }
                        }
                } footer: {
                    Text("Point the camera at the barcode on the package.")
                }
            } else {
                Section {
                    Label("The camera scanner isn't available here (for example, in the Simulator). Type the number under the barcode instead.",
                          systemImage: "barcode.viewfinder")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    TextField("Barcode number", text: $typedCode)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Barcode number")
                    Button("Look Up") { handle(typedCode) }
                        .disabled(typedCode.filter(\.isNumber).count < 8 || isLookingUp)
                }
                if isLookingUp && !BarcodeCamera.isAvailable {
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
        .navigationDestination(item: $route) { route in
            switch route {
            case .buyAgain(let product):
                BuyAgainView(product: product, onSaved: onSaved)
            case .newProduct(let lookup, let barcode):
                NewGroceryView(lookup: lookup, barcode: barcode, onSaved: onSaved)
            }
        }
        .onDisappear { lookupTask?.cancel() }
    }

    private var lookupOverlay: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Looking up…")
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func handle(_ rawCode: String) {
        let code = rawCode.filter(\.isNumber)
        guard code.count >= 8, !isLookingUp, route == nil else { return }
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
    // Needs a real iPhone with a camera; the Simulator can't scan.
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
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
        let onScan: (String) -> Void
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
