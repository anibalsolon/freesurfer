#! /usr/bin/tixwish

# $Id: fsgdfPlot.tcl,v 1.6 2003/04/23 21:16:50 kteich Exp $

package require Tix;
package require BLT;

# Look for the library in the following place. If we can't find it, bail.
set fnLib "libtclfsgdf.so"
if { [info exists env(OS)] } {
    switch $env(OS) {
	"Darwin" { set fnLib "libtclfsgdf.dylib" }
	"Linux" { set fnLib "libtclfsgdf.so" }
    }
} 

set bFound 0
catch { lappend lPath . }
catch { lappend lPath $env(FSGDF_DIR) }
catch { lappend lPath $env(MRI_DIR)/lib/$env(OS) }
catch { lappend lPath $env(DEV)/lib/$env(OS) }

set gbLibLoaded 0
foreach sPath $lPath {

    set fnLibrary [file join $sPath $fnLib]
    set err [catch {load $fnLibrary fsgdf} sResult]
    if { 0 == $err } {
	puts "Using $fnLibrary"
	set gbLibLoaded 1
	break
    }
}
if { !$gbLibLoaded } {
    puts "Couldn't load $fnLib."
}

# Also look for tkUtils.tcl.
foreach sSourceFileName { tkUtils.tcl } {
    set lPath [list "." "$env(MRI_DIR)/lib/tcl"]
    set bFound 0
    foreach sPath $lPath {
       if { $bFound == 0 } {
	    set sFullFileName [ file join $sPath $sSourceFileName ]
	    set nErr [catch { source $sFullFileName } sResult]
	    if { $nErr == 0 } {
		puts "Reading $sFullFileName"
		set bFound 1;
	    }
	}
    }    
    if { $bFound == 0 } {
	puts "Couldn't load $sSourceFileName: Not found in $lPath"
    }
}

# This is a description of the data arrays used throughout this code.
# gGDF - information gleaned from the header file.
#   lID - list of IDs
#   ID
#     bReadHeader - whether or not his GDF is parsed correctly
#     title - title of the graph
#     measurementName - label for the measurement
#     subjectName - subject name
#     dataFileName - data file name
#     cClasses - number of classes
#     classes,n - n is 0 -> cClasses
#       label - label for this class
#       marker - marker for this class
#       color - color for this class
#       subjects,n - n is 0 -> num subjects in this class
#         index - index of the subject
#     classes,label - label is the label
#       index - index is the index of this label
#     cVariables - number of variables
#     variables,n - n is 0 -> cVariables
#       label - label for this variable
#     nDefaultVariable - index of default variable
#     cSubjects - number of subjects
#     subjects,n - n is 0 -> cSubjects
#       id - label of this subject
#       nClass - index of class of this subject
#       variables,n - n is 0 -> cVariables
#         value - value for this variable for this subject
# gPlot - information about the plot, including current state.n
#   ID
#     state
#       nVariable - the index of the current variable
#       info - the info string displayed in lwInfo
#       lPoints - list of points
#       pointsChanged - dirty flag for points
#       data,subjects,n - where n is 0 -> cSubjects
#         variable - variable value for this subject (for state,nVariable)
#         measurement - measurement value for this subject
#       hiElement - name of hilighted element in plot
#       subjects,n - where n is 0 -> cSubjects
#         visible - whether or not is visible
#       classes,n - where n is 0 -> cClasses
#         visible - whether or not is visible
#       legend - subject or class
#       bTryRegressionLine - whether or not to try getting the offset/slope
# gWidgets - names of widgets
#   ID
#     wwTop - the top window
#     gwPlot - the graph widget
#     lwInfo - the info label widget
#     bWindowBuilt - boolean indicating if the window has been built
#     state
#       window
#         geometry - if hidden and reshown, will appear with same geometry

# constant values for stuff
set kValid(lMarkers) {square circle diamond plus cross splus scross triangle}
set kValid(lColors) {red blue green yellow black purple orange pink brown}

