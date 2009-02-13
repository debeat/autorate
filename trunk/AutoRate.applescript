-- AutoRate.applescript
-- Rate tracks in iTunes based on play/skip frequency
-- 
--  Copyright 2007 Michael Tyson. 
--  http://michael.tyson.id.au
--
-- Additions and modifications by Brandon Mol. 
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
global isRunning
global lastAnalysisDate
global wholeStarRatings
global rateUnratedTracksOnly
global cacheResults
global cacheTime
global ratingBias
global ratingMemory


global minFrequency
global maxFrequency
global minCount
global maxCount
global useHalfStarForItemsWithMoreSkipsThanPlays
global minRating
global maxRating
global skipCountFactor
global frequencyMethodOptimismFactor
global countMethodOptimismFactor
global lowerPercentile
global upperPercentile
global usePercentileScaleMethod
global logStats


-- Main controller
script AutoRateController
	on run {}
		-- log "Beginning rate procedure"
		
		loadSettings()
		set theNow to current date
		set analysisTrackErrors to ""
		set rateTrackErrors to ""
		set playlistTracks to {}
		
		setMainMessage("Loading playlist tracks...")
		startIndeterminateProgress()
		updateUI()
		
		tell application "iTunes"
			-- Initialise
			
			
			if minFrequency = -1.0 or minCount = -1.0 or maxFrequency = -1.0 or maxCount = -1.0 or (cacheResults and ((current date) - lastAnalysisDate) > (cacheTime * 60 * 60 * 24)) then
				
				
				set sumFrequency to 0
				set sumSquaredFrequency to 0
				set sumCount to 0
				set sumSquaredCount to 0
				set the frequencyList to {}
				set the countList to {}
				set the sortedFrequencyList to {}
				set the sortedCountList to {}
				
				try
					tell AutoRateController to set thePlaylist to getPlaylist()
					with timeout of (10 * 60) seconds
						set theTracks to file tracks in library playlist 1
						set playlistTracks to file tracks in thePlaylist
					end timeout
				on error errStr number errNumber
					display dialog "Encountered error " & (errNumber as string) & " (" & errStr & ") while attempting to obtain iTunes playlist.  Please report this to the developer."
					tell AutoRateController
						endProgress()
						endButton()
						endLabel()
					end tell
					set isRunning to false
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
				set theTrackCount to 0
				set numAnalysed to 0
				repeat with theTrack in theTracks
					if not isRunning then exit repeat
					set theTrackCount to theTrackCount + 1
					
					-- log "Analysing track " & (theTrackCount as string)
					
					try
						-- log "Track is " & location of theTrack
						
						tell AutoRateController
							setSecondaryMessage("Analysing track " & (theTrackCount as string) & " of " & (length of theTracks))
							incrementProgress()
						end tell
						
						set playCount to (played count of theTrack)
						set skipCount to (skipped count of theTrack) * skipCountFactor
						
						if (playCount > skipCount) then
							set numAnalysed to numAnalysed + 1
							
							set theDateAdded to (date added of theTrack)
							
							set combinedCount to playCount - skipCount
							set combinedFrequency to (combinedCount / (theNow - theDateAdded))
							
							
							if usePercentileScaleMethod then
								copy (combinedCount as string) to the end of the countList
								copy (combinedFrequency as string) to the end of the frequencyList
							else
								set sumFrequency to sumFrequency + combinedFrequency
								set sumSquaredFrequency to sumSquaredFrequency + (combinedFrequency ^ 2)
								set sumCount to sumCount + combinedCount
								set sumSquaredCount to sumSquaredCount + (combinedCount ^ 2)
							end if
						end if
						-- log "Frequency is " & (frequency as string)
						
					on error errStr number errNumber
						
						-- log "error " & errStr & ", number " & (errNumber as string)
						
						set theTrackLocation to ""
						
						try
							set theTrackLocation to location of theTrack
						on error
							-- Noop
						end try
						
						if theTrackLocation = "" then
							set analysisTrackErrors to analysisTrackErrors & "(Track " & (theTrackCount as string) & ")" & (ASCII character 10)
						else
							set analysisTrackErrors to analysisTrackErrors & theTrackLocation & (ASCII character 10)
						end if
						
						if errStr is not "" then set analysisTrackErrors to analysisTrackErrors & ": " & errStr
						
					end try
					
				end repeat
				
				if isRunning then
					try
						(*
						
						Option to calculation statistics in 2 ways
							Method 1. the mean +/- 2 standard deviations (95% of a normal distribution)
							Method 2. on a scale between an upper and lower percentile 2.5 to 97.5% (the middle 95% of sample values. Better for non-normal distribution)
						
						Note that with this change we need to store the min and max values rather than the mean and standard deviations.
						
						*)
						--set the scaleMethod to 2
						
						if usePercentileScaleMethod then
							
							--display dialog "Using percentile based scaling."
							-- Calculate percentile method
							
							
							--use the 2.5 and 97.5 percentiles (adjustable)
							--set theLowerPercentile to 0.025
							--set theUpperPercentile to 0.975
							
							--sort the lists so we can find the item at lower and upper percentiles
							set the sortedFrequencyList to my unix_sort(the frequencyList)
							set the sortedCountList to my unix_sort(the countList)
							
							
							--Prevent index out of bounds errors
							set minIndex to (numAnalysed * lowerPercentile) as integer
							if minIndex < 1 then set minIndex to 1
							-- Ditto
							set maxIndex to (numAnalysed * upperPercentile) as integer
							if maxIndex > numAnalysed then set maxIndex to numAnalysed
							
							--Setting the lower and upper percentile values as the min and max
							set minFrequency to (item minIndex of the sortedFrequencyList as real)
							if minFrequency < 0 then set minFrequency to 0
							set maxFrequency to (item maxIndex of the sortedFrequencyList as real)
							
							set minCount to (item minIndex of the sortedCountList as real)
							if minCount < 0 then set minCount to 0
							set maxCount to (item maxIndex of the sortedCountList as real)
							
						else
							--display dialog "Using normal distribution based scaling."
							-- Calculate normal distribution method
							set averageFrequency to sumFrequency / numAnalysed
							set averageCount to sumCount / numAnalysed
							
							-- Calculate standard deviations, allow replacing or shifting mean
							set standardDeviationFrequency to ((sumSquaredFrequency - (2 * averageFrequency * sumFrequency) + (numAnalysed * (averageFrequency ^ 2))) / (numAnalysed - 1)) ^ (1 / 2)
							set standardDeviationCount to ((sumSquaredCount - (2 * averageCount * sumCount) + (numAnalysed * (averageCount ^ 2))) / (numAnalysed - 1)) ^ (1 / 2)
							
							-- Set min and max to be 2*sd from the mean
							set minFrequency to averageFrequency - (2 * standardDeviationFrequency)
							set maxFrequency to averageFrequency + (2 * standardDeviationFrequency)
							if minFrequency < 0 then set minFrequency to 0
							set minCount to averageCount - (2 * standardDeviationCount)
							set maxCount to averageCount + (2 * standardDeviationCount)
							if minCount < 0 then set minCount to 0
							
						end if
						
						
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
			if isRunning then
				
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
							set isRunning to false
						end tell
						return
					end try
				end if
				
				tell AutoRateController to setMainMessage("Assigning Ratings...")
				-- log ((minFrequency as string) & "/" & (maxFrequency as string) & "/" & (minCount as string) & "/" & (maxCount as string))
				
				-- log "Entering rating assignment loop"
				
				-- TODO: new parameters in need of GUI access
				(*
				
				useHalfStarForItemsWithMoreSkipsThanPlays [boolean] -- will override statistical calculations, see below. Not valid if using whole star only ratings
				minRating [integer] -- ie 20 = 1 star. Note that tracks that have never been played OR skipped always get a rating of zero.
				maxRating [integer] -- ie 100= 5 star
				skipCountFactor [integer] -- are skips considered more important than plays? 
				frequencyMethodOptimismFactor
				countMethodOptimismFactor				
				*)
				-- end of new parameters
				
				--Correct minimum rating value if user selects whole-star ratings or to reserve 1/2 star for disliked songs
				if (wholeStarRatings or useHalfStarForItemsWithMoreSkipsThanPlays) and (minRating < 20) then set minRating to 20 as integer -- ie 1 star
				
				set theTrackCount to 0
				repeat with theTrack in playlistTracks
					if not isRunning then exit repeat
					set theTrackCount to theTrackCount + 1
					
					-- log "Rating track " & (theTrackCount as string)
					
					try
						
						tell AutoRateController
							incrementProgress()
							setSecondaryMessage("Rating track " & (theTrackCount as string) & " of " & length of playlistTracks)
						end tell
						
						if not rateUnratedTracksOnly or rating of theTrack is 0 then
							-- log "Track is " & location of theTrack
							
							set playCount to (played count of theTrack)
							set skipCount to (skipped count of theTrack) * skipCountFactor --weighted skips relative to plays
							
							set theDateAdded to (date added of theTrack)
							set combinedCount to playCount - skipCount
							set combinedFrequency to (combinedCount / (theNow - theDateAdded))
							
							
							--Override everything if the track has never been played OR skipped and should therefore not have a rating assigned.
							--	I am aware that this means skipped songs are rated higher than unplayed songs, which may be
							--	counter-intuative, but lends itself to more meaningful ratings IMHO.
							if playCount = 0 and skipCount = 0 then
								set theRating to 0
								--Override calculated rating if the weighted skip count is greater than the play count and ignores rating memory
							else if useHalfStarForItemsWithMoreSkipsThanPlays and (playCount < skipCount) then
								set theRating to 10
							else
								-- Calculate frequency-based rating on a scale of 0 to (maxRating - minRating)
								--================================================================
								set frequencyMethodRating to ((maxRating - minRating) * ((combinedFrequency - minFrequency) / (maxFrequency - minFrequency)))
								
								-- Scale the rating above minRating by frequncyMethodOptimismFactor and round to integer
								set frequencyMethodRating to (frequencyMethodRating * frequencyMethodOptimismFactor) as integer
								
								--Check for lower outlier
								if frequencyMethodRating < 0 then set frequencyMethodRating to 0
								
								-- Shift the rating up to the range (minRating --> maxRating)
								set frequencyMethodRating to frequencyMethodRating + minRating
								
								-- check for upper outlier
								if frequencyMethodRating > maxRating then set frequencyMethodRating to maxRating
								--================================================================
								-- End of Frequency-based rating
								
								
								-- Calculate count-based rating on a scale of 0 to (maxRating - minRating)
								--================================================================								
								set countMethodRating to ((maxRating - minRating) * ((combinedCount - minCount) / (maxCount - minCount)))
								
								-- Scale the rating above theMinRating by countMethodOptimismFactor and round to integer
								set countMethodRating to (countMethodRating * countMethodOptimismFactor) as integer
								
								--Check for lower outlier
								if countMethodRating < 0 then set countMethodRating to 0
								
								-- Shift the rating up to the range (theMinRating --> theMaxRating)
								set countMethodRating to countMethodRating + minRating
								
								-- check for upper outlier
								if countMethodRating > maxRating then set countMethodRating to maxRating
								--================================================================
								-- End of Count-based rating
								
								
								-- Combine ratings according to user preferences
								--================================================================
								set theRating to (frequencyMethodRating * (1.0 - ratingBias)) + (countMethodRating * ratingBias)
								
								-- Factor in previous rating memory
								set theRating to ((rating of theTrack) * ratingMemory) + (theRating * (1.0 - ratingMemory))
								--================================================================
								
								
							end if
							
							
							
							-- Round to whole stars if requested to
							if wholeStarRatings then
								set theRating to (theRating / 20 as integer) * 20
							else
								(*
							Otherwise round to half stars. Previously ratings were not rounded to nearest 10,
								which worked in itunes but I don't know if itunes would round the value internally or just drop down.
								Also third party utilities might get confused by values like "24" when they expect "20".
								I know GimmeSomeTunes does. This should fix that and have no negative consequences.
							*)
								set theRating to (theRating / 10 as integer) * 10
							end if
							
							
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
							set rateTrackErrors to rateTrackErrors & "(Track " & (theTrackCount as string) & ")" & (ASCII character 10)
						else
							set rateTrackErrors to rateTrackErrors & theTrackLocation & (ASCII character 10)
						end if
						
						if errStr is not "" then set rateTrackErrors to rateTrackErrors & ": " & errStr
						
					end try
				end repeat
			end if
		end tell
		
		-- log "Finished"
		if analysisTrackErrors is not "" or rateTrackErrors is not "" then
			tell text view "reportText" of scroll view "reportTextScroll" of window "reportPanel"
				set contents to (analysisTrackErrors & rateTrackErrors)
			end tell
			display panel window "reportPanel" attached to window "main"
		end if
		
		endProgress()
		endButton()
		endLabel()
		set isRunning to false
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
		set isRunning to false
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
		set isRunning to false
		
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
			
			make new default entry at end of default entries with properties {name:"lastAnalysisDate", contents:""}
			make new default entry at end of default entries with properties {name:"wholeStarRatings", contents:false}
			make new default entry at end of default entries with properties {name:"rateUnratedTracksOnly", contents:false}
			make new default entry at end of default entries with properties {name:"cacheResults", contents:true}
			make new default entry at end of default entries with properties {name:"cacheTime", contents:3}
			make new default entry at end of default entries with properties {name:"ratingBias", contents:0.5}
			make new default entry at end of default entries with properties {name:"ratingMemory", contents:0}
			make new default entry at end of default entries with properties {name:"playlist", contents:"Entire library"}
			
			
			--New preferences v1.5+
			--Parameters for rating
			make new default entry at end of default entries with properties {name:"minFrequency", contents:(-1.0 as number)}
			make new default entry at end of default entries with properties {name:"maxFrequency", contents:(-1.0 as number)}
			make new default entry at end of default entries with properties {name:"minCount", contents:(-1.0 as number)}
			make new default entry at end of default entries with properties {name:"maxCount", contents:(-1.0 as number)}
			make new default entry at end of default entries with properties {name:"useHalfStarForItemsWithMoreSkipsThanPlays", contents:true}
			make new default entry at end of default entries with properties {name:"minRating", contents:(20 as number)}
			make new default entry at end of default entries with properties {name:"maxRating", contents:(100 as number)}
			make new default entry at end of default entries with properties {name:"frequencyMethodOptimismFactor", contents:(1.0 as number)}
			make new default entry at end of default entries with properties {name:"countMethodOptimismFactor", contents:(1.0 as number)}
			--Parameters for analysis
			make new default entry at end of default entries with properties {name:"usePercentileScaleMethod", contents:true}
			make new default entry at end of default entries with properties {name:"lowerPercentile", contents:(0.025 as number)}
			make new default entry at end of default entries with properties {name:"upperPercentile", contents:(0.975 as number)}
			--Parameters for both
			make new default entry at end of default entries with properties {name:"skipCountFactor", contents:(1.0 as number)}
			make new default entry at end of default entries with properties {name:"logStats", contents:false}
			
			register
		end tell
	end initSettings
	
	on loadSettings()
		tell user defaults
			-- Read settings
			
			set lastAnalysisDateStr to contents of default entry "lastAnalysisDate"
			if lastAnalysisDateStr is not "" then set lastAnalysisDate to lastAnalysisDateStr as date
			set wholeStarRatings to contents of default entry "wholeStarRatings" as boolean
			set rateUnratedTracksOnly to contents of default entry "rateUnratedTracksOnly" as boolean
			set cacheResults to contents of default entry "cacheResults" as boolean
			set cacheTime to contents of default entry "cacheTime" as number
			set ratingBias to contents of default entry "ratingBias" as number
			set ratingMemory to contents of default entry "ratingMemory" as number
			
			-- New v1.5+
			--Rating
			set minFrequency to contents of default entry "minFrequency" as number
			set maxFrequency to contents of default entry "maxFrequency" as number
			set minCount to contents of default entry "minCount" as number
			set maxCount to contents of default entry "maxCount" as number
			set useHalfStarForItemsWithMoreSkipsThanPlays to contents of default entry "useHalfStarForItemsWithMoreSkipsThanPlays" as boolean
			set minRating to contents of default entry "minRating" as number
			set maxRating to contents of default entry "maxRating" as number
			set frequencyMethodOptimismFactor to contents of default entry "frequencyMethodOptimismFactor" as number
			set countMethodOptimismFactor to contents of default entry "countMethodOptimismFactor" as number
			--Analysis
			set usePercentileScaleMethod to contents of default entry "usePercentileScaleMethod" as boolean
			set lowerPercentile to contents of default entry "lowerPercentile" as number
			set upperPercentile to contents of default entry "upperPercentile" as number
			set logStats to contents of default entry "logStats" as boolean
			--Both
			set skipCountFactor to contents of default entry "skipCountFactor" as number
			
			
			
		end tell
	end loadSettings
	
	on clearCache()
		--New v1.5+
		set minFrequency to -1.0
		set maxFrequency to -1.0
		set minCount to -1.0
		set maxCount to -1.0
		
		set lastAnalysisDate to ""
		saveCache()
	end clearCache
	
	on saveCache()
		tell user defaults
			
			--New v1.5+
			set contents of default entry "minFrequency" to (minFrequency as number)
			set contents of default entry "maxFrequency" to (maxFrequency as number)
			set contents of default entry "minCount" to (minCount as number)
			set contents of default entry "maxCount" to (maxCount as number)
			
			--Unchanged
			set contents of default entry "lastAnalysisDate" to lastAnalysisDate
		end tell
	end saveCache
	
	--Sorting subroutine added by Brandon. Used for percentile calculations
	on unix_sort(the_list)
		(*
		Though sorting could be done natively (albeit manually) in applescript, this runs about 50,000 times faster.
			I tried it using Apple's sort sub routine @ 
			applescript://com.apple.scripteditor/?action=new&script=on%20simple_sort%28my_list%29%0D%09set%20the%20index_list%20to%20%7B%7D%0D%09set%20the%20sorted_list%20to%20%7B%7D%0D%09repeat%20%28the%20number%20of%20items%20in%20my_list%29%20times%0D%09%09set%20the%20low_item%20to%20%22%22%0D%09%09repeat%20with%20i%20from%201%20to%20%28number%20of%20items%20in%20my_list%29%0D%09%09%09if%20i%20is%20not%20in%20the%20index_list%20then%0D%09%09%09%09set%20this_item%20to%20item%20i%20of%20my_list%20as%20text%0D%09%09%09%09if%20the%20low_item%20is%20%22%22%20then%0D%09%09%09%09%09set%20the%20low_item%20to%20this_item%0D%09%09%09%09%09set%20the%20low_item_index%20to%20i%0D%09%09%09%09else%20if%20this_item%20comes%20before%20the%20low_item%20then%0D%09%09%09%09%09set%20the%20low_item%20to%20this_item%0D%09%09%09%09%09set%20the%20low_item_index%20to%20i%0D%09%09%09%09end%20if%0D%09%09%09end%20if%0D%09%09end%20repeat%0D%09%09set%20the%20end%20of%20sorted_list%20to%20the%20low_item%0D%09%09set%20the%20end%20of%20the%20index_list%20to%20the%20low_item_index%0D%09end%20repeat%0D%09return%20the%20sorted_list%0Dend%20simple_sort
			Assuming that is as efficient as it's going to get (?) I killed the task after an hour in
			favour of this code which takes ~1 second on my G4 for ~3000 songs. The only problem I
			can see is if someone opts out of installing the BSD sub-system when installing OS X 
			on their machine. Perhaps a 1-time warning about this?
		*)
		set old_delims to AppleScript's text item delimiters
		set AppleScript's text item delimiters to {ASCII character 10} -- always a linefeed
		set list_string to (the_list as string)
		set new_string to do shell script "echo " & quoted form of list_string & " | sort -fg"
		
		--The following will dump out the sorted list to a txt file 
		if logStats then do shell script "echo List " & new_string & " >> lists.txt"
		
		set new_list to (paragraphs of new_string)
		set AppleScript's text item delimiters to old_delims
		return new_list
	end unix_sort
	
end script

on clicked theObject
	if name of theObject is "clearCacheButton" then
		tell AutoRateController to clearCache()
	else if name of theObject is "reportButton" then
		close panel (window of theObject)
	else
		if not isRunning then
			set isRunning to true
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

