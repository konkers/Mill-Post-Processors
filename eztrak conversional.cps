/**
  Copyright (C) 2012-2014 by Autodesk, Inc.
  All rights reserved.

  EZ-TRAK post processor configuration.

  $Revision: 28197 $
  $Date: 2011-12-14 19:24:28 +0100 (on, 14 dec 2011) $
  
  FORKID {470F5A95-4FA5-455e-BBF7-E9F9D69FED45}
*/

description = "GitHub - Generic EZ-Trak Conversional";
vendor = "Autodesk, Inc.";
vendorUrl = "http://www.autodesk.com";
legal = "Copyright (C) 2012-2014 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

extension = "pgm";
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
  writeMachine: true, // write machine
  writeTools: true, // writes the tools
  sequenceNumberStart: 1000, // first sequence number // ATTENTION: some block numbers can result in errors
  sequenceNumberIncrement: 10, // increment for sequence numbers
  useRadius: false, // specifies that arcs should be output using the radius (R word)
  useToolChanger: true // specifies that a tool changer is available
};



var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true});
var feedFormat = createFormat({decimals:(unit == MM ? 1 : 2), forceDecimal:true});
var toolFormat = createFormat({decimals:0});
var nFormat = createFormat({decimals:0});
var rpmFormat = createFormat({decimals:0});
var taperFormat = createFormat({decimals:1, scale:DEG});

var xOutput = createVariable({prefix:"X", force:true}, xyzFormat);
var yOutput = createVariable({prefix:"Y", force:true}, xyzFormat);
var zOutput = createVariable({prefix:"Z", force:true}, xyzFormat);
var rOutput = createVariable({prefix:"R", force:true}, xyzFormat);
var feedOutput = createVariable({prefix:"F", force:true}, feedFormat);
var sOutput = createVariable({prefix:"S", force:true}, rpmFormat);

// circular output
var xcOutput = createVariable({prefix:"XC", force:true}, xyzFormat);
var ycOutput = createVariable({prefix:"YC", force:true}, xyzFormat);

var WARNING_WORK_OFFSET = 0;

// collected state
var sequenceNumber;

/**
  Writes the specified block.
*/
function writeBlock() {
  if (true) {
    writeWords2(nFormat.format(sequenceNumber), arguments);
    sequenceNumber += properties.sequenceNumberIncrement;
    if (sequenceNumber > 9999) {
      sequenceNumber = properties.sequenceNumberStart;
    }
  } else {
    writeWords(arguments);
  }
}

/**
  Output a comment.
*/
function writeComment(text) {
  // not supported writeln("(" + text + ")");
}

function onOpen() {
  sequenceNumber = properties.sequenceNumberStart;
  
  writeln("0000 EZTRAK|SX 1 MODE|" + ((unit == MM) ? "MM" : "INCH") + " |SAT JAN 1 00:00:00 2011");
  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }

  // dump tool information
  if (properties.writeTools) {
    var zRanges = {};
    if (is3D()) {
      var numberOfSections = getNumberOfSections();
      for (var i = 0; i < numberOfSections; ++i) {
        var section = getSection(i);
        var zRange = section.getGlobalZRange();
        var tool = section.getTool();
        if (zRanges[tool.number]) {
          zRanges[tool.number].expandToRange(zRange);
        } else {
          zRanges[tool.number] = zRange;
        }
      }
    }

    var tools = getToolTable();
    if (tools.getNumberOfTools() > 0) {
      for (var i = 0; i < tools.getNumberOfTools(); ++i) {
        var tool = tools.getTool(i);
        var comment = "T" + toolFormat.format(tool.number) + "  " +
          "D=" + xyzFormat.format(tool.diameter) + " " +
          localize("CR") + "=" + xyzFormat.format(tool.cornerRadius);
        if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
          comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
        }
        if (zRanges[tool.number]) {
          comment += " - " + localize("ZMIN") + "=" + xyzFormat.format(zRanges[tool.number].getMinimum());
        }
        comment += " - " + getToolTypeName(tool.type);
        writeComment(comment);
      }
    }
  }
}

function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

