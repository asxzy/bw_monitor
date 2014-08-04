#!/bin/sh
# THE PROCESSOR
#Lock File
MONITOR_LOCK_FILE=/tmp/monitor-started.lock
MONITOR_STOP_FILE=/tmp/monitor-stop
MONITOR_STOPPED_FILE=/tmp/monitor-stopped
if [ -f $MONITOR_LOCK_FILE ] || [ -f $MONITOR_STOP_FILE ]; then
 echo 'Cannot start bw_monitor.sh. Either the '"$MONITOR_LOCK_FILE "'already exists, or the bw_monitor has been force stopped '"$MONITOR_STOP_FILE"
 exit 0
fi
[ -f $MONITOR_STOPPED_FILE ] && rm $MONITOR_STOPPED_FILE
touch $MONITOR_LOCK_FILE 
#Constants
MONITOR_CLIENTKEY_FILE_PATH=/tmp/clientKey
CHAIN_RULE='BWMON'
CONNECTED_USERS_FILE=/proc/net/arp
LAN_IFACE=`nvram get lan_ifname`
DNSMASQ_TEMP_FILE_PATH=/tmp/dnsmasq2users.file
DEFAULT_USAGE_FILE_PATH=/tmp/mac_usage.db
JAVASCRIPT_FILE_NAME='user_details.js'
#Fields
_intervalUpdate=$1
_iterationPublish=$2
_iterationBackup=$3
_resetDay=$4
_userFilePath=$5
_backupUsageFilePath=$6
_backupHistoryPath=$7
_macUsageFilePath=$8 #Optional. 3 different values
_javascriptPath=$9 #Optional
_doUsageFileRestore=1 #Optional 10
_keepLastJSFile=0 #Optional 11
_historyJSFile=0 #Optional 12
_recordDailyUsage=0 #Optional 13
_autoAddUserMACs=1 #Optional 14
_supportBit32=0 #Optional 15
_showMAC=0 #Optional 16
_logFilePath='' #Optional 17
_clientsDetails=""
_dnsmasqFilePath=""
_previousDay=`date +%d`
_forceJavascriptReload=0
_macUsageData=''
_savedMD5Value=''
_newClientsAutoAdded=''
# ==========================================================
#                  SECTION START - HELPER METHODS
# ==========================================================
#Perform a basic not null check for mandatory parameters
checkParameters()
{
if [ -z "$_intervalUpdate" ] || [ -z "$_iterationPublish" ] || [ -z "$_iterationBackup" ] ||
   [ -z "$_resetDay" ] || [ -z "$_userFilePath" ] || [ -z "$_backupUsageFilePath" ] ||
   [ -z "$_backupHistoryPath" ]; then
	echo 'Unable to start Monitor. Missing Input Parameters'
	echo 'Arg 1 - Interval Update (Mandatory): This indicates in seconds how often an update is performed.'
	echo 'Arg 2 - Publish Iteration (Mandatory): Indicates how many update iterations must past before a publish is done.'
	echo 'Arg 3 Iteration Backup (Mandatory): Indicates how many update iterations must past before a backup is done.'
	echo 'Arg 4 Reset Day (Mandatory): Indicates what day at midnight should the usage data be reset to 0 and backed up to history. If no reset value is stated, no reset will occur'
	echo 'Arg 5 User File Path (Mandatory): The path and file name for where user data is saved. Format MUST be MAC,IP,USER,MAC TYPE'
	echo 'Arg 6 Backup Usage File Path (Mandatory): The path and file name for the interval back up of the usage file.'
	echo 'Arg 7 Backup History Path (Mandatory): The path for where history files will be kept. Used when reset occurs.'
	echo 'Arg 8 MAC Usage File Path (Optional): Indicates the path and file name for usage data. If none is defined a default will be used. A Value of 1 will keep the usage in memory. Any other value will force the values to be written to disk'
	echo 'Arg 9 Javascript Output Path (Optional): The path for where the user_details.js output file should be saved. If none is defined the deafult /tmp/www folder will be used'
	echo 'Arg 10 Do Usage File Restore (Optional): Indicates if the usage file is restored from the backed up location when the monitor is started. Values are 1 (true) and 0(false). Default is 1'
	echo 'Arg 11 Keep Last Javascript File(Optional): Indicates if the last js file should be kept for showing last months usage. Default 0 (false)'
	echo 'Arg 12 History Javascript File(Optional): Indicates if the javascript file should also be backed up to history. Default 0 (false)'
	echo 'Arg 13 Record Daily Usage(Optional): Indicates if you would like to record daily usage or not. Default is  0 (false)'
	echo 'Arg 14 Auto Add MACS(Optional): Indicates if the system to auto add MAC addresses that do not exist in the users file. Default is  1 (yes)'
	echo 'Arg 15 Add 32 BIt support: Indicates the value that should be used to divide the usage value by. default is 0 (no needed support)'
	echo 'Arg 16 Show MAC; Indicates if MAC addresses should be shown on the display'
	rm -f $MONITOR_LOCK_FILE
fi 
}
#Load and Unload usage data if required. Based on user configuration
loadUsageData()
{
	if [ "$_macUsageFilePath" != "1" ]; then
	  _macUsageData=`cat $_macUsageFilePath`
	fi
}
unloadUsageData()
{
	if [ "$_macUsageFilePath" != "1" ]; then
	  _macUsageData=''
	fi
}