# Builds the main window. Assumes the header is already read.
proc FsgdfPlot_BuildWindow { iID } {
    global gWidgets gGDF

    set wwTop         .fsgdf-$iID
    set gwPlot        $wwTop.gwPlot
    set lwInfo        $wwTop.lwInfo
    set owVar         $wwTop.owVar
    set owLegendMode  $wwTop.owLegendMode
    set fwClassConfig $wwTop.fwClassConfig


    # Make the to window and set its title.
    toplevel $wwTop -height 500 -width 500
    wm title $wwTop $gGDF($iID,title)

    # Make the graph.
    blt::graph $gwPlot \
	-title $gGDF($iID,title) \
	-plotbackground white \
	-relief raised -border 2

    # Bind our callbacks.
    $gwPlot legend bind all <Enter> [list FsgdfPlot_CBLegendEnter $iID %W]
    $gwPlot legend bind all <Leave> [list FsgdfPlot_CBLegendLeave $iID %W]
    $gwPlot legend bind all <ButtonPress-1> [list FsgdfPlot_CBLegendClick $iID %W]
    bind $gwPlot <Motion> [list FsgdfPlot_CBGraphMotion $iID %W %x %y]
    bind $gwPlot <Destroy> [list FsgdfPlot_CBCloseWindow $iID] 

    # Hooking up the zoom functions seems to break some of the other
    # bindings. Needs more work.  
    # Blt_ZoomStack $gwPlot

    # Set the y axis label to the measurement name.
    $gwPlot axis configure y -title $gGDF($iID,measurementName)

    # Make the info label.
    set gPlot($iID,state,info) ""
    tkuMakeActiveLabel $lwInfo \
	-variable gPlot($iID,state,info)

    # Make the variable menu.
    tixOptionMenu $owVar \
	-command "FsgdfPlot_SetVariable $iID" \
	-options "label.font [tkuLabelFont]"

    # Make the mode menu.
    tixOptionMenu $owLegendMode \
	-command "FsgdfPlot_SetMode $iID" \
	-options "label.font [tkuLabelFont]"
    $owLegendMode config -disablecallback 1
    $owLegendMode add command subject -label "View by subject"
    $owLegendMode add command class -label "View by class"
    $owLegendMode config -disablecallback 0

    # Make a frame for the class controls, which we'll fill in later.
    tixLabelFrame $fwClassConfig -label "Configure Classes"

    # Place everythingin the window.
    grid $gwPlot        -column 0 -row 0 -columnspan 3 -sticky news
    grid $lwInfo        -column 0 -row 1 -sticky nwe
    grid $owLegendMode  -column 1 -row 1 -sticky se
    grid $owVar         -column 2 -row 1 -sticky se
    grid $fwClassConfig -column 0 -row 2 -columnspan 3 -sticky ews
    grid columnconfigure $wwTop 0 -weight 1
    grid columnconfigure $wwTop 1 -weight 0
    grid columnconfigure $wwTop 2 -weight 0
    grid rowconfigure $wwTop 0 -weight 1
    grid rowconfigure $wwTop 1 -weight 0
    grid rowconfigure $wwTop 2 -weight 0

    # Set the names in the gWidgets array.
    set gWidgets($iID,wwTop)          $wwTop
    set gWidgets($iID,gwPlot)         $gwPlot
    set gWidgets($iID,lwInfo)         $lwInfo
    set gWidgets($iID,owVar)          $owVar
    set gWidgets($iID,fwClassConfig)  [$fwClassConfig subwidget frame]

    # Build the dynamic window elements for the window.
    FsgdfPlot_BuildDynamicWindowElements $iID

    # Set the variable menu value to the header's default variable
    # index.
    $owVar config -value $gGDF($iID,nDefaultVariable)

    # Set our initial legen mode to class.
    $owLegendMode config -value class

    # Create the pen for our active element.
    $gwPlot pen create activeElement \
	-symbol circle -color red -pixels 0.2i -fill ""

    # Note that the window has been built.
    set gWidgets($iID,bWindowBuilt) 1
}

# Builds the window elements that are dependant on data, including the
# variable menu and the class configuration section.
proc FsgdfPlot_BuildDynamicWindowElements { iID } {
    global gGDF gWidgets kValid

    # First delete all entries in the menu. Then for each variable,
    # make an entry with that variable's label. The command for the
    # menu has already been set.
    $gWidgets($iID,owVar) config -disablecallback 1
    set lEntries [$gWidgets($iID,owVar) entries]
    foreach entry $lEntries { 
	$gWidgets($iID,owVar) delete $entry
    }
    for { set nVar 0 } { $nVar < $gGDF($iID,cVariables) } { incr nVar } {
	$gWidgets($iID,owVar) add command $nVar \
	    -label "$gGDF($iID,variables,$nVar,label)"
    }
    $gWidgets($iID,owVar) config -disablecallback 0

    # Fill out the class config frame. For each class, make an entry
    # with an option widget for colors and one for markers. Set up the
    # entries appropriately and bind it to the right variable.
    for { set nClass 0 } { $nClass < $gGDF($iID,cClasses) } { incr nClass } {

	set lw       $gWidgets($iID,fwClassConfig).lw$nClass
	set owMarker $gWidgets($iID,fwClassConfig).owMarker$nClass
	set owColor  $gWidgets($iID,fwClassConfig).owColor$nClass

	tkuMakeNormalLabel $lw \
	    -label $gGDF($iID,classes,$nClass,label) \
	    -anchor e

	tixOptionMenu $owMarker \
	    -command "FsgdfPlot_SetNthClassMarker $iID $nClass" \
	    -options "label.font [tkuLabelFont]"
	$owMarker config -disablecallback 1
	foreach marker $kValid(lMarkers) {
	    $owMarker add command $marker -label $marker
	}
	$owMarker config -disablecallback 0
	$owMarker config -value $gGDF($iID,classes,$nClass,marker)

	tixOptionMenu $owColor \
	    -command "FsgdfPlot_SetNthClassColor $iID $nClass" \
	    -options "label.font [tkuLabelFont]"
	$owColor config -disablecallback 1
	foreach color $kValid(lColors) {
	    $owColor add command $color -label $color
	}
	$owColor config -disablecallback 0
	$owColor config -value $gGDF($iID,classes,$nClass,color)

	# We're packing them in two columns (of three columns each).
	set nCol [expr ($nClass % 2) * 3]
	set nRow [expr $nClass / 2]
	grid $lw       -column $nCol            -row $nRow -sticky ew
	grid $owMarker -column [expr $nCol + 1] -row $nRow -sticky ew
	grid $owColor  -column [expr $nCol + 2] -row $nRow -sticky ew
    }
    grid columnconfigure $gWidgets($iID,fwClassConfig) 0 -weight 1
    grid columnconfigure $gWidgets($iID,fwClassConfig) 1 -weight 0
    grid columnconfigure $gWidgets($iID,fwClassConfig) 2 -weight 0
    grid columnconfigure $gWidgets($iID,fwClassConfig) 3 -weight 1
    grid columnconfigure $gWidgets($iID,fwClassConfig) 4 -weight 0
    grid columnconfigure $gWidgets($iID,fwClassConfig) 5 -weight 0
}


