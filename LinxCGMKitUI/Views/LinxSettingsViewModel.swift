import Combine
import Foundation
import HealthKit
import LinxCGMKit
import LoopKit
import LoopKitUI

class LinxSettingsViewModel: ObservableObject, LinxStateObserver {
    private(set) var cgmManager: LinxCGMManager
    private var displayGlucosePreference: DisplayGlucosePreference

    @Published var sensorSerial: String
    /// Linx sensors detected in range (for the picker list).
    @Published var nearbyDevices: [LinxNearbyDevice] = []
    @Published var statusText: String
    @Published var latestGlucoseText: String
    @Published var calA: Double
    @Published var calB: Double
    @Published var calPoints: [LinxCalPoint]

    init(cgmManager: LinxCGMManager, displayGlucosePreference: DisplayGlucosePreference) {
        self.cgmManager = cgmManager
        self.displayGlucosePreference = displayGlucosePreference

        let st = cgmManager.state
        sensorSerial = st.sensorSerial ?? ""
        calA = st.calibration.calA
        calB = st.calibration.calB
        calPoints = st.calibration.points
        statusText = cgmManager.currentStatusText
        latestGlucoseText = Self.glucoseText(
            cgmManager.latestReading,
            displayGlucosePreference: displayGlucosePreference
        )
        nearbyDevices = cgmManager.nearbyDevices

        cgmManager.addStateObserver(self)
    }

    deinit {
        cgmManager.removeStateObserver(self)
    }

    private static func glucoseText(
        _ r: LinxGlucoseReading?,
        displayGlucosePreference: DisplayGlucosePreference
    ) -> String {
        guard let r = r else { return "—" }
        let quantity = HKQuantity(
            unit: HKUnit(from: "mg/dL"),
            doubleValue: Double(r.glucoseMgdl)
        )
        return displayGlucosePreference.format(quantity)
    }

    private var displaysMgdl: Bool {
        displayGlucosePreference.unit == HKUnit(from: "mg/dL")
    }

    var calibrationInputPlaceholder: String {
        displaysMgdl ? "Ref mg/dL" : "Ref mmol/L"
    }

    var activeCurveText: String {
        if displaysMgdl {
            return String(format: "mg/dL = %.5f·raw + %.3f", calA * 18, calB * 18)
        }
        return String(format: "mmol/L = %.5f·raw + %.3f", calA, calB)
    }

    func calibrationPointText(_ point: LinxCalPoint) -> String {
        if displaysMgdl {
            return "\(LinxDecoder.mmolToMgdl(point.mmol)) mg/dL"
        }
        return String(format: "%.1f mmol/L", point.mmol)
    }

    /// Raw glu10 value from the latest reading (for calibration).
    var currentRaw10: Int? { cgmManager.latestReading?.raw10 }

    // MARK: - Actions

    func saveSerial() {
        cgmManager.setSensorSerial(sensorSerial.trimmingCharacters(in: .whitespaces))
    }

    /// Persist the sensor chosen from the picker list: we only filter to it,
    /// no connection is needed (we read from Linx advertisements). We save the
    /// full advertised name so the scanner filters to exactly this one sensor.
    func selectDevice(_ device: LinxNearbyDevice) {
        sensorSerial = device.name
        cgmManager.setSensorSerial(device.name)
    }

    /// Called when opening settings: starts scanning and loads the currently
    /// known sensor list.
    func startScanning() {
        cgmManager.startScanningForPicker()
        nearbyDevices = cgmManager.nearbyDevices
    }

    /// Record a new calibration point in the user's display unit against
    /// the CURRENT raw glu10 value.
    func addCalibration(referenceValue: Double) {
        guard let raw10 = currentRaw10 else { return }
        let refMmol = displaysMgdl ? referenceValue / 18 : referenceValue
        cgmManager.addCalibration(glu10: raw10, mmol: refMmol)
        refresh()
    }

    func resetCalibration() {
        cgmManager.resetCalibration()
        refresh()
    }

    private func refresh() {
        let st = cgmManager.state
        calA = st.calibration.calA
        calB = st.calibration.calB
        calPoints = st.calibration.points
    }

    // MARK: - LinxStateObserver

    func linxStateDidUpdate(_ state: LinxCGMManagerState) {
        DispatchQueue.main.async {
            self.calA = state.calibration.calA
            self.calB = state.calibration.calB
            self.calPoints = state.calibration.points
            if self.sensorSerial.isEmpty, let s = state.sensorSerial { self.sensorSerial = s }
            self.latestGlucoseText = Self.glucoseText(
                self.cgmManager.latestReading,
                displayGlucosePreference: self.displayGlucosePreference
            )
        }
    }

    func linxStatusDidUpdate(_ status: String) {
        DispatchQueue.main.async {
            self.statusText = status
            self.latestGlucoseText = Self.glucoseText(
                self.cgmManager.latestReading,
                displayGlucosePreference: self.displayGlucosePreference
            )
        }
    }

    func linxNearbyDevicesDidUpdate(_ devices: [LinxNearbyDevice]) {
        DispatchQueue.main.async {
            self.nearbyDevices = devices
        }
    }
}
