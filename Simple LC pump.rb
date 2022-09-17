include UNI

#########################################################################
# User written helper global variables.
#########################################################################
# Terminating command character.
$cmdCharTerm = 0x2F   # char: /
# Send command time out [ms].
$timeOut = 1500
# Timer period [ms]
$timerPeriod = 1000
# Delay time [ms] when next command will be sent.
$commandsDelay = 100
# Command send repeat counter
$repeatCommandCount = 5


#########################################################################
# User written helper function.
#
# Returns true if the given character is a number character.
#########################################################################
def isNumber(ch)
	if (ch >= ?0.ord && ch <= ?9.ord)
		return true
	end
	return false
end

#########################################################################
# Sub-device class expected by framework.
#
# Sub-device represents functional part of the chromatography hardware.
# LC implementation.
#########################################################################
class LC < LCSubDeviceWrapper
	# Constructor. Call base and do nothing. Make your initialization in the Init function instead.
	def initialize
		super
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Initialize LC sub-device. 
	# Set sub-device name, specify method items, specify monitor items, ...
	# Returns nothing.
	#########################################################################	
	def Init
		#SetLCIsInterpolating(true)
	end
	
end # class LC



#########################################################################
# Device class expected by framework.
#
# Basic class for access to the chromatography hardware.
# Maintains a set of sub-devices.
# Device represents whole box while sub-device represents particular 
# functional part of chromatography hardware.
# The class name has to be set to "Device" because the device instance
# is created from the C++ code and the "Device" name is expected.
#########################################################################
class Device < DeviceWrapper
	# Constructor. Call base and do nothing. Make your initialization in the Init function instead.
	def initialize
		super
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Initialize configuration data object of the device and nothing else.
	# Returns nothing.
	#########################################################################	
	def InitConfiguration
    	# Setup configuration.
    	Configuration().AddString("LCName", "LC Pump Name", "My LC Pump", "VerifyLCName")
    	Configuration().AddCheckBox("AuxiliaryPump", "Auxiliary pump", false,"")
		
		Configuration().AddChoiceList("PumpType", "Pump type", "10 ml/min SS","")
    	Configuration().AddChoiceListItem("PumpType", "10 ml/min SS")
    	Configuration().AddChoiceListItem("PumpType", "10 ml/min PEEK")
    	Configuration().AddChoiceListItem("PumpType", "40 ml/min SS")
		Configuration().AddChoiceListItem("PumpType", "40 ml/min PEEK")
		
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Initialize device. Configuration object is already initialized and filled with previously stored values.
	# (set device name, add all sub-devices, setup configuration, set pipe
	# configurations for communication, #  ...).
	# Returns nothing.
	#########################################################################	
	def Init
		
		# Device name.
		SetName("LC Pump")
		
		# Set sub-device name.
		@m_LC=LC.new
		AddSubDevice(@m_LC)
		@m_LC.SetName("LC pump kickoff")
		
		@m_LC.SetLCIsAuxiliaryEventTable(Configuration().GetInt("AuxiliaryPump")!=0) #if true, close LC Gradient tab and opens LC tab with (Auxiliary Pump and Properties)
		#if false (no auxiliary pump), then 2 tabs (LC tab) for properties, and LC Gradient
		
    	
		
    	# Auxiliary signal: specify sub-device to associate measured flow and pressure with specific LC Pump
		if(Configuration().GetInt("AuxiliaryPump")!=0)
			#if the pump is auxiliary specify EMeaningAuxiliaryFlowRate to prevent this flow to be sent to FRC
			AuxSignal().AddSignal(@m_LC,"LCFlow", "LC flow", EMeaningAuxiliaryFlowRate)
			SetHidePropertyPage(false)
			SetHideMonitor(false)
		else
			#standard flow rate
			AuxSignal().AddSignal(@m_LC,"LCCurrentFlow", "LC flow", EMeaningFlowRate)
			AuxSignal().AddSignal(@m_LC,"LCCurrentPressure", "LC pressure", EMeaningPressure)
			SetHidePropertyPage(false)
			SetHideMonitor(false)
		end
		#Those 2 lines will be displayed on creating new method
		#Default lower pressure limit by Clarity=0, if the user lower pressure limit > 0 in MPa, it will take the highest value
		#Ex: Default upper pressure limit value of Clarity=0 MPa, the developer set the upper pressure limit to 200 psi=1.379 MPa, 
		#the value in Method-> LC Gradient-> Options -> Min. pressure will be the highest value (1.379)
		SetDefaultLowerPressureLimit(0)
		#Default highest pressure limit by Clarity=40 MPa, if the user upper pressure limit > 40 in MPa, it will take the lowest value
		#Ex: Default upper pressure limit value of Clarity=40 MPa, the developer set the upper pressure limit to 4000 psi=27.579 MPa, 
		#the value in Method-> LC Gradient-> Options -> Max. pressure will be the lowest value (27.579)
		SetDefaultUpperPressureLimit(GetUpperPressureLimit(Configuration().GetString("PumpType")))
		
		
		
		Method().AddDouble("FlowRate", "Flow rate", 5.0, 1, EMeaningFlowRate,"VerifyFlow")
		
		Method().AddDouble("LowerPressure", "Lower Pressure Limit", GetDefaultLowerPressureLimit(),1,EMeaningPressure,"",true)
		#Note on this
		Method().AddDouble("UpperPressure", "Upper Pressure Limit",GetDefaultUpperPressureLimit(),1,EMeaningPressure,"",true)
		#method GetDefaultUpperPressureLimit() should return the lowest value between 40 MPa and the upper pressure limit of the pump, but it doesn't do that,
		#it returns the upper value, ex: Clarity default upper limit=40 MPa, and SST pump head upper limit 6000 psi=41.3 MPa, it should return 40, but it returns 41.3 instead
		
		Monitor().AddDouble("CurrentFlow","Current flow",0,2,EMeaningFlowRate,"",true)
		Monitor().AddDouble("CurrentPressure","Current pressure",0,2,EMeaningPressure,"",true)
		
		
		SetTimerPeriod($timerPeriod)
 	end
	
	
	
	#########################################################################
	# Method expected by framework.
	#
	# Sets communication parameters.
	# Returns nothing.
	#########################################################################	
	def InitCommunication()
		# Set number of pipe configurations for communication. In our case one - serial communication.
		Communication().SetPipeConfigCount(1)
		# Set type for created pipe configuration.
		Communication().GetPipeConfig(0).SetType(EPT_SERIAL)
		# The rest of pipe configuration parameters can be set here after all  Configuration().Add* calls due to possible dependecies - for example "BaudRate"!, etc)
		Communication().GetPipeConfig(0).SetBaudRate(9600)
		Communication().GetPipeConfig(0).SetParity(NOPARITY)
		Communication().GetPipeConfig(0).SetDataBits(DATABITS_8)
		Communication().GetPipeConfig(0).SetStopBits(ONESTOPBIT)
 	end
	
	
 	
	#########################################################################
	# Method expected by framework
	#
	# Here you should check leading and ending sequence of characters, 
	# check sum, etc. If any error occurred, use ReportError function.
	#	dataArraySent - sent buffer (can be nil, so it has to be checked 
	#						before use if it isn't nil), array of bytes 
	#						(values are in the range <0, 255>).
	#	dataArrayReceived - received buffer, array of bytes 
	#						(values are in the range <0, 255>).
	# Returns true if frame is found otherwise false.		
	#########################################################################	
	def FindFrame(dataArraySent, dataArrayReceived)
		# Search for frame end
		nEndFrameIdx = dataArrayReceived.index($cmdCharTerm)
		if (nEndFrameIdx == nil)
			return false  
		end
		
		# Set frame start and end indexes.
		SetFrameStart(0)
		SetFrameEnd(nEndFrameIdx)
		return true
	end
	
	#########################################################################
	# Method expected by framework
	#
	# Return true if received frame (dataArrayReceived) is answer to command
	# sent previously in dataArraySent.
	#	dataArraySent - sent buffer, array of bytes 
	#						(values are in the range <0, 255>).
	#	dataArrayReceived - received buffer, array of bytes 
	#						(values are in the range <0, 255>).
	# Return true if in the received buffer is answer to the command 
	#   from the sent buffer. 
	# Found frames, for which IsItAnswer returns false are processed 
	#  in ParseReceivedFrame
	#########################################################################		
	def IsItAnswer(dataArraySent, dataArrayReceived)
		# Check received data length.
		return true 
	end
	
	#########################################################################
	# Method expected by framework
	#
	# Returns serial number string from HW (to comply with CFR21) when 
	# succeessful otherwise false or nil. If not supported return false or nil.
	#########################################################################	
	def CmdGetSN
		if IsDemo()
	   		return true
		end
		strSN=""
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("ID")
		
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK,")==false)
			return false
		end
		
		while((cmdSN=cmd.ParseANSIChar())!=false)
			if (cmdSN == $cmdCharTerm || cmdSN == " ".ord)
				return strSN
			end
			strSN.concat(cmdSN)
		end
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Called when Clarity CDS's instrument window is opened.
	# Returns true when successful otherwise false.
	#########################################################################
	def CmdOpenInstrument
		if(IsDemo())
			return true
		end
		#run CC command to get current flow rate,current pressure from pump, get OK,x,y.yy/)
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("CC")
		
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK,")==false)
			return false
		end
		
		if((current_flow_rate=cmd.ParseANSIDouble())==false)
			return false
		end
		
		if(cmd.ParseANSIString(",")==false)
			return false
		end
		
		if((current_pressure=cmd.ParseANSIDouble())==false)
			return false
		end
		
		if(cmd.ParseANSIString($cmdCharTerm)==false)
			return false
		end
		
		
		Monitor().SetDouble("CurrentFlow",flow_rate)
		Monitor().SetDouble("CurrentPressure",ConvertPressure(current_pressure,EPU_PSI,EPU_MPA))
		
		return true
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Called when Clarity CDS's sequence is started.
	# Returns true when successful otherwise false.
	#########################################################################
	def CmdStartSequence
		# Nothing to send.
		return true
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Called when Clarity CDS's paused sequence is resumed.
	# Returns true when successful otherwise false.
	#########################################################################
	def CmdResumeSequence
		# Nothing to send.
		return true
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Called when Clarity CDS's run is started.
	# Returns true when successful otherwise false.
	#########################################################################
	def CmdStartRun
		# Nothing to send.
		return true
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Indicates into samplers, that injection should be performed
	# Returns true when successful otherwise false.
	#########################################################################
	def CmdPerformInjection
		# Nothing to send.
		return true
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Indicates into detectors, that they should start, as injection by samplers is bypassed
	# Returns true when successful otherwise false.
	#########################################################################
	def CmdByPassInjection
		# Nothing to send.
		return true
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Starts method in HW.
	# Returns true when successful otherwise false.
	#########################################################################
	def CmdStartAcquisition
		Monitor().SetRunning(true)
		# Command formatter.
		if(IsDemo())
			return true
		end
		#1- Send command to disable keypad, send (KD) receive (OK/)
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("KD")
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK/")==false)
			return false
		end
		
		#2- Send command to set the flowrate to the specified value in Method() FlowRate  , send (FOxxxx) receive ("OK/")
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("FO")
		cmd.AppendANSIDouble(Method().GetDouble("FlowRate"))
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK/")==false)
			return false
		end
		
		#3- Send command to start running the pump , send (RU) receive ("OK/")
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("RU")
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK/")==false)
			return false
		end
		
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Indicates that acquisition is restarted.
	# Returns true when successful otherwise false.
	#########################################################################
	def CmdRestartAcquisition
		# Nothing to send.
		return true
	end	

	#########################################################################
	# Method expected by framework.
	#
	# Stops running method in hardware. 
	# Returns true when successful otherwise false.	
	#########################################################################
	def CmdStopAcquisition
		Monitor().SetRunning(false)
		return true
	end	
	
	#########################################################################
	# Method expected by framework.
	#
	# Aborts running method or current operation. Sets initial state.
	# Returns true when successful otherwise false.	
	#########################################################################
	def CmdAbortRunError
		Monitor().SetRunning(false)
		if IsDemo()
	   		return true
		end
		return true
	end

	#########################################################################
	# Method expected by framework.
	#
	# Aborts running method or current operation. Sets initial state. 
	# Abort was caused by user.
	# Returns true when successful otherwise false.	
	#########################################################################
	def CmdAbortRunUser
		Monitor().SetRunning(false)
		return true
	end
	
	#########################################################################
	# Method expected by framework.
	# 
	# Called when instrument shutdown
	# Returns true when successful otherwise false.	
	#########################################################################
	def CmdShutDown
		Monitor().SetRunning(false)
		if IsDemo()
	   		return true
		end
		#1- Send command to set flow to zero, send FO0000 receive OK/
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("FO0000")
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK/")==false)
			return false
		end
		
		#2- Clear
		cmd.AppendANSIString("#")
		cmd.SendCommand(0)
		
		#3- Send command to stop the pump, send ST receive OK/
		cmd.AppendANSIString("ST")
		if(cmd.SendCommad($timeOut)==false)
			return false
		end
		if(cmdParseANSIString("OK/")==false)
			return false
		end
		return true
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Called when hardware finished its method
	# Returns true when successful otherwise false.
	#########################################################################
	def CmdStopRun
		Monitor().SetRunning(false)
		# Nothing to send.
		return true
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Called when Clarity CDS's sequence is stopped or paused.
	# Returns true when successful otherwise false.
	#########################################################################
	def CmdStopSequence
		# Nothing to send.
		return true
	end
	
	#########################################################################
	# Method expected by framework.
	#
	# Called when Clarity CDS's instrument window is closed.
	# Returns true when successful otherwise false.
	#########################################################################
	def CmdCloseInstrument
		if IsDemo()
	   		return true
		end
		#send command to set flow to 0 send FO0000 and receive OK/
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("FO0000")
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK/")==false)
			return false
		end
		
		cmd.AppendANSIString("#")
		cmd.SendCommand(0)
		
		#send command to stop pump, send ST and recieve OK/
		cmd.AppendANSIString("ST")
		if(cmd.SnedCommand($timeOut)==false)
			return false
		end
		if(cmd.ParseANSIString("OK/")==false)
			return false
		end
		return true
	end	
	
	#########################################################################
	# Method expected by framework.
	#
	# Tests whether hardware device is present on the other end of the communication line.
	# Send some simple command with fast response and check, whether it has made it
	# through pipe and back successfully.
	# Returns true when successful otherwise false.
	#########################################################################
	def CmdTestConnect
		if IsDemo()
	   		return true
		end
		#send command to get serial number and receive a response, send ID and receive OK,......
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("ID")
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK,")==false)
			return false
		end
		
		return true
	end
		
	#########################################################################
	# Method expected by framework.
	#
	# Send method to hardware.
	# Returns true when successful otherwise false.	
	#########################################################################
	def CmdSendMethod()
		if IsDemo()
	   		return true
		end
		#1- Send command UPx to set upper pump pressure, receive OK/
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("UP")
		cmd.AppendANSIDouble(Method().GetDouble("UpperPressure"))
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK/")==false)
			return false
		end
		#2- Send command LPx to set lower pump pressure, receive OK/
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("LP")
		cmd.AppendANSIDouble(Method().GetDouble("LowerPressure"))
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK/")==false)
			return false
		end
		#3- Send command FOxxxx to set flow from method to pump, receive OK/
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("FO")
		cmd.AppendANSIDouble(Method().GetDouble("FlowRate"),4,0,'0')
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK/")==false)
			return false
		end
		#4- Send RU to run pump
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("RU")
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		if(cmd.ParseANSIString("OK/")==false)
			return false
		end
		sleep(0.5)
	end
	
	
	#########################################################################
	# Method expected by framework.
	#
	# Loads method from hardware. Use method parameter and NOT object returned by Method().
	# Returns true when successful otherwise false.	
	#########################################################################
	def CmdLoadMethod(method)
		if IsDemo()
	   		return true
		end	
	end
		
	#########################################################################
	# Method expected by framework.
	#
	# Duration of LC method.
	# Returns complete (from start of acquisition) length (in minutes) 
	# 	of the current method in sub-device (can use GetRunLengthTime()).
	# Returns METHOD_FINISHED when hardware instrument is not to be waited for or 
	# 	method is not implemented.
	# Returns METHOD_IN_PROCESS when hardware instrument currently processes 
	# 	the method and sub-device cannot tell how long it will take.
	#########################################################################
	def GetMethodLength
		return METHOD_FINISHED
	end	
	
	
	#########################################################################
	# Method expected by framework.
	#
	# Periodically called function which should update state 
	# of the sub-device and monitor.
	# Returns true when successful otherwise false.	
	#########################################################################
	def CmdTimer
		#Trace(">>> CmdTimer\n")
		if IsDemo()
	   		return true
		end
		#1- Send CS command to read pump status, receive flow rate, upper pressure limit, lower pressure limit data
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("CS")
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK,")==false)
			return false
		end
		
		if((current_flow_rate=cmd.ParseANSIDouble())==false)
			return false
		end
		if(cmd.ParseANSIString(",")==false)
			return false
		end
		
		if((upper_pressure_limit=cmd.ParseANSIDouble())==false)
			return false
		end
		if(cmd.ParseANSIString(",")==false)
			return false
		end
		
		if((lower_pressure_limit=cmd.ParseANSIDouble())==false)
			return false
		end
		if(cmd.ParseANSIString($cmdCharTerm)==false)
			return false
		end
		cmd.AppendANSIString("#")
		cmd.SendCommand(0)
		#2- Send RF command to read fault status, receive status for motor stall, upper pressure limit and lower pressure limit faults(OK,x,y,z/)
		cmd.AppendANSIString("RF")
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK,")==false)
			return false
		end
		
		if((motor_stall=cmd.ParseANSIInt())==false)
			return false
		end
		if(cmd.ParseANSIString(",")==false)
			return false
		end
		
		if((upper_pressure_limit_fault=cmd.ParseANSIInt())==false)
			return false
		end
		if(cmd.ParseANSIString(",")==false)
			return false
		end
		
		if((lower_pressure_limit_fault=cmd.ParseANSIInt())==false)
			return false
		end
		if(cmd.ParseANSIString($cmdCharTerm)==false)
			return false
		end
		cmd.AppendANSIString("#")
		cmd.SendCommand(0)
		
		if(motor_stall==1 || upper_pressure_limit_fault==1 || lower_pressure_limit_fault==1)
			return false
		end
		#3- Send PR to read current pressure, receive current pressure in PSI
		cmd.AppendANSIString("PR")
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK,")==false)
			return false
		end
		
		if((current_pressure=cmd.ParseANSIInt())==false)
			return false
		end
		if(cmd.ParseANSIString($cmdCharTerm)==false)
			return false
		end
		cmd.AppendANSIString("#")
		cmd.SendCommand(0)
		
		AuxSignal().WriteSignal("LCCurrentFlow",current_flow)
		Monitor().SetDouble("CurrentFlow",current_flow)
		AuxSignal().WriteSignal("LCCurrentPressure",current_pressure)
		Monitor().SetDouble("CurrentPressure",current_pressure)
		return true
	end	


	#########################################################################
	# Method expected by framework
	#
	# gets called when method is sent or event table triggers event to change aux pump flow
	# return true, false or error message (equals to false)
	#########################################################################
	def CmdSendAuxiliaryLCFlow(lc,float)
		Trace("LC flow of auxiliary is now "+float.to_s)
		return true
	end
	
	#########################################################################
	# Method expected by framework
	#
	# gets called when method is sent or when time for next interpolating step elapses
	# return true, false or error message (equals to false)
	#########################################################################
	def CmdSendLCFlow(floats)
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("FO")
		cmd.AppendANSIDouble(floats[0])
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		if(cmd.ParseANSIString("OK/")==false)
			return false
		end
		Trace("LC flow is now "+floats[0].to_s)
		return true
	end

	#########################################################################
	# User written method.
	#
	# Parses any digit (0..9)
	#########################################################################
	def ParseNumericChar(cmd)
		num = cmd.ParseANSIInt(10, 1)
	  	if (num != false)
			return true
		end
		
		return false
	end
	
	#########################################################################
	# Method expected by framework
	#
	# gets called when user presses autodetect button in configuration dialog box, changes Configuration()  object only.
	# return true, false or error message (equals to false)
	#########################################################################
	def CmdAutoDetect
		pump_type=0
		#in real version these line will be deleted

		if(IsDemo())
			pump_type=rand(1..4)
			SetPumpTypeFromAutoDetect(pump_type)
			return true
		end

		#send RH command and receive the head type as number (1 for 10ml/min SS, 2 for 10ml/min PEEK, 3 for 40ml/min SS, 4 for 40ml/min PEEK)
		cmd=CommandWrapper.new(self)
		cmd.AppendANSIString("RH")
		if(cmd.SendCommand($timeOut)==false)
			return false
		end
		
		if(cmd.ParseANSIString("OK,")==false)
			return false
		end
		
		if((pump_type=cmd.ParseANSIInt())==false)
			return false
		end
		SetPumpTypeFromAutoDetect(pump_type)
		return true
	end
	
	def SetPumpTypeFromAutoDetect(pumpType)
		case pumpType
			when 1
				Configuration().SetString("PumpType","10 ml/min SS")
			when 2
				Configuration().SetString("PumpType","10 ml/min PEEK")
			when 3
				Configuration().SetString("PumpType","40 ml/min SS")
			when 4
				Configuration().SetString("PumpType","40 ml/min PEEK")
			else
				ReportError(EsCommunication,"Pump type is not recognized")
		end
	end
	
	def GetUpperPressureLimit(pumpType)
		pressureLimit=0
		case pumpType
			when "10 ml/min SS"
				pressureLimit=6000
			when "10 ml/min PEEK"
				pressureLimit=2000
			when "40 ml/min SS"
				pressureLimit=6000
			when "40 ml/min PEEK"
				pressureLimit=2000
			else
				ReportError(EsCommunication,"Pump type is not recognized")
		end
		return ConvertPressure(pressureLimit,EPU_PSI,EPU_MPA)
	end
	
	def GetUpperFlowLimit(pumpType)
		flowLimit=0
		case pumpType
			when "10 ml/min SS"
				flowLimit=10.0
			when "10 ml/min PEEK"
				flowLimit=10.0
			when "40 ml/min SS"
				flowLimit=40.0
			when "40 ml/min PEEK"
				flowLimit=40.0
			else
				ReportError(EsCommunication,"Pump type is not recognized")
		end
		return flowLimit
	end
	#########################################################################
	# Method expected by framework
	#
	# Processes unrequested data sent by hardware. 
	#	dataArrayReceived - received buffer, array of bytes 
	#						(values are in the range <0, 255>).
	# Returns true if frame was processed otherwise false.
	# The frame found by FindFrame can be processed here if 
	#  IsItAnswer returns false for it.
	#########################################################################
	def ParseReceivedFrame(dataArrayReceived)
		# Passes received frame to appropriate sub-device's ParseReceivedFrame function.
	end
	
	#########################################################################
	# User written method.
	#
	# Validates length of LC name.
	# Validation function returns true when validation is successful otherwise
	# it returns message which will be shown in the Message box.	
	#########################################################################
	def VerifyLCName(uiitemcollection,value)
		if (value.length >= 32)
			return t("NAME_LONG")
		end
		return true
	end

	#########################################################################
	# Required by Framework
	#
	# Gets called when chromatogram is acquired, chromatogram might not exist at the time.
	#########################################################################
	def NotifyChromatogramFileName(chromatogramFileName)
	end
	
	
	#########################################################################
	# Required by Framework
	#
	# Validates whole method. Use method parameter and NOT object returned by Method(). 
	# There is no need to validate again attributes validated somewhere else.
	# Validation function returns true when validation is successful otherwise
	# it returns message which will be shown in the Message box.	
	#########################################################################
	def CheckMethod(situation,method)
		return true
	end
	
	#########################################################################
	# Required by Framework
	#
	# Validates auxiliary LC event table flow
	# Validation function returns true when validation is successful otherwise
	# it returns message which will be shown in the Message box.	
	#########################################################################
	def CheckAuxiliaryLCFlow(lc,value)
		
		return true
	end
	
	def VerifyLCName(uiitemcollection,value)
		if(value.length>=32)
			return "Name is too long"
		end
		return true
	end
	
	
	def VerifyFlow(uiitemcollection,value)
		case Configuration().GetString("PumpType")
			when "10 ml/min SS"
				if(value>10 or value<0)
					return "Max flow limit for this type ranges from 0 - 10 ml/min" 
				end
			when "10 ml/min PEEK"
				if(value>10 or value<0)
					return "Max flow limit for this type ranges from 0 - 10 ml/min" 
				end
			when "40 ml/min SS"
				if(value>40 or value<0)
					return "Max flow limit for this type ranges from 0 - 40 ml/min" 
				end
			when "40 ml/min PEEK"
				if(value>40 or value<0)
					return "Max flow limit for this type ranges from 0 - 40 ml/min" 
				end
		end
	end
	
	def VerifyPressure(uiitemcollection,value)
		case Configuration().GetString("PumpType")
			when "10 ml/min SS"
				if(value>6000 or value<0)
					return "Max presure limit for this type ranges from 0 - 6000 psi" 
				end
			when "10 ml/min PEEK"
				if(value>2000 or value<0)
					return "Max presure limit for this type ranges from 0 - 2000 psi"
				end
			when "40 ml/min SS"
				if(value>6000 or value<0)
					return "Max presure limit for this type ranges from 0 - 6000 psi" 
				end
			when "40 ml/min PEEK"
				if(value>2000 or value<0)
					return "Max presure limit for this type ranges from 0 - 2000 psi" 
				end
		end
	end
	
end # class Device
