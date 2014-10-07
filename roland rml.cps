/**
  Copyright (C) 2012-2013 by Autodesk, Inc.
  All rights reserved.

  Roland post processor configuration.

  $Revision: 35007 $
  $Date: 2013-09-19 16:53:42 +0200 (to, 19 sep 2013) $
  
  FORKID {C1E71A5D-CAD6-45ba-B223-FE41348C147E}
*/

description = "GitHub - Generic Roland RML";
vendor = "Autodesk, Inc.";
vendorUrl = "http://www.autodesk.com";
legal = "Copyright (C) 2012-2013 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

extension = "prn";
programNameIsInteger = true;
setCodePage("ascii");

tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined; // allow any circular motion



// user-defined properties
properties = {
  MDX15or20: false, // set machine type
  MDX40: false, // set machine type
  MDX540: false, // set machine type
  useToolChanger: false, // automatic tool changer (ATC)
  Spindle_speed_in_RPM: false // RPM output instead of RC spindle speed codes
};



var mFormat = createFormat({decimals:0});

var xyzFormat; // set in onOpen
var feedFormat = createFormat({decimals:(unit == MM ? 1 : 1), forceDecimal:true, trim:false, scale: 1.0/60});
var toolFormat = createFormat({decimals:0});
var rpmFormat = createFormat({decimals:0});
var milliFormat = createFormat({decimals:0}); // milliseconds

var xOutput; // set in onOpen
var yOutput; // set in onOpen
var zOutput; // set in onOpen
var feedOutput = createVariable({}, feedFormat);
var sOutput = createVariable({force:true}, rpmFormat);

// collected state
var rapidFeed;
var sMin;
var sMax;
 
/**
  Writes the specified block.
*/
function writeBlock() {
  writeln(formatWords(arguments) + ";");
}

