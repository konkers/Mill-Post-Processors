/**
  Copyright (C) 2012-2014 by Autodesk, Inc.
  All rights reserved.

  ShopBot OpenSBP post processor configuration.

  $Revision: 36361 $
  $Date: 2014-01-21 09:26:20 +0100 (ti, 21 jan 2014) $
  
  FORKID {866F31A2-119D-485c-B228-090CC89C9BE8}
*/

description = "GitHub - ShopBot OpenSBP";
vendor = "Autodesk, Inc.";
vendorUrl = "http://www.autodesk.com";
legal = "Copyright (C) 2012-2014 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

capabilities = CAPABILITY_MILLING;
extension = "sbp";
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
  useToolChanger: false // specifies that a tool changer is available
};

var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var abcFormat = createFormat({decimals:3, scale:DEG});
var feedFormat = createFormat({decimals:(unit == MM ? 0 : 1)});
var secFormat = createFormat({decimals:2}); // seconds

var xOutput = createVariable({force:true}, xyzFormat);
var yOutput = createVariable({force:true}, xyzFormat);
var zOutput = createVariable({force:true}, xyzFormat);
var aOutput = createVariable({force:true}, abcFormat);
var bOutput = createVariable({force:true}, abcFormat);
var feedOutput = createVariable({}, feedFormat);

/**
  Writes the specified block.
*/
function writeBlock() {
  var result = "";
  for (var i = 0; i < arguments.length; ++i) {
    if (i > 0) {
      result += ", ";
    }
    result += arguments[i];
  }
  writeln(result);  
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln("' " + text);
}

function onOpen() {

  if (false) { // note: setup your machine here
    var aAxis = createAxis({coordinate:0, table:false, axis:[1, 0, 0], range:[-360,360], preference:1});
    var bAxis = createAxis({coordinate:1, table:false, axis:[0, 0, 1], range:[-360,360], preference:1});
    machineConfiguration = new MachineConfiguration(aAxis, bAxis);

    setMachineConfiguration(machineConfiguration);
    optimizeMachineAngles2(0); // TCP mode
  }

  if (!machineConfiguration.isMachineCoordinate(0)) {
    aOutput.disable();
  }
  if (!machineConfiguration.isMachineCoordinate(1)) {
    bOutput.disable();
  }
  
  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  writeBlock("SA"); // absolute

  switch (unit) {
  case IN:
    writeBlock("VD, , , 0");
    break;
  case MM:
    writeBlock("VD, , , 1");
    break;
  };

/*  
  if (hasParameter("operation:clearanceHeightOffset")) {
    var safeZ = getParameter("operation:clearanceHeightOffset");
    writeln("&PWSafeZ = " + safeZ);
  }
*/

  var workpiece = getWorkpiece();
  var zStock = unit ? (workpiece.upper.z - workpiece.lower.z) : (workpiece.upper.z - workpiece.lower.z);
  writeln("&PWMaterial = " + xyzFormat.format(zStock));
  var partDatum = workpiece.lower.z;
  if (partDatum > 0) {
    writeln("&PWZorigin = Table Surface");
  } else {
    writeln("&PWZorigin = Part Surface");
	}
}

function onComment(message) {
  writeComment(message);
}

function onParameter(name, value) {
}

var currentWorkPlaneABC = undefined;

function forceWorkPlane() {
  currentWorkPlaneABC = undefined;
}

function setWorkPlane(abc) {
  if (!machineConfiguration.isMultiAxisConfiguration()) {
    return; // ignore
  }

  if (!((currentWorkPlaneABC == undefined) ||
        abcFormat.areDifferent(abc.x, currentWorkPlaneABC.x) ||
        abcFormat.areDifferent(abc.y, currentWorkPlaneABC.y) ||
        abcFormat.areDifferent(abc.z, currentWorkPlaneABC.z))) {
    return; // no change
  }

  // NOTE: add retract here

  writeBlock(
    "J5",
    "", // x
    "", // y
    "", // z
    conditional(machineConfiguration.isMachineCoordinate(0), abcFormat.format(abc.x)),
    conditional(machineConfiguration.isMachineCoordinate(1), abcFormat.format(abc.y))
    // conditional(machineConfiguration.isMachineCoordinate(2), abcFormat.format(abc.z))
  );
  
  currentWorkPlaneABC = abc;
}

var closestABC = false; // choose closest machine angles
var currentMachineABC;