# Parse the header file, using the gdf functions to read it and pull
# data out of it. Returns -1 if there was an error, else it returns an
# ID number for the fsgdf.
proc FsgdfPlot_ParseHeader { ifnHeader } {
    global gGDF gPlot gWidgets kValid

    # Generate a new ID.
    set ID 0
    while { [lsearch -exact $gGDF(lID) $ID] != -1 } { incr ID }

    set err [catch {set gGDF($ID,object) [gdfRead $ifnHeader 1]}]
    if { $err } {
	puts "Couldn't init GDF."
	return -1
    }

    # Grab all the data and put it into our TCL object. All these gdf*
    # functions return a list of results. The first is an integer
    # representing a result code. The second -> whatever is the actual
    # result of the function.
    set lResults [gdfGetTitle $gGDF($ID,object) ignore]
    set err [lindex $lResults 0]
    if { 0 == $err } {
	set gGDF($ID,title)  [lindex $lResults 1]
    } else {
	puts "WARNING: Could not get the graph title."
	set gGDF($ID,title)  "Untitled graph"
    }

    set lResults [gdfGetMeasurementName $gGDF($ID,object) ignore]
    set err [lindex $lResults 0]
    if { 0 == $err } {
	set gGDF($ID,measurementName)  [lindex $lResults 1]
    } else {
	puts "WARNING: Could not get the measurement label."
	set gGDF($ID,measurementName)  "Measurement"
    }

    set lResults [gdfGetSubjectName $gGDF($ID,object) ignore]
    set err [lindex $lResults 0]
    if { 0 == $err } {
	set gGDF($ID,subjectName)  [lindex $lResults 1]
    } else {
	puts "WARNING: Could not get the subject name."
	set gGDF($ID,subjectName) "Unknown"
    }


    set lResults [gdfGetDataFileName $gGDF($ID,object) ignore]
    set err [lindex $lResults 0]
    if { 0 == $err } {
	set gGDF($ID,dataFileName)  [lindex $lResults 1]
    } else {
	puts "WARNING: Could not get the data file name."
	set gGDF($ID,dataFileName)  "Unknown"
    }


    set lResults [gdfGetNumClasses $gGDF($ID,object)]
    set err [lindex $lResults 0]
    if { 0 == $err } {
	set gGDF($ID,cClasses)  [lindex $lResults 1]

	# If they didn't specify color or marker for the class, use
	# these and increment so all the classes are different.
	set nColor 0
	set nMarker 0

	for { set nClass 0 } { $nClass < $gGDF($ID,cClasses) } { incr nClass } {

	    set lResults [gdfGetNthClassLabel $gGDF($ID,object) $nClass ignore]
	    set err [lindex $lResults 0]
	    if { 0 == $err } {
		set gGDF($ID,classes,$nClass,label)  [lindex $lResults 1]
	    } else {
		puts "WARNING: Could not get ${nClass}th label."
		set gGDF($ID,classes,$nClass,label) "Class $nClass"
	    }
	    
	    set lResults [gdfGetNthClassMarker $gGDF($ID,object) $nClass ignore]
	    set err [lindex $lResults 0]
	    if { 0 == $err } {
		set gGDF($ID,classes,$nClass,marker)  [lindex $lResults 1]
	    } else {
		puts "WARNING: Could not get ${nClass}th label."
		set gGDF($ID,classes,$nClass,marker) ""
	    }
	    

	    # Look for the marker in the array of valid markers. If
	    # it's not found, output a warning and set it to the
	    # default.
	    set n [lsearch -exact $kValid(lMarkers) \
		       $gGDF($ID,classes,$nClass,marker)]
	    if { $n == -1 } {
		puts "WARNING: Marker for class $gGDF($ID,classes,$nClass,label) was invalid."
		set gGDF($ID,classes,$nClass,marker) \
		    [lindex $kValid(lMarkers) $nMarker]
		incr nMarker
		if { $nMarker >= [llength $kValid(lMarkers)] } {set nMarker 0 }
	    }

	    set lResults [gdfGetNthClassColor $gGDF($ID,object) $nClass ignore]
	    set err [lindex $lResults 0]
	    if { 0 == $err } {
		set gGDF($ID,classes,$nClass,color)  [lindex $lResults 1]
	    } else {
		puts "WARNING: Could not get ${nClass}th label."
		set gGDF($ID,classes,$nClass,color) ""
	    }
	    

	    # Look for the coclor in the array of valid color. If
	    # it's not found, output a warning and set it to the
	    # default.
	    set n [lsearch -exact $kValid(lColors) \
		       $gGDF($ID,classes,$nClass,color)]
	    if { $n == -1 } {
		puts "WARNING: Color for class $gGDF($ID,classes,$nClass,label) was invalid."
		set gGDF($ID,classes,$nClass,color) \
		    [lindex $kValid(lColors) $nColor]
		incr nColor
		if { $nColor >= [llength $kValid(lColors)] } { set nColor 0 }
	    }

	    # This is the reverse lookup for a class label -> index.
	    set gGDF($ID,classes,$gGDF($ID,classes,$nClass,label),index) $nClass

	    # Initialize all classes as visible.
	    set gPlot($ID,state,classes,$nClass,visible) 1
	}
    } else {
	puts "ERROR: Could not get number of classes."
	return -1
    }


    set lResults [gdfGetNumVariables $gGDF($ID,object)]
    set err [lindex $lResults 0]
    if { 0 == $err } {
	set gGDF($ID,cVariables)  [lindex $lResults 1]

	for { set nVariable 0 } \
	    { $nVariable < $gGDF($ID,cVariables) } { incr nVariable } {

	    set lResults [gdfGetNthVariableLabel $gGDF($ID,object) $nVariable ignore]
	    set err [lindex $lResults 0]
	    if { 0 == $err } {
		set gGDF($ID,variables,$nVariable,label)  [lindex $lResults 1]
	    } else {
		puts "WARNING: Could not get ${nClass}th label."
		set gGDF($ID,variables,$nVariable,label)  "Variable $nVariable"
	    }

	}
    } else {
	puts "ERROR: Could not get number of variables."
	return -1
    }


    set lResults [gdfGetDefaultVariable $gGDF($ID,object) ignore]
    set err [lindex $lResults 0]
    if { 0 == $err } {
	set gGDF($ID,defaultVariable)  [lindex $lResults 1]
    } else {
	puts "WARNING: Could not get default variable."
	set gGDF($ID,defaultVariable) $gGDF($ID,variables,0,label)
    }

    set lResults [gdfGetDefaultVariableIndex $gGDF($ID,object)]
    set err [lindex $lResults 0]
    if { 0 == $err } {
	set gGDF($ID,nDefaultVariable)  [lindex $lResults 1]
    } else {
	puts "WARNING: Could not get default variable index."
	set gGDF($ID,defaultVariable) 0
    }

    set lResults [gdfGetNumSubjects $gGDF($ID,object)]
    set err [lindex $lResults 0]
    if { 0 == $err } {
	set gGDF($ID,cSubjects)  [lindex $lResults 1]

	for { set nSubject 0 } \
	    { $nSubject < $gGDF($ID,cSubjects) } { incr nSubject } {

	    set lResults [gdfGetNthSubjectID $gGDF($ID,object) $nSubject ignore]
	    set err [lindex $lResults 0]
	    if { 0 == $err } {
		set gGDF($ID,subjects,$nSubject,id)  [lindex $lResults 1]
	    } else {
		puts "WARNING: Could not get ${nSubject}th subject."
		set gGDF($ID,classes,$nClass,label) "Subject $nSubject"
	    }

	    set lResults [gdfGetNthSubjectClass $gGDF($ID,object) $nSubject]
	    set err [lindex $lResults 0]
	    if { 0 == $err } {
		set gGDF($ID,subjects,$nSubject,nClass)  [lindex $lResults 1]
	    } else {
		puts "WARNING: Could not get ${nSubject}th subject."
		set gGDF($ID,classes,$nClass,label) 0
	    }


	    for { set nVariable 0 } \
		{ $nVariable < $gGDF($ID,cVariables) } { incr nVariable } {

		    set lResults [gdfGetNthSubjectNthValue \
				      $gGDF($ID,object) $nSubject $nVariable]
		    set err [lindex $lResults 0]
		    if { 0 == $err } {
		      set gGDF($ID,subjects,$nSubject,variables,$nVariable,value) \
			  [lindex $lResults 1]
		    } else {
			puts "WARNING: Could not value for ${nSubject}th subject ${nVariable}th variable."
		      set gGDF($ID,subjects,$nSubject,variables,$nVariable,value) 0
		    }
		}

	    # Initialize all subjects as visible.
	    set gPlot($ID,state,subjects,$nSubject,visible) 1
	}
    } else {
	puts "ERROR: Could not get number of subjects."
	return -1
    }


    # This groups the subjects by the class they are in. For each
    # class, for each subject, if the subject is in the class, assign
    # the subject index to that subject-in-class index.
    for  { set nClass 0 } { $nClass < $gGDF($ID,cClasses) } { incr nClass } {
	set nSubjInClass 0
	for { set nSubj 0 } { $nSubj < $gGDF($ID,cSubjects) } { incr nSubj } {
	    if { $gGDF($ID,subjects,$nSubj,nClass) == $nClass } {
		set gGDF($ID,classes,$nClass,subjects,$nSubjInClass,index) $nSubj
		incr nSubjInClass
	    }
	}
    }

    # We now have a header.
    set gGDF($ID,bReadHeader) 1

    # Start out trying to find the offset/slope for a class/var.
    set gPlot($ID,state,bTryRegressionLine) 1

    # If we have a window, build the dynamic elements.
    if { [info exists gWidgets($ID,bWindowBuilt)] && 
	 $gWidgets($ID,bWindowBuilt) } {
	FsgdfPlot_BuildDynamicWindowElements $ID
    }

    if { 0 } {
	puts "$gGDF($ID,cClasses) classes:"
	for { set nClass 0 } { $nClass < $gGDF($ID,cClasses) } { incr nClass } {
	    puts "$nClass: label=$gGDF($ID,classes,$nClass,label) marker=$gGDF($ID,classes,$nClass,marker) color=$gGDF($ID,classes,$nClass,color) reverse index=$gGDF($ID,classes,$gGDF($ID,classes,$nClass,label),index)"
	}
	
	puts "$gGDF($ID,cVariables) variables:"
	for { set nVar 0 } { $nVar < $gGDF($ID,cVariables) } { incr nVar } {
	    puts "$nVar: label=$gGDF($ID,variables,$nVar,label)"
	}
	
	puts "$gGDF($ID,cSubjects) subjects:"
	for { set nSubj 0 } { $nSubj < $gGDF($ID,cSubjects) } { incr nSubj } {
	    puts "$nSubj: id=$gGDF($ID,subjects,$nSubj,id) class=$gGDF($ID,subjects,$nSubj,nClass)"
	}
    }

    lappend gGDF(lID) $ID
    return $ID
}


