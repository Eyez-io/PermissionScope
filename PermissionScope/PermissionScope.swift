//
//  PermissionScope.swift
//  PermissionScope
//
//  Created by Nick O'Neill on 4/5/15.
//  Copyright (c) 2015 That Thing in Swift. All rights reserved.
//

import UIKit
import CoreLocation
import AddressBook
import AVFoundation
import Photos
import EventKit
import CoreBluetooth
import CoreMotion
import Contacts

public typealias statusRequestClosure = (status: PermissionStatus) -> Void
public typealias authClosureType      = (finished: Bool, results: [PermissionResult]) -> Void
public typealias cancelClosureType    = (results: [PermissionResult]) -> Void
typealias resultsForConfigClosure     = ([PermissionResult]) -> Void

@objc public class PermissionScope: UIViewController, CLLocationManagerDelegate, UIGestureRecognizerDelegate, CBPeripheralManagerDelegate {

    // MARK: UI Parameters
    
    /// Header UILabel with the message "Hey, listen!" by default.
    public var headerLabel                 = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 50))
    /// Header UILabel with the message "We need a couple things\r\nbefore you get started." by default.
    public var bodyLabel                   = UILabel(frame: CGRect(x: 0, y: 0, width: 240, height: 70))
    /// Color for the close button's text color.
    public var closeButtonTextColor        = UIColor(red: 0, green: 0.47, blue: 1, alpha: 1)
    /// Color for the permission buttons' text color.
    public var permissionButtonTextColor   = UIColor(red: 0, green: 0.47, blue: 1, alpha: 1)
    /// Color for the permission buttons' border color.
    public var permissionButtonBorderColor = UIColor(red: 0, green: 0.47, blue: 1, alpha: 1)
    /// Width for the permission buttons.
    public var permissionButtonΒorderWidth  : CGFloat = 1
    /// Corner radius for the permission buttons.
    public var permissionButtonCornerRadius : CGFloat = 6
    /// Color for the permission labels' text color.
    public var permissionLabelColor:UIColor = .blackColor()
    /// Font used for all the UIButtons
    public var buttonFont:UIFont            = .boldSystemFontOfSize(14)
    /// Font used for all the UILabels
    public var labelFont:UIFont             = .systemFontOfSize(14)
    /// Close button. By default in the top right corner.
    public var closeButton                  = UIButton(frame: CGRect(x: 0, y: 0, width: 50, height: 32))
    /// Offset used to position the Close button.
    public var closeOffset                  = CGSizeZero
    /// Color used for permission buttons with authorized status
    public var authorizedButtonColor        = UIColor(red: 0, green: 0.47, blue: 1, alpha: 1)
    /// Color used for permission buttons with unauthorized status. By default, inverse of `authorizedButtonColor`.
    public var unauthorizedButtonColor:UIColor?
    
    public var allowedIconLabelString: String = "V"
    public var deniedIconLabelString: String = "X"
    public var disabledIconLabelString: String = "-"
    
    public var iconLabelStringByTypeMap: [PermissionType: String] = [
        .Bluetooth: "BT",
        .Camera: "CA",
        .Contacts: "CO",
        .Events: "EV",
        .LocationAlways: "LA",
        .LocationInUse: "LU",
        .Microphone: "MI",
        .Motion: "MO",
        .Notifications: "NO",
        .Photos: "PH",
        .Reminders: "RE"
    ]
    
    /// Messages for the body label of the dialog presented when requesting access.
    lazy var permissionMessages: [PermissionType : String?] = [:]
    
    // MARK: View hierarchy for custom alert
    let baseView    = UIView()
    public let contentView = UIView()

    // MARK: - Various lazy managers
    lazy var locationManager:CLLocationManager = {
        let lm = CLLocationManager()
        lm.delegate = self
        return lm
    }()

    lazy var bluetoothManager:CBPeripheralManager = {
        return CBPeripheralManager(delegate: self, queue: nil, options:[CBPeripheralManagerOptionShowPowerAlertKey: false])
    }()
    
    lazy var motionManager:CMMotionActivityManager = {
        return CMMotionActivityManager()
    }()
    
    /// NSUserDefaults standardDefaults lazy var
    lazy var defaults:NSUserDefaults = {
        return .standardUserDefaults()
    }()
    
    /// Default status for Core Motion Activity
    var motionPermissionStatus: PermissionStatus = .Unknown

    // MARK: - Internal state and resolution
    
    /// Permissions configured using `addPermission(:)`
    var configuredPermissions: [Permission] = []
    var permissionButtonContainerViews: [UIView] = []
    var permissionLabels: [PermissionType: UILabel] = [:]
	
	// Useful for direct use of the request* methods
    
    /// Callback called when permissions status change.
    public var onAuthChange: authClosureType? = nil
    /// Callback called when the user taps on the close button.
    public var onCancel: cancelClosureType?   = nil
    
    /// Called when the user has disabled or denied access to notifications, and we're presenting them with a help dialog.
    public var onDisabledOrDenied: cancelClosureType? = nil
	/// View controller to be used when presenting alerts. Defaults to self. You'll want to set this if you are calling the `request*` methods directly.
	public var viewControllerForAlerts : UIViewController?

    /**
    Checks whether all the configured permission are authorized or not.
    
    - parameter completion: Closure used to send the result of the check.
    */
    func allAuthorized(completion: (Bool) -> Void ) {
        self.getResultsForConfig{ results in
            let result = results
                .first { $0.status != .Authorized }
                .isNil
            completion(result)
        }
    }
    
    /**
    Checks whether all the required configured permission are authorized or not.
    **Deprecated** See issues #50 and #51.
    
    - parameter completion: Closure used to send the result of the check.
    */
    func requiredAuthorized(completion: (Bool) -> Void ) {
        self.getResultsForConfig{ results in
            let result = results
                .first { $0.status != .Authorized }
                .isNil
            completion(result)
        }
    }
    
    // use the code we have to see permission status
    public func permissionStatuses(permissionTypes: [PermissionType]?) -> Dictionary<PermissionType, PermissionStatus> {
        var statuses: Dictionary<PermissionType, PermissionStatus> = [:]
        let types: [PermissionType] = permissionTypes ?? PermissionType.allValues
        
        for type in types {
            self.statusForPermission(type, completion: { status in
                statuses[type] = status
            })
        }
        
        return statuses
    }
    
    /**
    Designated initializer.
    
    - parameter backgroundTapCancels: True if a tap on the background should trigger the dialog dismissal.
    */
    public init(backgroundTapCancels: Bool) {
        super.init(nibName: nil, bundle: nil)

		self.viewControllerForAlerts = self
		
        // Set up main view
        self.view.frame = UIScreen.mainScreen().bounds
        self.view.autoresizingMask = [UIViewAutoresizing.FlexibleHeight, UIViewAutoresizing.FlexibleWidth]
        self.view.backgroundColor = UIColor(red:0, green:0, blue:0, alpha:0.7)
        self.view.addSubview(self.baseView)
        // Base View
        self.baseView.frame = self.view.frame
        self.baseView.addSubview(self.contentView)
        if backgroundTapCancels {
            let tap = UITapGestureRecognizer(target: self, action: Selector("cancel"))
            tap.delegate = self
            self.baseView.addGestureRecognizer(tap)
        }
        // Content View
        self.contentView.backgroundColor = UIColor.whiteColor()
        self.contentView.layer.cornerRadius = 3
        self.contentView.layer.masksToBounds = true
        self.contentView.layer.borderWidth = 0.5

        // header label
        self.headerLabel.font = UIFont.systemFontOfSize(22)
        self.headerLabel.textColor = UIColor.blackColor()
        self.headerLabel.textAlignment = NSTextAlignment.Center
        self.headerLabel.text = "Hey, listen!".localized

        self.contentView.addSubview(self.headerLabel)

        // body label
        self.bodyLabel.font = UIFont.boldSystemFontOfSize(16)
        self.bodyLabel.textColor = UIColor.blackColor()
        self.bodyLabel.textAlignment = NSTextAlignment.Center
        self.bodyLabel.text = "We need a couple things\r\nbefore you get started.".localized
        self.bodyLabel.numberOfLines = 2

        self.contentView.addSubview(self.bodyLabel)
        
        // close button
        self.closeButton.setTitle("Close".localized, forState: .Normal)
        self.closeButton.addTarget(self, action: Selector("cancel"), forControlEvents: UIControlEvents.TouchUpInside)
        
        self.contentView.addSubview(self.closeButton)
        
        self.statusMotion() //Added to check motion status on load
    }
    
    /**
    Convenience initializer. Same as `init(backgroundTapCancels: true)`
    */
    public convenience init() {
        self.init(backgroundTapCancels: true)
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
        super.init(nibName:nibNameOrNil, bundle:nibBundleOrNil)
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let screenSize = UIScreen.mainScreen().bounds.size
        // Set background frame
        self.view.frame.size = screenSize
        // Set frames
        let x = (screenSize.width - Constants.UI.contentWidth) / 2

        let dialogHeight: CGFloat
        switch self.configuredPermissions.count {
        case 2:
            dialogHeight = Constants.UI.dialogHeightTwoPermissions
        case 3:
            dialogHeight = Constants.UI.dialogHeightThreePermissions
        default:
            dialogHeight = Constants.UI.dialogHeightSinglePermission
        }
        
        let y = (screenSize.height - dialogHeight) / 2
        self.contentView.frame = CGRect(x:x, y:y, width:Constants.UI.contentWidth, height:dialogHeight)

        // offset the header from the content center, compensate for the content's offset
        self.headerLabel.center = self.contentView.center
        self.headerLabel.frame.offsetInPlace(dx: -self.contentView.frame.origin.x, dy: -self.contentView.frame.origin.y)
        self.headerLabel.frame.offsetInPlace(dx: 0, dy: -((dialogHeight/2)-50))

        // ... same with the body
        self.bodyLabel.center = self.contentView.center
        self.bodyLabel.frame.offsetInPlace(dx: -self.contentView.frame.origin.x, dy: -self.contentView.frame.origin.y)
        self.bodyLabel.frame.offsetInPlace(dx: 0, dy: -((dialogHeight/2)-100))
        
        self.closeButton.center = self.contentView.center
        self.closeButton.frame.offsetInPlace(dx: -self.contentView.frame.origin.x, dy: -self.contentView.frame.origin.y)
        self.closeButton.frame.offsetInPlace(dx: 105, dy: -((dialogHeight/2)-20))
        self.closeButton.frame.offsetInPlace(dx: self.closeOffset.width, dy: self.closeOffset.height)
        if let _ = self.closeButton.imageView?.image {
            self.closeButton.setTitle("", forState: .Normal)
        }
        self.closeButton.setTitleColor(self.closeButtonTextColor, forState: .Normal)

        var index = 0
        var offset: CGFloat = CGRectGetMaxY(self.bodyLabel.frame) + 10
        let offsetForButton: CGFloat = 45
        let offsetForMessage: CGFloat = 60
        for bcv in self.permissionButtonContainerViews {
            bcv.center = self.contentView.center
            bcv.frame.offsetInPlace(dx: -self.contentView.frame.origin.x, dy: -self.contentView.frame.origin.y)
            bcv.frame.origin = CGPoint(x: bcv.frame.origin.x, y: offset)
            offset += offsetForButton
            
            let type = self.configuredPermissions[index].type

            if let label = self.permissionLabels[type] {
                label.center = self.contentView.center
                label.frame.offsetInPlace(dx: -self.contentView.frame.origin.x, dy: -self.contentView.frame.origin.y)
                label.frame.origin = CGPoint(x: label.frame.origin.x, y: offset)
                offset += offsetForMessage
            }
            
            index++

            self.statusForPermission(type,
                completion: { currentStatus in
                    if let iconLabel = bcv.viewWithTag(1) as? UILabel, let mainLabel = bcv.viewWithTag(2) as? UILabel {
                        let prettyDescription = type.prettyDescription
                        if currentStatus == .Authorized {
                            self.setButtonContainerViewAuthorizedStyle(bcv)
                            mainLabel.text = "Allowed \(prettyDescription)".localized.uppercaseString
                            iconLabel.text = self.allowedIconLabelString
                        } else if currentStatus == .Unauthorized {
                            self.setButtonContainerViewUnauthorizedStyle(bcv)
                            mainLabel.text = "Denied \(prettyDescription)".localized.uppercaseString
                            iconLabel.text = self.deniedIconLabelString
                        } else if currentStatus == .Disabled {
                            //                setButtonDisabledStyle(button)
                            mainLabel.text = "\(prettyDescription) Disabled".localized.uppercaseString
                            iconLabel.text = self.disabledIconLabelString
                        }
                    }
            })
        }
        
        offset += 10
        self.contentView.frame.size = CGSize(width: Constants.UI.contentWidth, height: offset)
        self.contentView.center = CGPoint(x: self.baseView.bounds.size.width / 2, y: self.baseView.bounds.size.height / 2)
    }

    // MARK: - Customizing the permissions
    
    /**
    Adds a permission configuration to PermissionScope.
    
    - parameter config: Configuration for a specific permission.
    - parameter message: Body label's text on the presented dialog when requesting access.
    */
    @objc public func addPermission(permission: Permission, message: String? = nil) {
        assert(self.configuredPermissions.count < 3, "Ask for three or fewer permissions at a time")
        assert(self.configuredPermissions.first { $0.type == permission.type }.isNil, "Permission for \(permission.type) already set")
        
        self.configuredPermissions.append(permission)
        self.permissionMessages[permission.type] = message
        
        if permission.type == .Bluetooth && self.askedBluetooth {
            self.triggerBluetoothStatusUpdate()
        } else if permission.type == .Motion && self.askedMotion {
            self.triggerMotionStatusUpdate()
        }
    }

    /**
    Permission button factory. Uses the custom style parameters such as `permissionButtonTextColor`, `buttonFont`, etc.
    
    - parameter type: Permission type
    
    - returns: UIButton instance with a custom style.
    */
    func permissionStyledButtonContainerView(type: PermissionType) -> UIView {
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 220, height: 40))
        containerView.layer.borderWidth = self.permissionButtonΒorderWidth
        containerView.layer.borderColor = self.permissionButtonBorderColor.CGColor
        containerView.layer.cornerRadius = self.permissionButtonCornerRadius

        let iconLabel = UILabel(frame: CGRect(x: 5, y: 5, width: 30, height: 30))
        iconLabel.backgroundColor = UIColor.clearColor()
        iconLabel.font = UIFont.systemFontOfSize(12)
        iconLabel.textColor = self.permissionButtonTextColor
        iconLabel.tag = 1
        iconLabel.text = self.iconLabelStringByTypeMap[type] ?? ""
        containerView.addSubview(iconLabel)
        
        let mainLabel = UILabel(frame: CGRect(x: 40, y: 0, width: 180, height: 40))
        mainLabel.backgroundColor = UIColor.clearColor()
        mainLabel.font = self.buttonFont
        mainLabel.textColor = self.permissionButtonTextColor
        mainLabel.adjustsFontSizeToFitWidth = true
        mainLabel.minimumScaleFactor = 0.7
        mainLabel.tag = 2
        
        // this is a bit of a mess, eh?
        switch type {
        case .LocationAlways, .LocationInUse:
            mainLabel.text = "Enable \(type.prettyDescription)".localized
        default:
            mainLabel.text = "Enable \(type)".localized
        }
        
        containerView.addSubview(mainLabel)

        let button = UIButton(type: .Custom)
        button.frame = CGRect(x: 0, y: 0, width: 220, height: 40)
        button.addTarget(self, action: Selector("request\(type)"), forControlEvents: .TouchUpInside)
        
        containerView.addSubview(button)
        
        return containerView
    }

    /**
    Sets the style for permission buttons with authorized status.
    
    - parameter button: Permission button
    */
    func setButtonContainerViewAuthorizedStyle(buttonContainerView: UIView) {
        buttonContainerView.layer.borderWidth = 0
        buttonContainerView.backgroundColor = self.authorizedButtonColor
        if let label = buttonContainerView.viewWithTag(1) as? UILabel {
            label.textColor = .whiteColor()
        }
        if let label = buttonContainerView.viewWithTag(2) as? UILabel {
            label.textColor = .whiteColor()
        }
    }
    
    /**
    Sets the style for permission buttons with unauthorized status.
    
    - parameter button: Permission button
    */
    func setButtonContainerViewUnauthorizedStyle(buttonContainerView: UIView) {
        buttonContainerView.layer.borderWidth = 0
        buttonContainerView.backgroundColor = self.unauthorizedButtonColor ?? self.authorizedButtonColor.inverseColor
        if let label = buttonContainerView.viewWithTag(1) as? UILabel {
            label.textColor = .whiteColor()
        }
        if let label = buttonContainerView.viewWithTag(2) as? UILabel {
            label.textColor = .whiteColor()
        }
    }

    /**
    Permission label factory, located below the permission buttons.
    
    - parameter type: Permission type
    
    - returns: UILabel instance with a custom style.
    */
    func permissionStyledLabel(type: PermissionType) -> UILabel? {
        guard let message = self.permissionMessages[type], let msgString = message where msgString.isEmpty == false else {
            return nil
        }
        
        let label  = UILabel(frame: CGRect(x: 0, y: 0, width: 260, height: 50))
        label.font = self.labelFont
        label.numberOfLines = 2
        label.textAlignment = .Center
        label.text = msgString
        label.textColor = self.permissionLabelColor
        
        return label
    }

    // MARK: - Status and Requests for each permission
    
    // MARK: Location
    
    /**
    Returns the current permission status for accessing LocationAlways.
    
    - returns: Permission status for the requested type.
    */
    public func statusLocationAlways() -> PermissionStatus {
        guard CLLocationManager.locationServicesEnabled() else { return .Disabled }

        let status = CLLocationManager.authorizationStatus()
        switch status {
        case .AuthorizedAlways:
            return .Authorized
        case .Restricted, .Denied:
            return .Unauthorized
        case .AuthorizedWhenInUse:
            // Curious why this happens? Details on upgrading from WhenInUse to Always:
            // [Check this issue](https://github.com/nickoneill/PermissionScope/issues/24)
            if self.defaults.boolForKey(Constants.NSUserDefaultsKeys.requestedInUseToAlwaysUpgrade) {
                return .Unauthorized
            } else {
                return .Unknown
            }
        case .NotDetermined:
            return .Unknown
        }
    }

    /**
    Requests access to LocationAlways, if necessary.
    */
    public func requestLocationAlways() {
    	let hasAlwaysKey:Bool = !NSBundle.mainBundle()
    		.objectForInfoDictionaryKey(Constants.InfoPlistKeys.locationAlways).isNil
    	assert(hasAlwaysKey, Constants.InfoPlistKeys.locationAlways + " not found in Info.plist.")
    	
        let status = self.statusLocationAlways()
        switch status {
        case .Unknown:
            if CLLocationManager.authorizationStatus() == .AuthorizedWhenInUse {
                self.defaults.setBool(true, forKey: Constants.NSUserDefaultsKeys.requestedInUseToAlwaysUpgrade)
                self.defaults.synchronize()
            }
            self.locationManager.requestAlwaysAuthorization()
        case .Unauthorized:
            self.showDeniedAlert(.LocationAlways)
        case .Disabled:
            self.showDisabledAlert(.LocationInUse)
        default:
            break
        }
    }

    /**
    Returns the current permission status for accessing LocationWhileInUse.
    
    - returns: Permission status for the requested type.
    */
    public func statusLocationInUse() -> PermissionStatus {
        guard CLLocationManager.locationServicesEnabled() else { return .Disabled }
        
        let status = CLLocationManager.authorizationStatus()
        // if you're already "always" authorized, then you don't need in use
        // but the user can still demote you! So I still use them separately.
        switch status {
        case .AuthorizedWhenInUse, .AuthorizedAlways:
            return .Authorized
        case .Restricted, .Denied:
            return .Unauthorized
        case .NotDetermined:
            return .Unknown
        }
    }

    /**
    Requests access to LocationWhileInUse, if necessary.
    */
    public func requestLocationInUse() {
    	let hasWhenInUseKey :Bool = !NSBundle.mainBundle()
    		.objectForInfoDictionaryKey(Constants.InfoPlistKeys.locationWhenInUse).isNil
    	assert(hasWhenInUseKey, Constants.InfoPlistKeys.locationWhenInUse + " not found in Info.plist.")
    	
        let status = self.statusLocationInUse()
        switch status {
        case .Unknown:
            self.locationManager.requestWhenInUseAuthorization()
        case .Unauthorized:
            self.showDeniedAlert(.LocationInUse)
        case .Disabled:
            self.showDisabledAlert(.LocationInUse)
        default:
            break
        }
    }

    // MARK: Contacts
    
    /**
    Returns the current permission status for accessing Contacts.
    
    - returns: Permission status for the requested type.
    */
    public func statusContacts() -> PermissionStatus {
        if #available(iOS 9.0, *) {
            let status = CNContactStore.authorizationStatusForEntityType(.Contacts)
            switch status {
            case .Authorized:
                return .Authorized
            case .Restricted, .Denied:
                return .Unauthorized
            case .NotDetermined:
                return .Unknown
            }
        } else {
            // Fallback on earlier versions
            let status = ABAddressBookGetAuthorizationStatus()
            switch status {
            case .Authorized:
                return .Authorized
            case .Restricted, .Denied:
                return .Unauthorized
            case .NotDetermined:
                return .Unknown
            }
        }
    }

    /**
    Requests access to Contacts, if necessary.
    */
    public func requestContacts() {
        let status = self.statusContacts()
        switch status {
        case .Unknown:
            if #available(iOS 9.0, *) {
                CNContactStore().requestAccessForEntityType(.Contacts, completionHandler: {
                    success, error in
                    self.detectAndCallback()
                })
            } else {
                ABAddressBookRequestAccessWithCompletion(nil) { success, error in
                    self.detectAndCallback()
                }
            }
        case .Unauthorized:
            self.showDeniedAlert(.Contacts)
        default:
            break
        }
    }

    // MARK: Notifications
    
    /**
    Returns the current permission status for accessing Notifications.
    
    - returns: Permission status for the requested type.
    */
    public func statusNotifications() -> PermissionStatus {
        let settings = UIApplication.sharedApplication().currentUserNotificationSettings()
        if let settingTypes = settings?.types where settingTypes != .None {
            return .Authorized
        } else {
            if self.defaults.boolForKey(Constants.NSUserDefaultsKeys.requestedNotifications) {
                return .Unauthorized
            } else {
                return .Unknown
            }
        }
    }
    
    /**
    To simulate the denied status for a notifications permission,
    we track when the permission has been asked for and then detect
    when the app becomes active again. If the permission is not granted
    immediately after becoming active, the user has cancelled or denied
    the request.
    
    This function is called when we want to show the notifications
    alert, kicking off the entire process.
    */
    func showingNotificationPermission() {
        NSNotificationCenter.defaultCenter().removeObserver(self,
            name: UIApplicationWillResignActiveNotification,
            object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: Selector("finishedShowingNotificationPermission"),
            name: UIApplicationDidBecomeActiveNotification, object: nil)
        self.notificationTimer?.invalidate()
    }
    
    /**
    A timer that fires the event to let us know the user has asked for 
    notifications permission.
    */
    var notificationTimer : NSTimer?

    /**
    This function is triggered when the app becomes 'active' again after
    showing the notification permission dialog.
    
    See `showingNotificationPermission` for a more detailed description
    of the entire process.
    */
    func finishedShowingNotificationPermission () {
        NSNotificationCenter.defaultCenter().removeObserver(self,
            name: UIApplicationWillResignActiveNotification,
            object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self,
            name: UIApplicationDidBecomeActiveNotification,
            object: nil)
        
        self.notificationTimer?.invalidate()
        
        self.defaults.setBool(true, forKey: Constants.NSUserDefaultsKeys.requestedNotifications)
        self.defaults.synchronize()

        // callback after a short delay, otherwise notifications don't report proper auth
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,Int64(0.1 * Double(NSEC_PER_SEC))),
            dispatch_get_main_queue(), {
            self.getResultsForConfig { results in
                guard let notificationResult = results
                    .first({ $0.type == .Notifications }) else { return }
                if notificationResult.status == .Unknown {
                    self.showDeniedAlert(notificationResult.type)
                } else {
                    self.detectAndCallback()
                }
            }
        })
    }
    
    /**
    Requests access to User Notifications, if necessary.
    */
    public func requestNotifications() {
        let status = self.statusNotifications()
        switch status {
        case .Unknown:
            let notificationsPermission = self.configuredPermissions
                .first { $0 is NotificationsPermission } as? NotificationsPermission
            let notificationsPermissionSet = notificationsPermission?.notificationCategories

            NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("showingNotificationPermission"), name: UIApplicationWillResignActiveNotification, object: nil)
            
            self.notificationTimer = NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: Selector("finishedShowingNotificationPermission"), userInfo: nil, repeats: false)
            
            UIApplication.sharedApplication().registerUserNotificationSettings(
                UIUserNotificationSettings(forTypes: [.Alert, .Sound, .Badge],
                categories: notificationsPermissionSet)
            )
        case .Unauthorized:
            self.showDeniedAlert(.Notifications)
        case .Disabled:
            self.showDisabledAlert(.Notifications)
        case .Authorized:
            self.detectAndCallback()
        }
    }
    
    // MARK: Microphone
    
    /**
    Returns the current permission status for accessing the Microphone.
    
    - returns: Permission status for the requested type.
    */
    public func statusMicrophone() -> PermissionStatus {
        let recordPermission = AVAudioSession.sharedInstance().recordPermission()
        switch recordPermission {
        case AVAudioSessionRecordPermission.Denied:
            return .Unauthorized
        case AVAudioSessionRecordPermission.Granted:
            return .Authorized
        default:
            return .Unknown
        }
    }
    
    /**
    Requests access to the Microphone, if necessary.
    */
    public func requestMicrophone() {
        let status = self.statusMicrophone()
        switch status {
        case .Unknown:
            AVAudioSession.sharedInstance().requestRecordPermission({ granted in
                self.detectAndCallback()
            })
        case .Unauthorized:
            self.showDeniedAlert(.Microphone)
        case .Disabled:
            self.showDisabledAlert(.Microphone)
        case .Authorized:
            break
        }
    }
    
    // MARK: Camera
    
    /**
    Returns the current permission status for accessing the Camera.
    
    - returns: Permission status for the requested type.
    */
    public func statusCamera() -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeVideo)
        switch status {
        case .Authorized:
            return .Authorized
        case .Restricted, .Denied:
            return .Unauthorized
        case .NotDetermined:
            return .Unknown
        }
    }
    
    /**
    Requests access to the Camera, if necessary.
    */
    public func requestCamera() {
        let status = self.statusCamera()
        switch status {
        case .Unknown:
            AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo,
                completionHandler: { granted in
                    self.detectAndCallback()
            })
        case .Unauthorized:
            self.showDeniedAlert(.Camera)
        case .Disabled:
            self.showDisabledAlert(.Camera)
        case .Authorized:
            break
        }
    }

    // MARK: Photos
    
    /**
    Returns the current permission status for accessing Photos.
    
    - returns: Permission status for the requested type.
    */
    public func statusPhotos() -> PermissionStatus {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .Authorized:
            return .Authorized
        case .Denied, .Restricted:
            return .Unauthorized
        case .NotDetermined:
            return .Unknown
        }
    }
    
    /**
    Requests access to Photos, if necessary.
    */
    public func requestPhotos() {
        let status = self.statusPhotos()
        switch status {
        case .Unknown:
            PHPhotoLibrary.requestAuthorization({ status in
                self.detectAndCallback()
            })
        case .Unauthorized:
            self.showDeniedAlert(.Photos)
        case .Disabled:
            self.showDisabledAlert(.Photos)
        case .Authorized:
            break
        }
    }
    
    // MARK: Reminders
    
    /**
    Returns the current permission status for accessing Reminders.
    
    - returns: Permission status for the requested type.
    */
    public func statusReminders() -> PermissionStatus {
        let status = EKEventStore.authorizationStatusForEntityType(.Reminder)
        switch status {
        case .Authorized:
            return .Authorized
        case .Restricted, .Denied:
            return .Unauthorized
        case .NotDetermined:
            return .Unknown
        }
    }
    
    /**
    Requests access to Reminders, if necessary.
    */
    public func requestReminders() {
        let status = self.statusReminders()
        switch status {
        case .Unknown:
            EKEventStore().requestAccessToEntityType(.Reminder,
                completion: { granted, error in
                    self.detectAndCallback()
            })
        case .Unauthorized:
            self.showDeniedAlert(.Reminders)
        default:
            break
        }
    }
    
    // MARK: Events
    
    /**
    Returns the current permission status for accessing Events.
    
    - returns: Permission status for the requested type.
    */
    public func statusEvents() -> PermissionStatus {
        let status = EKEventStore.authorizationStatusForEntityType(.Event)
        switch status {
        case .Authorized:
            return .Authorized
        case .Restricted, .Denied:
            return .Unauthorized
        case .NotDetermined:
            return .Unknown
        }
    }
    
    /**
    Requests access to Events, if necessary.
    */
    public func requestEvents() {
        let status = self.statusEvents()
        switch status {
        case .Unknown:
            EKEventStore().requestAccessToEntityType(.Event,
                completion: { granted, error in
                    self.detectAndCallback()
            })
        case .Unauthorized:
            self.showDeniedAlert(.Events)
        default:
            break
        }
    }
    
    // MARK: Bluetooth
    
    /// Returns whether Bluetooth access was asked before or not.
    private var askedBluetooth:Bool {
        get {
            return self.defaults.boolForKey(Constants.NSUserDefaultsKeys.requestedBluetooth)
        }
        set {
            self.defaults.setBool(newValue, forKey: Constants.NSUserDefaultsKeys.requestedBluetooth)
            self.defaults.synchronize()
        }
    }
    
    /// Returns whether PermissionScope is waiting for the user to enable/disable bluetooth access or not.
    private var waitingForBluetooth = false
    
    /**
    Returns the current permission status for accessing Bluetooth.
    
    - returns: Permission status for the requested type.
    */
    public func statusBluetooth() -> PermissionStatus {
        // if already asked for bluetooth before, do a request to get status, else wait for user to request
        if self.askedBluetooth{
            self.triggerBluetoothStatusUpdate()
        } else {
            return .Unknown
        }
        
        let state = (self.bluetoothManager.state, CBPeripheralManager.authorizationStatus())
        switch state {
        case (.Unsupported, _), (.PoweredOff, _), (_, .Restricted):
            return .Disabled
        case (.Unauthorized, _), (_, .Denied):
            return .Unauthorized
        case (.PoweredOn, .Authorized):
            return .Authorized
        default:
            return .Unknown
        }
        
    }
    
    /**
    Requests access to Bluetooth, if necessary.
    */
    public func requestBluetooth() {
        let status = self.statusBluetooth()
        switch status {
        case .Disabled:
            self.showDisabledAlert(.Bluetooth)
        case .Unauthorized:
            self.showDeniedAlert(.Bluetooth)
        case .Unknown:
            self.triggerBluetoothStatusUpdate()
        default:
            break
        }
        
    }
    
    /**
    Start and immediately stop bluetooth advertising to trigger
    its permission dialog.
    */
    private func triggerBluetoothStatusUpdate() {
        if !self.waitingForBluetooth && self.bluetoothManager.state == .Unknown {
            self.bluetoothManager.startAdvertising(nil)
            self.bluetoothManager.stopAdvertising()
            self.askedBluetooth = true
            self.waitingForBluetooth = true
        }
    }
    
    // MARK: Core Motion Activity
    
    /**
    Returns the current permission status for accessing Core Motion Activity.
    
    - returns: Permission status for the requested type.
    */
    public func statusMotion() -> PermissionStatus {
        if self.askedMotion {
            self.triggerMotionStatusUpdate()
        }
        return self.motionPermissionStatus
    }
    
    /**
    Requests access to Core Motion Activity, if necessary.
    */
    public func requestMotion() {
        let status = self.statusMotion()
        switch status {
        case .Unauthorized:
            showDeniedAlert(.Motion)
        case .Unknown:
            self.triggerMotionStatusUpdate()
        default:
            break
        }
    }
    
    /**
    Prompts motionManager to request a status update. If permission is not already granted the user will be prompted with the system's permission dialog.
    */
    private func triggerMotionStatusUpdate() {
        let tmpMotionPermissionStatus = self.motionPermissionStatus
        self.defaults.setBool(true, forKey: Constants.NSUserDefaultsKeys.requestedMotion)
        self.defaults.synchronize()
        
        let today = NSDate()
        self.motionManager.queryActivityStartingFromDate(today,
            toDate: today,
            toQueue: .mainQueue()) { activities, error in
                if let error = error where error.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
                    self.motionPermissionStatus = .Unauthorized
                } else {
                    self.motionPermissionStatus = .Authorized
                }
                
                self.motionManager.stopActivityUpdates()
                if tmpMotionPermissionStatus != self.motionPermissionStatus {
                    self.waitingForMotion = false
                    self.detectAndCallback()
                }
        }
        
        self.askedMotion = true
        self.waitingForMotion = true
    }
    
    /// Returns whether Bluetooth access was asked before or not.
    private var askedMotion:Bool {
        get {
            return self.defaults.boolForKey(Constants.NSUserDefaultsKeys.requestedMotion)
        }
        set {
            self.defaults.setBool(newValue, forKey: Constants.NSUserDefaultsKeys.requestedMotion)
            self.defaults.synchronize()
        }
    }
    
    /// Returns whether PermissionScope is waiting for the user to enable/disable motion access or not.
    private var waitingForMotion = false
    
    // MARK: - UI
    
    /**
    Shows the modal viewcontroller for requesting access to the configured permissions and sets up the closures on it.
    
    - parameter authChange: Called when a status is detected on any of the permissions.
    - parameter cancelled:  Called when the user taps the Close button.
    */
    @objc public func show(authChange: authClosureType? = nil, cancelled: cancelClosureType? = nil) {
        assert(!self.configuredPermissions.isEmpty, "Please add at least one permission")

        self.onAuthChange = authChange
        self.onCancel = cancelled
        
        dispatch_async(dispatch_get_main_queue()) {
            while self.waitingForBluetooth || self.waitingForMotion { }
            // call other methods that need to wait before show
            // no missing required perms? callback and do nothing
            self.requiredAuthorized({ areAuthorized in
                if areAuthorized {
                    self.getResultsForConfig({ results in

                        self.onAuthChange?(finished: true, results: results)
                    })
                } else {
                    self.showAlert()
                }
            })
        }
    }
    
    /**
    Creates the modal viewcontroller and shows it.
    */
    private func showAlert() {
        // add the backing views
        let window = UIApplication.sharedApplication().keyWindow!
        
        //hide KB if it is shown
        window.endEditing(true)
        
        window.addSubview(self.view)
        self.view.frame = window.bounds
        self.baseView.frame = window.bounds

        for bcv in self.permissionButtonContainerViews {
            bcv.removeFromSuperview()
        }
        self.permissionButtonContainerViews = []

        for (_, label) in self.permissionLabels {
            label.removeFromSuperview()
        }
        self.permissionLabels = [:]

        // create the buttons
        for permission in self.configuredPermissions {
            let buttonContainerView = self.permissionStyledButtonContainerView(permission.type)
            self.permissionButtonContainerViews.append(buttonContainerView)
            self.contentView.addSubview(buttonContainerView)

            if let label = self.permissionStyledLabel(permission.type) {
                self.permissionLabels[permission.type] = label
                self.contentView.addSubview(label)
            }
        }
        
        self.view.setNeedsLayout()
        
        // slide in the view
        self.baseView.frame.origin.y = self.view.bounds.origin.y - self.baseView.frame.size.height
        self.view.alpha = 0
        
        UIView.animateWithDuration(0.2, delay: 0.0, options: [], animations: {
            self.baseView.center.y = window.center.y + 15
            self.view.alpha = 1
        }, completion: { finished in
            UIView.animateWithDuration(0.2, animations: {
                self.baseView.center = window.center
            })
        })
    }

    /**
    Hides the modal viewcontroller with an animation.
    */
    public func hide() {
        let window = UIApplication.sharedApplication().keyWindow!

        dispatch_async(dispatch_get_main_queue(), {
            UIView.animateWithDuration(0.2, animations: {
                self.baseView.frame.origin.y = window.center.y + 400
                self.view.alpha = 0
            }, completion: { finished in
                self.view.removeFromSuperview()
            })
        })
        
        self.notificationTimer?.invalidate()
        self.notificationTimer = nil
    }
    
    // MARK: - Delegates
    
    // MARK: Gesture delegate
    
    public func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldReceiveTouch touch: UITouch) -> Bool {
        // this prevents our tap gesture from firing for subviews of baseview
        if touch.view == self.baseView {
            return true
        }
        return false
    }

    // MARK: Location delegate
    
    public func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        self.detectAndCallback()
    }
    
    // MARK: Bluetooth delegate
    
    public func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager) {
        self.waitingForBluetooth = false
        self.detectAndCallback()
    }

    // MARK: - UI Helpers
    
    /**
    Called when the users taps on the close button.
    */
    func cancel() {
        self.hide()
        
        if let onCancel = self.onCancel {
            self.getResultsForConfig({ results in
                onCancel(results: results)
            })
        }
    }
    
    /**
    Shows an alert for a permission which was Denied.
    
    - parameter permission: Permission type.
    */
    func showDeniedAlert(permission: PermissionType) {
        // compile the results and pass them back if necessary
        if let onDisabledOrDenied = self.onDisabledOrDenied {
            self.getResultsForConfig({ results in
                onDisabledOrDenied(results: results)
            })
        }
        
        let alert = UIAlertController(title: "Permission for \(permission.prettyDescription) was denied.".localized,
            message: "Please enable access to \(permission.prettyDescription) in the Settings app".localized,
            preferredStyle: .Alert)
        alert.addAction(UIAlertAction(title: "OK".localized,
            style: .Cancel,
            handler: nil))
        alert.addAction(UIAlertAction(title: "Show me".localized,
            style: .Default,
            handler: { action in
                NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("appForegroundedAfterSettings"), name: UIApplicationDidBecomeActiveNotification, object: nil)
                
                let settingsUrl = NSURL(string: UIApplicationOpenSettingsURLString)
                UIApplication.sharedApplication().openURL(settingsUrl!)
        }))
        
        dispatch_async(dispatch_get_main_queue()) {
            self.viewControllerForAlerts?.presentViewController(alert,
                animated: true, completion: nil)
        }
    }
    
    /**
    Shows an alert for a permission which was Disabled (system-wide).
    
    - parameter permission: Permission type.
    */
    func showDisabledAlert(permission: PermissionType) {
        // compile the results and pass them back if necessary
        if let onDisabledOrDenied = self.onDisabledOrDenied {
            self.getResultsForConfig({ results in
                onDisabledOrDenied(results: results)
            })
        }
        
        let alert = UIAlertController(title: "\(permission.prettyDescription) is currently disabled.".localized,
            message: "Please enable access to \(permission.prettyDescription) in Settings".localized,
            preferredStyle: .Alert)
        alert.addAction(UIAlertAction(title: "OK".localized,
            style: .Cancel,
            handler: nil))
        alert.addAction(UIAlertAction(title: "Show me".localized,
            style: .Default,
            handler: { action in
                NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("appForegroundedAfterSettings"), name: UIApplicationDidBecomeActiveNotification, object: nil)
                
                let settingsUrl = NSURL(string: UIApplicationOpenSettingsURLString)
                UIApplication.sharedApplication().openURL(settingsUrl!)
        }))
        
        dispatch_async(dispatch_get_main_queue()) {
            self.viewControllerForAlerts?.presentViewController(alert,
                animated: true, completion: nil)
        }
    }

    // MARK: Helpers
    
    /**
    This notification callback is triggered when the app comes back
    from the settings page, after a user has tapped the "show me" 
    button to check on a disabled permission. It calls detectAndCallback
    to recheck all the permissions and update the UI.
    */
    func appForegroundedAfterSettings() {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationDidBecomeActiveNotification, object: nil)
        
        self.detectAndCallback()
    }
    
    /**
    Requests the status of any permission.
    
    - parameter type:       Permission type to be requested
    - parameter completion: Closure called when the request is done.
    */
    func statusForPermission(type: PermissionType, completion: statusRequestClosure) {
        // Get permission status
        let permissionStatus: PermissionStatus
        switch type {
        case .LocationAlways:
            permissionStatus = statusLocationAlways()
        case .LocationInUse:
            permissionStatus = statusLocationInUse()
        case .Contacts:
            permissionStatus = statusContacts()
        case .Notifications:
            permissionStatus = statusNotifications()
        case .Microphone:
            permissionStatus = statusMicrophone()
        case .Camera:
            permissionStatus = statusCamera()
        case .Photos:
            permissionStatus = statusPhotos()
        case .Reminders:
            permissionStatus = statusReminders()
        case .Events:
            permissionStatus = statusEvents()
        case .Bluetooth:
            permissionStatus = statusBluetooth()
        case .Motion:
            permissionStatus = statusMotion()
        }
        
        // Perform completion
        completion(status: permissionStatus)
    }
    
    /**
    Rechecks the status of each requested permission, updates
    the PermissionScope UI in response and calls your onAuthChange
    to notifiy the parent app.
    */
    func detectAndCallback() {
        dispatch_async(dispatch_get_main_queue()) {
            // compile the results and pass them back if necessary
            if let onAuthChange = self.onAuthChange {
                self.getResultsForConfig({ results in
                    self.allAuthorized({ areAuthorized in
                        onAuthChange(finished: areAuthorized, results: results)
                    })
                })
            }
            
            self.view.setNeedsLayout()

            // and hide if we've sucessfully got all permissions
            self.allAuthorized({ areAuthorized in
                if areAuthorized {
                    self.hide()
                }
            })
        }
    }
    
    /**
    Calculates the status for each configured permissions for the caller
    */
    func getResultsForConfig(completionBlock: resultsForConfigClosure) {
        var results: [PermissionResult] = []
        
        for config in self.configuredPermissions {
            self.statusForPermission(config.type, completion: { status in
                let result = PermissionResult(type: config.type,
                    status: status)
                results.append(result)
            })
        }
        
        completionBlock(results)
    }
}