function getWorkPlaneMachineABC(workPlane) {
  var W = workPlane; // map to global frame

  var abc = machineConfiguration.getABC(W);
  if (closestABC) {
    if (currentMachineABC) {
      abc = machineConfiguration.remapToABC(abc, currentMachineABC);
    } else {
      abc = machineConfiguration.getPreferredABC(abc);
    }
  } else {
    abc = machineConfiguration.getPreferredABC(abc);
  }
  
  try {
    abc = machineConfiguration.remapABC(abc);
    currentMachineABC = abc;
  } catch (e) {
    error(
      localize("Machine angles not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      // + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
  }
  
  var direction = machineConfiguration.getDirection(abc);
  if (!isSameDirection(direction, W.forward)) {
    error(localize("Orientation not supported."));
  }
  
  if (!machineConfiguration.isABCSupported(abc)) {
    error(
      localize("Work plane is not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      // + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
  }

  var tcp = true;
  if (tcp) {
    setRotation(W); // TCP mode
  } else {
    var O = machineConfiguration.getOrientation(abc);
    var R = machineConfiguration.getRemainingOrientation(abc, W);
    setRotation(R);
  }
  
  return abc;
}

function onSection() {
  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);
  
  writeln("");
  
  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }
  
  if (properties.showNotes && hasParameter("notes")) {
    var notes = getParameter("notes");
    if (notes) {
      var lines = String(notes).split("\n");
      var r1 = new RegExp("^[\\s]+", "g");
      var r2 = new RegExp("[\\s]+$", "g");
      for (line in lines) {
        var comment = lines[line].replace(r1, "").replace(r2, "");
        if (comment) {
          writeComment(comment);
        }
      }
    }
  }
  
  if (machineConfiguration.isMultiAxisConfiguration()) { // use 5-axis indexing for multi-axis mode
    // set working plane after datum shift

    var abc = new Vector(0, 0, 0);
    if (currentSection.isMultiAxis()) {
      cancelTransformation();
    } else {
      abc = getWorkPlaneMachineABC(currentSection.workPlane);
    }
    setWorkPlane(abc);
  } else { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  feedOutput.reset();

  if (insertToolCall && properties.useToolChanger) {
    forceWorkPlane();
    
    retracted = true;

    if (tool.number > 99) {
      warning(localize("Tool number exceeds maximum value."));
    }
    if (isFirstSection() ||
        currentSection.getForceToolChange && currentSection.getForceToolChange() ||
        (tool.number != getPreviousSection().getTool().number)){
      writeln("&Tool = " + tool.number);
      writeln("C9");
        
      if (tool.spindleRPM < 1) {
        error(localize("Spindle speed out of range."));
        return;
      }
      if (tool.spindleRPM > 99999) {
        warning(localize("Spindle speed exceeds maximum value."));
      }

      writeBlock("TR", tool.spindleRPM);
	    writeln("C6");
	  }
    if (tool.comment) {
      writeln("&ToolName = " + tool.comment);
    }
  }
  
  if (!properties.useToolChanger) {
    writeBlock("PAUSE"); // wait for user
  }

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  var retracted = false;
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z) {
      writeBlock("J3", zOutput.format(initialPosition.z));
    }
  }

  if (false /*insertToolCall*/) {
    writeBlock(
      "J3",
      xOutput.format(initialPosition.x),
      yOutput.format(initialPosition.y),
      zOutput.format(initialPosition.z)
    );
  }
}

function onDwell(seconds) {
  seconds = clamp(0.01, seconds, 99999);
  writeBlock("PAUSE", secFormat.format(seconds));
}

function onRadiusCompensation() {
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    writeBlock("J3", x, y, z);
  }
}

function onLinear(_x, _y, _z, feed) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed/60);
  if (f) {
    writeBlock("VS", f, f);
  }
  if (x || y || z) {
    writeBlock("M3", x, y, z);
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  writeBlock("J5", x, y, z, a, b);
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  var f = feedOutput.format(feed/60);
  if (f) {
    writeBlock("VS", f, f);
  }
  if (x || y || z || a || b) {
    writeBlock("M5", x, y, z, a, b);
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  var start = getCurrentPosition();

  if (isHelical()) {
    linearize(tolerance);
    return;
  }

  var f = feedOutput.format(feed/60);
  if (f) {
    writeBlock("VS", f, f);
  }

  switch (getCircularPlane()) {
  case PLANE_XY:
    writeBlock("CG", "", xOutput.format(x), yOutput.format(y), xyzFormat.format(cx - start.x), xyzFormat.format(cy - start.y), "", clockwise ? 1 : -1);
    break;
  default:
    linearize(tolerance);
  }
}

function onCommand(command) {
}

function onSectionEnd() {
  writeln("C7");
}

function onClose() {
  writeBlock("JH");

  setWorkPlane(new Vector(0, 0, 0)); // reset working plane
}