#Log
bwMonitorLog()
{
	if [ -n "$_logFilePath" ]; then	
		[ ! -f $_logFilePath ] && touch $_logFilePath		
		echo `date +%Y-%m-%d`' '`date +%H:%M:%S`':'" $1" >> $_logFilePath
	fi
}

#log Current Configuration
logCurrentConfiguration()
{
	if [ -n "$_logFilePath" ]; then	
logString=" CONFIGURATION
------CONSTANTS-------
CHAIN_RULE=BWMON
CONNECTED_USERS_FILE = /proc/net/arp
LAN_IFACE = nvram get lan_ifname
DNSMASQ_TEMP_FILE_PATH = /tmp/dnsmasq2users.file
DEFAULT_USAGE_FILE_PATH = /tmp/mac_usage.db
JAVASCRIPT_FILE_NAME = user_details.js
------CONFIGURATION-------
Interval Update = $_intervalUpdate
Publish Iteration = $_iterationPublish
Backup Iteration = $_iterationBackup
Reset Day = $_resetDay
User File Path = $_userFilePath
Backup Usage File Path = $_backupUsageFilePath
Backup History Path = $_backupHistoryPath
MAC Usage File Path = $_macUsageFilePath
Javascript Output Path = $_javascriptPath
Do Usage File Restore = $_doUsageFileRestore
Keep Last Javascript File = $_keepLastJSFile
History Javascript File = $_historyJSFile
Record Daily Usage = $_recordDailyUsage
Auto Add MAC Addresses = $_autoAddUserMACs
Add 32 Bit Support = $_supportBit32
Show MAC = $_showMAC
"
		[ -n "$_logFilePath" ] && bwMonitorLog "$logString"
	fi
}

#Regenerate SecureKeys
generateSecureClient()
{
	[ -n "$_logFilePath" ] && bwMonitorLog '***generateSecureClient***'
	clientsLineIndex=1
	currentClient=`echo "$_clientsDetails" | sed -n "$clientsLineIndex"'p'`
	while [ -n "$currentClient" ]; do
		echo "$currentClient" > $MONITOR_CLIENTKEY_FILE_PATH
		key=`md5sum $MONITOR_CLIENTKEY_FILE_PATH | awk '{print $1}'`
		secureClient="$currentClient"',ID'"$key"
		_clientsDetails=`echo "$_clientsDetails" | sed s/"$currentClient"/"$secureClient"/`
		rm $MONITOR_CLIENTKEY_FILE_PATH
		
		clientsLineIndex=`expr $clientsLineIndex + 1`
		currentClient=`echo "$_clientsDetails" | sed -n "$clientsLineIndex"'p'`
	done 
	[ -n "$_logFilePath" ] && bwMonitorLog "$_clientsDetails"
}

#Determines if the current user file has been modified
hasUserFileChanged()
{
	[ -n "$_logFilePath" ] && bwMonitorLog '***hasUserFileChanged***'
	hasChanged=1
	currentMd5=`md5sum $1 | awk '{print $1}'` 	
	if [ -n "$_savedMD5Value" ]; then
		[ "$_savedMD5Value" != "$currentMd5" ] && hasChanged=0
	fi
	[ $hasChanged -eq 0 ] && _forceJavascriptReload=1	
	_savedMD5Value=$currentMd5
	
	[ -n "$_logFilePath" ] && bwMonitorLog 'Has Changed = '"$hasChanged"
	
	return $hasChanged
}