# This plots the current data on the graph. It is fast enough that it
# can be called any time the data is changed to completely redraw it
# from scratch.
proc FsgdfPlot_PlotData { iID } {
    global gWidgets gPlot gGDF

    # Don't plot if the window isn't built or we don't have data.
    if { ![info exists gWidgets($iID,bWindowBuilt)] ||
	 ![info exists gGDF($iID,bReadHeader)] ||
	 !$gWidgets($iID,bWindowBuilt) || 
	 !$gGDF($iID,bReadHeader) } {
	return
    }

    set gw $gWidgets($iID,gwPlot)

    # Set the x axis title to the label of the current variable.
    $gw axis configure x \
	-title $gGDF($iID,variables,$gPlot($iID,state,nVariable),label)

    # Remove all the elements and markers from the graph.
    set lElements [$gw element names *]
    foreach element $lElements {
	$gw element delete $element
    }
    set lMarkers [$gw marker names *]
    foreach marker $lMarkers {
	$gw marker delete $marker
    }
    
    # If we have no points, return.
    if { ![info exists gPlot($iID,state,lPoints)] || 
	 [llength $gPlot($iID,state,lPoints)] == 0 } {
	return
    }

    # Depending on our legend mode, we'll draw by class or subject.
    if { $gPlot($iID,state,legend) == "class" } {
	
	# For each class, for each subject, if the subject's class is
	# the same as the current class, get its data points and add
	# them to a list. Then draw the entire list of data in the
	# class's color/marker. If the class is hidden, set the color
	# to white (so it shows up white in the legend) and hide the
	# element.
	for  { set nClass 0 } { $nClass < $gGDF($iID,cClasses) } { incr nClass } {

	    set lData {}
	    set nSubjInClass 0
	    for { set nSubj 0 } { $nSubj < $gGDF($iID,cSubjects) } { incr nSubj } {

		if { $gGDF($iID,subjects,$nSubj,nClass) == $nClass } {
		    
		    if { $gPlot($iID,state,pointsChanged) } {
			FsgdfPlot_CalculateSubjectMeasurement $iID $nSubj
		    }
		
		    set gPlot($iID,state,data,subjects,$nSubj,variable) \
			$gGDF($iID,subjects,$nSubj,variables,$gPlot($iID,state,nVariable),value)
		    
		    lappend lData $gPlot($iID,state,data,subjects,$nSubj,variable)
		    lappend lData $gPlot($iID,state,data,subjects,$nSubj,measurement)
		}
	    }

	    if { $gPlot($iID,state,classes,$nClass,visible) } {
		set bHide 0
		set color $gGDF($iID,classes,$nClass,color)
	    } else {
		set bHide 1
		set color white
	    }
	    $gw element create $gGDF($iID,classes,$nClass,label) \
		-data $lData \
		-symbol $gGDF($iID,classes,$nClass,marker) \
		-color $color -linewidth 0 -outlinewidth 1 -hide $bHide \
		-activepen activeElement
	}

    } else {
	
	
	# For each subject, if the points have changed, calculate the #
	# measurements. Get the variable value. If the subject is visible,
	# set # the hide flag to 0 and the color to the subject's class
	# color, else # set the hide flag to 1 and set the color to
	# white. Create the # element.
	for { set nSubj 0 } { $nSubj < $gGDF($iID,cSubjects) } { incr nSubj } {
	    
	    if { $gPlot($iID,state,pointsChanged) } {
		FsgdfPlot_CalculateSubjectMeasurement $iID $nSubj
	    }
	    
	    set gPlot($iID,state,data,subjects,$nSubj,variable) \
		$gGDF($iID,subjects,$nSubj,variables,$gPlot($iID,state,nVariable),value)
	    
	    if {  $gPlot($iID,state,subjects,$nSubj,visible) } {
		set bHide 0
		set color $gGDF($iID,classes,$gGDF($iID,subjects,$nSubj,nClass),color)
	    } else {
		set bHide 1
		set color white
	    }
	    $gw element create $gGDF($iID,subjects,$nSubj,id) \
		-data [list $gPlot($iID,state,data,subjects,$nSubj,variable) \
			   $gPlot($iID,state,data,subjects,$nSubj,measurement)] \
		-symbol $gGDF($iID,classes,$gGDF($iID,subjects,$nSubj,nClass),marker) \
		-color $color -linewidth 0 -outlinewidth 1 -hide $bHide \
		-activepen activeElement
	}
    }

    # If we're trying to draw the regression line, for each class, if
    # the class is visible, get the offset and slope for that class
    # and the current variable. This depends on the point we're
    # drawing, so get the avg of all the points if necessary. Then
    # make a marker calculating two points on the line. if
    # gdfOffsetSlope() failes, set the bTryRegressionLine flag to
    # false, so we won't try drawing it again.
    if { $gPlot($iID,state,bTryRegressionLine) } {

	for  { set nClass 0 } { $nClass < $gGDF($iID,cClasses) } { incr nClass } {
	    
	    if { $gPlot($iID,state,classes,$nClass,visible) } {
		
		set nVar $gPlot($iID,state,nVariable)
		
		# Calc the avg offset and slope for all points.
		set offset 0
		set slope 0
		set cGood 0
		foreach lPoint $gPlot($iID,state,lPoints) {
		    scan $lPoint "%d %d %d" x y z
		    set lResults [gdfOffsetSlope $gGDF($iID,object) \
				      $nClass $nVar $x $y $z]
		    set err [lindex $lResults 0]
		    if { 0 == $err } {
			set offset [expr $offset + [lindex $lResults 1]]
			set slope [expr $slope + [lindex $lResults 2]]
			incr cGood
		    } else {
			set gPlot($iID,state,bTryRegressionLine) 0
			break
		    }

		    if { $cGood > 0 } {
			set x1 -200
			set y1 [expr ($slope * $x1) + $offset]
			set x2 200
			set y2 [expr ($slope * $x2) + $offset]

			$gw marker create line \
			    -coords [list $x1 $y1 $x2 $y2] \
			    -outline $gGDF($iID,classes,$nClass,color) \
			    -dashes {5 5}
		    }
		}
	    }

	    if { $gPlot($iID,state,bTryRegressionLine) == 0 } { break }
	}
    }
    
    set gPlot($iID,state,pointsChanged) 0
}


