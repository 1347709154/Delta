//
//  Game.swift
//  Delta
//
//  Created by Riley Testut on 10/3/15.
//  Copyright © 2015 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import DeltaCore
import SNESDeltaCore
import GBADeltaCore

extension Game
{
    enum Attributes: String
    {
        case artworkURL
        case filename
        case identifier
        case name
        case type
        
        case gameCollections
        case saveStates
        case previewSaveState
        case cheats
    }
}

@objc(Game)
class Game: NSManagedObject, GameProtocol
{
    @NSManaged var artworkURL: URL?
    @NSManaged var filename: String
    @NSManaged var identifier: String
    @NSManaged var name: String
    @NSManaged var type: GameType
    
    @NSManaged var gameCollections: Set<GameCollection>
    @NSManaged var previewSaveState: SaveState?
    @NSManaged var saveStates: Set<SaveState>
    
    var fileURL: URL {
        var fileURL: URL!
        
        self.managedObjectContext?.performAndWait {
            fileURL = DatabaseManager.gamesDirectoryURL.appendingPathComponent(self.filename)
        }
        
        return fileURL
    }
    
    var preferredFileExtension: String {
        switch self.type
        {
        case GameType.snes: return "smc"
        case GameType.gba: return "gba"
        default: return "delta"
        }
    }
}

extension Game
{
    override public func prepareForDeletion()
    {
        super.prepareForDeletion()
        
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        
        do
        {
            try FileManager.default.removeItem(at: self.fileURL)
        }
        catch
        {
            print(error)
        }
        
        if let managedObjectContext = self.managedObjectContext
        {
            for collection in self.gameCollections where collection.games.count == 1
            {
                // Once this game is deleted, collection will have 0 games, so we should delete it
                managedObjectContext.delete(collection)
            }
            
            // Manually cascade deletion since SaveState.fileURL references Game, and so we need to ensure we delete SaveState's before Game
            // Otherwise, we crash when accessing SaveState.game since it is nil
            for saveState in self.saveStates
            {
                managedObjectContext.delete(saveState)
            }
            
            if managedObjectContext.hasChanges
            {
                managedObjectContext.saveWithErrorLogging()
            }
        }
    }
}

extension Game
{
    class func supportedTypeIdentifiers() -> Set<String>
    {
        return [GameType.snes.rawValue, GameType.gba.rawValue]
    }
}
