//
//  WindowController.swift
//  Muse
//
//  Created by Marco Albera on 21/11/16.
//  Copyright © 2016 Edge Apps. All rights reserved.
//

import Cocoa
import Carbon.HIToolbox
import MediaPlayer

@available(OSX 10.12.1, *)
class WindowController: NSWindowController {
    
    var spotifyHelper = SpotifyHelper.shared
    
    var songTrackingTimer = Timer()
    
    var autoCloseTimer = Timer()
    var counter = 0
    
    // Needed for media playback controls on the TouchBar
    let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    let remoteCommandCenter = MPRemoteCommandCenter.shared()
    
    // Store now playing info, creating an empty dictionary
    var nowPlayingInfo: [String : Any] = [:]
    
    var song = Song()
    let kSong = "song"

    override func windowDidLoad() {
        super.windowDidLoad()

        // Initialize our watcher
        initNotificationWatcher()
        
        // Set custom window attributes
        prepareWindow()
        
        prepareButtons()
        prepareImageView()
        
        // Register our DDHotKey
        registerHotkey()
        
        // Prepare system-wide controls
        prepareRemoteCommandCenter()
        
        // Load song at cold start
        prepareSong()
    }

    // Outlets
    @IBOutlet weak var songArtworkView: NSImageView!
    @IBOutlet weak var songTitleLabel: NSTextField!
    @IBOutlet weak var songProgressSlider: NSSlider!
    
    @IBOutlet weak var controlsSegmentedView: NSSegmentedControl!
    
    var isSliding = false
    
    // Actions
    @IBAction func controlsSegmentedViewClicked(_ sender: Any) {
        guard let segmentedControl = sender as? NSSegmentedControl else { return }
        
        switch segmentedControl.selectedSegment {
        case 0:
            spotifyHelper.previousTrack()
            updateSongProgressSlider()
        case 1:
            spotifyHelper.togglePlayPause()
        case 2:
            spotifyHelper.nextTrack()
            updateSongProgressSlider()
        default:
            return
        }
    }
    
    override func keyDown(with event: NSEvent) {
        // Catch key events
        switch Int(event.keyCode) {
        case kVK_Escape:
            guard let window = self.window else { return }
            toggleWindow(window, visible: false)
        case kVK_LeftArrow:
            spotifyHelper.previousTrack()
            updateSongProgressSlider()
        case kVK_Space:
            spotifyHelper.togglePlayPause()
        case kVK_RightArrow:
            spotifyHelper.nextTrack()
            updateSongProgressSlider()
        default:
            super.keyDown(with: event)
        }
    }
    
    @IBAction func progressSliderValueChanged(_ sender: Any) {
        if let slider = sender as? NSSlider {
            guard let currentEvent = NSApplication.shared().currentEvent else { return }
            
            for _ in (currentEvent.touches(matching: NSTouchPhase.began, in: slider)) {
                // Detected touch phase start
                isSliding = true
            }
            
            for _ in (currentEvent.touches(matching: NSTouchPhase.ended, in: slider)) {
                // Detected touch phase end
                isSliding = false
                
                self.song.playbackPosition = slider.doubleValue * self.song.duration
                spotifyHelper.goTo(time: Double(self.song.playbackPosition))
            }
        }
    }
    
    func prepareWindow() {
        guard let window = self.window else { return }
        
        window.titleVisibility = NSWindowTitleVisibility.hidden;
        window.titlebarAppearsTransparent = true
        window.styleMask.update(with: NSWindowStyleMask.fullSizeContentView)
        
        // Set fixed window position (at the center of the screen)
        window.center()
        window.isMovable = false
        
        // Show on every workspace
        window.collectionBehavior = .transient
        
        // Hide after losing focus
        window.hidesOnDeactivate = true
        
        window.makeFirstResponder(self)
    }
    
