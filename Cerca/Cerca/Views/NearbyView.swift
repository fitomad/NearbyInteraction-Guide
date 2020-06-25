//
//  NearbyView.swift
//  Cerca
//
//  Created by Adolfo Vera Blasco on 24/06/2020.
//

import SwiftUI

internal struct NearbyView: View
{
    ///
    @ObservedObject private var viewModel = CercaViewModel()
    
    ///
    @State private var distance = "···"
    ///
    @State private var backgroundGradient = [ Color.yellow, Color.green ]
    
    private let farColors = [ Color.yellow, Color.green ]
    private let mediumColors = [ Color.pink, Color.orange ]
    private let closeColors = [ Color.red, Color.purple ]
    
    internal var body: some View
    {
        VStack(alignment: .center, spacing: 8)
        {
            Spacer()
            
            Text(self.distance)
                .font(.system(size: 80, weight: .medium, design: .rounded))
                .onReceive(self.viewModel.$distanceToPeer, perform: { updatedDistance in
                    guard let updatedDistance = updatedDistance else
                    {
                        self.distance = "···"
                        return
                    }
                    
                    
                    self.distance = String(format: "%.2f m", updatedDistance)
                })
            
            Spacer()
            
            HStack(alignment: .center, spacing: 8)
            {
                Spacer()
                
                ZStack(alignment: .center)
                {
                    Circle()
                        .fill(LinearGradient(gradient: Gradient(colors: self.backgroundGradient), startPoint: .bottomTrailing, endPoint: .topLeading))
                        .frame(width: 200, height: 200)
                        .animation(.linear(duration: 0.50))
                        .onReceive(self.viewModel.$distanceToPeer, perform: { updatedDistance in
                            guard let updatedDistance = updatedDistance else
                            {
                                self.backgroundGradient = farColors
                                return
                            }
                            
                            switch updatedDistance
                            {
                                case 1.0 ... Float.infinity :
                                    self.backgroundGradient = farColors
                                case 0.5 ... 0.99:
                                    self.backgroundGradient = mediumColors
                                default:
                                    self.backgroundGradient = closeColors
                            }
                        })
                    
                    Image(systemName: "location.north.line.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .foregroundColor(.white)
                        .shadow(radius: 8)
                        .rotationEffect(.degrees(self.viewModel.directionAngle))
                        .opacity(self.viewModel.isDirectionAvailable ? 1.0 : 0.10)
                        .animation(.linear)
                        
                                   
                    Image(systemName: self.viewModel.isDirectionAvailable ? "eye.fill" : "eye.slash.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .frame(width: 25, height: 25)
                        .offset(x: 55, y: -45)
                        .opacity(0.50)
                        .animation(.linear)
                }
                
                Spacer()
            }
            
            Spacer()
            
            Text(self.viewModel.peerName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(self.viewModel.isConnectionLost ? .secondary : .primary)
            Text("Buscando a...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .onAppear() {
            
        }
    }
}

struct NearbyView_Previews: PreviewProvider {
    static var previews: some View {
        NearbyView()
            .preferredColorScheme(.dark)
    }
}
