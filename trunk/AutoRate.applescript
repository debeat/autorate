-- AutoRate.applescript
-- Rate tracks in iTunes based on play/skip frequency
-- 
--  Copyright 2007-2009 Tzi Software
--  http://tzisoftware.com
--
-- Written by Brandon Mol ....  brandon.mol [at] gmail [dot] com
--GUI additions by Michael Tyson, Tzi Software
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


global minFrequency
global maxFrequency
global minCount
global maxCount
global useHalfStarForItemsWithMoreSkipsThanPlays
global minRating
global maxRating
global skipCountFactor

global skewCoefficient0
global skewCoefficient1
global skewCoefficient2

global binLimitFrequencies
global binLimitCounts

global lowerPercentile
global upperPercentile
global useHistogramScaling
global logStats
global theNow
global oldFI
global timeoutValue

property skipCountSlider : ""
property ratingPlaylistPopup : ""
property analysisPlaylistPopup : ""

script AutoRateController
	on run {}
		tell application "iTunes"
			set oldFI to fixed indexing
			set fixed indexing to true
		end tell
		set timeoutValue to 1 #seconds
		
		loadSettings()
		
		set theNow to current date
		set analysisTrackErrors to ""
		set rateTrackErrors to ""
		set tracksToRateList to {}
		
		setMainMessage("Loading analysis playlist tracks...")
		startIndeterminateProgress()
		updateUI()
		
		if minFrequency = -1.0 or minCount = -1.0 or maxFrequency = -1.0 or maxCount = -1.0 or binLimitFrequencies contains -1.0 or binLimitCounts contains -1.0 or (not cacheResults) or ((theNow - lastAnalysisDate) > (cacheTime * 60 * 60 * 24)) then
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
						
						set tracksToAnalyseList to file tracks in theAnalysisPlaylist
						if length of tracksToAnalyseList < 100 and name of theAnalysisPlaylist is not defaultPlaylist then
							tell AutoRateController to display alert "At least 100 tracks are required for a meaningful statistical analysis. Using the " & defaultPlaylist & " playlist instead." as informational
							set tracksToAnalyseList to file tracks in item 1 of user playlists
						end if
						set tracksToRateList to file tracks in theRatingPlaylist
						
						
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
					
					(*set mostRecentPlayedDate to date "Monday, January 1, 1900 12:00:00 AM"
					
					repeat with theTrack in tracksToAnalyseList
						if not isRunning then exit repeat
						
						set the playedDate to the played date of theTrack
						if playedDate > mostRecentPlayedDate then set mostRecentPlayedDate to playedDate	
					end repeat
					*)
					set mostRecentPlayedDate to theNow
					
					repeat with theTrack in tracksToAnalyseList
						if not isRunning then exit repeat
						set theTrackCount to theTrackCount + 1
						
						-- log "Analysing track " & (theTrackCount as string)
						
						try
							-- log "Track is " & location of theTrack
							
							
							tell AutoRateController
								setSecondaryMessage("Analysing track " & (theTrackCount as string) & " of " & (numTracksToAnalyse as string))
								incrementProgress()
							end tell
							
							set playCount to the played count of theTrack
							set skipCount to the (skipped count of theTrack) * skipCountFactor
							
							if playCount > skipCount then
								set numAnalysed to numAnalysed + 1
								
								set theDateAdded to (date added of theTrack)
								
								set combinedCount to playCount - skipCount
								if combinedCount is less than or equal to 0 then
									set combinedCount to 0
									set combinedFrequency to 536870911
								else
									set combinedFrequency to ((mostRecentPlayedDate - theDateAdded) / combinedCount) as integer
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
							set the sortedFrequencyList to the reverse of my unixSort(the frequencyList)
							set the sortedCountList to my unixSort(the countList)
							
							set minIndex to (numAnalysed * lowerPercentile) as integer
							set maxIndex to (numAnalysed * upperPercentile) as integer
							
							--Prevent index out of bounds errors
							if minIndex < 1 then set minIndex to 1
							if maxIndex > numAnalysed then set maxIndex to numAnalysed
							
							--Setting the lower and upper percentile values as the min and max
							set minFrequency to item minIndex of the sortedFrequencyList
							--if minFrequency < 0.0 then set minFrequency to 0.0
							set maxFrequency to item maxIndex of the sortedFrequencyList
							
							set minCount to item minIndex of the sortedCountList
							if minCount < 0.0 then set minCount to 0.0
							set maxCount to item maxIndex of the sortedCountList
							
							set binLimits to {0.01, 0.04, 0.11, 0.23, 0.4, 0.6, 0.77, 0.89, 0.96, 1.0} --Cumulative normal density for each bin
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
		
		
		-- Second loop: Assign ratings
		if isRunning then
			-- Load playlist
			tell application "iTunes"
				with timeout of (timeoutValue) seconds
					if tracksToRateList = {} then
						try
							tell AutoRateController
								set theRatingPlaylist to getRatingPlaylist()
							end tell
							set tracksToRateList to file tracks in theRatingPlaylist
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
					-- log ((minFrequency as string) & "/" & (maxFrequency as string) & "/" & (minCount as string) & "/" & (maxCount as string))
					
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
					
					
					--change "star-based" values to the correct range for the math to work out
					set skewCoefficient0 to skewCoefficient0 / 5.0
					set skewCoefficient1 to (skewCoefficient1 / 5.0) + 1.0
					set skewCoefficient2 to skewCoefficient2 / 5.0
					
					set n to (10.0 ^ (skewCoefficient2 * 8)) - 1.0
					(*
	 The "8", above, is a value that, experimentally, gave the full range of results when using input 
	 values from 0 to 0.4 to be consisten with the others and it is approximately a 40% boost of mid range values. 
	 *)
					set nSquared to n * n
					set m to ((2 * n) + 1) ^ 0.5
					
					set theTrackCount to 0
					set ratingScale to maxRatingPercent - minRatingPercent
					set frequencyScale to maxFrequency - minFrequency
					set countScale to maxCount - minCount
					
					set minBin to minRatingPercent / 10 as integer
					set maxBin to maxRatingPercent / 10 as integer
					
					if wholeStarRatings then
						set binIncrement to 2
					else
						set binIncrement to 1
					end if
					
					set numTracksToRate to the length of tracksToRateList
					
					
					(*set mostRecentPlayedDate to date "Monday, January 1, 1900 12:00:00 AM"
					repeat with theTrack in tracksToRateList
						if not isRunning then exit repeat
						set the playedDate to the played date of theTrack
						if playedDate > mostRecentPlayedDate then set mostRecentPlayedDate to playedDate
					end repeat
					*)
					set mostRecentPlayedDate to theNow
					
					
					repeat with theTrack in tracksToRateList
						if not isRunning then
							exit repeat
						end if
						set theTrackCount to theTrackCount + 1
						try
							tell AutoRateController
								incrementProgress()
								setSecondaryMessage("Rating track " & (theTrackCount as string) & " of " & numTracksToRate)
							end tell
							
							if (not rateUnratedTracksOnly) or (the rating of theTrack = 0) then
								
								
								--log "Track is " & location of theTrack
								set playCount to (played count of theTrack)
								set skipCount to (skipped count of theTrack) * skipCountFactor --weighted skips relative to plays
								set theDateAdded to (date added of theTrack)
								
								set combinedCount to (playCount - skipCount) as integer
								if combinedCount is less than or equal to 0 then
									set combinedCount to 0
									set combinedFrequency to 536870911
								else
									set combinedFrequency to ((mostRecentPlayedDate - theDateAdded) / combinedCount) as integer
									if combinedFrequency < 0 then
										display dialog "Date last played is before date added"
										combinedFrequency = 0
									end if
								end if
								(*
			 Override everything if the track has never been played OR skipped and should therefore not have a rating assigned.
			 I am aware that this means skipped songs are rated higher than unplayed songs, which may be
			 counter-intuative, but lends itself to more meaningful ratings IMHO. Most people consider a rating 
			 of no stars to mean "unrated" rather to mean a rating of zero.
			 *)
								if playCount = 0 and skipCount = 0 then
									set theRating to 0
									--Override calculated rating if the weighted skip count is greater than the play count and ignores rating memory
								else if useHalfStarForItemsWithMoreSkipsThanPlays and (playCount < skipCount) then
									set theRating to 10
								else
									if useHistogramScaling then
										--Frequency method
										set bin to minBin
										repeat while combinedFrequency < (item bin of binLimitFrequencies) and bin < maxBin
											set bin to bin + binIncrement
										end repeat
										set frequencyMethodRating to bin * 10.0
										--log "F:" & (frequencyMethodRating as string)
										
										--Count method
										set bin to minBin
										repeat while combinedCount > (item bin of binLimitCounts) and bin < maxBin
											set bin to bin + binIncrement
										end repeat
										set countMethodRating to bin * 10.0
										--log "C:" & (countMethodRating as string)
										
									else
										--log "using manual stretching"
										--Frequency method
										set frequencyMethodRating to ((combinedFrequency - minFrequency) / frequencyScale)
										-- Clean up outliers. This is important because the hyperbolic skewing equation will do strange things to the values otherwise
										if frequencyMethodRating > 1.0 then
											set frequencyMethodRating to 1.0
										else if frequencyMethodRating < 0.0 then
											set frequencyMethodRating to 0.0
										end if
										
										-- Hyperbolic skewing
										set frequencyMethodRating to skewCoefficient0 + (skewCoefficient1 * ((((frequencyMethodRating + n) ^ 2) - nSquared) ^ 0.5) / m)
										set frequencyMethodRating to (ratingScale * frequencyMethodRating) as integer
										
										if frequencyMethodRating > ratingScale then
											-- check for upper outlier
											set frequencyMethodRating to maxRatingPercent
										else if frequencyMethodRating < 0 then
											--Check for lower outlier
											set frequencyMethodRating to minRatingPercent
										else
											-- Shift the rating up to the range (minRatingPercent --> maxRatingPercent) from (0 --> ratingScale)
											set frequencyMethodRating to frequencyMethodRating + minRatingPercent
										end if
										
										--Count method
										set countMethodRating to ((combinedCount - minCount) / countScale)
										-- Clean up outliers. This is important because the hyperbolic skewing equation will do strange things to the values otherwise
										if countMethodRating > 1.0 then
											set countMethodRating to 1.0
										else if countMethodRating < 0.0 then
											set countMethodRating to 0.0
										end if
										
										--Hyperbolic skewing
										set countMethodRating to skewCoefficient0 + (skewCoefficient1 * ((((countMethodRating + n) ^ 2) - nSquared) ^ 0.5) / m)
										set countMethodRating to (ratingScale * countMethodRating) as integer
										
										if countMethodRating > ratingScale then
											-- check for upper outlier
											set countMethodRating to maxRatingPercent
										else if countMethodRating < 0 then
											--Check for lower outlier
											set countMethodRating to minRatingPercent
										else
											-- Shift the rating up to the range (minRatingPercent --> maxRatingPercent) from (0 --> ratingScale)
											set countMethodRating to countMethodRating + minRatingPercent
										end if
									end if
									
									-- Combine ratings according to user preferences
									set theRating to (frequencyMethodRating * (1.0 - ratingBias)) + (countMethodRating * ratingBias)
									
									-- Factor in previous rating memory
									if ratingMemory > 0.0 then
										set theRating to ((rating of theTrack) * ratingMemory) + (theRating * (1.0 - ratingMemory))
									end if
									
								end if
								
								
								
								-- Round to whole stars if requested to
								if wholeStarRatings then
									set theRating to (theRating / 20 as integer) * 20
								else
									set theRating to (theRating / 10 as integer) * 10
								end if
								
								-- Save to track
								
								set the rating of theTrack to theRating
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
				end timeout
			end tell
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
	
	on getRatingPlaylist()
		tell user defaults to set theRatingPlaylistName to contents of default entry "ratingPlaylist"
		tell application "iTunes"
			with timeout of (timeoutValue) seconds
				return user playlist theRatingPlaylistName
			end timeout
		end tell
		
	end getRatingPlaylist
	
	on getAnalysisPlaylist()
		tell user defaults to set theAnalysisPlaylistName to contents of default entry "analysisPlaylist"
		tell application "iTunes"
			with timeout of (timeoutValue) seconds
				return user playlist theAnalysisPlaylistName
			end timeout
		end tell
	end getAnalysisPlaylist
	
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
		setMainMessage("Finished.")
		setSecondaryMessage(("Completed in " & ((current date) - theNow) as text) & " seconds.")
	end endLabel
	
	on setup()
		set isRunning to false
		initSettings()
	end setup
	
	on initSettings()
		
		--Used to determine if preferences need to be reset or changed. 
		set currentPreferenceVersionID to "1.5.5"
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
			make new default entry at end of default entries with properties {name:"minFrequency", contents:(-1.0 as number)}
			make new default entry at end of default entries with properties {name:"maxFrequency", contents:(-1.0 as number)}
			make new default entry at end of default entries with properties {name:"minCount", contents:(-1.0 as number)}
			make new default entry at end of default entries with properties {name:"maxCount", contents:(-1.0 as number)}
			make new default entry at end of default entries with properties {name:"useHalfStarForItemsWithMoreSkipsThanPlays", contents:true}
			make new default entry at end of default entries with properties {name:"minRating", contents:(1.0 as number)}
			make new default entry at end of default entries with properties {name:"maxRating", contents:(5.0 as number)}
			make new default entry at end of default entries with properties {name:"skewCoefficient0", contents:(0.0 as number)}
			make new default entry at end of default entries with properties {name:"skewCoefficient1", contents:(0.0 as number)}
			make new default entry at end of default entries with properties {name:"skewCoefficient2", contents:(0.0 as number)}
			make new default entry at end of default entries with properties {name:"lowerPercentile", contents:(0.025 as number)}
			make new default entry at end of default entries with properties {name:"upperPercentile", contents:(0.975 as number)}
			make new default entry at end of default entries with properties {name:"skipCountFactor", contents:(3.0 as number)}
			make new default entry at end of default entries with properties {name:"logStats", contents:false}
			make new default entry at end of default entries with properties {name:"binLimitFrequencies", contents:{-1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number}}
			make new default entry at end of default entries with properties {name:"binLimitCounts", contents:{-1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number}}
			make new default entry at end of default entries with properties {name:"useHistogramScaling", contents:true} --as opposed to using linear scaling
			make new default entry at end of default entries with properties {name:"ratingPlaylist", contents:(defaultPlaylist as text)}
			make new default entry at end of default entries with properties {name:"analysisPlaylist", contents:(defaultPlaylist as text)}
			make new default entry at end of default entries with properties {name:"preferenceVersionID", contents:"none"}
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
			set contents of default entry "minFrequency" to (-1 as number)
			set contents of default entry "maxFrequency" to (-1 as number)
			set contents of default entry "minCount" to (-1 as number)
			set contents of default entry "maxCount" to (-1 as number)
			set contents of default entry "useHalfStarForItemsWithMoreSkipsThanPlays" to true
			set contents of default entry "minRating" to (1.0 as number)
			set contents of default entry "maxRating" to (5.0 as number)
			set contents of default entry "skewCoefficient0" to (0.0 as number)
			set contents of default entry "skewCoefficient1" to (0.0 as number)
			set contents of default entry "skewCoefficient2" to (0.0 as number)
			set contents of default entry "lowerPercentile" to (0.025 as number)
			set contents of default entry "upperPercentile" to (0.975 as number)
			set contents of default entry "skipCountFactor" to (3.0 as number)
			set contents of default entry "binLimitFrequencies" to {-1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number}
			set contents of default entry "binLimitCounts" to {-1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number}
			set contents of default entry "useHistogramScaling" to true --as opposed to using linear scaling
			set contents of default entry "ratingPlaylist" to (defaultPlaylist as text)
			set contents of default entry "analysisPlaylist" to (defaultPlaylist as text)
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
			set minFrequency to contents of default entry "minFrequency" as integer
			set maxFrequency to contents of default entry "maxFrequency" as integer
			set minCount to contents of default entry "minCount" as integer
			set maxCount to contents of default entry "maxCount" as integer
			set useHalfStarForItemsWithMoreSkipsThanPlays to contents of default entry "useHalfStarForItemsWithMoreSkipsThanPlays" as boolean
			set minRating to contents of default entry "minRating" as real
			set maxRating to contents of default entry "maxRating" as real
			set skewCoefficient0 to contents of default entry "skewCoefficient0" as real
			set skewCoefficient1 to contents of default entry "skewCoefficient1" as real
			set skewCoefficient2 to contents of default entry "skewCoefficient2" as real
			set lowerPercentile to contents of default entry "lowerPercentile" as real
			set upperPercentile to contents of default entry "upperPercentile" as real
			set logStats to contents of default entry "logStats" as boolean
			set skipCountFactor to contents of default entry "skipCountFactor"
			if skipCountFactor is "infinity" then set skipCountFactor to 9999999
			set binLimitFrequencies to contents of default entry "binLimitFrequencies"
			set binLimitCounts to contents of default entry "binLimitCounts"
			set useHistogramScaling to contents of default entry "useHistogramScaling" as boolean
		end tell
	end loadSettings
	
	on clearCache()
		set minFrequency to -1.0
		set maxFrequency to -1.0
		set minCount to -1.0
		set maxCount to -1.0
		set binLimitFrequencies to {-1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number}
		set binLimitCounts to {-1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number, -1 as number}
		set lastAnalysisDate to ""
		saveCache()
	end clearCache
	
	on saveCache()
		tell user defaults
			set contents of default entry "minFrequency" to (minFrequency as number)
			set contents of default entry "maxFrequency" to (maxFrequency as number)
			set contents of default entry "minCount" to (minCount as number)
			set contents of default entry "maxCount" to (maxCount as number)
			set contents of default entry "binLimitFrequencies" to binLimitFrequencies
			set contents of default entry "binLimitCounts" to binLimitCounts
			set contents of default entry "lastAnalysisDate" to lastAnalysisDate
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

on should quit after last window closed theObject
	return false
end should quit after last window closed

on will finish launching theObject
	tell AutoRateController to setup()
end will finish launching

on action theObject
	if name of theObject is "skipCountSlider" then
		if content of theObject is 2.0 then
			set skipCountFactor to "�"
		else if content of theObject = 1 then
			set skipCountFactor to 1
		else if content of theObject � 1 then
			set skipCountFactor to text 1 through 3 of (content of theObject as string)
		else
			set skipCountFactor to round (1 + (4 * (((content of theObject as real) - 1.0) / 0.82)))
		end if
		tell user defaults to set contents of default entry "skipCountFactor" to skipCountFactor
		
		
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
		
		if skipCountFactor is "�" then
			set content of skipCountSlider to 2.0
		else if skipCountFactor � 1 then
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