function onSection() {
  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);
  
  if (insertToolCall) {
    if (properties.useToolChanger) {
      writeBlock("||", "TOOLCHG|CLRPT", "T" + toolFormat.format(currentSection.getTool().number));
    } else {
      var comment = "T" + toolFormat.format(tool.number) + "  " +
        "D=" + xyzFormat.format(tool.diameter) + " " +
        localize("CR") + "=" + xyzFormat.format(tool.cornerRadius);
      if ((tool.taperAngle > 0) && (tool.taperAngle < Math.PI)) {
        comment += " " + localize("TAPER") + "=" + taperFormat.format(tool.taperAngle) + localize("deg");
      }
      comment += " - " + getToolTypeName(tool.type);
      writeComment(comment);
    }
    if (tool.comment) {
      writeComment(tool.comment);
    }
    var showToolZMin = false;
    if (showToolZMin) {
      if (is3D()) {
        var numberOfSections = getNumberOfSections();
        var zRange = currentSection.getGlobalZRange();
        var number = tool.number;
        for (var i = currentSection.getId() + 1; i < numberOfSections; ++i) {
          var section = getSection(i);
          if (section.getTool().number != number) {
            break;
          }
          zRange.expandToRange(section.getGlobalZRange());
        }
        writeComment(localize("ZMIN") + "=" + zRange.getMinimum());
      }
    }
  }
  
  writeBlock("|| SPINDLE ON", sOutput.format(tool.spindleRPM));
  
  // wcs
  if (currentSection.workOffset != 0) {
    warningOnce(localize("Work offset is not supported."), WARNING_WORK_OFFSET);
  }

  { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  forceAny();

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (insertToolCall) {
    // we would like to move horizontally only
    writeBlock("RAPID ABS", xOutput.format(initialPosition.x), yOutput.format(initialPosition.y), zOutput.format(initialPosition.z));
  } else {
    if (getCurrentPosition().z < initialPosition.z) {
      // move up
      writeBlock("RAPID ABS", xOutput.format(getCurrentPosition().x), yOutput.format(getCurrentPosition().y), zOutput.format(initialPosition.z));
    } else if (getCurrentPosition().z > initialPosition.z) {
      // move horizontally
      writeBlock("RAPID ABS", xOutput.format(initialPosition.x), yOutput.format(initialPosition.y), zOutput.format(getCurrentPosition().z));
    }
  }
  writeBlock("RAPID ABS", xOutput.format(initialPosition.x), yOutput.format(initialPosition.y), zOutput.format(initialPosition.z));
}

function onDwell(seconds) {
  warning(localize("Dwelling is not supported."));
}

function onSpindleSpeed(spindleSpeed) {
  writeBlock("|| SPINDLE ON", sOutput.format(spindleSpeed));
}

function onCycle() {
}

function onCyclePoint(x, y, z) {
  // bore and tap should be supported
  switch (cycleType) {
  case "drilling":
    writeBlock("DR|PT ABS", xOutput.format(x), yOutput.format(y), zOutput.format(z), feedOutput.format(cycle.feedrate));
    break;
  default:
    expandCyclePoint(x, y, z);
  }
}

function onCycleEnd() {
}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

function onRapid(x, y, z) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation mode cannot be changed at rapid traversal."));
    return;
  }
  // ABS|INC
  writeBlock("RAPID ABS", xOutput.format(x), yOutput.format(y), zOutput.format(z));
}

function onLinear(x, y, z, feed) {
  if (pendingRadiusCompensation >= 0) {
    pendingRadiusCompensation = -1;
    switch (radiusCompensation) {
    case RADIUS_COMPENSATION_LEFT:
      // TAG: use D and P
      writeBlock("COMP|ON LFT", xOutput.format(x), yOutput.format(y), zOutput.format(z), feedOutput.format(feed));
      break;
    case RADIUS_COMPENSATION_RIGHT:
      // TAG: use D and P
      writeBlock("COMP|ON xxx", xOutput.format(x), yOutput.format(y), zOutput.format(z), feedOutput.format(feed));
      break;
    default:
      writeBlock("COMP|OFF", zOutput.format(z));
      writeBlock("LINE ABS", xOutput.format(x), yOutput.format(y), zOutput.format(z), feedOutput.format(feed));
    }
  } else {
    writeBlock("LINE ABS", xOutput.format(x), yOutput.format(y), zOutput.format(z), feedOutput.format(feed));
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }
  
  if (properties.useRadius) {
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock("ARC|RADIUS ABS " + (clockwise ? "CW" : "CCW"), xOutput.format(x), yOutput.format(y), zOutput.format(z), rOutput.format(radius), feedOutput.format(feed));
      break;
    case PLANE_ZX:
      if (isHelical()) {
        linearize(tolerance);
        return;
      }
      writeBlock("ARC|RADIUS|ZX ABS " + (clockwise ? "CW" : "CCW"), xOutput.format(x), yOutput.format(y), zOutput.format(z), rOutput.format(radius), feedOutput.format(feed));
      break;
    case PLANE_YZ:
      if (isHelical()) {
        linearize(tolerance);
        return;
      }
      writeBlock("ARC|RADIUS|YZ ABS " + (clockwise ? "CW" : "CCW"), xOutput.format(x), yOutput.format(y), zOutput.format(z), rOutput.format(radius), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else {
    switch (getCircularPlane()) {
    case PLANE_XY:
      writeBlock("ARC|CNTRPT ABS " + (clockwise ? "CW" : "CCW"), xOutput.format(x), yOutput.format(y), zOutput.format(z), xcOutput.format(cx), ycOutput.format(cy), feedOutput.format(feed));
      break;
    case PLANE_ZX:
      if (isHelical()) {
        linearize(tolerance);
        return;
      }
      writeBlock("ARC|CNTRPT|ZX ABS " + (clockwise ? "CW" : "CCW"), xOutput.format(x), yOutput.format(y), zOutput.format(z), xcOutput.format(cx), ycOutput.format(cy), feedOutput.format(feed));
      break;
    case PLANE_YZ:
      if (isHelical()) {
        linearize(tolerance);
        return;
      }
      writeBlock("ARC|CNTRPT|YZ ABS " + (clockwise ? "CW" : "CCW"), xOutput.format(x), yOutput.format(y), zOutput.format(z), xcOutput.format(cx), ycOutput.format(cy), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  }
}

function onCommand(command) {
  onUnsupportedCommand(command);
}

function onSectionEnd() {
  forceAny();
}

function onClose() {
  writeBlock("|| END|PROGRAM @ CLR");
}