# Accesses and calculates the (averaged if necessary) measurment
# values at the current point(s). Stores the values in gPlot.
proc FsgdfPlot_CalculateSubjectMeasurement { iID inSubject } {
    global gPlot gGDF

    # Get the average of the points we've been given.
    set meas 0
    set cGood 0
    foreach lPoint $gPlot($iID,state,lPoints) {
	
	scan $lPoint "%d %d %d" x y z
	set lResults [gdfGetNthSubjectMeasurement $gGDF($iID,object) \
			  $inSubject $x $y $z]
	set err [lindex $lResults 0]
	if { 0 == $err } {
	    set meas [expr $meas + [lindex $lResults 1]]
	    incr cGood
	}
    }
    if { $cGood > 0 } {
	set meas [expr $meas / $cGood.0]
    }
    
    # Store the values in gPlot.
    set gPlot($iID,state,data,subjects,$inSubject,measurement) $meas
}


# Hilight/UnhilightElement works on an element by name (which could be
# a subject or class, depending on viewing mode). It will
# select/unselect the element name in the legend and change the
# drawing pen of the element in the graph, which if activated draws it
# with a red circle around it.
proc FsgdfPlot_HilightElement { iID iElement } {
    global gWidgets
    $gWidgets($iID,gwPlot) legend activate $iElement
    $gWidgets($iID,gwPlot) element activate $iElement
}

