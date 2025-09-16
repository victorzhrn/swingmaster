//
//  NavigationState.swift
//  swingmaster
//
//  Centralized navigation state management
//

import SwiftUI

enum NavigationDestination: Hashable {
    case camera
    case analysis(Session)
    case picker
}

enum SheetDestination: Identifiable {
    case recordOptions
    case picker
    
    var id: String {
        switch self {
        case .recordOptions: return "recordOptions"
        case .picker: return "picker"
        }
    }
}

@MainActor
class NavigationState: ObservableObject {
    @Published var path = NavigationPath()
    @Published var activeSheet: SheetDestination?
    
    func push(_ destination: NavigationDestination) {
        path.append(destination)
    }
    
    func popToRoot() {
        path.removeLast(path.count)
    }
    
    func showRecordOptions() {
        activeSheet = .recordOptions
    }
    
    func showPicker() {
        activeSheet = .picker
    }
}