#This will take in a standard dnsmasq user file (generated via web admin) and convert it into a users.file
loadDNSMasqUsers()
{
	[ -n "$_logFilePath" ] && bwMonitorLog '***loadDNSMasqUsers***'
	
	[ -z "$_dnsmasqFilePath" ] && _dnsmasqFilePath=$_userFilePath
	_userFilePath=$DNSMASQ_TEMP_FILE_PATH
	
	dnsMasqUserFile=`grep "dhcp-host" $_dnsmasqFilePath | sed 's/dhcp-host=//'`
	[ ! -f $_userFilePath ] && touch $_userFilePath
	usersFile=`cat $_userFilePath`

	dnsLineIndex=1
	dnsEntry=`echo "$dnsMasqUserFile" | sed -n "$dnsLineIndex"'p'`
	while [ -n "$dnsEntry" ]; do
		dnsUserType=`echo "$dnsEntry" | cut -d, -f2`
		dnsMAC=`echo "$dnsEntry" | cut -d, -f1 | sed 's/^[ \t]*//;s/[ \t]*$//'`
		dnsIP=`echo "$dnsEntry" | cut -d, -f3`
		dnsUser=`echo "$dnsUserType" | cut -d_ -f1`
		removeUser="$dnsUser"'_'
		dnsType=`echo "$dnsUserType" | sed "s/$removeUser//"`

		usersFileEntry=` echo "$usersFile" | grep "$dnsMAC"`
		outputLine="$dnsMAC,$dnsIP,$dnsUser,$dnsType"
		if [ -n "$usersFileEntry" ]; then
			usersFile=`echo "$usersFile" | sed "s/$usersFileEntry/$outputLine/"`
		else
			if [ -z "$usersFile" ]; then
				usersFile=$outputLine
			else
usersFile="$usersFile
$outputLine"	
			fi
		fi		
	dnsLineIndex=`expr $dnsLineIndex + 1`
	dnsEntry=`echo "$dnsMasqUserFile" | sed -n "$dnsLineIndex"'p'`
	done

	echo "$usersFile" > $_userFilePath
	_clientsDetails=`cat $_userFilePath`
	usersFile=''
}

#This will check and reload user details if required.
userFileUpdate()
{
	[ -n "$_logFilePath" ] && bwMonitorLog '***userFileUpdate***'
	
	_forceJavascriptReload=0
	#Handle new clients that might be auto added
	if [ -n "$_newClientsAutoAdded" ]; then
	
		[ -n "$_logFilePath" ] && bwMonitorLog 'ADD NEW CLIENTS'
		[ -n "$_logFilePath" ] && bwMonitorLog "$_newClientsAutoAdded"
		
		echo "$_newClientsAutoAdded" >> $_userFilePath	
		[ -n "$_dnsmasqFilePath" ] && _clientsDetails=`cat $_userFilePath`
		_forceJavascriptReload=1
		_newClientsAutoAdded=''
	fi	
	#Load User files if they have been updated since our last read
	if [ -n "$_dnsmasqFilePath" ]; then
		hasUserFileChanged $_dnsmasqFilePath
		[ $? = 0 ] && loadDNSMasqUsers
	else
		hasUserFileChanged $_userFilePath
		[ $? = 0 ] && _clientsDetails=`cat $_userFilePath`
	fi
	
	[ $_forceJavascriptReload -eq 1 ] && generateSecureClient
}

#Will backup the current usage.db. Will also check to see if the user details need to be updated
backupAndUpdates()
{
	[ -n "$_logFilePath" ] && bwMonitorLog '***backupAndUpdates***'
	loadUsageData
	
	echo "$_macUsageData" > $_backupUsageFilePath
	
	userFileUpdate
	unloadUsageData
}

