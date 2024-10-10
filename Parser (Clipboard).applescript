property pattern : "%t. %n"

property pathToBase : 0
if pathToBase is 0 then
	set pathToBase to ((path to "dlib" from user domain as string) & "iTunes:Scripts:Parser (Song Names).scpt")
end if

set success to false
repeat while not success
	try
		set parser to (load script (pathToBase as alias))
		tell parser to loadPrefs()
		set success to true
	on error
		set pathToBase to (choose file with prompt "Please locate the 'Parser (Song Names)' script" default location (path to "dlib" from user domain)) as string
	end try
end repeat

tell application "iTunes"
	set saveD to AppleScript's text item delimiters
	set txt to (the clipboard as text)
	set mlines to parser's split(return, txt)
	
	set action to parser's getPattern("Pick a format. Sample Line:" & return & (item 1 of mlines), pattern, parser's pref's histC)
	set pattern to action's pattern
	set cPat to parser's compilePattern(pattern)
	
	set sel to selection of front browser window
	set numT to length of sel
	set numL to length of mlines
	set matched to false
	set iLine to 0
	repeat with iTrack from 1 to numT
		set thisTrack to item iTrack of sel
		-- Skip blank lines -- this is to allow for Windows-formatted text
		set iLine to iLine + 1
		repeat while item iLine of mlines is ""
			set iLine to iLine + 1
		end repeat
		set thisLine to item iLine of mlines
		set res to parser's applyPattern(thisLine, cPat, thisTrack, action's callback)
		if res is false and iTrack < numT then
			if button returned of (display dialog "An error occured matching " & pattern & " to '" & thisLine & "'. Would you like to continue matching?" buttons {"Stop Now", "Continue Matching"} default button 1) is "Stop Now" then
				error number -128
			end if
		else if not matched then
			set matched to true
			set matchedTrack to thisLine
		end if
	end repeat
	
	if matched and not parser's inHistory(parser's pref's histC, pattern) then
		set patName to parser's getPatternName(matchedTrack)
		if patName ­ false then parser's addPattern(parser's pref's histC, pattern, patName)
	end if
end tell

