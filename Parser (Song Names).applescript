(*

Track Parser 1.3
By Dan Vanderkam
See the accompanying README for details

*)

property pattern : "%t - %n"
property pToPrefs : 0
property pref : 0
property TPversion : 1.2 -- To make sure the prefs are in the right format
property substQACode : "" -- this is a bit of a hack
my loadPrefs()

tell application "Music"
	set action to my getPattern("Pick a pattern that matches your songs, or enter a new one" & Â
		" (see the Read Me for details).", Â
		pref's lastSongPattern, pref's histSN)
	set pattern to action's pattern
	set pref's lastSongPattern to pattern
	my savePrefs()
	set cPat to my compilePattern(pattern)
	if cPat is false then error number -128
	
	my initPattern(cPat)
	
	set sel to selection of front browser window
	set num to length of sel
	set foundMatch to false
	repeat with i from 1 to num
		set theTrack to item i of sel
		set trackName to theTrack's name
		my applyPattern(trackName, cPat, theTrack, action's callback)
		if result is false and i < num then
			if button returned of (display dialog "An error occured matching " & pattern & " to '" & trackName & "'. Would you like to continue matching?" buttons {"Stop Now", "Continue Matching"} default button 1) is "Stop Now" then
				error number -128
			end if
		else if not foundMatch and result then
			set foundMatch to true
			set matchedTrack to trackName
		end if
	end repeat
	
	if foundMatch and not my inHistory(pref's histSN, pattern) then
		set patName to my getPatternName(matchedTrack)
		if patName ­ false then my addPattern(pref's histSN, pattern, patName)
	end if
end tell

to getNewPattern(msg, pat, hist)
	local res, rout
	if pattern = "" then set pattern to "%t - %n"
	copy (display dialog msg default answer pat Â
		buttons {"Cancel", "Test Run", "Run"} default button 3) to result_of_dd
	if button returned of result_of_dd is "Quit" then error number -128
	if button returned of result_of_dd is "Test Run" then set rout to my displayChanges
	if button returned of result_of_dd is "Run" then set rout to my makeChanges
	if button returned of result_of_dd is "SavedÉ" then return getPatternFromHist(msg, hist)
	copy text returned of result_of_dd to text_returned
	return {pattern:text_returned, callback:rout}
end getNewPattern


to getPattern(msg, pat, hist)
	local txtList
	set txtList to {"<QUIT>"}
	repeat with itm in hist
		copy itm's txt to the end of txtList
	end repeat
	
	set res to choose from list txtList with prompt msg Â
		OK button name "Run" cancel button name Â
		"New PatternÉ" default items {"<QUIT>"} Â
		without multiple selections allowed and empty selection allowed
	if res is false then return getNewPattern(msg, pat, hist)
	
	set chosen to item 1 of res
	if chosen = "<QUIT>" then error number -128
	repeat with itm in hist
		if itm's txt = chosen then return {pattern:itm's pat, callback:my makeChanges}
	end repeat
	
	display dialog "Huh?" & return & chosen
	error number -128
end getPattern

to getPatternName(defName)
	set res to display dialog Â
		"This pattern matched successfully. Would you like to save it for later use?" buttons {"Don't Save", "Save"} default button 2 default answer defName
	if button returned of res is "Don't Save" then return false
	return text returned of res
end getPatternName

-- General Parser Stuff

-- "Compiles" pat for faster,
-- easier application later on
to compilePattern(pat)
	local prefix
	set prefix to text 1 thru 2 of pat
	if (text 1 thru 1 of pat is "/" or prefix is "s/" or prefix is "s{" or prefix is "s[") then return my compileRegex(pat)
	local fldV
	local fldT
	local txt
	set fldV to {}
	set fldT to {}
	set txt to pat
	repeat until length of txt = 0
		--display dialog "'" & txt & "'"
		if (text 1 thru 1 of txt) = "%" then
			copy 1 to the end of fldT
			copy (text 2 thru 2 of txt) to the end of fldV
			--display dialog "added 0; '" & (text 2 thru 2 of txt) & "'"
			if length of txt = 1 then
				display dialog "Cannot end the search pattern with a %" buttons {"OK"}
				return false
			else if length of txt = 2 then
				set txt to ""
			else
				set txt to text 3 thru -1 of txt
			end if
		else
			copy 0 to the end of fldT
			set nextPos to offset of "%" in txt
			if nextPos = 0 then
				copy txt to the end of fldV
				--display dialog "added 1; '" & txt & "'"
				set txt to ""
			else
				copy (text 1 thru (nextPos - 1) of txt) to the end of fldV
				--display dialog "added 1; '" & (text 1 thru (nextPos - 1) of txt) & "'"
				set txt to (text nextPos thru -1 of txt)
			end if
		end if
	end repeat
	return {type:"scanf", t:fldT, v:fldV}
end compilePattern

to compileRegex(pat)
	local tmp
	if text 1 thru 1 of pat = "s" then
		-- Let pat through uninterpreted for now
		return compileSubst(pat)
		--set flds to {"n"}
		--return {type:"regexsub", p:pat, t:flds}
	else
		set tmp to match(pat, "^/(.*)/(\\w*)$")
		if length of tmp = 0 then
			display dialog "Regular Expressions must be of the form /expr[/flags]/fields or s/match/rep/[flags]" buttons {"OK"}
			return false
		end if
		return {type:"regex", p:(item 1 of tmp), t:(every text item of (item 2 of tmp))}
	end if
end compileRegex

-- Syntax for a substitution is:
-- s[question1; question2; ...]{[t|l|a|É]*}/find/rep/flags
-- everything after the first '/' goes to Perl unfiltered
-- default data source is Track Name (n)
-- ex: s{ag}/(.*)\r(.*)/ga\n$2\n$1/s
--  (swaps artist/genre)
-- ex: s[Enter the new play count:]{p}/.*/$ans[0]/
-- displays a dialog and sets the play count of the selected songs
-- ex: s[Enter the new artist:;Enter the new album:]/.*/al\n$ans[0]\n$ans[1]/
-- displays two dialogs, and sets the artist/album.
to compileSubst(pat)
	set sections to match(pat, "^s(?:\\[([^\\]/]*)\\])?(?:\\{([^\\}/]*)\\})?/(.*)")
	if (item 1 of sections) = "" then
		set questions to {}
	else
		set questions to split(";", item 1 of sections)
	end if
	
	set flds to every character of ((item 2 of sections) as string)
	if length of flds is 0 then set flds to {"n"}
	set pat to "s/" & item 3 of sections
	--display dialog "Pat: '" & pat & "'; flds: " & (flds as string) & return & "qs: " & (questions as string)
	return {type:"regexsub", p:pat, t:flds, q:questions}
	
end compileSubst

-- At the moment, this routine just asks questions
-- before the pattern is applied, so that they aren't
-- asked for each individiual song.
to initPattern(pat)
	local ans, q
	if pat's type is "regexsub" then
		set ans to {}
		repeat with q in pat's q
			set res to display dialog q default answer ""
			copy text returned of res to the end of ans
		end repeat
		set substQACode to my GetQACode(ans)
	end if
end initPattern

-- Matches pat to song, applying
-- the results to theSong
-- using the dispatcher(field,value,song) routine
to applyPattern(song, pat, theSong, callback)
	if pat's type is "regex" then return my applyRegex(song, pat, theSong, callback)
	if pat's type is "regexsub" then return my applySubst(song, pat, theSong, callback)
	
	local fldT
	local fldV
	local pos
	local txt
	set fldT to pat's t --item 1 of pat
	set fldV to pat's v --item 2 of pat
	set pos to 1
	set txt to song
	
	-- Set things up for the callback
	script cb
		property fn : callback
	end script
	
	repeat with i from 1 to length of fldV
		set v to item i of fldV
		set t to item i of fldT
		if t = 0 then
			-- Check that the characters match
			if (text 1 thru (length of v) of txt) ­ v then
				display dialog "Song '" & song & "' did not match pattern '" & pattern & Â
					". Expected '" & v & "' but found '" & Â
					(text 1 thru (length of v) of txt) & "'." buttons {"OK"}
				return false
			else
				-- It Matched, so advance our position
				if txt = v then
					txt = ""
				else
					set txt to text (1 + (length of v)) thru -1 of txt
				end if
				--display dialog "Matched '" & v & "' (" & (length of v) & ") => '" & txt & "'"
			end if
		else if t = 1 then
			-- Scan until we hit the next string literal
			if i = length of fldV then
				cb's fn(v, txt, theSong)
				--my dispatcher(v, txt, theSong)
			else
				if (item (i + 1) of fldT) = 1 then
					display dialog "Fields must be separated by strings literals" buttons {"OK"}
					return false
				else
					set nextPos to offset of (item (i + 1) of fldV) in txt
					if nextPos = 0 then
						display dialog "Song '" & song & "' did not match pattern '" & pattern & Â
							". Expected '" & (item (i + 1) of fldV) & "', but it was not found." buttons {"OK"}
						return false
					else
						set itm to text 1 thru (nextPos - 1) of txt
						set txt to text nextPos thru -1 of txt
						cb's fn(v, itm, theSong)
					end if
				end if
			end if
		end if
	end repeat
	return true
end applyPattern

-- Split txt around delim
on split(delim, txt)
	local saveD, mlines
	set saveD to AppleScript's text item delimiters
	set AppleScript's text item delimiters to (delim as list)
	set mlines to every text item of txt
	set AppleScript's text item delimiters to saveD
	return mlines
end split

-- Should double quote |, single quote ' in pat, txt
on match(ptxt, ppat)
	local scpt, res, txt, pat
	set txt to ptxt
	set pat to ppat
	if txt contains "'" then set txt to escapeApostrophe(txt)
	if pat contains "'" then set pat to escapeApostrophe(pat)
	if txt contains "|" then set txt to escape(txt, {"|"})
	if pat contains "!" then set pat to escape(pat, {"!"})
	
	try
		set scpt to "perl -e '@m = q|" & txt & "| =~ m!" & pat & "!i; print join qq/\\n/, @m'"
		--set scpt to "perl -e \"@m = q|" & txt & "| =~ m|" & pat & "|i; print join qq/\\n/,@m\""
	on error
		return false
	end try
	--set the clipboard to scpt
	set res to do shell script scpt
	if res is "" then return false
	return split(return, res)
end match

-- run ppat on ptxt
-- ppat is of the form s/a/b/gi
-- ppat gets directly thrown into the perl script, so watch out
-- prefix gets inserted before the pattern to do whatever initialization
-- is necessary. Typically this is an empty string.
on subst(ptxt, ppat, pprefix)
	local scpt, res, txt, pat, prefix
	set txt to ptxt
	set pat to ppat
	set prefix to pprefix
	if txt contains "|" then set txt to escape(ptxt, {"|"})
	if txt contains "'" then set txt to escapeApostrophe(txt)
	if pat contains "'" then set pat to escapeApostrophe(pat)
	if prefix contains "'" then set prefix to escapeApostrophe(prefix)
	
	try
		-- Not sure why I did the @m business before
		--set scpt to "perl -e '$x = q|" & txt & "|; @m = $x =~ " & pat & "; print $x, qq/\\n/, join qq/\\n/, @m'"
		set scpt to "perl -e '" & prefix & " $x = q|" & txt & "|; $x =~ " & pat & "; print $x'"
	on error
		return false
	end try
	
	--set the clipboard to scpt
	set res to do shell script scpt
	if res is "" then return false
	--display dialog res
	return split(return, res)
end subst

-- In the string theText, escapes each element of chars
-- If a character occurs twice in chars, it is double quoted
on escape(theText, chars)
	local OldDelims, newText
	set OldDelims to AppleScript's text item delimiters
	set newText to theText
	repeat with c in chars
		set AppleScript's text item delimiters to c
		set newText to text items of newText
		set AppleScript's text item delimiters to ("\\" & c)
		set newText to newText as text
	end repeat
	set AppleScript's text item delimiters to OldDelims
	return newText
end escape

on escapeApostrophe(txt)
	local OldDelims, newText
	set OldDelims to AppleScript's text item delimiters
	set newText to txt
	set AppleScript's text item delimiters to "'"
	set newText to text items of newText
	set AppleScript's text item delimiters to ("'\\''")
	set newText to newText as text
	set AppleScript's text item delimiters to OldDelims
	return newText
end escapeApostrophe

on applyRegex(txt, pat, song, callback)
	local matches, types
	set matches to match(txt, pat's p)
	set types to pat's t
	
	if matches = false then
		display dialog "Couldn't match /" & pat's p & "/" & (types as string) & " to '" & txt & "'" buttons {"OK"}
		return false
	end if
	
	-- Set things up for the callback
	script cb
		property fn : callback
	end script
	
	repeat with i from 1 to length of types
		cb's fn(item i of types, item i of matches, song)
	end repeat
	
	return true
end applyRegex

on applySubst(txt, pat, song, callback)
	-- Ready the input string for the pattern
	local inp, i, res, vals, matches
	set inp to ""
	repeat with i from 1 to length of pat's t --fld in pat's t
		set fld to item i of pat's t
		if i ­ 1 then set inp to inp & return
		set inp to inp & my getField(fld as string, song)
	end repeat
	
	--display dialog "Input: '" & inp & "'"
	set matches to subst(inp, pat's p, substQACode)
	set vals to split(return, matches)
	
	if length of vals is 1 then
		-- Default target is the first source pattern
		set targets to {item 1 of pat's t}
		set vD to 0
	else
		set targets to every character of (item 1 of vals as string)
		--set vals to item 2 thru (length vals) of vals
		set vD to 1
	end if
	
	-- Set things up for the callback
	script cb
		property fn : callback
	end script
	
	-- Always returning true might be better than this
	--try
	repeat with i from 1 to length of targets
		set fld to item i of targets as string
		set val to item (i + vD) of vals
		cb's fn(fld, val, song)
	end repeat
	return true
	--on error e
	--	return false
	--end try
end applySubst

to GetQACode(ans)
	local perl, varName, i, itm
	set perl to ""
	set varName to "$ans"
	repeat with i from 1 to length of ans
		set itm to item i of ans
		set itm to my escape(itm, {"!"})
		set perl to perl & varName & "[" & (i - 1) & "] = q!" & itm & "!; "
	end repeat
	return perl
end GetQACode

-- Alert the user of what woudld be changed,
-- but don't actually change the song
-- the property is determined by the character var,
-- and the new value is determined by the string/number value
to displayChanges(var, value, theSong)
	considering case
		tell application "Music"
			if var = "a" then
				display dialog "Setting artist of '" & theSong's name & "' to '" & value & "'"
			else if var = "d" then
				display dialog "Setting disc number of '" & theSong's name & "' to '" & value & "'"
			else if var = "D" then
				display dialog "Setting Disc Count of '" & theSong's name & "' to " & value
			else if var = "l" then
				display dialog "Setting album of '" & theSong's name & "' to '" & value & "'"
			else if var = "n" then
				display dialog "Setting song name of '" & theSong's name & "' to '" & value & "'"
			else if var = "t" then
				display dialog "Setting track number of '" & theSong's name & "' to " & value
			else if var = "T" then
				display dialog "Setting track count of '" & theSong's name & "' to " & value
			else if var = "y" then
				display dialog "Setting year of '" & theSong's name & "' to " & value
			else if var = "c" then
				display dialog "Setting comments of '" & theSong's name & "' to '" & value & "'"
			else if var = "g" then
				display dialog "Setting genre of '" & theSong's name & "' to '" & value & "'"
			else if var = "r" then
				display dialog "Setting grouping of '" & theSong's name & "' to '" & value & "'"
			else if var = "p" then
				display dialog "Setting played count of '" & theSong's name & "' to " & value
			else if var = "b" then
				display dialog "Setting BPM of '" & theSong's name & "' to " & value
			else if var = "C" then
				display dialog "Setting Composer of '" & theSong's name & "' to '" & value & "'"
			else if var = "e" then
				display dialog "Setting Last Played Date of '" & theSong's name & "' to " & value
			else if var = "#" then
				display dialog "Setting Rating of '" & theSong's name & "' to " & value
			else if var = "0" then
				-- Do Nothing
			end if
		end tell
	end considering
end displayChanges

-- This construct doesn't work within a tell...end tell block
-- This is the only workaround that I could think of.
to getDate(dateStr)
	return (date dateStr)
end getDate

-- Actually modify the song
to makeChanges(var, value, theSong)
	considering case
		tell application "Music"
			tell theSong
				if var = "a" then
					set artist to value
				else if var = "d" then
					set the disc number to value as number
				else if var = "D" then
					set the disc count to value as number
				else if var = "l" then
					set album to value
				else if var = "n" then
					set name to value
				else if var = "t" then
					set the track number to value as number
				else if var = "T" then
					set the track count to value as number
				else if var = "y" then
					set year to value as number
				else if var = "g" then
					set genre to value
				else if var = "r" then
					set grouping to value
				else if var = "p" then
					set played count to value as number
				else if var = "b" then
					set bpm to value as number
				else if var = "C" then
					set composer to value
				else if var = "e" then
					set played date to my getDate(value)
				else if var = "#" then
					set rating to value as number
				else if var = "0" then
					-- Do nothing
				end if
			end tell
		end tell
	end considering
end makeChanges

-- Return the value of a field as a string
-- Used in complex multi-source substitutions
to getField(var, theSong)
	considering case
		tell application "Music"
			tell theSong as track
				if var = "a" then
					return artist
				else if var = "d" then
					return disc number as string
				else if var = "D" then
					return disc count as string
				else if var = "f" then
					set f to location
					return name of (info for f)
				else if var = "l" then
					return album
				else if var = "n" then
					return name
				else if var = "t" then
					return track number as string
				else if var = "T" then
					return track count as string
				else if var = "y" then
					return year as string
				else if var = "g" then
					return genre
				else if var = "r" then
					return grouping
				else if var = "p" then
					return played count as string
				else if var = "b" then
					return bpm as string
				else if var = "C" then
					return composer
				else if var = "e" then
					return played date as string
				else if var = "#" then
					return rating as string
				else if var = "0" then
					return "" -- not sure why anyone would use this
				end if
			end tell
		end tell
	end considering
end getField

-- Preferences Stuff
to loadPrefs()
	set pToPrefs to ((path to preferences folder from user domain as string) & "Music Parser prefs")
	try
		set pref to load script alias pToPrefs --file "blah.scpt"
		if pref's TPversion < my TPversion then error number 1
	on error
		script b
			property timesRun : 0
			property TPversion : 1.2
			property lastClipboardPattern : "%t. %n"
			property lastSongPattern : "%t - %n"
			property histSN : {Â
				{pat:"%a - %t - %n", txt:"The Beatles - 01 - Taxman"}, Â
				{pat:"%a - %l - %t - %n", txt:"The Beatles - Revolver - 01 - Taxman"}, Â
				{pat:"%t - %l - %n", txt:"01 - Revolver - Taxman"}, Â
				{pat:"%a - %n", txt:"The Beatles - Taxman"}, Â
				{pat:"%t %n", txt:"01 Taxman"}, Â
				{pat:"%t. %n", txt:"01. Taxman"}, Â
				{pat:"%t - %n", txt:"01 - Taxman"}, Â
				{pat:"/(\\d+)(.*)/tn", txt:"01Taxman"}, Â
				{pat:"/(\\D+)((\\d+)-\\d+-\\d+)-?d(\\d)t(\\d+)/alydt", txt:"pixies2004-04-19[-]d1t01"}, Â
				{pat:"d%dt%t", txt:"d2t12 (Disc/Track Number)"}, Â
				{pat:"s/(?ix-sm::(\\s*)((?-xism:\\w[\\w']*))|(^\\W*)((?-xism:\\w[\\w']*))|(\\b(?-xism:\\w[\\w']*))(\\W*$)|\\b(of|a|an|the|and|but|or|nor|for|so|yet|amid|as|at|but|by|down|for|from|in|into|like|near|off|on|onto|over|past|per|plus|save|than|to|up|upon|via|with)\\b|\\b((?-xism:\\w[\\w']*)))/$2?\":$1\\u\\L$2\":\"$3\\u\\L$4\"||\"\\u\\L$5$6\"||\"\\L$7\"||\"\\u\\L$8\"/ige", txt:"Song Name to Title Case"}, Â
				{pat:"/^\\s*(.*?)\\s*(?:\\.(?:mp3|m4a|mp4|aac|ogg))?\\s*$/n", txt:"Trim Leading/Trailing Space, Extension"}, Â
				{pat:"s/(\\w)/\\U$1/g", txt:"Song Name to All Caps"}}
			property histC : {Â
				{pat:"%t. %n", txt:"01. Airbag"}, Â
				{pat:"%t: %n", txt:"01: Airbag"}, Â
				{pat:"%t %n", txt:"01 Airbag"}, Â
				{pat:"/(\\d+)\\S*\\s+(.*)/tn", txt:"01<anything>Airbag"}}
		end script
		set pref to b
	end try
	
	set pref's timesRun to (pref's timesRun) + 1
end loadPrefs

to inHistory(hist, newPat)
	repeat with itm in hist
		if itm's pat = newPat then return true
	end repeat
	return false
end inHistory

-- Check if pat is in the history, and add it if not
to addPattern(hist, newPat, match)
	if inHistory(hist, newPat) then return
	
	copy {pat:newPat, txt:match} to the end of hist
	my savePrefs()
end addPattern

-- Given an alias, delete it with 'rm'
to deleteFile(f)
	local pth
	set pth to "'" & escapeApostrophe(f's POSIX path) & "'"
	do shell script "rm " & pth
end deleteFile

to savePrefs()
	set pToPrefs to ((path to preferences folder from user domain as string) & "Music Parser prefs")
	try
		my deleteFile(pToPrefs as alias)
	end try
	try
		store script pref in file pToPrefs
	on error
		display dialog "Couldn't save preferences"
	end try
end savePrefs