proc FsgdfPlot_UnhilightElement { iID iElement } {
    global gWidgets
    $gWidgets($iID,gwPlot) legend deactivate $iElement
    $gWidgets($iID,gwPlot) element deactivate $iElement
}


# Shows or hide an element by name, in subject or class mode. Changes
# the value of the gPlot visibility flag.
proc FsgdfPlot_ToggleVisibility { iID iElement } {
    global gPlot

    # If we're in subject legend mode, the legend label is a subject
    # name. Get the subject index and toggle its visibility. If we're in
    # class legend mode, the legend label is a class name, so get the
    # class index and toggle its visibility.
    if { $gPlot($iID,state,legend) == "subject" } {
	set nSubj [FsgdfPlot_GetSubjectIndexFromID $iID $iElement]
	if { $gPlot($iID,state,subjects,$nSubj,visible) } {
	    set gPlot($iID,state,subjects,$nSubj,visible) 0
	} else {
	    set gPlot($iID,state,subjects,$nSubj,visible) 1
	}
    } else {
	set nClass [FsgdfPlot_GetClassIndexFromLabel $iID $iElement]
	if { $gPlot($iID,state,classes,$nClass,visible) } {
	    set gPlot($iID,state,classes,$nClass,visible) 0
	} else {
	    set gPlot($iID,state,classes,$nClass,visible) 1
	}
    }
}


