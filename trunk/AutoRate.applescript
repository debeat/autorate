
--  Copyright 2007-2010 Brandon Mol and Micael Tyson
--
-- Written by Brandon Mol and Michael Tyson, Tzi Software
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
--Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

-- Globals
global isRunning
global lastAnalysisDate
global wholeStarRatings
global rateUnratedTracksOnly
global cacheResults
global cacheTime
global ratingBias
global ratingMemory

global useHalfStarForItemsWithMoreSkipsThanPlays
global minRating
global maxRating
global skipCountFactor
global binLimitFrequencies
global binLimitCounts
global logStats
global theNow
global oldFI
global timeoutValue
global rateButton
global backup

property skipCountSlider : ""
property ratingPlaylistPopup : ""
property analysisPlaylistPopup : ""


script AutoRateController
	on run {}
		tell application "iTunes"
			activate
			set oldFI to fixed indexing
			set fixed indexing to true
		end tell
		
		
		loadSettings()
		
		set theNow to current date
		set analysisTrackErrors to ""
		set rateTrackErrors to ""
		set tracksToRateList to {}
		
		setMainMessage("Loading analysis playlist tracks...")
		startIndeterminateProgress()
		updateUI()
		
		if binLimitFrequencies contains -1.0 or binLimitCounts contains -1.0 or (not cacheResults) or ((theNow - lastAnalysisDate) > (cacheTime * 60 * 60 * 24)) then
			-- Initialise statistical analysis temp values
			set frequencyList to {}
			set countList to {}
			set sortedFrequencyList to {}
			set sortedCountList to {}
			tell application "iTunes"
				with timeout of (timeoutValue) seconds
					try
						tell AutoRateController to set theRatingPlaylist to getRatingPlaylist()
						tell AutoRateController to set theAnalysisPlaylist to getAnalysisPlaylist()
						
						
						set defaultPlaylist to name of item 1 of user playlists
						
						set tracksToAnalyseList to file tracks in theAnalysisPlaylist whose video kind is none
						if length of tracksToAnalyseList < 100 and name of theAnalysisPlaylist is not defaultPlaylist then
							tell AutoRateController to display alert "At least 100 tracks are required for a meaningful statistical analysis. Using the " & defaultPlaylist & " playlist instead." as informational
							set tracksToAnalyseList to file tracks in item 1 of user playlists
						end if
						set tracksToRateList to file tracks in theRatingPlaylist whose video kind is none
						
						
						
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
					tell AutoRateController
						setProgressLimit((length of tracksToAnalyseList) + (length of tracksToRateList))
						startProgress()
						setMainMessage("Building statistics...")
					end tell
					set theTrackCount to 0
					set numAnalysed to 0
					
					set numTracksToAnalyse to length of tracksToAnalyseList
					
					
					repeat with theTrackNum from 1 to numTracksToAnalyse
						if not isRunning then exit repeat
						set theTrack to (a reference to item theTrackNum in the tracksToAnalyseList)
						set theTrackCount to theTrackCount + 1
						
						
						-- log "Analysing track " & (theTrackCount as string)
						
						try
							-- log "Track is " & location of theTrack
							
							
							tell AutoRateController
								setSecondaryMessage("Analysing track " & (theTrackCount as string) & " of " & (numTracksToAnalyse as string))
								incrementProgress()
							end tell
							set playCount to (played count of theTrack) as integer
							set skipCount to the (skipped count of theTrack) * skipCountFactor
							set trackLength to 1 --(the finish of theTrack) - (the start of theTrack)
							
							if playCount > skipCount then
								set numAnalysed to numAnalysed + 1
								set theDateAdded to (date added of theTrack)
								set combinedCount to ((playCount - skipCount) * trackLength) as integer
								if combinedCount is less than or equal to 0 then
									set combinedCount to 0
									set combinedFrequency to 0.0 as real
								else
									set combinedFrequency to (combinedCount / (theNow - theDateAdded)) as real
								end if
								copy combinedCount to the end of countList
								copy combinedFrequency to the end of frequencyList
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
								set analysisTrackErrors to analysisTrackErrors & "(Track " & (theTrackCount as string) & ")" & {ASCII character 10}
							else
								set analysisTrackErrors to analysisTrackErrors & theTrackLocation & {ASCII character 10}
							end if
							if errStr is not "" then set analysisTrackErrors to analysisTrackErrors & ": " & errStr
						end try
						
					end repeat
					
					if isRunning then
						try
							--sort the lists so we can find the item at lower and upper percentiles and bin the values in a histogram.
							set the sortedFrequencyList to my unixSort(the frequencyList)
							set the sortedCountList to my unixSort(the countList)
							
							set binLimits to {0.0, 0.01, 0.04, 0.11, 0.23, 0.4, 0.6, 0.77, 0.89, 0.96} --Cumulative normal density for each bin
							set binLimitFrequencies to {}
							set binLimitCounts to {}
							
							repeat with binLimit in the binLimits
								set the binLimitIndex to (numAnalysed * (binLimit as real)) as integer
								if binLimitIndex < 1 then
									set binLimitIndex to 1
								else if binLimitIndex > numAnalysed then
									set binLimitIndex to numAnalysed
								end if
								copy item binLimitIndex of the sortedFrequencyList to the end of the binLimitFrequencies
								copy item binLimitIndex of the sortedCountList to the end of the binLimitCounts
							end repeat
							
							-- Remember when we last analysed
							set lastAnalysisDate to theNow
							
							-- Save to defaults
							tell AutoRateController to saveCache()
							
						on error errorStr number errNumber
							-- log "error " & errStr & ", number " & (errNumber as string)
							set debugErrorCode to 0
							display dialog "Encountered error while processing statistics (error " & (errNumber as string) & "): " & errorStr & ". Please notify the developer: error code: " & (debugErrorCode as string)
							return
						end try
					end if
				end timeout
			end tell
		end if
		-- log "Left analysis loop"
		
		set minRatingPercent to minRating * 20
		set maxRatingPercent to maxRating * 20
		set the backup to {}
		
		
		-- Second loop: Assign ratings
		if isRunning then
			-- Load playlist
			tell application "iTunes"
				with timeout of (timeoutValue) seconds
					
					if tracksToRateList = {} then
						-- log "Analysis not run..."
						try
							tell AutoRateController
								set theRatingPlaylist to getRatingPlaylist()
							end tell
							set tracksToRateList to file tracks in theRatingPlaylist whose video kind is none
							tell AutoRateController
								setProgressLimit(length of tracksToRateList)
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
					
					tell AutoRateController
						setMainMessage("Assigning Ratings...")
					end tell
					--Correct minimum rating value if user selects whole-star ratings or to reserve 1/2 star for disliked songs
					--0 star ratings are always reserved for songs with no skips and no plays
					if (wholeStarRatings or useHalfStarForItemsWithMoreSkipsThanPlays) and (minRatingPercent < 20) then
						set minRatingPercent to 20 -- ie 1 star
					else if minRatingPercent < 10 then
						set minRatingPercent to 10 --ie 1/2 star
					end if
					
					if wholeStarRatings then
						set minRatingPercent to (minRatingPercent / 20 as integer) * 20
						set maxRatingPercent to (maxRatingPercent / 20 as integer) * 20
					end if
					
					set theTrackCount to 0
					set ratingScale to maxRatingPercent - minRatingPercent
					
					set minBin to minRatingPercent / 10 as integer
					set maxBin to maxRatingPercent / 10 as integer
					
					if wholeStarRatings then
						set binIncrement to 2
					else
						set binIncrement to 1
					end if
					
					set numTracksToRate to the length of tracksToRateList
					
					
					set timeoutCount to 0
					
					
					if logStats then
						set statsLogFile to ((path to desktop as text) & "stats.csv")
						try
							set dataStream to open for access file statsLogFile with write permission
							set eof of dataStream to 0
							write ("Count,Frequency" & {ASCII character 10}) to dataStream starting at eof
						on error
							try
								close access file statsLogFile
							end try
						end try
					end if
					
					
					repeat with theTrackNum from 1 to numTracksToRate
						
						if not isRunning then
							exit repeat
						end if
						set theTrack to (a reference to item theTrackNum of tracksToRateList)
						set theTrackCount to theTrackCount + 1
						try
							tell AutoRateController
								incrementProgress()
								setSecondaryMessage("Rating track " & (theTrackCount as string) & " of " & numTracksToRate)
							end tell
							
							if (not rateUnratedTracksOnly) or (the rating of theTrack is 0) then
								
								set attempts to 0
								set unsuccessful to true
								set maxAttempts to 10
								repeat while attempts ² maxAttempts and unsuccessful
									with timeout of 2 seconds
										try
											set playCount to (played count of theTrack) as integer
											set skipCount to (skipped count of theTrack) * skipCountFactor --weighted skips relative to plays
											
											set theDateAdded to (date added of theTrack)
											set unsuccessful to false
										on error
											set attempts to attempts + 1
											set timeoutCount to timeoutCount + 1
											if attempts ³ maxAttempts and timeoutCount is 0 then
												ignoring application responses
													display alert "An unrecoverable time-out error has occured. After AutoRate has finished, close it and run it again."
												end ignoring
											end if
										end try
									end timeout
								end repeat
								
								set combinedCount to (playCount - skipCount) as integer
								if combinedCount is less than or equal to 0 then
									set combinedCount to 0
									set combinedFrequency to 0.0 as real
								else
									set combinedFrequency to (combinedCount / (theNow - theDateAdded)) as real
								end if
								
								if logStats then
									try
										write ((combinedCount as text) & "," & (combinedFrequency as text) & {ASCII character 10}) to dataStream starting at eof
									end try
								end if
								
								set theOldRating to rating of theTrack
								if playCount = 0 and skipCount = 0 then
									set theRating to 0
									--Override calculated rating if the weighted skip count is greater than the play count and ignores rating memory
								else if useHalfStarForItemsWithMoreSkipsThanPlays and (playCount < skipCount) then
									set theRating to 10
								else
									
									--Frequency method
									set bin to maxBin
									repeat while combinedFrequency < (item bin of binLimitFrequencies) and bin > minBin
										set bin to bin - binIncrement
									end repeat
									set frequencyMethodRating to bin * 10.0
									--log "F:" & (frequencyMethodRating as string)
									
									--Count method
									set bin to maxBin
									repeat while combinedCount < (item bin of binLimitCounts) and bin > minBin
										set bin to bin - binIncrement
									end repeat
									set countMethodRating to bin * 10.0
									--log "C:" & (countMethodRating as string)
									
									-- Combine ratings according to user preferences
									set theRating to (frequencyMethodRating * (1.0 - ratingBias)) + (countMethodRating * ratingBias)
									
									-- Factor in previous rating memory
									if ratingMemory > 0.0 then
										set theRating to ((theOldRating) * ratingMemory) + (theRating * (1.0 - ratingMemory))
									end if
									
								end if
								
								-- Round to whole stars if requested to
								if wholeStarRatings then
									set theRating to (theRating / 20 as integer) * 20
								else
									set theRating to (theRating / 10 as integer) * 10
								end if
								
								set the persistentID to the persistent ID of theTrack as text
								
								-- Save to track
								ignoring application responses
									set the backupItem to {}
									copy the persistentID as text to the end of the backupItem
									copy the theOldRating as integer to the end of the backupItem
									copy the backupItem to the end of the backup
									set the rating of theTrack to theRating
								end ignoring
								--log "rating set successfully."
								
							end if
							
						on error errStr number errNumber
							log "error " & errStr & ", number " & (errNumber as string)
							set theTrackLocation to ""
							try
								set theTrackLocation to location of theTrack
							on error
								-- Noop
							end try
							if theTrackLocation = "" then
								set rateTrackErrors to rateTrackErrors & "(Track " & (theTrackCount as string) & ")" & linefeed --{ASCII character 10}
							else
								set rateTrackErrors to rateTrackErrors & theTrackLocation & linefeed --{ASCII character 10}
							end if
							
							if errStr is not "" then
								set rateTrackErrors to rateTrackErrors & ": " & errStr
							end if
						end try
					end repeat
					if logStats then
						try
							close access dataStream
						on error
							try
								close access file statsLogFile
							end try
						end try
					end if
				end timeout
			end tell
			saveBackup()
		end if
		
		
		
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
		tell application "iTunes"
			set fixed indexing to oldFI
		end tell
		set isRunning to false
		
	end run
	
	on revertRatings()
		
		loadSettings()
		set theNow to current date
		tell user defaults to set the backup to the contents of default entry "backup"
		if isRunning then
			-- Load playlist
			tell application "iTunes"
				with timeout of (timeoutValue) seconds
					try
						
						tell AutoRateController
							set theRatingPlaylist to getRatingPlaylist()
						end tell
						set tracksToRateList to file tracks in theRatingPlaylist whose video kind is none
						set numTracksToRate to the length of tracksToRateList
					on error errStr number errNumber
						-- log "error " & errStr & ", number " & (errNumber as string)
						display dialog "Encountered error " & (errNumber as string) & " (" & errStr & ") while attempting to obtain iTunes playlist.  Please report this to the developer."
						tell AutoRateController
							endProgress()
							endLabel()
							set isRunning to false
						end tell
						return
					end try
					
					numTracksToRate = 0
					set theTrackCount to 0
					if isRunning then
						tell AutoRateController
							setMainMessage("Restoring Previous Ratings...")
						end tell
						
						tell AutoRateController
							setProgressLimit(numTracksToRate)
							startProgress()
						end tell
					end if
					
					repeat with theTrackNum from 1 to numTracksToRate
						if not isRunning then
							exit repeat
						end if
						set theTrack to (a reference to item theTrackNum of tracksToRateList)
						set theTrackCount to theTrackCount + 1
						
						tell AutoRateController
							incrementProgress()
							setSecondaryMessage("Reverting track " & (theTrackCount as string) & " of " & numTracksToRate)
						end tell
						
						
						set backup2 to {}
						set backupItemNum to 0
						set backupSize to the length of backup
						repeat with backupItemNum from 1 to backupSize
							if not isRunning then
								exit repeat
							end if
							set backupItem to (a reference to item backupItemNum of backup)
							set the persistentID to item 1 in the backupItem
							if the persistentID = (persistent ID of theTrack) then
								set the rating of theTrack to the item 2 in the backupItem as integer
								try
									if backupItemNum > 1 then
										set backup2 to items 1 thru (backupItemNum - 1) of backup & items (backupItemNum + 1) thru -1 of backup
										set backup to backup2
									end if
								end try
								
								exit repeat
							end if
						end repeat
					end repeat
				end timeout
			end tell
		end if
		
		
		set the title of the button "revertRatingsButton" of window "main" to "Revert Ratings"
		set the enabled of the button "revertRatingsButton" of window "main" to true
		endProgress()
		endLabel()
		set isRunning to false
	end revertRatings
	
	on saveBackup()
		tell user defaults to set the contents of default entry "backup" to the backup
	end saveBackup
	
	
	on getRatingPlaylist()
		tell user defaults to set theRatingPlaylistName to contents of default entry "ratingPlaylist"
		tell application "iTunes"
			with timeout of (timeoutValue) seconds
				copy user playlist theRatingPlaylistName to ratingPlaylist
				return ratingPlaylist
			end timeout
		end tell
		
	end getRatingPlaylist
	
	on getAnalysisPlaylist()
		tell user defaults to set theAnalysisPlaylistName to contents of default entry "analysisPlaylist"
		tell application "iTunes"
			with timeout of (timeoutValue) seconds
				copy user playlist theAnalysisPlaylistName to analysisPlaylist
				return analysisPlaylist
			end timeout
		end tell
	end getAnalysisPlaylist
	
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
	
	on endButton()
		set the title of rateButton to "Begin Rating"
		set the enabled of rateButton to true
	end endButton
	
	on endLabel()
		setMainMessage("Finished.")
		setSecondaryMessage(("Completed in " & ((current date) - theNow) as text) & " seconds.")
	end endLabel
	
	on setup()
		set isRunning to false
		initSettings()
	end setup
	
	on initSettings()
		
		--Used to determine if preferences need to be reset or changed. 
		set currentPreferenceVersionID to "1.6"
		set isFirstRun to true
		tell application "iTunes" to set defaultPlaylist to ((name of (item 1 of user playlists)) as text)
		tell user defaults
			try
				set isFirstRun to (contents of default entry "preferenceVersionID" as text = "")
			on error
				#do nothing
			end try
			-- Register default entries (won't overwrite existing settings)
			make new default entry at end of default entries with properties {name:"lastAnalysisDate", contents:""}
			make new default entry at end of default entries with properties {name:"wholeStarRatings", contents:false}
			make new default entry at end of default entries with properties {name:"rateUnratedTracksOnly", contents:false}
			make new default entry at end of default entries with properties {name:"cacheResults", contents:true}
			make new default entry at end of default entries with properties {name:"cacheTime", contents:(3 as number)}
			make new default entry at end of default entries with properties {name:"ratingBias", contents:(0.5 as number)}
			make new default entry at end of default entries with properties {name:"ratingMemory", contents:(0.0 as number)}
			make new default entry at end of default entries with properties {name:"useHalfStarForItemsWithMoreSkipsThanPlays", contents:true}
			make new default entry at end of default entries with properties {name:"minRating", contents:(1.0 as number)}
			make new default entry at end of default entries with properties {name:"maxRating", contents:(5.0 as number)}
			make new default entry at end of default entries with properties {name:"skipCountFactor", contents:(3.0 as number)}
			make new default entry at end of default entries with properties {name:"logStats", contents:false}
			make new default entry at end of default entries with properties {name:"binLimitFrequencies", contents:{-1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number}}
			make new default entry at end of default entries with properties {name:"binLimitCounts", contents:{-1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number}}
			make new default entry at end of default entries with properties {name:"ratingPlaylist", contents:(defaultPlaylist as text)}
			make new default entry at end of default entries with properties {name:"analysisPlaylist", contents:(defaultPlaylist as text)}
			make new default entry at end of default entries with properties {name:"preferenceVersionID", contents:"none"}
			make new default entry at end of default entries with properties {name:"timeoutValue", contents:(30 as number)}
			make new default entry at end of default entries with properties {name:"backup", contents:{""}}
			register
			
			set savedPreferenceVersionID to contents of default entry "preferenceVersionID"
			set contents of default entry "preferenceVersionID" to (currentPreferenceVersionID as text)
			register
			
		end tell
		
		if (not isFirstRun and (savedPreferenceVersionID is not currentPreferenceVersionID)) then resetSettings(currentPreferenceVersionID)
		
	end initSettings
	
	on resetSettings(versionStr)
		display alert "All settings returned to defaults. Please check and adjust your settings back to your liking." as informational
		-- Any settings whose ranges or format changes should be in here to make sure they are over written.
		clearCache()
		tell application "iTunes" to set defaultPlaylist to ((name of (item 1 of user playlists)) as text)
		tell user defaults
			set contents of default entry "lastAnalysisDate" to ""
			set contents of default entry "wholeStarRatings" to false
			set contents of default entry "rateUnratedTracksOnly" to false
			set contents of default entry "cacheResults" to true
			set contents of default entry "cacheTime" to (3 as number)
			set contents of default entry "ratingBias" to (0.5 as number)
			set contents of default entry "ratingMemory" to (0.0 as number)
			set contents of default entry "useHalfStarForItemsWithMoreSkipsThanPlays" to true
			set contents of default entry "minRating" to (1.0 as number)
			set contents of default entry "maxRating" to (5.0 as number)
			set contents of default entry "skipCountFactor" to (3.0 as number)
			set contents of default entry "binLimitFrequencies" to {-1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number}
			set contents of default entry "binLimitCounts" to {-1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number}
			set contents of default entry "ratingPlaylist" to (defaultPlaylist as text)
			set contents of default entry "analysisPlaylist" to (defaultPlaylist as text)
			set contents of default entry "logStats" to false
			register
		end tell
	end resetSettings
	
	on loadSettings()
		tell user defaults
			set lastAnalysisDateStr to contents of default entry "lastAnalysisDate"
			if lastAnalysisDateStr is not "" then set lastAnalysisDate to lastAnalysisDateStr as date
			set wholeStarRatings to contents of default entry "wholeStarRatings" as boolean
			set rateUnratedTracksOnly to contents of default entry "rateUnratedTracksOnly" as boolean
			set cacheResults to contents of default entry "cacheResults" as boolean
			set cacheTime to contents of default entry "cacheTime" as integer
			set ratingBias to contents of default entry "ratingBias" as real
			set ratingMemory to contents of default entry "ratingMemory" as real
			set useHalfStarForItemsWithMoreSkipsThanPlays to contents of default entry "useHalfStarForItemsWithMoreSkipsThanPlays" as boolean
			set minRating to contents of default entry "minRating" as real
			set maxRating to contents of default entry "maxRating" as real
			set logStats to contents of default entry "logStats" as boolean
			set skipCountFactor to contents of default entry "skipCountFactor"
			if skipCountFactor is "infinity" then set skipCountFactor to 9999999
			set binLimitFrequencies to contents of default entry "binLimitFrequencies"
			set binLimitCounts to contents of default entry "binLimitCounts"
			set timeoutValue to contents of default entry "timeoutValue" as integer
		end tell
	end loadSettings
	
	on clearCache()
		set binLimitFrequencies to {-1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number}
		set binLimitCounts to {-1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number}
		set lastAnalysisDate to ""
		saveCache()
	end clearCache
	
	on saveCache()
		tell user defaults
			set contents of default entry "binLimitFrequencies" to binLimitFrequencies
			set contents of default entry "binLimitCounts" to binLimitCounts
			set contents of default entry "lastAnalysisDate" to lastAnalysisDate
			register
		end tell
	end saveCache
	
	on unixSort(unsortedList)
		set old_delims to AppleScript's text item delimiters
		set AppleScript's text item delimiters to {ASCII character 10} -- always a linefeed
		set the unsortedListString to (the unsortedList as string)
		set the sortedListString to do shell script "echo " & quoted form of unsortedListString & " | sort -fg"
		set the sortedList to (paragraphs of the sortedListString)
		set AppleScript's text item delimiters to old_delims
		return sortedList
	end unixSort
	
end script

on clicked theObject
	if the name of theObject is "clearCacheButton" then
		tell AutoRateController to clearCache()
	else if the name of theObject is "reportButton" then
		close panel (window of theObject)
	else if the name of theObject is "beginRatingButton" then
		if not isRunning then
			set rateButton to theObject
			set isRunning to true
			tell AutoRateController
				set the title of theObject to "Cancel"
				run
			end tell
		else
			tell AutoRateController
				set isRunning to false
				set the title of theObject to "Aborting"
				set enabled of theObject to false
			end tell
		end if
	else if the name of theObject is "revertRatingsButton" then
		if not isRunning then
			set isRunning to true
			tell AutoRateController
				set the title of theObject to "Cancel"
				revertRatings()
			end tell
		else
			tell AutoRateController
				set isRunning to false
				set the title of theObject to "Aborting"
				set enabled of theObject to false
			end tell
		end if
	end if
end clicked

on should quit after last window closed theObject
	return false
end should quit after last window closed

on will finish launching theObject
	tell AutoRateController to setup()
end will finish launching

on action theObject
	if name of theObject is "skipCountSlider" then
		if content of theObject = 2.0 then
			set skipCountFactor to "°"
		else if content of theObject = 1 then
			set skipCountFactor to 1
		else if content of theObject = 0.0 then
			set skipCountFactor to 0
		else if content of theObject < 1 then
			--set skipCountFactor to text 1 through 3 of (content of theObject as string)
			set skipCountFactor to text 1 through 4 of ((1 / (1 + (4 * ((1 - (content of theObject) as real) / 0.8))) as string) & "0000")
		else
			set skipCountFactor to round (1 + (4 * (((content of theObject as real) - 1.0) / 0.8)))
		end if
		tell user defaults
			set contents of default entry "skipCountFactor" to skipCountFactor
			register
		end tell
	end if
end action

on awake from nib theObject
	
	if name of theObject is "ratingPlaylist" then
		try
			tell user defaults to set theRatingPlaylistName to contents of default entry "ratingPlaylist"
			--log "Rating playlist: " & theRatingPlaylistName
			set ratingPlaylistPopup to theObject
			-- Populate popup menu with playlists
			tell menu of ratingPlaylistPopup
				delete every menu item
				tell application "iTunes" to set theRatingPlaylists to user playlists whose special kind is none or special kind is Music
				make new menu item at end of menu items with properties {title:theRatingPlaylistName}
				repeat with theRatingPlaylist in theRatingPlaylists
					make new menu item at end of menu items with properties {title:name of theRatingPlaylist}
				end repeat
			end tell
		on error
			#do nothing
		end try
		
	else if name of theObject is "analysisPlaylist" then
		try
			tell user defaults to set theAnalysisPlaylistName to contents of default entry "analysisPlaylist"
			--log "Analysis playlist: " & theAnalysisPlaylistName
			set analysisPlaylistPopup to theObject
			-- Populate popup menu with playlists
			tell menu of analysisPlaylistPopup
				delete every menu item
				tell application "iTunes" to set theAnalysisPlaylists to user playlists whose special kind is none or special kind is Music
				make new menu item at end of menu items with properties {title:theAnalysisPlaylistName}
				repeat with theAnalysisPlaylist in theAnalysisPlaylists
					make new menu item at end of menu items with properties {title:name of theAnalysisPlaylist}
				end repeat
			end tell
		on error
			#do nothing
		end try
		
	else if name of theObject is "skipCountSlider" then
		
		set skipCountSlider to theObject
		
		-- Set value of skip count slider
		tell user defaults to set skipCountFactor to contents of default entry "skipCountFactor"
		
		if skipCountFactor is "°" then
			set content of skipCountSlider to 2.0
		else if skipCountFactor ² 1 then
			set content of skipCountSlider to skipCountFactor
		else if skipCountFactor > 1 then
			set content of skipCountSlider to ((((skipCountFactor - 1) / 4) * 0.8) + 1)
		end if
	end if
	
	
	
end awake from nib

on will open theObject
	set state of button "showPrefs" of window "main" to on state
end will open

on will close theObject
	quit
end will close

on choose menu item theObject
	(*Add your script here.*)
end choose menu item

on will pop up theObject
	(*Add your script here.*)
end will pop up

on keyboard down theObject event theEvent
	(*Add your script here.*)
end keyboard down

on keyboard up theObject event theEvent
	(*Add your script here.*)
end keyboard up