#Resets and backs up the usage.db. This will cause all usage stats to revert to 0.
resetUsage()
{
	[ -n "$_logFilePath" ] && bwMonitorLog '***resetUsage***'
	
	backupFilePath=$_backupHistoryPath`date +%d-%m-%Y`'.db'
	
	if [ ! -f $backupFilePath ]; then
		loadUsageData
		echo "$_macUsageData" > $backupFilePath
		if [ $? -eq 0 ]; then
			[ -n "$_logFilePath" ] && bwMonitorLog 'USAGE DATA ARCHIVED'
			_macUsageData=''
			[ -f $_macUsageFilePath ] && rm $_macUsageFilePath
			rm -f $_backupUsageFilePath	
			[ $_keepLastJSFile -eq 1 ] && cp -f $_javascriptPath$JAVASCRIPT_FILE_NAME $_javascriptPath'last_'$JAVASCRIPT_FILE_NAME
			[ $_historyJSFile -eq 1 ] && cp $_javascriptPath$JAVASCRIPT_FILE_NAME $_backupHistoryPath`date +%d-%m-%Y`'_'$JAVASCRIPT_FILE_NAME
		fi
		_forceJavascriptReload=1
		unloadUsageData
	fi
}
#Checks if a reset should occur
checkReset()
{
	secondsUntilNextDay=`expr $(expr $(date +%H) '*' 60 '*' 60) + $(expr $(date +%M) '*' 60) + $(expr $(date +%S))`
	secondsUntilNextDay=`expr 86400 - $secondsUntilNextDay`
	nextDay=`date --date='next day' +"%d"`
	if [ $? -ne 0 ]; then
	  #Attempt another way to determine the next day
	  nextDay=`TZ=MST-24 date +"%d"`
	fi
	nextDay=`expr $nextDay '*' 1`
	#Determine if next day will be reached before or after update
	secondsWithUpdateUntilNextDay=`expr $(expr $secondsUntilNextDay - $_intervalUpdate) - 60`
	#force reset day to numeric
	resetDay=`expr $_resetDay '*' 1`
	if [ $nextDay -eq $resetDay ] && [ $secondsWithUpdateUntilNextDay -le 0 ]; then
	  #determine if we can do another update of usage before stats are reset
	  sleepInterval=`expr  $secondsUntilNextDay - 30`
	  if [ $sleepInterval -ge 0 ]; then
		 sleep $sleepInterval
		 updateUsage
		 publishUsage
	  fi
	  #wait until next day
	  sleep 10
	  currentDay=`expr $(date +%d) '*' 1`
	  while [ $currentDay -ne $resetDay ]; do
		 sleep 10
		 currentDay=`expr $(date +%d) '*' 1`
	  done
	  sleep 10
	  resetUsage
	fi
}
# ==========================================================
#                  SECTION - MAIN METHODS
# ==========================================================
#Setups iptables chain rule. Ensures it is only at the top, and only one exists.
setupIPRule()
{
foundRuleNumber=`iptables -L FORWARD -n --line-numbers | grep "$CHAIN_RULE" | awk '{print $1}'`
if [ -z "$foundRuleNumber" ]; then
	iptables -N "$CHAIN_RULE"
	iptables -I FORWARD 1 -j "$CHAIN_RULE"
else
	lineNumber=`expr $foundRuleNumber '*' 1`
	if [ "$lineNumber" != "1" ]; then	
		while [ -n "$foundRuleNumber" ]; do
			lineNumber=`expr $foundRuleNumber '*' 1`
			iptables -D FORWARD $lineNumber
			foundRuleNumber=`iptables -L FORWARD -n --line-numbers | grep "$CHAIN_RULE" | awk '{print $1}'`
		done
		iptables -I FORWARD 1 -j "$CHAIN_RULE"
	fi
fi
}

#Add chain rules to IPs and MACs
setupUserIPRules()
{
connectedIPs=`grep "$LAN_IFACE" $CONNECTED_USERS_FILE`
connectedIPIndex=1
connectedIP=`echo "$connectedIPs" | sed -n "$connectedIPIndex"'p'`
while [ -n "$connectedIP" ];
do
	currentIP=`echo "$connectedIP" | awk '{print $1}'`
	#Add iptable rules (if non existing).
	foundLine=`iptables -nL "$CHAIN_RULE" | grep "$currentIP"'[^0-9].*'`
	if [ -z "$foundLine" ]; then
		iptables -I "$CHAIN_RULE" -d "$currentIP" -j RETURN
		iptables -I "$CHAIN_RULE" -s "$currentIP" -j RETURN
	fi

connectedIPIndex=`expr $connectedIPIndex + 1`
connectedIP=`echo "$connectedIPs" | sed -n "$connectedIPIndex"'p'`
done
}

