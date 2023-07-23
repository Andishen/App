//
//  ContentView.swift
//  arGPT
//
//  Created by Bart Trzynadlowski on 7/23/23.
//
//  Top-level application view. Observers Controller (the app logic or "model", effectively) and
//  decides what to display.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var _settings: Settings
    private let _chatMessageStore: ChatMessageStore
    @ObservedObject private var _controller: Controller

    /// Monocle state (as reported by Controller)
    @State private var _isMonocleConnected = false
    @State private var _pairedMonocleID: UUID?

    /// Bluetooth state
    @State private var _bluetoothEnabled = false

    /// Controls whether device sheet displayed
    @State private var _showDeviceSheet = false

    /// Controls which device sheet is displayed, if showDeviceSheeet == true
    @State private var _deviceSheetType: DeviceSheetType = .pairing

    /// Update percentage
    @State private var _updateProgressPercent: Int = 0

    var body: some View {
        VStack {
            // Initial view includes pairing and updating
            let showDeviceScreen = (_showDeviceSheet && _settings.pairedDeviceID == nil) || _controller.updateState != .notUpdating

            if showDeviceScreen {
                // This view shown until 1) device becomes paired or 2) forcible dismissed by
                // _showPairingView = false
                DeviceScreenView(
                    showDeviceSheet: $_showDeviceSheet,
                    deviceSheetType: $_deviceSheetType,
                    updateProgressPercent: $_updateProgressPercent
                )
                    .onAppear {
                        // Delay a moment before enabling Bluetooth scanning so we actually see
                        // the pairing dialog. Also ensure that by the time this callback fires,
                        // the user has not just aborted the procedure.
                        if !_bluetoothEnabled {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                if _showDeviceSheet {
                                    _bluetoothEnabled = true
                                }
                            }
                        }
                    }
            } else {
                ChatView(
                    isMonocleConnected: $_isMonocleConnected,
                    pairedMonocleID: $_pairedMonocleID,
                    bluetoothEnabled: $_bluetoothEnabled,
                    showPairingView: $_showDeviceSheet,
                    onTextSubmitted: { [weak _controller] (query: String) in
                        _controller?.submitQuery(query: query)
                    },
                    onClearChatButtonPressed: { [weak _controller] in
                        _controller?.clearHistory()
                    }
                )
                .onAppear {
                    // If this view became active and we are paired, ensure we enable Bluetooth
                    // because it is disabled initially. When app first loads, even with a paired
                    // device, need to explicitly enabled.
                    if _settings.pairedDeviceID != nil {
                        _bluetoothEnabled = true
                    }
                }
                .environmentObject(_chatMessageStore)
                .environmentObject(_settings)
            }
        }
        .onAppear {
            // Initialize state
            _isMonocleConnected = _controller.isMonocleConnected
            _pairedMonocleID = _controller.pairedMonocleID
            _bluetoothEnabled = _controller.bluetoothEnabled

            // Do we need to bring up device sheet initially? Do so if no Monocle paired or
            // if somehow already in an update state
            _deviceSheetType = decideDeviceSheetType()
            _showDeviceSheet = decideShowDeviceSheet()
        }
        .onChange(of: _controller.isMonocleConnected) {
            // Sync connection state
            _isMonocleConnected = $0
        }
        .onChange(of: _controller.pairedMonocleID) {
            // Sync paired device ID
            _pairedMonocleID = $0
        }
        .onChange(of: _controller.bluetoothEnabled) {
            // Sync Bluetooth state
            _bluetoothEnabled = $0
        }
        .onChange(of: _bluetoothEnabled) {
            // Pass through to controller (will not cause a cycle because we monitor change only)
            _controller.bluetoothEnabled = $0
        }
        .onChange(of: _showDeviceSheet) {
            let dismissed = $0 == false

            // When enabled, update device sheet type
            if !dismissed {
                _deviceSheetType = decideDeviceSheetType()
                return
            }

            // Cannot dismiss while updating
            if dismissed && _controller.updateState != .notUpdating {
                _showDeviceSheet = true
                return
            }

            // Detect when pairing view was dismissed. If we were scanning but did not pair (user
            // forcibly dismissed us), stop scanning altogether
            if dismissed && _settings.pairedDeviceID == nil {
                _bluetoothEnabled = false
            }
        }
        .onChange(of: _controller.updateState) { (value: Controller.UpdateState) in
            _showDeviceSheet = decideShowDeviceSheet()
            _deviceSheetType = decideDeviceSheetType()
        }
        .onChange(of: _controller.updateProgressPercent) {
            _updateProgressPercent = $0
        }
    }

    init(settings: Settings, chatMessageStore: ChatMessageStore, controller: Controller) {
        _settings = settings
        _chatMessageStore = chatMessageStore
        _controller = controller
    }

    private func decideShowDeviceSheet() -> Bool {
        return _settings.pairedDeviceID == nil || _controller.updateState != .notUpdating
    }

    private func decideDeviceSheetType() -> DeviceSheetType {
        switch _controller.updateState {
        case .notUpdating:
            return .pairing
        case .updatingFirmware:
            return .firmwareUpdate
        case .updatingFPGA:
            return .fpgaUpdate
        }
    }
}