function onOpen() {

  if (!properties.MDX15or20 && !properties.MDX40 && !properties.MDX540) {
    error(localize("No machine type is selected. You have to define a machine type using the properties."));
    return;
  }

  setWordSeparator("");

  writeBlock(";;" + (properties.MDX15or20 ? "^IN" : "^DF"));
  
  if (properties.MDX15or20) {
    rapidFeed = 15.0 * 60;
    step = 0.025;
    sMin = 6500;
    sMax = 6500;
  } else if (properties.MDX40) {
    rapidFeed = 50.0 * 60;
    step = 0.01;
    sMin = 4500;
    sMax = 15000;
  } else if (properties.MDX540) {
    rapidFeed = 125.0 * 60;
    step = 0.01;
    sMin = 3000;
    sMax = 12000;
  } else {
    error(localize("No machine type is selected. You have to define a machine type using the properties."));
    return;
  }
  
  xyzFormat = createFormat({decimals:(unit == MM ? 0 : 0), scale: 1.0/step});
  xOutput = createVariable({force:true}, xyzFormat);
  yOutput = createVariable({force:true}, xyzFormat);
  zOutput = createVariable({force:true}, xyzFormat);  

  writeBlock(properties.MDX15or20 ? "!MC1" : "!MC0;V" + feedOutput.format(rapidFeed)); 
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of X, Y, Z, and F on next output. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

function onParameter(name, value) {
}

function goHome() {
  feedOutput.reset(); // force V
  if (properties.MDX15or20) {
    writeBlock("^PR");
    writeBlock("V" + feedOutput.format(rapidFeed));
    writeBlock("Z0,0,162.6"); // retract
    writeBlock("^PA");
  } else if (properties.MDX40) {
    writeBlock("^PR");
    writeBlock("V" + feedOutput.format(rapidFeed));
    writeBlock("Z0,0,10500"); // retract			
    writeBlock("^PA");
  } else if (properties.MDX540) {
    writeBlock("^PR");
    writeBlock("V" + feedOutput.format(rapidFeed));
    writeBlock("Z0,0,15500"); // retract
    writeBlock("^PA");
  }
  zOutput.reset();
}

function getSpindleSpeed() {
  var rpm = tool.spindleRPM;
  var speedCode = 0;
  var sDiff = sMax - sMin;

  var checkrpm = sMin;
  var middle = sMin;
  while (checkrpm < rpm) { // find the closest speedCode
    speedCode = speedCode + 1;
    var nextSpindleSpeed = ((sDiff/15) * speedCode) + sMin;
    middle = (nextSpindleSpeed - checkrpm)/2;
    checkrpm = checkrpm + (nextSpindleSpeed - checkrpm);
  }
  if ((rpm + middle) < checkrpm) { // find the middle of spindle speed range
    speedCode = speedCode - 1;
  }
  return speedCode;  
}

function onSection() {
  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);
  
  var retracted = false; // specifies that the tool has been retracted to the safe plane
  var newWorkOffset = isFirstSection() ||
    (getPreviousSection().workOffset != currentSection.workOffset); // work offset changes
  var newWorkPlane = isFirstSection() ||
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis());
  if (insertToolCall || newWorkOffset || newWorkPlane) {
    // retract to safe plane
    retracted = true;
    goHome(); //retract
  }

  if (insertToolCall) {
    if (!isFirstSection() && properties.optionalStop) {
      onCommand(COMMAND_OPTIONAL_STOP);
    }

    if (tool.number > 4) {
      warning(localize("Tool number exceeds maximum value."));
    }

    if (properties.useToolChanger) {
      writeBlock("J" + toolFormat.format(tool.number));
    } else {
      if (!isFirstSection()) {
        error(localize("Tool change is not supported without ATC. Please only post operations using the same tool."));
        return;
      }
    }
  }
  
  if (insertToolCall ||
      isFirstSection() ||
      (rpmFormat.areDifferent(tool.spindleRPM, sOutput.getCurrent())) ||
      (tool.clockwise != getPreviousSection().getTool().clockwise)) {
    // spindle speed is fixed to 6500rpm on MDX15/20 Machines
    if (!properties.MDX15or20) {
      if (tool.spindleRPM < sMin) {
        error(localize("Spindle speed exceeds minimum value."));
        return;
      }
      if (tool.spindleRPM > sMax) {
        error(localize("Spindle speed exceeds maximum value."));
        return;
      }
      writeBlock(
        "!RC", 
        (properties.Spindle_speed_in_RPM  ? sOutput.format(tool.spindleRPM) : getSpindleSpeed()) + ";",
        "!MC1" // spindle on (M03))
      );
    }
  }

  // wcs
  var workOffset = currentSection.workOffset;
  if (workOffset > 0) {
    error(localize("Work offset out of range."));
    return;
  }

  forceAny();

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z) {
      goHome();
      feedOutput.reset();
    }
  }

  if (insertToolCall) {
    writeBlock(
      "Z",
      xOutput.format(initialPosition.x), ",",
      yOutput.format(initialPosition.y), ",",
      zOutput.format(initialPosition.z)
    );
  }
}

function onDwell(seconds) {
  if (seconds > 32767/1000.0) {
    warning(localize("Dwelling time is out of range."));
  }
  milliseconds = clamp(1, seconds * 1000, 32767);
  writeBlock("W", milliFormat.format(milliseconds));
}

function onRapid(_x, _y, _z) {
  if (radiusCompensation > 0) {
    error(localize("Radius compensation is not supported."));
    return;
  }

  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    var f = feedOutput.format(rapidFeed);
    if (f) {
      writeBlock("V" + f); // rapid feed (like G0)
    }
    writeBlock("Z", x + ",", y + ",", z);
    feedOutput.reset();
  }
}

function onLinear(_x, _y, _z, feed) {
  if (radiusCompensation > 0) {
    error(localize("Radius compensation is not supported."));
    return;
  }

  var f = feedOutput.format(feed);
  if (f) {
    writeBlock("V" + f);
  }

  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    writeBlock("Z", x + ",", y + ",", z);
  }
}

function onCircular() {
  linearize(tolerance); // note: could use operation tolerance
}

function onCommand(command) {
  onUnsupportedCommand(command);
}

function onSectionEnd() {
  forceAny();
}

function onClose() {
  writeBlock("!MC0"); // stop spindle
  goHome();

  onImpliedCommand(COMMAND_END);
  onImpliedCommand(COMMAND_STOP_SPINDLE);
  writeBlock(properties.MDX15or20 ? "^IN" : "^DF");
}