#Updates usage data per MAC basis
updateUsage()
{
[ -n "$_logFilePath" ] && bwMonitorLog '***updateUsage***'

loadUsageData
if [ "$_macUsageFilePath" != "1" ]; then
	[ ! -f $_macUsageFilePath ] && touch $_macUsageFilePath
fi
[ $_recordDailyUsage -eq 1 ] && currentDay=`date +%d` || currentDay='01'
connectedIPs=`grep "$LAN_IFACE" $CONNECTED_USERS_FILE`
iptablesData=`iptables -L "$CHAIN_RULE" -vnxZ`

[ -n "$_logFilePath" ] && bwMonitorLog 'IPTABLES DATA'"
$iptablesData
"
connectedIPIndex=1
connectedIP=`echo "$connectedIPs" | sed -n "$connectedIPIndex"'p'`
while [ -n "$connectedIP" ];
do

currentIP=`echo "$connectedIP" | awk '{print $1}'`
currentMAC=`echo "$connectedIP" | awk '{print $4}'`
#Check to see if an entry for this MAC exists in the users definition file. If it doesnt add it.
if [ $_autoAddUserMACs -eq 1 ]; then
	if [ -n "$currentMAC" ]; then
		foundEntry=`echo "$_clientsDetails" | grep -i "$currentMAC"`
		[ -z "$foundEntry" ] && foundEntry=`echo "$_newClientsAutoAdded" | grep -i "$currentMAC"`
		if [ -z "$foundEntry" ]; then
			if [ $_showMAC -eq 1 ]; then
				newClient="$currentMAC,$currentIP,$currentMAC,Auto-Added"
			else
				newClient="$currentMAC,$currentIP,System,Auto-Added"
			fi
			if [ -z "$_newClientsAutoAdded" ]; then
				_newClientsAutoAdded="$newClient"
			else
_newClientsAutoAdded="$_newClientsAutoAdded
$newClient"			
			fi	
		fi
	fi
fi
currentIPData=`echo "$iptablesData" | grep "$currentIP"'[^0-9].*'`
newUsageIn=`echo "$currentIPData" | awk '{print $2,$9}' | grep "$currentIP" | awk '{print $1}'`
newUsageOut=`echo "$currentIPData" | awk '{print $2,$8}' | grep "$currentIP" | awk '{print $1}'`

[ $newUsageIn -gt 0 ] || newUsageIn='0'
[ $newUsageOut -gt 0 ] || newUsageOut='0'

currentUsageLine=`echo "$_macUsageData" | grep -i "$currentMAC,.*,.*,.*,$currentDay"`
#If the line exists, update it, else just append a new line
if [ -n "$currentUsageLine" ]; then
  if [ "$newUsageIn" != "0" ] || [ -n "$newUsageOut" != "0" ];  then
	dbUsageIn=`echo "$currentUsageLine" | cut -d, -f3`
	dbUsageOut=`echo "$currentUsageLine" | cut -d, -f4`
	[ -z "$dbUsageIn" ] && dbUsageIn='0'
	[ -z "$dbUsageOut" ] && dbUsageOut='0'
	#add support for bit 32 routers
	if [ $_supportBit32 -ge 1 ]; then
		newUsageIn=`echo 'scale=2;'"$newUsageIn / $_supportBit32" | bc`  
		newUsageOut=`echo 'scale=2;'"$newUsageOut / $_supportBit32" | bc` 
	fi
	#Determine the new usage
	dbUsageIn=`echo 'scale=2;'"$dbUsageIn + $newUsageIn" | bc`
	dbUsageOut=`echo 'scale=2;'"$dbUsageOut + $newUsageOut" | bc`
	newUsageOutput="$currentMAC,$currentIP,$dbUsageIn,$dbUsageOut,$currentDay"
	#Update the existing line and save it to the usage variable
	_macUsageData=`echo "$_macUsageData" | sed "s/$currentMAC,.*,.*,.*,$currentDay/$newUsageOutput/"`
  fi
else
	newUsageOutput="$currentMAC,$currentIP,$newUsageIn,$newUsageOut,$currentDay"
	if [ ! -z "$_macUsageData" ]; then
#Leave exactly like this. This places the record on a new line
_macUsageData="$_macUsageData
$newUsageOutput"
	else
		_macUsageData=$newUsageOutput
	fi
fi
connectedIPIndex=`expr $connectedIPIndex + 1`
connectedIP=`echo "$connectedIPs" | sed -n "$connectedIPIndex"'p'`
done
#Update usage file
if [ -n "$_macUsageData" ] ; then
	if [ "$_macUsageFilePath" != "1" ]; then
		echo "$_macUsageData" > $_macUsageFilePath
	fi
fi

unloadUsageData
connectedIPs=''
iptablesData=''
}

