# NearbyInteraction Framework Guide

Imagine that you had a way of knowing how far away you are from other devices and also knowing which direction the devices are relative to yours. Well, Apple presents this ability to us with the NearbyInteraction framework presented at WWDC 2020.

This is possible thanks to the Apple-designed U1 chip that incorporates the iPhone 11 and the new iOS 14, currently in beta. These are the minimum requirements to be able to use this framework. 

To illustrate this article I will use a very simple app that searches for another device and will tell us the distance and its relative position.

## Presenting the players

 NearbyInteraction works through sessions. A session is a connection between two devices, and a device can connect to more than one device. 

The class that represents the session is called `NISession` and it is the gateway of our app in order to use the framework. With it you can check if your device has support for the framework, start, pause and resume a session with another device. 

When we want to start a session, we must use the `run` function to which we will pass a configuration represented by the `NINearbyPeerConfiguration` class that accepts as a parameter the token of the device with which we want to start a session.

Wait a second...what's a customer token? It is a unique identifier that represents the session's (or multiple sessions') devices, or points. And no, you don't have to generate it. `NISession` will create the device's when you instantiate the class.

To receive updates on the session status -- such as changes in distance and position with respect to the other device, if the session is suddenly invalid or the connection to the other point in the session is lost -- we will use the delegate pattern using the `NISessionDelegate` delegate

One of the reasons our session may be invalidated is because the app starts running in the background, at which point the delegate invokes the `sessionWasSuspended` function.

If the app runs in the foreground again within a reasonable time the delegate calls the `sessionSuspensionEnded` function. At that time we must call the `NISession` `run` function again, passing the configuration again.

If the app spends too much time in the background, there will be no possibility to restart the session and we will be informed with the session function ``(_: didInvalidateWith :)``

And the most interesting... the function where we will receive distance and position updates is called session `(_: didUpdate :)`. It is important to know that there may be times when distance, position or both have null values, so the app must be prepared for it.

## Wait ... How do I transfer my token to the other device?

There is no way that the NearbyInteraction framework can pass information to another device. For this we must use another way to communicate with the other points of the session.

You can use iCloud, the MultipeerConnectivity framework, sockets, Bonjour, etc. In the WWDC session they have decided to use the MultipeerConnectivity framework and for this example I will use it as well.

The decision to use this framework is motivated by the similarity as far as the distance between users is concerned.

Both of these frameworks (MultipeerConnectivity and NearbyInteraction) do note need to have a lot of distance between the points (devices). Therefore, if we can discover a device with MultipeerConnectivity, it means that it is very possible to establish a NearbyInteraction session.

Now that we have the complete picture we are going to get into the subject using a project called Cerca (Closer).

In the code, we will see a complete cycle of NearbyInteraction.

- Check if we can use the framework
- Discovery
- Token exchange
- Updating direction and distance

Let's get to it!

## Project Structure

Upon opening the app in Xcode 12 Beta, we will focus on four files:

- **CercaApp**. Here we check if the device supports the framework that can run the app.

- **NearbyView**. Presents distance and direction data to the other device.
- **ErrorView**. If the device does not support `NearbyInteractions`, we will alert the user.
- **CercaViewModel**. Contains all the logic to handle `NearbyInteractions` and `MultipeerConnectivity` sessions.
- 
About `CercaViewModel`: To make it easier to follow along with the code, all operations have been concentrated here and I have given myself some license with the MVVM architecture.

## Verification
The first thing we will do as soon as the app is started is to check if the user will be able to run the app.  Remember, the device must have the U1 chip and be running on iOS14.

The `NISession` class has a static property called `isSupported` that tells us if the device can work with NearbyInteractions. We must use this property to find out if we can continue executing the app.

```swift
// CercaViewModel
internal static var nearbySessionAvailable: Bool
{
    return NISession.isSupported
}

...

// CercaApp
if CercaViewModel.nearbySessionAvailable
{
    NearbyView()
}
else
{
    ErrorView()
}
```

Here we asked about the value of the property and, depending on the result, presented the main view or the error.

## Discovering other devices

If our device (both physical or in the simulator) is supported, we must now discover other devices and establish a NearbyInteraction session and a MultipeerConnectivity session. The sequence to follow is as follows

1. We start a `NISession` session
2. Exchange our token with other devices if it is a *reconnection*
3. Start a MultipeerConnectivity session:
   - We create the session
   - We start the advertiser (We announce our presence)
   - We start the browser (We search for other devices)

```swift
// CercaViewModel
...

/**
    Arrancamos las sesiones de `NearbyInteraction`
    y de `MultipeerConnectivity`
*/
override internal init()
{
    // Avoid any simulator instances from finding any actual devices.
    #if targetEnvironment(simulator)
    self.serviceIdentity = "com.desappstre.Cerca./simulator_ni"
    #else
    self.serviceIdentity = "com.desappstre.Cerca./device_ni"
    #endif

    super.init()

    self.startNearbySession()
    self.startMultipeerSession()
}

/**
    Arranca la sesión de `NearbyInteraction`.
    También se inicia la sesión de `MultipeerConectivity`
    en caso que sea la primera vez que se inica la app.
*/
internal func startNearbySession() -> Void
{
    // 1. Creamos la NISession.
    self.nearbySession = NISession()

    // 2. Ahora el delegado.
    // Recibimos datos sobre el estado de la sesión
    self.nearbySession?.delegate = self

    // Es una nueva sesión así que tendremos que
    // intercambiar nuestro token.
    sharedTokenWithPeer = false

    // 3. Si la variable `peer` existe es porque se ha reiniciado
    // la sesión así que tenemos qque volver a compartir el token.
    if self.peer != nil && self.multipeerSession != nil
    {
        if !self.sharedTokenWithPeer
        {
            shareTokenWithAllPeers()
        }
    }
    else
    {
        self.startMultipeerSession()
    }
}

/**
    Arranca la sesión de `MultipeerConnectivity`
    Lo principal son los tres objetos que se crean aquí
    * `MCSession`: La sesión de MultipeerConnectivity
    * `MCNearbyServiceAdvertiser`: Se encarga de decir a todos que
            estamos aquí.
    * `MCNearbyServiceBrowser`: Nos dice si hay otros dispositivos
            ahí fuera.
    Todos estos objetos tienen sus respectivos delegados
    **donde recibimos actualizaión del estado** de todo lo relacionado
    con `MultipeerConnectivity`
 */
private func startMultipeerSession() -> Void
{
    if self.multipeerSession == nil
    {
        let localPeer = MCPeerID(displayName: UIDevice.current.name)

        // 4
        self.multipeerSession = MCSession(peer: localPeer,
                                          securityIdentity: nil,
                                          encryptionPreference: .required)

        // 5
        self.multipeerAdvertiser = MCNearbyServiceAdvertiser(peer: localPeer,
                                                 discoveryInfo: [ "identity" : serviceIdentity],
                                                 serviceType: "desappstrecerca")

        // 6
        self.multipeerBrowser = MCNearbyServiceBrowser(peer: localPeer,
                                                       serviceType: "desappstrecerca")

        // 7
        self.multipeerSession?.delegate = self
        self.multipeerAdvertiser?.delegate = self
        self.multipeerBrowser?.delegate = self
    }

    self.stopMultipeerSession()

    // 8
    self.multipeerAdvertiser?.startAdvertisingPeer()
    self.multipeerBrowser?.startBrowsingForPeers()
}

...
```

As I said before, the first thing  to do is to: (1) create the session for NearbyInteraction, (2) assign it the class that implements the delegate, and (3) exchange the token if we are reconnecting with a client.

Now it is the MultipeerConnectivity session's turn, which we will use to exchange the token. Again we (4) create a session where we say who we are using the `MCPeerID` class (for the example we use the device model name).

Then we have to (5) create the advertising services so that others know that we are here and (6) the discovery service to know who is around. Then we have to (7) establish the delegates for each of them and (8) start the advertising and browser sessions.

Let's pause for a moment in creating the advertising session, `MCNearbyServiceAdvertiser` and discovery session, `MCNearbyServiceBrowser`. You will see that a parameter called `serviceType` is passed, which must comply with the Bonjour services nomenclature. The `discovertyInfo` parameter is the identifier of our service, which is recommended to call using the dns-reverse nomenclature.

## Connecting to other devices

Let's assume that there is another device near us and our app has started. The time has come to exchange tokens in order to start obtaining data from the `NearbyInteraction` session.

We will know that there is another device becuase we get alerted about it in the browser function: `(_: foundPeer :)`:

(1) If the service identifier is that of our app, we proceed to invite you to join a MultipeerConnectivity session.

(2) If the invitation is accepted, we will know how the connection process is going thanks to the session `(_: peer: didChange :)` function where we will know the exact moment in which we connect with the other device.

(3) Now we exchange tokens with the other client.

```swift
extension CercaViewModel: MCNearbyServiceBrowserDelegate
{
    ...
    
    /// 1
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) -> Void
    {
        guard let info = info,
              let identity = info["identity"],
              let multipeerSession = self.multipeerSession,
              (identity == self.serviceIdentity && multipeerSession.connectedPeers.count < self.maxPeersInSession)
        else
        {
            return
        }
        
        browser.invitePeer(peerID, to: multipeerSession, withContext: nil, timeout: 10)
    }
    
    ...
}

extension CercaViewModel: MCSessionDelegate
{
    ...
    
    /// 2
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState)
    {
        DispatchQueue.main.async
        {
            switch state
            {
                case .connected:
                    self.peerName = peerID.displayName
                    self.peer = peerID
                    
                    // 3
                    self.shareTokenWithAllPeers()
                    
                    self.isConnectionLost = false
                    
                case .notConnected:
                    self.isConnectionLost = true
                    
                case .connecting:
                    self.peerName = "Hola ¿Quién eres? 👋"
                    
                @unknown default:
                    fatalError("Ha aparecido un estado nuevo de la enumeración. Ni idea lo que hacer.")
            }
        }
    }
    
    ...
}
```

Token exchange is done using the MultipeerConnectivity session. Previously, we have had to encrypt the tokens using `NSKeyedArchiver`. Since `NIDiscoveryToken` implements the `NSSecureCoding` protocol, we can send it to the other device in a secure way.

```swift
/**
    Desde aquí compartimos nuestro token de
    `NearbyInteraction` con los otros dispositivos.
 */
private func shareTokenWithAllPeers() -> Void
{
    guard let token = nearbySession?.discoveryToken,
          let multipeerSession = self.multipeerSession,
          let encodedData = try?  NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    else
    {
        fatalError("Ese token no se puede codificar. 😭")
    }

    do
    {
        try self.multipeerSession?.send(encodedData,
                                        toPeers: multipeerSession.connectedPeers,
                                        with: .reliable)
    }
    catch let error
    {
        print("No se puede enviar el token a los dispositivos. \(error.localizedDescription)")
    }

    // Ya hemos compartido el token.
    self.sharedTokenWithPeer = true
}


```

However, as we said, we exchange the token so that the other point of connection send us their token, which we will use to start the NearbyInteraction session.

```swift
extension CercaViewModel: MCSessionDelegate
{
    ...
    
    /// 
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID)
    {
        guard peerID.displayName == self.peerName else
        {
            // Llegan datos de un cliente que no es
            // con el que hemos iniciado la sesión
            return
        }
        
        guard let discoveryToken = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else
        {
            fatalError("No se ha podido leer el token del otro dispositivo")
        }
        
        // Creamos la configuración...
        let config = NINearbyPeerConfiguration(peerToken: discoveryToken)

        // ...arrancamos la sesión de NearbyInteraction...
        self.nearbySession?.run(config)
        // ...y guardo el token del cliente por si tengo
        // que reanudar mi sesión.
        self.peerToken = discoveryToken
        
        DispatchQueue.main.async {
            self.isConnectionLost = false
        }
    }
    
    ...
}

```

Once we have decoded the token, we use it to create the `NISession` session configuration and then start it. With this we are ready to receive data on the position of the other device.

## Distance and Position

Now the NISession delegate enters the scene. Here where we will receive the position and distance updates relative to the other device.

Keep in mind that both (position and distance) can be null since there are times when it will not be possible to establish the position with respect to the other device due to obstacles that stand between them.

The position is a field that will be null if there is no line of sight on the device. This line of sight is the same as that of the iPhone's wide-angle camera.

The distance is a `Float` type whose value is measured in meters and the direction is a vector of type `simd_float3`, which contains the values for the X (left or right), Y (up or down) Z (near or far) axes.

All this comes through the session `(_: didUpdate :)` function that receives an array of `NINearbyObject`, which are the objects that contain the distance in the distance variable and the address in the direction variable.

```swift
extension CercaViewModel: NISessionDelegate
{
    ...
    
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) -> Void
    {
        guard let nearbyObject = nearbyObjects.first else
        {
            return
        }
        
        self.distanceToPeer = nearbyObject.distance
        
        if let direction = nearbyObject.direction
        {
            
            self.isDirectionAvailable = true
            self.directionAngle = direction.x > 0.0 ? 90.0 : -90.0
        }
        else
        {
            self.isDirectionAvailable = false
        }
    }
    
    ...
}
```

And with this we are already able to know where the other device is located.

## Session lifetime

We have to be careful with the session and the tokens, because when the session is lost, the tokens must be exchanged between the devices again.

For example, a session loss can happen because the user closes the app or stops being in the foreground.

```swift
extension CercaViewModel: NISessionDelegate
{
    /// La sesión no vale. 
    /// Hay que iniciar otra.
    func session(_ session: NISession, didInvalidateWith error: Error) -> Void
    {
        self.startNearbySession()
    }
    
    /// Se ha perdido la conexión con el otro dispositivo
    /// La sesión no vale, tenemos que crear otra.
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) -> Void
    {
        session.invalidate()
        self.startNearbySession()

    }
    
    /// La app vuelve al primer plano
    func sessionSuspensionEnded(_ session: NISession) -> Void
    {
        guard let peerToken = self.peerToken else
        {
            return
        }
        
        // Creamos la configuración...
        let config = NINearbyPeerConfiguration(peerToken: peerToken)
        // volvemos a levantar la sesión
        self.nearbySession?.run(config)
        
        self.shareTokenWithAllPeers()
    }
    
    /// La app pasa a background
    func sessionWasSuspended(_ session: NISession) -> Void
    {
        print("\(#function). Volveré... 🙋‍♂️")
    }
}
```

It is very important to remember that sessions can be invalidated and that it is necessary to exchange tokens.

## Good practices

The Cupertino engineers, who have developed this framework and know what they are talking about, recommend the following:

- Check if the device supports NearbyInteraction framework
- Keep in mind that distance and position can be null and that does not mean it is an error.
- Run the application in portrait mode if possible.
- 
Now you just have to have fun using the framework!
