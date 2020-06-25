//
//  CercaApp.swift
//  Cerca
//
//  Created by Adolfo Vera Blasco on 24/06/2020.
//

import SwiftUI

@main
struct CercaApp: App {
    var body: some Scene {
        WindowGroup {
            if CercaViewModel.nearbySessionAvailable
            {
                NearbyView()
            }
            else
            {
                ErrorView()
            }
        }
    }
}