#This method outputs a completely new Javascript File
reloadJavascript()
{
[ -n "$_logFilePath" ] && bwMonitorLog '***reloadJavascript***'

scriptFilePathName=$_javascriptPath$JAVASCRIPT_FILE_NAME
loadUsageData

lastClient=''
macIndex=0
clientIndex=-1
outputString=''
[ $_recordDailyUsage -eq 1 ] && today=`date +%e` || today=1
completedClients=''
today=`expr $today '*' 1`
outputString="_todaysDay=$today"'; var users=[]; _supportBit32='"$_supportBit32"';'

#Find Group Names
clientGroupIndex=1
currentGroupClient=`echo "$_clientsDetails" | sed -n "$clientGroupIndex"'p'`
while [ -n "$currentGroupClient" ]; do
groupName=`echo "$currentGroupClient" | cut -d, -f3`
clientGroupEntries=''

groupExists=`echo "$completedClients" | grep -i "00$groupName"'00'`
if [ -n "$groupExists" ]; then
	clientGroupIndex=`expr $clientGroupIndex + 1`
	currentGroupClient=`echo "$_clientsDetails" | sed -n "$clientGroupIndex"'p'`
	continue
fi

[ -n "$_logFilePath" ] && bwMonitorLog 'New Group to Process: '"$groupName"

#Only use values from 3rd column for Group Names
allClientGroupEntries=`echo "$_clientsDetails" | grep -i ','"$groupName"'[\s]*,'`

[ -n "$_logFilePath" ] && bwMonitorLog 'Found Group Entries: '"
$groupName"

groupNamesOnly=`echo "$allClientGroupEntries" | cut -d, -f3`
groupIndex=1
currentGroupName=`echo "$groupNamesOnly" | sed -n "$groupIndex"'p'`
while [ -n "$currentGroupName" ]; do
	if [ "$currentGroupName" = "$groupName" ]; then
		clientEntry=`echo "$allClientGroupEntries" | sed -n "$groupIndex"'p'`
		if [ -z "$clientGroupEntries" ]; then
			clientGroupEntries="$clientEntry"
		else
clientGroupEntries="$clientGroupEntries
$clientEntry"
		fi		
	fi
groupIndex=`expr $groupIndex + 1`
currentGroupName=`echo "$groupNamesOnly" | sed -n "$groupIndex"'p'`
done

[ -n "$_logFilePath" ] && bwMonitorLog 'Client Group Entries to Process: '"
$clientGroupEntries"

#Process by Group
clientsLineIndex=1
currentClient=`echo "$clientGroupEntries" | sed -n "$clientsLineIndex"'p'`
while [ -n "$currentClient" ]; do

  currentMAC=`echo "$currentClient" | cut -d, -f1`
  currentIP=`echo "$currentClient" | cut -d, -f2`
  userName=`echo "$currentClient" | cut -d, -f3`
  macType=`echo "$currentClient" | cut -d, -f4`
  macID=`echo "$currentClient" | awk -F, '{print $NF}'`
  #Display Data based on display flag value
  displayData=`echo "$currentClient" | cut -d, -f5` 
  if [ "$macID" != "$displayData" ]; then
	  if [ -n "$displayData" ] && [ "$displayData" != "1" ]; then
		clientsLineIndex=`expr $clientsLineIndex + 1`
		currentClient=`echo "$clientGroupEntries" | sed -n "$clientsLineIndex"'p'`
		nextUserName=`echo "$currentClient" | cut -d, -f3`
		if [ -n "$lastClient" ]; then
			if [ "$lastClient" = "$userName"] && [ "$userName" != "$nextUserName" ]; then
				outputString="$outputString users[$clientIndex]=$userObject"'; '
				lastClient=$userName
			fi
		fi
		continue
	  fi
  fi
  
  if [ "$lastClient" != "$userName" ]; then
        clientIndex=`expr $clientIndex + 1`
        macIndex=0
		userObject="User$clientIndex"
outputString="$outputString$userObject"'=new Object();'
outputString="$outputString $userObject"".ID='""$userName""';"
outputString="$outputString $userObject"'.userUsage=[];'
  fi
  macObject="$macID"
outputString="$outputString $macObject"'= new Object();'
	if [ -z "$macType" ] && [ $_showMAC -eq 1 ]; then
outputString="$outputString $macObject"".ID='$currentMAC""';"
	else
outputString="$outputString $macObject"".ID='$macType""';"	
	fi
outputString="$outputString $macObject"'.dayUsages=[];'

  [ $_recordDailyUsage -eq 1 ] && maxDays=31 || maxDays=1
  userMACData=`echo "$_macUsageData" | grep -i "$currentMAC"`
  usageDayIndex=0
  while [ $usageDayIndex -lt $maxDays ]; do
        usageDay=`expr $usageDayIndex + 1`
		[ $usageDay -lt 10 ] && usageDay='0'"$usageDay"		
        dayUsage=`echo "$userMACData" | grep ".*,.*,.*,.*,$usageDay"`
		currentUsageIn=0
		currentUsageOut=0
        if [ ! -z "$dayUsage" ]; then
            currentUsageIn=`echo "$dayUsage" | cut -d, -f3`
            currentUsageOut=`echo "$dayUsage" | cut -d, -f4`
        fi
        [ -z "$currentUsageIn" ] && currentUsageIn=0
        [ -z "$currentUsageOut" ] && currentUsageOut=0
		dayObject="$macObject$usageDay"
		usageDay=`expr $usageDay '*' 1`
outputString="$outputString $dayObject"'= new Object();'
outputString="$outputString
$dayObject"".down=$currentUsageIn"';'
outputString="$outputString
$dayObject"".up=$currentUsageOut"';'
outputString="$outputString
$macObject"".dayUsages[$usageDayIndex]=$dayObject"';'
        usageDayIndex=`expr $usageDayIndex + 1`
  done
outputString="$outputString $userObject"".userUsage[$macIndex]=$macObject"'; '

  clientsLineIndex=`expr $clientsLineIndex + 1`
  currentClient=`echo "$clientGroupEntries" | sed -n "$clientsLineIndex"'p'`
  nextUserName=`echo "$currentClient" | cut -d, -f3`
  [ "$userName" != "$nextUserName" ] && outputString="$outputString users[$clientIndex]=$userObject"'; '

  macIndex=`expr $macIndex + 1`
  lastClient=$userName
done

completedClients="$completedClients 00$groupName"'00'
clientGroupIndex=`expr $clientGroupIndex + 1`
currentGroupClient=`echo "$_clientsDetails" | sed -n "$clientGroupIndex"'p'`
done

[ -n "$_logFilePath" ] && bwMonitorLog 'Completed Clients Processed: '"$completedClients"

#Push to out put file  
if [ -n "$outputString" ]; then
	[ -f $scriptFilePathName ] && rm $scriptFilePathName
	echo "$outputString" > $scriptFilePathName
fi
clientGroupEntries=''
completedClients=''
outputString=''
unloadUsageData
currentClient=''
lastClient=''
}

