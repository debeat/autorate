-- AutoRate.applescript
-- Rate tracks in iTunes based on play/skip frequency
-- 
--  Copyright 2007-2009 Tzi Software
--  http://tzisoftware.com
--
-- Additions and modifications by Brandon Mol ....  brandon.mol [at] gmail [dot] com
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

global skewCoefficient0
global skewCoefficient1
global skewCoefficient2

global binLimitFrequencies
global binLimitCounts

global lowerPercentile
global upperPercentile
global useHistogramScaling
global logStats

property skipCountSlider : ""
property ratingPlaylistPopup : ""
property analysisPlaylistPopup : ""

-- Main controller
script AutoRateController
	on run {}
		-- log "Beginning rate procedure"
		
		loadSettings()
		
		set theNow to current date
		set analysisTrackErrors to ""
		set rateTrackErrors to ""
		set tracksToRateList to {}
		
		setMainMessage("Loading playlist tracks...")
		startIndeterminateProgress()
		updateUI()
		
		--tell application "iTunes"
		--with timeout of (20 * 60) seconds --20 minutes. Even with this at 1 second it produced no errors on my machine. I don't know why people are getting timeout errors
		--Decide whether to run a statistical analysis
		
		if minFrequency = -1.0 or minCount = -1.0 or maxFrequency = -1.0 or maxCount = -1.0 or binLimitFrequencies contains -1.0 or binLimitCounts contains -1.0 or (cacheResults and ((current date) - lastAnalysisDate) > (cacheTime * 60 * 60 * 24)) then
			
			-- Initialise statistical analysis temp values
			set sumFrequency to 0
			set sumSquaredFrequency to 0
			set sumCount to 0
			set sumSquaredCount to 0
			set frequencyList to {}
			set countList to {}
			set sortedFrequencyList to {}
			set sortedCountList to {}
			
			try
				tell AutoRateController to set theRatingPlaylist to getRatingPlaylist()
				tell AutoRateController to set theAnalysisPlaylist to getAnalysisPlaylist()
				with timeout of (20 * 60) seconds
					tell application "iTunes"
						if the name of theAnalysisPlaylist is "Movies" or the name of theAnalysisPlaylist is "TV Shows" or the name of theAnalysisPlaylist is "Applications" or the name of theAnalysisPlaylist is "Radio" or the name of theAnalysisPlaylist is "Ringtones" then
							tell AutoRateController to display alert "The playlist selected for analysis does not contain audio tracks. Using the Music playlist instead." as informational
							set tracksToAnalyseList to file tracks in user playlist "Music"
						else
							
							set tracksToAnalyseList to file tracks in theAnalysisPlaylist
							if length of tracksToAnalyseList < 100 and name of theAnalysisPlaylist is not "Music" then
								tell AutoRateController to display alert "At least 100 tracks are required for a meaningful statistical analysis. Using the Music playlist instead." as informational
								set tracksToAnalyseList to file tracks in user playlist "Music"
								
							end if
							set tracksToRateList to file tracks in theRatingPlaylist
						end if
					end tell
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
			
			-- log "Obtained " & (length of tracksToAnalyseList as string) & " tracks to analyse"
			
			tell AutoRateController
				setProgressLimit((length of tracksToAnalyseList) + (length of tracksToRateList))
				startProgress()
				setMainMessage("Analysing your iTunes Library...")
			end tell
			
			-- log "Beginning analysis loop"
			
			-- First loop: Get track playback statistics
			set theTrackCount to 0
			set numAnalysed to 0
			
			set numTracksToAnalyse to length of tracksToAnalyseList
			
			repeat with theTrack in tracksToAnalyseList
				if not isRunning then exit repeat
				set theTrackCount to theTrackCount + 1
				
				-- log "Analysing track " & (theTrackCount as string)
				
				try
					-- log "Track is " & location of theTrack
					tell application "iTunes"
						tell AutoRateController
							setSecondaryMessage("Analysing track " & (theTrackCount as string) & " of " & (numTracksToAnalyse as string))
							incrementProgress()
						end tell
						
						set playCount to (played count of theTrack)
						set skipCount to (skipped count of theTrack) * skipCountFactor
						
						if (playCount > skipCount) then
							set numAnalysed to numAnalysed + 1
							
							set theDateAdded to (date added of theTrack)
							
							set combinedCount to playCount - skipCount
							set combinedFrequency to (combinedCount / (theNow - theDateAdded))
							
							
							
							copy (combinedCount as real) to the end of countList
							copy (combinedFrequency as real) to the end of frequencyList
						end if
					end tell --itunes
					
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
				set debugErrorCode to 0
				try
					
					--sort the lists so we can find the item at lower and upper percentiles and bin the values in a histogram.
					set debugErrorCode to 1
					set the sortedFrequencyList to my unixSort(the frequencyList)
					set the sortedCountList to my unixSort(the countList)
					
					set debugErrorCode to 2
					set minIndex to (numAnalysed * lowerPercentile) as integer
					set maxIndex to (numAnalysed * upperPercentile) as integer
					
					set debugErrorCode to 3
					--Prevent index out of bounds errors
					if minIndex < 1 then set minIndex to 1
					if maxIndex > numAnalysed then set maxIndex to numAnalysed
					
					set debugErrorCode to 4
					--Setting the lower and upper percentile values as the min and max
					set minFrequency to (item minIndex of the sortedFrequencyList as real)
					if minFrequency < 0.0 then set minFrequency to 0.0
					set maxFrequency to (item maxIndex of the sortedFrequencyList as real)
					
					set debugErrorCode to 5
					set minCount to (item minIndex of the sortedCountList as real)
					if minCount < 0.0 then set minCount to 0.0
					set maxCount to (item maxIndex of the sortedCountList as real)
					
					set binLimits to {0.01, 0.04, 0.11, 0.23, 0.4, 0.6, 0.77, 0.89, 0.96, 1.0} --Cumulative normal density for each bin
					set binLimitFrequencies to {}
					set binLimitCounts to {}
					
					set debugErrorCode to 6
					repeat with binLimit in the binLimits
						set the binLimitIndex to (numAnalysed * (binLimit as real)) as integer
						if binLimitIndex < 1 then
							set binLimitIndex to 1
						else if binLimitIndex > numAnalysed then
							set binLimitIndex to numAnalysed
						end if
						copy ((item binLimitIndex of the sortedFrequencyList) as real) to the end of the binLimitFrequencies
						copy item binLimitIndex of the sortedCountList to the end of the binLimitCounts
					end repeat
					
					set debugErrorCode to 7
					-- Remember when we last analysed
					set lastAnalysisDate to theNow
					
					set debugErrorCode to 8
					-- Save to defaults
					tell AutoRateController to saveCache()
					
				on error errorStr number errNumber
					-- log "error " & errStr & ", number " & (errNumber as string)
					
					display dialog "Encountered error while processing statistics (error " & (errNumber as string) & "): " & errorStr & ". Please notify the developer: error code: " & (debugErrorCode as string)
					return
					
				end try
			end if
		end if
		-- log "Left analysis loop"
		
		set minRatingPercent to minRating * 20
		set maxRatingPercent to maxRating * 20
		
		
		-- Second loop: Assign ratings
		if isRunning then
			
			-- Load playlist
			if tracksToRateList = {} then
				try
					tell AutoRateController to set theRatingPlaylist to getRatingPlaylist()
					tell application "iTunes" to set tracksToRateList to file tracks in theRatingPlaylist
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
			
			tell AutoRateController to setMainMessage("Assigning Ratings...")
			-- log ((minFrequency as string) & "/" & (maxFrequency as string) & "/" & (minCount as string) & "/" & (maxCount as string))
			
			-- log "Entering rating assignment loop"
			
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
			
			(*
						skewCoefficient0     [-2...0...+2] @ 0.5 star intervals 
						skewCoefficient1     [-2...0...+2] @ 0.5 star intervals
						skewCoefficient2     [0...+2] @ 0.5 star intervals
						*)
			
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
			
			repeat with theTrack in tracksToRateList
				if not isRunning then exit repeat
				set theTrackCount to theTrackCount + 1
				
				-- log "Rating track " & (theTrackCount as string)
				
				try
					tell application "iTunes"
						tell AutoRateController
							incrementProgress()
							setSecondaryMessage("Rating track " & (theTrackCount as string) & " of " & numTracksToRate)
						end tell
						
						if (not rateUnratedTracksOnly) or (the rating of theTrack = 0) then
							-- log "Track is " & location of theTrack
							
							set playCount to (played count of theTrack)
							set skipCount to (skipped count of theTrack) * skipCountFactor --weighted skips relative to plays
							
							set theDateAdded to (date added of theTrack)
							set combinedCount to playCount - skipCount
							set combinedFrequency to (combinedCount / (theNow - theDateAdded))
							
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
								
								
								-- Calculate frequency-based rating on a scale of minRatingPercent to maxRatingPercent
								--================================================================
								
								if useHistogramScaling then
									set bin to minBin
									repeat while (combinedFrequency > (item bin of binLimitFrequencies as real)) and bin < maxBin
										set bin to bin + binIncrement
									end repeat
									set frequencyMethodRating to bin * 10.0
									--log "F:" & (frequencyMethodRating as string)
								else
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
								end if
								
								
								
								--================================================================
								-- End of Frequency-based rating
								
								
								-- Calculate count-based rating on a scale of minRatingPercent to maxRatingPercent
								--================================================================                              
								-- Set linear rating from 0.0 to 1.0
								if useHistogramScaling then
									set bin to minBin
									repeat while (combinedCount > (item bin of binLimitCounts as real)) and bin < maxBin
										set bin to bin + binIncrement
									end repeat
									set countMethodRating to bin * 10.0
									--log "C:" & (countMethodRating as string)
								else
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
								--================================================================
								-- End of Count-based rating
								
								
								-- Combine ratings according to user preferences
								--================================================================
								set theRating to (frequencyMethodRating * (1.0 - ratingBias)) + (countMethodRating * ratingBias)
								
								-- Factor in previous rating memory
								set theRating to ((the rating of theTrack) * ratingMemory) + (theRating * (1.0 - ratingMemory))
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
					end tell --itunes
				on error errStr number errNumber
					-- log "error " & errStr & ", number " & (errNumber as string)
					
					set theTrackLocation to ""
					
					try
						set theTrackLocation to location of theTrack
					on error
						-- Noop
					end try
					
					if theTrackLocation = "" then
						set rateTrackErrors to rateTrackErrors & "(Track " & (theTrackCount as string) & ")" & {ASCII character 10}
					else
						set rateTrackErrors to rateTrackErrors & theTrackLocation & {ASCII character 10}
					end if
					
					if errStr is not "" then set rateTrackErrors to rateTrackErrors & ": " & errStr
					
				end try
			end repeat
		end if
		--end timeout
		--end tell --iTunes
		
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
	
	on getRatingPlaylist()
		tell user defaults to set theRatingPlaylistName to contents of default entry "ratingPlaylist"
		if theRatingPlaylistName = "Entire library" then
			tell application "iTunes" to return library playlist 1
		else
			tell application "iTunes" to return user playlist theRatingPlaylistName
		end if
	end getRatingPlaylist
	
	on getAnalysisPlaylist()
		tell user defaults to set theAnalysisPlaylistName to contents of default entry "analysisPlaylist"
		if theAnalysisPlaylistName = "Entire library" then
			tell application "iTunes" to return library playlist 1
		else
			tell application "iTunes" to return user playlist theAnalysisPlaylistName
		end if
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
		setSecondaryMessage("")
	end endLabel
	
	on setup()
		set isRunning to false
		
		initSettings()
		
	end setup
	
	on initSettings()
		--Used to determine if preferences need to be reset or changed. 
		set currentPreferenceVersionID to "1.5.1"
		set isFirstRun to true
		
		tell user defaults
			
			try
				set isFirstRun to (contents of default entry "ratingPlaylist" as string = "")
			end try
			
			-- Register default entries (won't overwrite existing settings)
			make new default entry at end of default entries with properties {name:"lastAnalysisDate", contents:""}
			make new default entry at end of default entries with properties {name:"wholeStarRatings", contents:false}
			make new default entry at end of default entries with properties {name:"rateUnratedTracksOnly", contents:false}
			make new default entry at end of default entries with properties {name:"cacheResults", contents:true}
			make new default entry at end of default entries with properties {name:"cacheTime", contents:(3 as number)}
			make new default entry at end of default entries with properties {name:"ratingBias", contents:(0.5 as number)}
			make new default entry at end of default entries with properties {name:"ratingMemory", contents:(0.0 as number)}
			
			--New in 1.5.0
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
			make new default entry at end of default entries with properties {name:"skipCountFactor", contents:(1.0 as number)}
			make new default entry at end of default entries with properties {name:"logStats", contents:false}
			make new default entry at end of default entries with properties {name:"preferenceVersionID", contents:"none"}
			make new default entry at end of default entries with properties {name:"binLimitFrequencies", contents:{-1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0}}
			make new default entry at end of default entries with properties {name:"binLimitCounts", contents:{-1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0}}
			make new default entry at end of default entries with properties {name:"useHistogramScaling", contents:true} --as opposed to using linear scaling
			
			--New in 1.5.1
			make new default entry at end of default entries with properties {name:"ratingPlaylist", contents:"Music"}
			make new default entry at end of default entries with properties {name:"analysisPlaylist", contents:"Music"}
			
			set savedPreferenceVersionID to contents of default entry "preferenceVersionID"
			
			make new default entry at end of default entries with properties {name:"preferenceVersionID", contents:currentPreferenceVersionID as text}
			set contents of default entry "preferenceVersionID" to (currentPreferenceVersionID as text)
			
			register
			
		end tell
		
		if (not isFirstRun and (savedPreferenceVersionID ­ currentPreferenceVersionID)) then resetSettings(currentPreferenceVersionID)
		
	end initSettings
	
	on resetSettings(versionStr)
		display alert "Some settings returned to defaults. Please check and adjust your settings back to your liking." as informational
		-- Any settings whose ranges or format changes should be in here to make sure they are over written.
		clearCache()
		tell user defaults
			--changes in version "1.5.0"
			set contents of default entry "minRating" to (1.0 as number)
			set contents of default entry "maxRating" to (5.0 as number)
			
			--changes in version "1.5.1"
			set contents of default entry "cacheTime" to (3 as number)
			register
		end tell
	end resetSettings
	
	on loadSettings()
		tell user defaults
			-- Read settings
			
			set lastAnalysisDateStr to contents of default entry "lastAnalysisDate"
			if lastAnalysisDateStr is not "" then set lastAnalysisDate to lastAnalysisDateStr as date
			set wholeStarRatings to contents of default entry "wholeStarRatings" as boolean
			set rateUnratedTracksOnly to contents of default entry "rateUnratedTracksOnly" as boolean
			set cacheResults to contents of default entry "cacheResults" as boolean
			set cacheTime to contents of default entry "cacheTime" as integer
			set ratingBias to contents of default entry "ratingBias" as real
			set ratingMemory to contents of default entry "ratingMemory" as real
			-- New v1.5.0
			set minFrequency to contents of default entry "minFrequency" as real
			set maxFrequency to contents of default entry "maxFrequency" as real
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
			if skipCountFactor is "°" then set skipCountFactor to 9999999
			set binLimitFrequencies to contents of default entry "binLimitFrequencies"
			set binLimitCounts to contents of default entry "binLimitCounts"
			set useHistogramScaling to contents of default entry "useHistogramScaling" as boolean
			
			
			
		end tell
	end loadSettings
	
	on clearCache()
		--New v1.5+
		set minFrequency to -1.0
		set maxFrequency to -1.0
		set minCount to -1.0
		set maxCount to -1.0
		set binLimitFrequencies to {-1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0}
		set binLimitCounts to {-1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0}
		
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
		(*
        Though sorting could be done natively (albeit manually) in applescript, this runs about 50,000 times faster.
            I tried it using Apple's sort sub routine @ 
            
            applescript://com.apple.scripteditor/?action=new&script=on%20simple_sort%28my_list%29%0D%09set
            %20the%20index_list%20to%20%7B%7D%0D%09set%20the%20sorted_list%20to%20%7B%7D%0D
            %09repeat%20%28the%20number%20of%20items%20in%20my_list%29%20times%0D%09%09set
            %20the%20low_item%20to%20%22%22%0D%09%09repeat%20with%20i%20from%201%20to%20
            %28number%20of%20items%20in%20my_list%29%0D%09%09%09if%20i%20is%20not%20in%20the
            %20index_list%20then%0D%09%09%09%09set%20this_item%20to%20item%20i%20of%20my_list
            %20as%20text%0D%09%09%09%09if%20the%20low_item%20is%20%22%22%20then%0D%09%09
            %09%09%09set%20the%20low_item%20to%20this_item%0D%09%09%09%09%09set%20the
            %20low_item_index%20to%20i%0D%09%09%09%09else%20if%20this_item%20comes%20before
            %20the%20low_item%20then%0D%09%09%09%09%09set%20the%20low_item%20to%20this_item
            %0D%09%09%09%09%09set%20the%20low_item_index%20to%20i%0D%09%09%09%09end%20if
            %0D%09%09%09end%20if%0D%09%09end%20repeat%0D%09%09set%20the%20end%20of%20sorted_list
            %20to%20the%20low_item%0D%09%09set%20the%20end%20of%20the%20index_list%20to%20the
            %20low_item_index%0D%09end%20repeat%0D%09return%20the%20sorted_list%0Dend%20simple_sort
            
            Assuming that is as efficient as it's going to get (?) I killed the task after an hour in
            favour of this code which takes ~1 second on my G4 for ~3000 songs. The only problem I
            can see is if someone opts out of installing the BSD sub-system when installing OS X 
            on their machine. Perhaps a 1-time warning about this? So far no complaints...
        *)
		set old_delims to AppleScript's text item delimiters
		set AppleScript's text item delimiters to {ASCII character 10} -- always a linefeed
		set the unsortedListString to (the unsortedList as string)
		set the sortedListString to do shell script "echo " & quoted form of unsortedListString & " | sort -fg"
		
		--The following will dump out the sorted list to a txt file 
		if logStats then do shell script "echo List " & sortedListString & " >> lists.txt"
		
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
			set skipCountFactor to "°"
		else if content of theObject = 1 then
			set skipCountFactor to 1
		else if content of theObject ² 1 then
			set skipCountFactor to text 1 through 3 of (content of theObject as string)
		else
			set skipCountFactor to round (1 + (4 * (((content of theObject as real) - 1.0) / 0.82)))
		end if
		tell user defaults to set contents of default entry "skipCountFactor" to skipCountFactor
		
		
	end if
end action


on awake from nib theObject
	
	if name of theObject is "ratingPlaylist" then
		set ratingPlaylistPopup to theObject
		
		-- Populate popup menu with playlists
		tell menu of ratingPlaylistPopup
			tell application "iTunes" to set theRatingPlaylists to user playlists
			repeat with theRatingPlaylist in theRatingPlaylists
				make new menu item at end of menu items with properties {title:name of theRatingPlaylist}
			end repeat
		end tell
		
	else if name of theObject is "analysisPlaylist" then
		set analysisPlaylistPopup to theObject
		
		-- Populate popup menu with playlists
		tell menu of analysisPlaylistPopup
			tell application "iTunes" to set theAnalysisPlaylists to user playlists
			repeat with theAnalysisPlaylist in theAnalysisPlaylists
				if the name of theAnalysisPlaylist is not "Movies" and the name of theAnalysisPlaylist is not "Entire library" and the name of theAnalysisPlaylist is not "TV Shows" and the name of theAnalysisPlaylist is not "Applications" and the name of theAnalysisPlaylist is not "Radio" and the name of theAnalysisPlaylist is not "Ringtones" then
					make new menu item at end of menu items with properties {title:name of theAnalysisPlaylist}
				end if
			end repeat
		end tell
		
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