# Focus/Unfocus is called to 'mouseover' an element. It
# Hilight/Unhilights an element and puts or removes the subject name
# in a text marker in the graph.
proc FsgdfPlot_UnfocusElement { iID } {
    global gPlot gWidgets

    # If we have a focused element, unhighlight it, set the
    # highlighted element name to null, and delete the hover text
    # marker.
    if { [info exists gPlot($iID,state,hiElement)] && \
	     "$gPlot($iID,state,hiElement)" != "" } {
	FsgdfPlot_UnhilightElement $iID $gPlot($iID,state,hiElement)
	set gPlot($iID,state,hiElement) ""
	$gWidgets($iID,gwPlot) marker delete hover
    }
}

proc FsgdfPlot_FocusElement { iID iElement inSubjInClass iX iY } {
    global gPlot gWidgets gGDF

    # Set the highlighted element name and highlight the element.
    set gPlot($iID,state,hiElement) $iElement
    FsgdfPlot_HilightElement $iID $gPlot($iID,state,hiElement)

    # Need to get the subject name. If we're in subject mode, this is
    # just the element name, otherwise we're getting the class name in
    # the element name so get the class index, then use that and the
    # parameter we got (index of the data point, also the
    # subject-in-class index) to get th subject index, and then the
    # subject name.
    if { $gPlot($iID,state,legend) == "subject" } {
	set sId $iElement
    } else {
	set nClass [FsgdfPlot_GetClassIndexFromLabel $iID $iElement]
	set nSubj $gGDF($iID,classes,$nClass,subjects,$inSubjInClass,index)
      set sId $gGDF($iID,subjects,$nSubj,id)
    }
    $gWidgets($iID,gwPlot) marker create text \
	-name hover -text $sId -anchor nw \
	-coords [list $iX $iY]
}


# Finds the element under the mouse.
proc FsgdfPlot_FindMousedElement { iID iX iY } {
    global gWidgets
    set bFound [$gWidgets($iID,gwPlot) element closest $iX $iY aFound -halo 10]
    if { $bFound } {
	return [list $aFound(name) $aFound(index) $aFound(x) $aFound(y)]
    }
    return ""
}


# Converts from subject or class names to indicies.
proc FsgdfPlot_GetSubjectIndexFromID { iID iSubjID } {
    global gGDF
    for { set nSubj 0 } { $nSubj < $gGDF($iID,cSubjects) } { incr nSubj } {
	if { "$iSubjID" == "$gGDF($iID,subjects,$nSubj,id)" } { return $nSubj }
    }
    return -1
}

proc FsgdfPlot_GetClassIndexFromLabel { iID iLabel } {
    global gGDF
    for { set nClass 0 } { $nClass < $gGDF($iID,cClasses) } { incr nClass } {
	if { "$iLabel" == "$gGDF($iID,classes,$nClass,label)" } { return $nClass }
    }
    return -1
}


# Our callbacks.
proc FsgdfPlot_CBCloseWindow { iID } {
    global gWidgets
    set gWidgets($iID,bWindowBuilt) 0
}

proc FsgdfPlot_CBLegendEnter { iID igw } {
    FsgdfPlot_HilightElement $iID [$igw legend get current]
}

proc FsgdfPlot_CBLegendLeave { iID igw } {
    FsgdfPlot_UnhilightElement $iID [$igw legend get current]
}

proc FsgdfPlot_CBLegendClick { iID igw } {
    FsgdfPlot_ToggleVisibility $iID [$igw legend get current]
    FsgdfPlot_PlotData $iID
}

proc FsgdfPlot_CBGraphMotion { iID igw iX iY } {
    FsgdfPlot_UnfocusElement $iID
    set lResult [FsgdfPlot_FindMousedElement $iID $iX $iY]
    set element [lindex $lResult 0]
    if { "$element" != "" } { 
	set index [lindex $lResult 1]
	set x [lindex $lResult 2]
	set y [lindex $lResult 3]
	FsgdfPlot_FocusElement $iID $element $index $x $y
    }
}

# ============================================================ PUBLIC


# Call once before anything else to initialize the data structures.
proc FsgdfPlot_Init {} {
    global gWidgets gbLibLoaded gGDF
    if { !$gbLibLoaded } { return }
    set gGDF(lID) {}
}


# Read a header file.
proc FsgdfPlot_Read { ifnHeader } {
    global gbLibLoaded
    if { !$gbLibLoaded } { return -1 }
    set ID [FsgdfPlot_ParseHeader $ifnHeader]
    return $ID
}


# Print information about the header.
proc FsgdfPlot_Print { iID } {
    global gGDF gbLibLoaded
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
    gdfPrintStdout $gGDF($iID,object)
}