#This will only update the current days JS values. It will also update the previuos days values as well if need be.
updateJavascript()
{
[ -n "$_logFilePath" ] && bwMonitorLog '***updateJavascript***'

scriptFilePathName=$_javascriptPath$JAVASCRIPT_FILE_NAME
currentScript=`cat $scriptFilePathName`
loadUsageData
[ $_recordDailyUsage -eq 1 ] && currentDay=`date +%d` || currentDay='01'

if [ "$_previousDay" != "$currentDay" ]; then
	previous=`expr $_previousDay '*' 1`
	today=`expr $currentDay '*' 1`
	replaceToday='_todaysDay='"$previous"
	replaceNewDay='_todaysDay='"$today"
	currentScript=`echo "$currentScript" | sed "s/$replaceToday/$replaceNewDay"/`
fi
	
clientsLineIndex=1
currentClient=`echo "$_clientsDetails" | sed -n "$clientsLineIndex"'p'`
while [ -n "$currentClient" ]; do
  currentMAC=`echo "$currentClient" | cut -d, -f1`
  macType=`echo "$currentClient" | cut -d, -f4`
  macID=`echo "$currentClient" | awk -F, '{print $NF}'`
  displayData=`echo "$currentClient" | cut -d, -f5`  
  if [ "$macID" != "$displayData" ]; then
	  if [ -n "$displayData" ] && [ "$displayData" != "1" ]; then
		clientsLineIndex=`expr $clientsLineIndex + 1`
		currentClient=`echo "$sortedClientsDetails" | sed -n "$clientsLineIndex"'p'`
		continue
	  fi
  fi
 
  macObject="$macID"
  usageDay=$currentDay
  jsDayLines=`echo "$currentScript" | grep "$macObject$usageDay"`
  currentUsageLine=`echo "$_macUsageData" | grep "$currentMAC,.*,.*,.*,$usageDay"`
  while [ -n "$currentUsageLine" ]; do
		jsDayIn=`echo "$jsDayLines" | grep "$macObject$usageDay"'.down'`
		jsDayOut=`echo "$jsDayLines" | grep "$macObject$usageDay"'.up'`	
		currentUsageIn=`echo "$currentUsageLine" | cut -f3 -s -d,`
		currentUsageOut=`echo "$currentUsageLine" | cut -f4 -s -d,`
		[ -z "$currentUsageIn" ] && currentUsageIn=0
        [ -z "$currentUsageOut" ] && currentUsageOut=0
		#Determine the new usage
		newUsageDown="$macObject$usageDay"".down=$currentUsageIn"';'
		newUsageUp="$macObject$usageDay"".up=$currentUsageOut"';'	
		#Update the existing line and save it to the usage variable
		currentScript=`echo "$currentScript" | sed s/"$jsDayIn"/"$newUsageDown"/`
		currentScript=`echo "$currentScript" | sed s/"$jsDayOut"/"$newUsageUp"/`
		#update the previous line in case we have gone over midnight
		currentUsageLine=''
		if [ $_recordDailyUsage -eq 1 ] && [ "$_previousDay" != "$usageDay" ]; then
			usageDay=$_previousDay
			jsDayLines=`echo "$currentScript" | grep "$macObject$usageDay"`
			currentUsageLine=`echo "$_macUsageData" | grep "$currentMAC,.*,.*,.*,$usageDay"`
		fi
  done
clientsLineIndex=`expr $clientsLineIndex + 1`
currentClient=`echo "$_clientsDetails" | sed -n "$clientsLineIndex"'p'`
done
#Copy new information to file
if [ -n "$currentScript" ]; then
	[ -f $scriptFilePathName ] &&  rm -f $scriptFilePathName
	echo "$currentScript" > $scriptFilePathName
	[ "$_previousDay" != "$currentDay" ] && _previousDay=$currentDay
fi
unloadUsageData
currentScript=''
}

