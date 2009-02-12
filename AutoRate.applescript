-- AutoRate.applescript
-- Rate tracks in iTunes based on play/skip frequency
-- 
--  Copyright 2007 Michael Tyson.
--  http://michael.tyson.id.au
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

-- Globals
global running
global averageFrequency
global standardDeviationFrequency
global averagePlayCount
global standardDeviationPlayCount
global lastAnalysisDate

global wholeStarRatings
global rateUnratedTracksOnly
global cacheResults
global cacheTime
global ratingBias
global ratingMemory

-- Main controller
script AutoRateController
	on run {}
		-- log "Beginning rate procedure"
		
		loadSettings()
		set theNow to current date
		set analysisTrackErrors to ""
		set rateTrackErrors to ""
		set playlistTracks to {}
		
		setMainMessage("Loading playlist tracksÉ")
		startIndeterminateProgress()
		updateUI()
		
		tell application "iTunes"
			-- Initialise
			if averageFrequency = -1.0 or averagePlayCount = -1.0 or (cacheResults and ((current date) - lastAnalysisDate) > (cacheTime * 60 * 60 * 24)) then
				set frequencySum to 0
				set squaredFrequencySum to 0
				set playCountSum to 0
				set squaredPlayCountSum to 0
				
				try
					tell AutoRateController to set thePlaylist to getPlaylist()
					with timeout of (10 * 60) seconds
						set theTracks to file tracks in library playlist 1
						set playlistTracks to file tracks in thePlaylist
					end timeout
				on error errStr number errNumber
					-- log "error " & errStr & ", number " & (errNumber as string)
					display dialog "Encountered error " & (errNumber as string) & " (" & errStr & ") while attempting to obtain iTunes playlist.  Please report this to the developer."
					tell AutoRateController
						endProgress()
						endButton()
						endLabel()
					end tell
					set running to false
					return
				end try
				
				-- log "Obtained " & (length of theTracks as string) & " tracks to analyse"
				
				tell AutoRateController
					setProgressLimit((length of theTracks) + (length of playlistTracks))
					startProgress()
					setMainMessage("Analysing...")
				end tell
				
				-- log "Beginning analysis loop"
				
				-- First loop: Get track playback statistics
				set thecount to 0
				set analysedCount to 0
				repeat with theTrack in theTracks
					if not running then exit repeat
					set thecount to thecount + 1
					
					-- log "Analysing track " & (thecount as string)
					
					try
						-- log "Track is " & location of theTrack
						
						tell AutoRateController
							setSecondaryMessage("Analysing track " & (thecount as string) & " of " & (length of theTracks))
							incrementProgress()
						end tell
						
						if played count of theTrack is not 0 then
							set analysedCount to analysedCount + 1
							set thePlayCount to (played count of theTrack)
							set theFrequency to thePlayCount / (theNow - (date added of theTrack))
							
							set frequencySum to frequencySum + theFrequency
							set squaredFrequencySum to squaredFrequencySum + (theFrequency * theFrequency)
							set playCountSum to playCountSum + thePlayCount
							set squaredPlayCountSum to squaredPlayCountSum + (thePlayCount * thePlayCount)
						end if
						-- log "Frequency is " & (theFrequency as string)
						
					on error errStr number errNumber
						
						-- log "error " & errStr & ", number " & (errNumber as string)
						
						set theTrackLocation to ""
						
						try
							set theTrackLocation to location of theTrack
						on error
							-- Noop
						end try
						
						if theTrackLocation = "" then
							set analysisTrackErrors to analysisTrackErrors & "(Track " & (thecount as string) & ")" & (ASCII character 10)
						else
							set analysisTrackErrors to analysisTrackErrors & theTrackLocation & (ASCII character 10)
						end if
						
						if errStr ­ "" then set analysisTrackErrors to analysisTrackErrors & ": " & errStr
						
					end try
					
				end repeat
				
				if running then
					try
						-- Calculate averages
						set averageFrequency to frequencySum / analysedCount
						set averagePlayCount to playCountSum / analysedCount
						
						-- Calculate standard deviations
						set standardDeviationFrequency to (((analysedCount * squaredFrequencySum) - (frequencySum * frequencySum)) / (analysedCount * (analysedCount - 1))) ^ (1 / 2)
						set standardDeviationPlayCount to (((analysedCount * squaredPlayCountSum) - (playCountSum * playCountSum)) / (analysedCount * (analysedCount - 1))) ^ (1 / 2)
						
						-- Remember when we last analysed
						set lastAnalysisDate to theNow
						
						-- Save to defaults
						tell AutoRateController to saveCache()
						
					on error errorStr number errNumber
						-- log "error " & errStr & ", number " & (errNumber as string)
						
						display dialog "Encountered error while processing statistics (error " & (errNumber as string) & "): " & errorStr & ". Please notify the developer."
						return
						
					end try
				end if
			end if
			-- log "Left analysis loop"
			
			
			-- Second loop: Assign ratings
			if running then
				
				-- Set min and max to be 2*sd from the mean
				set minFrequency to averageFrequency - (2 * standardDeviationFrequency)
				set maxFrequency to averageFrequency + (2 * standardDeviationFrequency)
				if minFrequency < 0 then set minFrequency to 0
				set minPlayCount to averagePlayCount - (2 * standardDeviationPlayCount)
				set maxPlayCount to averagePlayCount + (2 * standardDeviationPlayCount)
				if minPlayCount < 0 then set minPlayCount to 0
				
				set thecount to 0
				
				-- Load playlist
				if playlistTracks = {} then
					try
						tell AutoRateController to set thePlaylist to getPlaylist()
						set playlistTracks to file tracks in thePlaylist
						tell AutoRateController
							setProgressLimit(length of playlistTracks)
							startProgress()
						end tell
					on error errStr number errNumber
						-- log "error " & errStr & ", number " & (errNumber as string)
						display dialog "Encountered error " & (errNumber as string) & " (" & errStr & ") while attempting to obtain iTunes playlist.  Please report this to the developer."
						tell AutoRateController
							endProgress()
							endButton()
							endLabel()
							set running to false
						end tell
						return
					end try
				end if
				
				tell AutoRateController to setMainMessage("Assigning Ratings...")
				
				-- log "Entering rating assignment loop"
				repeat with theTrack in playlistTracks
					if not running then exit repeat
					set thecount to thecount + 1
					
					-- log "Rating track " & (thecount as string)
					
					try
						tell AutoRateController
							incrementProgress()
							setSecondaryMessage("Rating track " & (thecount as string) & " of " & length of playlistTracks)
						end tell
						
						if not rateUnratedTracksOnly or rating of theTrack is 0 then
							-- log "Track is " & location of theTrack
							
							set thePlayCount to (played count of theTrack)
							set theSkipCount to (skipped count of theTrack)
							set thePlayFrequency to thePlayCount / (theNow - (date added of theTrack))
							set theSkipFrequency to theSkipCount / (theNow - (date added of theTrack))
							
							-- Calculate frequency-based rating
							set theFrequencyRating to (100 * ((thePlayFrequency - minFrequency) / (maxFrequency - minFrequency))) as integer
							set theSkipFrequencyRating to (100 * ((theSkipFrequency - minFrequency) / (maxFrequency - minFrequency))) as integer
							if theFrequencyRating > 100 then set theFrequencyRating to 100
							set theFrequencyRating to (theFrequencyRating - theSkipFrequencyRating) as integer
							if theFrequencyRating < 0 then set theFrequencyRating to 0
							
							-- Calculate play count-based rating
							set thePlayCountRating to (100 * ((thePlayCount - minPlayCount) / (maxPlayCount - minPlayCount))) as integer
							if thePlayCountRating > 100 then set thePlayCountRating to 100
							set thePlayCountRating to (thePlayCountRating - theSkipCount) as integer
							if thePlayCountRating < 0 then set thePlayCountRating to 0
							
							-- Combine ratings according to user preferences
							set theRating to (theFrequencyRating * (1.0 - ratingBias)) + (thePlayCountRating * ratingBias)
							
							-- Factor in memory
							set theRating to ((rating of theTrack) * ratingMemory) + (theRating * (1.0 - ratingMemory))
							
							-- Round to whole stars if requested to
							if wholeStarRatings then set theRating to (theRating / 20 as integer) * 20
							
							-- Save to track
							set rating of theTrack to theRating
						end if
					on error errStr number errNumber
						-- log "error " & errStr & ", number " & (errNumber as string)
						
						set theTrackLocation to ""
						
						try
							set theTrackLocation to location of theTrack
						on error
							-- Noop
						end try
						
						if theTrackLocation = "" then
							set rateTrackErrors to rateTrackErrors & "(Track " & (thecount as string) & ")" & (ASCII character 10)
						else
							set rateTrackErrors to rateTrackErrors & theTrackLocation & (ASCII character 10)
						end if
						
						if errStr ­ "" then set rateTrackErrors to rateTrackErrors & ": " & errStr
						
					end try
				end repeat
			end if
		end tell
		
		-- log "Finished"
		if analysisTrackErrors ­ "" or rateTrackErrors ­ "" then
			tell text view "reportText" of scroll view "reportTextScroll" of window "reportPanel"
				set contents to (analysisTrackErrors & rateTrackErrors)
			end tell
			display panel window "reportPanel" attached to window "main"
		end if
		
		endProgress()
		endButton()
		endLabel()
		set running to false
	end run
	
	on getPlaylist()
		tell user defaults to set thePlaylistName to contents of default entry "playlist"
		if thePlaylistName = "Entire library" then
			tell application "iTunes" to return library playlist 1
		else
			tell application "iTunes" to return user playlist thePlaylistName
		end if
	end getPlaylist
	
	on abort()
		set running to false
		endingButton()
	end abort
	
	on updateUI()
		tell window "main" to update
	end updateUI
	
	on setProgressLimit(limit)
		tell progress indicator "progress" of window "main"
			set indeterminate to false
			set maximum value to limit
		end tell
	end setProgressLimit
	
	on startIndeterminateProgress()
		tell progress indicator "progress" of window "main"
			set indeterminate to true
			start
		end tell
	end startIndeterminateProgress
	
	on startProgress()
		tell progress indicator "progress" of window "main" to start
	end startProgress
	
	on incrementProgress()
		tell progress indicator "progress" of window "main" to increment by 1
	end incrementProgress
	
	on endProgress()
		tell progress indicator "progress" of window "main"
			stop
			set contents to 0
		end tell
	end endProgress
	
	on setMainMessage(message)
		set contents of text field "mainMessage" of window "main" to message
	end setMainMessage
	
	on setSecondaryMessage(message)
		set contents of text field "secondaryMessage" of window "main" to message
	end setSecondaryMessage
	
	on startButton()
		set title of button "button" of window "main" to "Cancel"
	end startButton
	
	on endingButton()
		tell button "button" of window "main"
			set title to "Aborting"
			set enabled to false
		end tell
	end endingButton
	
	on endButton()
		tell button "button" of window "main"
			set title to "Begin"
			set enabled to true
		end tell
	end endButton
	
	on endLabel()
		setMainMessage("Finished")
		setSecondaryMessage("")
	end endLabel
	
	on setup()
		set running to false
		
		tell menu of popup button "playlist" of drawer "drawer" of window "main"
			tell application "iTunes" to set thePlaylists to user playlists
			repeat with thePlaylist in thePlaylists
				make new menu item at end of menu items with properties {title:name of thePlaylist}
			end repeat
		end tell
		
		initSettings()
		
	end setup
	
	on initSettings()
		tell user defaults
			-- Register default entries (won't overwrite existing settings)
			make new default entry at end of default entries with properties {name:"averageFrequency", contents:-1.0}
			make new default entry at end of default entries with properties {name:"standardDeviationFrequency", contents:-1.0}
			make new default entry at end of default entries with properties {name:"averagePlayCount", contents:-1.0}
			make new default entry at end of default entries with properties {name:"standardDeviationPlayCount", contents:-1.0}
			make new default entry at end of default entries with properties {name:"lastAnalysisDate", contents:""}
			make new default entry at end of default entries with properties {name:"wholeStarRatings", contents:false}
			make new default entry at end of default entries with properties {name:"rateUnratedTracksOnly", contents:true}
			make new default entry at end of default entries with properties {name:"cacheResults", contents:true}
			make new default entry at end of default entries with properties {name:"cacheTime", contents:7}
			make new default entry at end of default entries with properties {name:"ratingBias", contents:0.5}
			make new default entry at end of default entries with properties {name:"ratingMemory", contents:0.1}
			make new default entry at end of default entries with properties {name:"playlist", contents:"Entire library"}
			register
		end tell
	end initSettings
	
	on loadSettings()
		tell user defaults
			-- Read settings
			
			-- Repair bad prefs (from prior versions)
			if contents of default entry "averageFrequency" = "-1.0" then set contents of default entry "averageFrequency" to (-1.0 as number)
			
			-- Save cache
			if contents of default entry "averageFrequency" = "-1.0" then set contents of default entry "averageFrequency" to (-1.0 as number)
			if contents of default entry "standardDeviationFrequency" = "-1.0" then set contents of default entry "standardDeviationFrequency" to (-1.0 as number)
			if contents of default entry "averagePlayCount" = "-1.0" then set contents of default entry "averagePlayCount" to (-1.0 as number)
			if contents of default entry "standardDeviationPlayCount" = "-1.0" then set contents of default entry "standardDeviationPlayCount" to (-1.0 as number)
			
			set averageFrequency to contents of default entry "averageFrequency" as number
			set standardDeviationFrequency to contents of default entry "standardDeviationFrequency" as number
			set averagePlayCount to contents of default entry "averagePlayCount" as number
			set standardDeviationPlayCount to contents of default entry "standardDeviationPlayCount" as number
			set lastAnalysisDateStr to contents of default entry "lastAnalysisDate"
			if lastAnalysisDateStr ­ "" then set lastAnalysisDate to lastAnalysisDateStr as date
			set wholeStarRatings to contents of default entry "wholeStarRatings" as boolean
			set rateUnratedTracksOnly to contents of default entry "rateUnratedTracksOnly" as boolean
			set cacheResults to contents of default entry "cacheResults" as boolean
			set cacheTime to contents of default entry "cacheTime" as number
			set ratingBias to contents of default entry "ratingBias" as number
			set ratingMemory to contents of default entry "ratingMemory" as number
		end tell
	end loadSettings
	
	on clearCache()
		set averageFrequency to -1.0
		set standardDeviationFrequency to -1.0
		set averagePlayCount to -1.0
		set standardDeviationPlayCount to -1.0
		set lastAnalysisDate to ""
		saveCache()
	end clearCache
	
	on saveCache()
		tell user defaults
			set contents of default entry "averageFrequency" to averageFrequency
			set contents of default entry "standardDeviationFrequency" to standardDeviationFrequency
			set contents of default entry "averagePlayCount" to averagePlayCount
			set contents of default entry "standardDeviationPlayCount" to standardDeviationPlayCount
			set contents of default entry "lastAnalysisDate" to lastAnalysisDate
		end tell
	end saveCache
	
end script

on clicked theObject
	if name of theObject is "clearCacheButton" then
		tell AutoRateController to clearCache()
	else if name of theObject is "reportButton" then
		close panel (window of theObject)
	else
		if not running then
			set running to true
			tell AutoRateController
				startButton()
				run
			end tell
		else
			tell AutoRateController to abort()
		end if
	end if
end clicked

on will finish launching theObject
	tell AutoRateController to setup()
end will finish launching

on should quit after last window closed theObject
	return true
end should quit after last window closed

on action theObject
	(*Add your script here.*)
end action

on awake from nib theObject
	if name of theObject is "drawer" then
		set content size of theObject to {440, 150}
	end if
end awake from nib

on will open theObject
	set state of button "showPrefs" of window "main" to on state
end will open