    func prepareAutoClose() {
        // Timer for auto-close
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: {
            timer in
            
            self.counter += 1
            
            if self.counter == 10 {
                timer.invalidate()
                
                self.counter = 0
            }
        })
    }
    
    func prepareSong() {
        self.song = spotifyHelper.song
        
        updateUIAfterNotification()
        
        trackSongProgress()
    }
    
    @available(OSX 10.12.1, *)
    func prepareButtons() {
        self.controlsSegmentedView.setImage(NSImage(named: NSImageNameTouchBarRewindTemplate), forSegment: 0)
        self.controlsSegmentedView.setImage(NSImage(named: NSImageNameTouchBarPlayPauseTemplate), forSegment: 1)
        self.controlsSegmentedView.setImage(NSImage(named: NSImageNameTouchBarFastForwardTemplate), forSegment: 2)
    }
    
    @available(OSX 10.12.1, *)
    func prepareImageView() {
        self.songArtworkView.wantsLayer = true
        self.songArtworkView.layer?.cornerRadius = 4.0
        self.songArtworkView.layer?.masksToBounds = true
    }
    
    func initNotificationWatcher() {
        // Attach the NotificationObserver for Spotify notifications
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(hookNotification(notification:)), name: NSNotification.Name(rawValue: spotifyHelper.notificationID), object: nil)
    }
    
    func hookNotification(notification: NSNotification) {
        willChangeValue(forKey: kSong)
        
        // Retrieve new value from notification
        self.song = spotifyHelper.song
        
        didChangeValue(forKey: kSong)
        
        updateUIAfterNotification()
        
        trackSongProgress()
    }
    
    func registerHotkey() {
        let modifiers: UInt = NSEventModifierFlags.control.rawValue | NSEventModifierFlags.command.rawValue
        
        DDHotKeyCenter.shared().registerHotKey(withKeyCode: UInt16(kVK_ANSI_S), modifierFlags: modifiers, target: self, action: #selector(hotkeyAction), object: nil)
    }
    
    func hotkeyAction() {
        guard let window = self.window else { return }
        
        // Hide window if focused, show if not
        toggleWindow(window, visible: !window.isKeyWindow)
    }
    
    func toggleWindow(_ window: NSWindow, visible: Bool) {
        if (visible) {
            window.makeKeyAndOrderFront(self)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.hide(self)
        }
    }
    
    func trackSongProgress() {
        if song.isPlaying {
            songTrackingTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateSongProgressSlider), userInfo: nil, repeats: true)
        } else {
            songTrackingTimer.invalidate()
            updateSongProgressSlider()
        }
    }
    
    func updateSongProgressSlider() {
        if !isSliding {
            guard let currentPlaybackPosition = spotifyHelper.currentPlaybackPosition() else { return }
            
            self.song.playbackPosition = currentPlaybackPosition
            
            songProgressSlider.doubleValue = self.song.playbackPosition / self.song.duration
            
            // Also update native touchbar scrubber
            updateNowPlayingInfoElapsedPlaybackTime()
        }
    }
    
    @available(OSX 10.12.1, *)
    func updateUIAfterNotification() {
        updateTouchBarUI()
        
        updateViewUI()
        
        updateNowPlayingInfo()
    }
    
    func updateTouchBarUI() {
        self.songTitleLabel.stringValue = self.song.name
        
        self.controlsSegmentedView.setImage(
            self.song.isPlaying ?
                NSImage(named: NSImageNameTouchBarPauseTemplate) :
                NSImage(named: NSImageNameTouchBarPlayTemplate),
            forSegment: 1
        )
        
        guard   let stringURL = spotifyHelper.artwork() as? String,
                let artworkURL = URL(string: stringURL)
        else { return }
        
        self.songArtworkView.loadImageFromURL(url: artworkURL)
    }
    
    func updateViewUI() {
        guard let viewController = self.contentViewController as? ViewController else { return }
        
        viewController.updateTitleAlbumArtistViewForSong(self.song)
        
        guard   let stringURL = spotifyHelper.artwork() as? String,
                let artworkURL = URL(string: stringURL)
        else { return }
        
        viewController.updateFullSongArtworkViewForUrl(artworkURL)
    }
    
}