#Entry method for publishing a javascript file. Will either do a FULL update or a partial update
publishUsage()
{
	[ -n "$_logFilePath" ] && bwMonitorLog '***publishUsage***'
	if [ ! -f $_javascriptPath$JAVASCRIPT_FILE_NAME ] || [ $_forceJavascriptReload -eq 1 ]; then
		_forceJavascriptReload=0
		reloadJavascript
	else
		updateJavascript
	fi
}
# ==========================================================
#                  SECTION - CONTROLLER
# ==========================================================
[ -n "${17}" ] && _logFilePath=${17}
[ -n "$_logFilePath" ] && bwMonitorLog '============== STARTING BW MONITOR ============== '
#Set up IPTABLES and user IP's
setupIPRule
setupUserIPRules
#Verify the parameters and test the dnsmasq load
checkParameters
#Set Optional Values or Default if required
[ -n "$_logFilePath" ] && bwMonitorLog 'Assign Configuration and setup defaults'
[ -n "${10}" ] &&  _doUsageFileRestore=${10}
[ -n "${11}" ] &&  _keepLastJSFile=${11}
[ -n "${12}" ] && _historyJSFile=${12}
[ -n "${13}" ] && _recordDailyUsage=${13}
[ -n "${14}" ] && _autoAddUserMACs=${14}
[ -n "${15}" ] && _supportBit32=${15}
[ -n "${16}" ] && _showMAC=${16}

if [ -z "$_macUsageFilePath" ]; then
    [ -n "$_logFilePath" ] && bwMonitorLog 'Using current folder and default file name for usage database: mac_usage.db'
    _macUsageFilePath=$DEFAULT_USAGE_FILE_PATH
fi
if [ -z "$_javascriptPath" ]; then
	[ -n "$_logFilePath" ] && bwMonitorLog 'Setting default file path for javascript output. /tmp/www/'
	_javascriptPath=/tmp/www/
fi
if [ $_doUsageFileRestore -eq 1 ]; then
	[ "$_macUsageFilePath" = "1" ] && _macUsageData=`cat $_backupUsageFilePath` || cp -f $_backupUsageFilePath $_macUsageFilePath
fi
#Check for a DNS file being passed through. If it is passed in, we need to convert it
isDNSMASQFilePath=`echo "$_userFilePath" | grep -i "dnsmasq"`
if [ -n "$isDNSMASQFilePath" ]; then
	[ -n "$_logFilePath" ] && bwMonitorLog 'Using dnsmasq users file'
	loadDNSMasqUsers
	hasUserFileChanged $_dnsmasqFilePath
else
	[ -n "$_logFilePath" ] && bwMonitorLog 'Using custom users file'
	_clientsDetails=`cat $_userFilePath`
	hasUserFileChanged $_userFilePath
fi
if [ -z "$_clientsDetails" ]; then
	[ -n "$_logFilePath" ] && bwMonitorLog 'No Clients found in User File: '"$_userFilePath"
	[ -n "$_logFilePath" ] && bwMonitorLog 'Exiting .....'
	rm $MONITOR_LOCK_FILE
	exit 0
fi
generateSecureClient
logCurrentConfiguration
#Continually Check for NEW IPs
[ -n "$_logFilePath" ] && bwMonitorLog 'Checking IPs and iptables'
while [ -f $MONITOR_LOCK_FILE ] && [ ! -f $MONITOR_STOP_FILE ]; do
	setupIPRule
	setupUserIPRules
	sleep 10
done &
#Start polling updates,publish,resets,backups
[ -n "$_logFilePath" ] && bwMonitorLog 'Main Controller'
publishIteration=0
backupIteration=0
while [ -f $MONITOR_LOCK_FILE ] && [ ! -f $MONITOR_STOP_FILE ]; do
	#check for a reset
	checkReset	
	sleep $_intervalUpdate	
	updateUsage		
	publishIteration=`expr $publishIteration + 1`
	backupIteration=`expr $backupIteration + 1`	
	#Check for a publish
	if [ $publishIteration -eq $_iterationPublish ]; then
		publishUsage
		publishIteration=0
	fi
	#Check for a backup
	if [ $backupIteration -eq $_iterationBackup ]; then
		backupAndUpdates
		backupIteration=0
	fi
	
	if [ ! -f $MONITOR_LOCK_FILE ] || [ -f $MONITOR_STOP_FILE ]; then
		backupAndUpdates
		_clientsDetails=''
		bwMonitorLog 'Shutting Down Monitor'
		sleep 10
		touch $MONITOR_STOPPED_FILE
		exit 1
	fi
done &