# Show or hide the window. If it hasn't been built, builds the window
# first.
proc FsgdfPlot_ShowWindow { iID } {
    global gGDF gWidgets gbLibLoaded
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
    if { ![info exists gWidgets($iID,bWindowBuilt)] ||
	 !$gWidgets($iID,bWindowBuilt) } {
	FsgdfPlot_BuildWindow $iID
    }
    wm deiconify $gWidgets($iID,wwTop)
    if { [info exists gWidgets($iID,state,window,geometry)] } {
	wm geometry $gWidgets($iID,wwTop) $gWidgets($iID,state,window,geometry)
    }
}

proc FsgdfPlot_HideWindow { iID } {
    global gGDF gWidgets gbLibLoaded
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
    if { [info exists gWidgets($iID,wwTop)] } {
	set gWidgets($iID,state,window,geometry) \
	    [wm geometry $gWidgets($iID,wwTop)]
	wm withdraw $gWidgets($iID,wwTop)
    }
}


# Set the current variable.
proc FsgdfPlot_SetVariable { iID inVariable } {
    global gGDF gWidgets gPlot gbLibLoaded
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }

    set gPlot($iID,state,nVariable) $inVariable

    FsgdfPlot_PlotData $iID
}


# Set legend mode to subject or class.
proc FsgdfPlot_SetMode { iID iMode } {
    global gGDF gWidgets gPlot gbLibLoaded
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
    if { $iMode != "subject" && $iMode != "class" } { return }

    set gPlot($iID,state,legend) $iMode

    FsgdfPlot_PlotData $iID
}


# Set display settings for a class.
proc FsgdfPlot_SetNthClassMarker { iID inClass iMarker } {
    global gGDF kValid gbLibLoaded
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
    if { $inClass < 0 || $inClass >= $gGDF($iID,cClasses) } { return }
    if { [lsearch -exact $kValid(lMarkers) $iMarker] == -1 } { return }

    set gGDF($iID,classes,$inClass,marker) $iMarker

    FsgdfPlot_PlotData $iID
}

proc FsgdfPlot_SetNthClassColor { iID inClass iColor } {
    global gGDF kValid gbLibLoaded
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
    if { $inClass < 0 || $inClass >= $gGDF($iID,cClasses) } { return }
    if { [lsearch -exact $kValid(lColors) $iColor] == -1 } { return }

    set gGDF($iID,classes,$inClass,color) $iColor

    FsgdfPlot_PlotData $iID
}


# Choose a point to be displayed. Either choose one point or make a
# point list to be averaged.
proc FsgdfPlot_SetPoint { iID iX iY iZ } {
    global gbLibLoaded gGDF
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
    FsgdfPlot_BeginPointList $iID
    FsgdfPlot_AddPoint $iID $iX $iY $iZ
    FsgdfPlot_EndPointList $iID
}

proc FsgdfPlot_BeginPointList { iID } {
    global gGDF gPlot gbLibLoaded
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
    set gPlot($iID,state,lPoints) {}
}

proc FsgdfPlot_AddPoint { iID iX iY iZ } {
    global gGDF gWidgets gPlot gbLibLoaded
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
    lappend gPlot($iID,state,lPoints) [list $iX $iY $iZ]
    set gPlot($iID,state,pointsChanged) 1
}

proc FsgdfPlot_EndPointList { iID } {
    global gGDF gbLibLoaded
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
    FsgdfPlot_PlotData $iID
}


# Set the info string displayed under the graph.
proc FsgdfPlot_SetInfo { iID isInfo } {
    global gGDF gPlot gbLibLoaded
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
    set gPlot($iID,state,info) $isInfo
}


# Save the currently plotted data to a table.
proc FsgdfPlot_SaveToTable { iID ifnTable } {
    global gPlot gGDF gbLibLoaded
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }

    set fp 0
    set err [catch {set fp [open $ifnTable w+]}]
    if { $err || $fp == 0 } {
	puts "Couldn't write file $ifnTable."
	return
    }
    
    puts $fp "Graph: $gGDF($iID,title)"
    puts $fp "Data: $gGDF($iID,dataFileName)"
    puts $fp "Variable: $gGDF($iID,variables,$gPlot($iID,state,nVariable),label)"
    puts $fp "Measurement: $gGDF($iID,measurementName)"
    puts $fp "subject id, class id, variable value, measurement value"
    puts $fp "------------"
    for { set nSubj 0 } { $nSubj < $gGDF($iID,cSubjects) } { incr nSubj } {

	set subjLabel $gGDF($iID,subjects,$nSubj,id)
	set classLabel $gGDF($iID,classes,$gGDF($iID,subjects,$nSubj,nClass),label)
	set var $gPlot($iID,state,data,subjects,$nSubj,variable)
	set meas $gPlot($iID,state,data,subjects,$nSubj,measurement)

	puts $fp "$subjLabel $classLabel $var $meas"
    }
    puts $fp "------------"
    puts ""

    close $fp
}


# Save the current plot graphic to a postscript file.
proc FsgdfPlot_SaveToPostscript { iID ifnPS } {
    global gGDF gWidgets gbLibLoaded
    if { !$gbLibLoaded } { return }
    if { [lsearch $gGDF(lID) $iID] == -1 } { puts "ID not found"; return }
    set err [catch {$gWidgets($iID,gwPlot) postscript output $ifnPS} sResult]
    if { $err } {
	puts "Could not save postscript file: $sResult"
    }
}